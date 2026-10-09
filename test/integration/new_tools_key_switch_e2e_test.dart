import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/cloud_config.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/models/unified_provider_config.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';
import 'package:key_core/services/mcp/mcp_tool_formats.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:key_core/services/tool_providers/tool_provider_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

/// 端到端：OpenCode / Grok Build / Hermes / Pi / MiniMax Code 的密钥切换。
/// 在临时 HOME 中预置“用户自己的配置”，执行 写入 A → 读回 → 写入 B → 读回 → 移除 B → 移除 A，
/// 用真实解析器（JSON / YAML / TOML 切分器）读回文件，并断言用户内容始终保留。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final raw = jsonDecode(File('assets/config/app_config.json').readAsStringSync()) as Map<String, dynamic>;
  final presets = {for (final pr in CloudConfig.fromJson(raw).config.providers) pr.id: pr};
  final deepSeek = presets['deepSeek']!;
  final packy = presets['packycode']!;

  late Directory tmp;
  late Map<AiToolType, String> dirs;
  late ToolProviderService service;

  AIKey key(int id, String name, {PlatformType? type, Map<String, Map<String, dynamic>> toolConfigs = const {}}) => AIKey(
        id: id,
        name: name,
        platform: name,
        platformType: type ?? PlatformType.deepSeek,
        keyValue: 'enc-$id',
        tags: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        toolConfigs: toolConfigs,
      );

  Map<String, dynamic> json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  Map yaml(String path) => loadYaml(File(path).readAsStringSync()) as Map;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('new_tools_e2e_');
    final home = p.join(tmp.path, 'home');
    dirs = {
      AiToolType.opencode: p.join(home, '.config', 'opencode'),
      AiToolType.grokBuild: p.join(home, '.grok'),
      AiToolType.hermes: p.join(home, '.hermes'),
      AiToolType.pi: p.join(home, '.pi', 'agent'),
      AiToolType.mcode: p.join(home, '.minimax'),
    };
    for (final d in dirs.values) {
      Directory(d).createSync(recursive: true);
    }
    SharedPreferences.setMockInitialValues({
      for (final e in dirs.entries) 'ai_tool_config_dir_${e.key.value}': e.value,
    });
    SettingsService.debugHomeDirOverride = home;
    LiveConfigWriter.debugBackupRootOverride = p.join(tmp.path, 'backups');
    service = ToolProviderService();
  });

  tearDown(() {
    SettingsService.debugHomeDirOverride = null;
    LiveConfigWriter.debugBackupRootOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('预设数据：主流供应商带有 5 个新工具的预设块', () {
    for (final k in UnifiedProviderConfig.newToolPresetKeys) {
      final n = presets.values.where((pr) => pr.toolPresets.containsKey(k)).length;
      expect(n, greaterThan(30), reason: k);
    }
    expect(deepSeek.toolPresets['hermes']!['baseUrl'], 'https://api.deepseek.com');
    expect(packy.toolPresets['grokBuild']!['model'], 'grok-4.5');
  });

  test('OpenCode：累加写入 provider，默认模型随切换变化，移除后恢复原样', () async {
    final file = p.join(dirs[AiToolType.opencode]!, 'opencode.json');
    const original = {
      r'$schema': 'https://opencode.ai/config.json',
      'theme': 'tokyonight',
      'model': 'anthropic/claude-sonnet-4',
      'provider': {
        'mine': {'npm': '@ai-sdk/openai-compatible', 'options': {'baseURL': 'https://my.example/v1'}}
      },
      'mcp': {'fs': {'type': 'local', 'command': ['npx', 'fs']}},
    };
    File(file).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(original));

    final a = key(1, 'DeepSeek A');
    final b = key(2, 'DeepSeek B', toolConfigs: {
      'opencode': {'enabled': true, 'model': 'deepseek-v4-pro'}
    });
    await service.apply(AiToolType.opencode, a, 'sk-a', preset: deepSeek);
    var doc = json(file);
    expect(doc['provider']['keycore-1']['options']['apiKey'], 'sk-a');
    expect(doc['provider']['keycore-1']['options']['baseURL'], 'https://api.deepseek.com/v1');
    expect(doc['provider']['keycore-1']['npm'], '@ai-sdk/openai-compatible');
    expect((doc['provider']['keycore-1']['models'] as Map).keys, contains('deepseek-v4-pro'));
    expect(doc['model'], 'keycore-1/deepseek-v4-pro');
    expect(await service.defaultKeyId(AiToolType.opencode), 1);

    await service.apply(AiToolType.opencode, b, 'sk-b', preset: deepSeek);
    doc = json(file);
    expect(await service.appliedKeyIds(AiToolType.opencode), {1, 2});
    expect(doc['model'], 'keycore-2/deepseek-v4-pro');
    expect(doc['provider']['mine'], (original['provider'] as Map)['mine'], reason: '用户自己的 provider 保留');
    expect(doc['mcp'], original['mcp']);

    await service.remove(AiToolType.opencode, b);
    doc = json(file);
    expect(doc.containsKey('model'), isFalse, reason: '默认项被移除后不留悬空引用');
    await service.remove(AiToolType.opencode, a);
    doc = json(file);
    expect(doc['provider'], original['provider']);
    expect(doc['theme'], 'tokyonight');
    if (!Platform.isWindows) expect(File(file).statSync().mode & 0x1FF, 0x180, reason: '含密钥文件为 0600');
  });

  test('Grok Build：切换型，写入 [models]/[model."<模型>"]，切回官方后其他表保留', () async {
    final file = p.join(dirs[AiToolType.grokBuild]!, 'config.toml');
    const original = '# grok cli\n'
        'theme = "dark"\n'
        '\n'
        '[mcp_servers.fs]\n'
        'command = "npx"\n'
        'args = ["-y", "@modelcontextprotocol/server-filesystem"]\n';
    File(file).writeAsStringSync(original);

    final a = key(11, 'Packy A', type: PlatformType.custom);
    final b = key(12, 'Packy B', type: PlatformType.custom, toolConfigs: {
      'grok_build': {'enabled': true, 'baseUrl': 'https://relay.example/v1', 'model': 'grok-4.5-fast'}
    });
    await service.apply(AiToolType.grokBuild, a, 'sk-a', preset: packy);
    var text = File(file).readAsStringSync();
    var doc = TomlDoc.parse(text);
    final paths = doc.tables.map((t) => t.path.join('.')).toList();
    expect(paths, containsAll(['mcp_servers.fs', 'models', 'model.grok-4.5']));
    final table = doc.tables.firstWhere((t) => t.path.join('.') == 'model.grok-4.5');
    final entries = {for (final e in TomlDoc.parseEntries(table.lines.skip(1).join('\n'))) e.key: e.value};
    expect(entries['base_url'], 'https://www.packyapi.ai/v1');
    expect(entries['api_key'], 'sk-a');
    expect(entries['api_backend'], 'responses');
    expect(entries['context_window'], isNotNull);
    expect(text, contains('[model."grok-4.5"]'), reason: '带点号的模型名必须加引号');
    expect(await service.currentGrokApiKey(), 'sk-a');

    await service.apply(AiToolType.grokBuild, b, 'sk-b', preset: packy);
    text = File(file).readAsStringSync();
    doc = TomlDoc.parse(text);
    expect(doc.tables.where((t) => t.path.first == 'model').map((t) => t.path[1]), ['grok-4.5-fast'],
        reason: '切换后旧密钥的模型表被替换，不残留');
    expect(await service.currentGrokApiKey(), 'sk-b');

    // 移除非当前密钥不影响当前配置
    await service.remove(AiToolType.grokBuild, a, decryptedKey: 'sk-a');
    expect(await service.currentGrokApiKey(), 'sk-b');
    await service.remove(AiToolType.grokBuild, b, decryptedKey: 'sk-b');
    expect(await service.currentGrokApiKey(), isNull);
    expect(File(file).readAsStringSync(), original, reason: '切回官方后与原文件完全一致');
  });

  test('Hermes：custom_providers 增改、model 段切换，保留用户条目的额外字段与其他段', () async {
    final file = p.join(dirs[AiToolType.hermes]!, 'config.yaml');
    const original = 'model:\n'
        '  default: anthropic/claude-opus-4-8\n'
        '  provider: openrouter\n'
        '  context_length: 200000\n'
        'agent:\n'
        '  max_turns: 50\n'
        'custom_providers:\n'
        '  - name: openrouter\n'
        '    base_url: https://openrouter.ai/api/v1\n'
        '    api_key: sk-or\n'
        'mcp_servers:\n'
        '  fs:\n'
        '    command: npx\n';
    File(file).writeAsStringSync(original);

    final a = key(21, 'DeepSeek A');
    await service.apply(AiToolType.hermes, a, 'sk-a', preset: deepSeek);
    var doc = yaml(file);
    final list = doc['custom_providers'] as List;
    expect(list.map((e) => e['name']), ['openrouter', 'keycore-21']);
    final mine = list.last as Map;
    expect(mine['base_url'], 'https://api.deepseek.com');
    expect(mine['api_key'], 'sk-a');
    expect(mine['api_mode'], 'chat_completions');
    expect(mine['model'], 'deepseek-v4-pro');
    expect((mine['models'] as Map).keys.first, 'deepseek-v4-pro');
    expect((mine['models'] as Map)['deepseek-v4-pro']['context_length'], 1000000);
    expect(doc['model']['provider'], 'keycore-21');
    expect(doc['model']['default'], 'deepseek-v4-pro');
    expect(doc['model']['context_length'], 200000, reason: 'model 段其他字段保留');
    expect(doc['agent'], {'max_turns': 50});
    expect(await service.defaultKeyId(AiToolType.hermes), 21);

    // 用户在 Hermes 里给我们的条目加了字段，再次写入时保留
    File(file).writeAsStringSync(File(file).readAsStringSync().replaceFirst(
        '    api_mode: "chat_completions"', '    api_mode: "chat_completions"\n    request_timeout_seconds: 120'));
    await service.apply(AiToolType.hermes, a, 'sk-a2', preset: deepSeek);
    doc = yaml(file);
    expect((doc['custom_providers'] as List).last['request_timeout_seconds'], 120);
    expect((doc['custom_providers'] as List).last['api_key'], 'sk-a2');

    await service.remove(AiToolType.hermes, a);
    doc = yaml(file);
    expect((doc['custom_providers'] as List).map((e) => e['name']), ['openrouter']);
    expect(doc['model'], {'context_length': 200000}, reason: '指向我们的 default/provider 被清除');
    expect(doc['mcp_servers'], {'fs': {'command': 'npx'}});
  });

  test('Pi：models.json 累加 + settings.json 默认项', () async {
    final models = p.join(dirs[AiToolType.pi]!, 'models.json');
    final settings = p.join(dirs[AiToolType.pi]!, 'settings.json');
    File(models).writeAsStringSync(jsonEncode({
      'providers': {
        'ollama': {'baseUrl': 'http://localhost:11434/v1', 'api': 'openai-completions', 'models': []}
      }
    }));
    File(settings).writeAsStringSync(jsonEncode({'defaultProvider': 'ollama', 'defaultModel': 'qwen3', 'theme': 'dark'}));

    await service.apply(AiToolType.pi, key(31, 'A'), 'sk-a', preset: deepSeek);
    var m = json(models);
    expect(m['providers']['keycore-31']['apiKey'], 'sk-a');
    expect(m['providers']['keycore-31']['baseUrl'], 'https://api.deepseek.com/v1');
    expect((m['providers']['keycore-31']['models'] as List).first['id'], 'deepseek-v4-pro');
    expect(json(settings), {'defaultProvider': 'keycore-31', 'defaultModel': 'deepseek-v4-pro', 'theme': 'dark'});

    await service.apply(AiToolType.pi, key(32, 'B'), 'sk-b', preset: deepSeek, makeDefault: false);
    expect(await service.appliedKeyIds(AiToolType.pi), {31, 32});
    expect(await service.defaultKeyId(AiToolType.pi), 31);

    await service.remove(AiToolType.pi, key(31, 'A'));
    m = json(models);
    expect((m['providers'] as Map).keys, ['ollama', 'keycore-32']);
    expect(json(settings), {'theme': 'dark'});
  });

  test('MiniMax Code：custom_provider 累加、defaultModel、账号供应商不可覆盖、尊重 MCode 锁', () async {
    final file = p.join(dirs[AiToolType.mcode]!, 'config.yaml');
    const original = 'defaultModel: minimax/MiniMax-M3\n'
        'custom_provider:\n'
        '  minimax:\n'
        '    kind: minimax\n'
        '    enabled: true\n'
        'telemetry: false\n';
    File(file).writeAsStringSync(original);

    await service.apply(AiToolType.mcode, key(41, 'A'), 'sk-a', preset: deepSeek);
    var doc = yaml(file);
    final mine = doc['custom_provider']['keycore-41'] as Map;
    expect(mine['kind'], 'custom');
    expect(mine['api'], 'openai-completions');
    expect(mine['options'], {'baseURL': 'https://api.deepseek.com/v1', 'apiKey': 'sk-a'});
    expect((mine['models'] as Map).keys, contains('deepseek-v4-pro'));
    expect(doc['defaultModel'], 'custom_provider:keycore-41/deepseek-v4-pro');
    expect(doc['custom_provider']['minimax'], {'kind': 'minimax', 'enabled': true});
    expect(doc['telemetry'], false);
    expect(Directory('$file.lock').existsSync(), isFalse, reason: '写完释放锁');

    // MCode 正在保存（新鲜的锁目录）→ 拒绝写入，文件不变
    final before = File(file).readAsStringSync();
    Directory('$file.lock').createSync();
    await expectLater(service.apply(AiToolType.mcode, key(42, 'B'), 'sk-b', preset: deepSeek),
        throwsA(isA<ToolProviderException>()));
    expect(File(file).readAsStringSync(), before);
    Directory('$file.lock').deleteSync();

    // 账号供应商（kind != custom）同名时拒绝覆盖
    expect(
      () => ToolProviderService.applyMCode('custom_provider:\n  keycore-9:\n    kind: minimax\n',
          providerKey: 'keycore-9', entry: {'kind': 'custom'}),
      throwsA(isA<ToolProviderException>()),
    );

    await service.remove(AiToolType.mcode, key(41, 'A'));
    doc = yaml(file);
    expect((doc['custom_provider'] as Map).keys, ['minimax']);
    expect(doc.containsKey('defaultModel'), isFalse);
  });

  test('YAML 无法解析时中止，文件不变', () async {
    final file = p.join(dirs[AiToolType.hermes]!, 'config.yaml');
    File(file).writeAsStringSync('model: [unclosed\n');
    Object? err;
    try { await service.apply(AiToolType.hermes, key(51, 'A'), 'sk-a', preset: deepSeek); } catch (e) { err = e; }
    expect(err, isNotNull);
    expect(File(file).readAsStringSync(), 'model: [unclosed\n');
  });

  test('没有预设块时：OpenAI 兼容工具回退到密钥 API 地址；缺模型则给出可读错误', () async {
    final custom = AIKey(
      id: 61,
      name: 'Relay',
      platform: 'Relay',
      platformType: PlatformType.custom,
      apiEndpoint: 'https://relay.example/v1',
      keyValue: 'x',
      tags: const [],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      toolConfigs: const {
        'pi': {'enabled': true, 'model': 'qwen3-coder'}
      },
    );
    final spec = ToolProviderService.resolve(custom, AiToolType.pi)!;
    expect(spec.baseUrl, 'https://relay.example/v1');
    expect(spec.model, 'qwen3-coder');
    expect(ToolProviderService.resolve(custom, AiToolType.opencode), isNull, reason: '没有模型');
    await expectLater(service.apply(AiToolType.grokBuild, custom, 'sk'), throwsA(isA<ToolProviderException>()));
  });
}
