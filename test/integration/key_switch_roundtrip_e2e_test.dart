import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/claude_config_service.dart';
import 'package:key_core/services/claude_desktop_config_service.dart';
import 'package:key_core/services/codex_config_service.dart';
import 'package:key_core/services/gemini_config_service.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 端到端：Claude Code / Codex / Gemini / Claude Desktop 的 切换 A → 读回 → 切换 B → 读回 → 切回官方。
/// 临时 HOME + 真实文件格式，断言用户自己的配置在整个往返中保留。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String home, claudeDir, codexDir, geminiDir, desktopDir;

  AIKey key(String value, {String? base}) => AIKey(
        id: value.hashCode & 0xffff,
        name: 'k-$value',
        platform: 'DeepSeek',
        platformType: PlatformType.deepSeek,
        keyValue: value,
        tags: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        enableClaudeCode: true,
        claudeCodeBaseUrl: base ?? 'https://api.deepseek.com/anthropic',
        claudeCodeModel: 'deepseek-v4-pro',
        enableCodex: true,
        codexBaseUrl: base ?? 'https://api.deepseek.com/v1',
        codexModel: 'deepseek-v4-pro',
        enableGemini: true,
        geminiBaseUrl: base ?? 'https://gw.example',
        geminiModel: 'gemini-3-pro',
        claudeDesktopBaseUrl: base ?? 'https://api.deepseek.com/anthropic',
      );

  Map<String, dynamic> json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('switch_roundtrip_');
    home = p.join(tmp.path, 'home');
    claudeDir = p.join(home, '.claude');
    codexDir = p.join(home, '.codex');
    geminiDir = p.join(home, '.gemini');
    desktopDir = p.join(home, '.config', 'Claude');
    for (final d in [claudeDir, codexDir, geminiDir, desktopDir]) {
      Directory(d).createSync(recursive: true);
    }
    SharedPreferences.setMockInitialValues({
      'claude_config_dir': claudeDir,
      'codex_config_dir': codexDir,
      'ai_tool_config_dir_codex': codexDir,
      'gemini_config_dir': geminiDir,
      'claude_desktop_config_dir': desktopDir,
    });
    FlutterSecureStorage.setMockInitialValues({});
    SettingsService.debugResetOfficialKeyCache();
    SettingsService.debugHomeDirOverride = home;
    LiveConfigWriter.debugBackupRootOverride = p.join(tmp.path, 'backups');
  });

  tearDown(() {
    SettingsService.debugHomeDirOverride = null;
    LiveConfigWriter.debugBackupRootOverride = null;
    SettingsService.debugResetOfficialKeyCache();
    tmp.deleteSync(recursive: true);
  });

  test('Claude Code', () async {
    final settings = p.join(claudeDir, 'settings.json');
    File(settings).writeAsStringSync(jsonEncode({
      'permissions': {'allow': ['Bash(ls)']},
      'env': {'HTTPS_PROXY': 'http://127.0.0.1:7890'},
      'hooks': {},
    }));
    final s = ClaudeConfigService();
    expect(await s.switchProvider(key('sk-a')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-a');
    expect(json(settings)['env']['ANTHROPIC_BASE_URL'], 'https://api.deepseek.com/anthropic');
    expect(await s.isOfficialConfig(), isFalse);

    expect(await s.switchProvider(key('sk-b', base: 'https://relay.example')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-b');
    expect(json(settings)['env']['ANTHROPIC_BASE_URL'], 'https://relay.example');

    expect(await s.switchToOfficial(), isTrue);
    expect(await s.isOfficialConfig(), isTrue);
    final doc = json(settings);
    expect(doc['permissions'], {'allow': ['Bash(ls)']});
    expect(doc['env'], {'HTTPS_PROXY': 'http://127.0.0.1:7890'}, reason: '切回官方后只剩用户自己的 env');
  });

  test('Codex', () async {
    final toml = p.join(codexDir, 'config.toml');
    const userToml = 'model_reasoning_effort = "low"\n\n[mcp_servers.fs]\ncommand = "npx"\n\n[projects."/repo"]\ntrust_level = "trusted"\n';
    File(toml).writeAsStringSync(userToml);
    File(p.join(codexDir, 'auth.json')).writeAsStringSync(jsonEncode({'tokens': {'id_token': 'oauth'}}));
    final s = CodexConfigService();
    expect(await s.switchProvider(key('sk-a')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-a');
    var text = File(toml).readAsStringSync();
    expect(text, contains('[model_providers.keycore]'));
    expect(text, contains('[mcp_servers.fs]'));
    expect(text, contains('base_url = "https://api.deepseek.com/v1"'));

    expect(await s.switchProvider(key('sk-b', base: 'https://relay.example/v1')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-b');
    text = File(toml).readAsStringSync();
    expect(RegExp(r'\[model_providers\.keycore\]').allMatches(text).length, 1, reason: '固定一张表，会话历史不被拆散');

    expect(await s.switchToOfficial(), isTrue);
    expect(await s.isOfficialConfig(), isTrue);
    text = File(toml).readAsStringSync();
    expect(text, isNot(contains('keycore')));
    expect(text, contains('[projects."/repo"]'));
    expect(text, contains('model_reasoning_effort = "low"'), reason: '用户的推理强度偏好保留');
    expect(json(p.join(codexDir, 'auth.json'))['tokens'], {'id_token': 'oauth'});
  });

  test('Gemini', () async {
    File(p.join(geminiDir, '.env')).writeAsStringSync('# mine\nHTTP_PROXY=http://127.0.0.1:7890\n');
    File(p.join(geminiDir, 'settings.json')).writeAsStringSync(jsonEncode({'theme': 'GitHub'}));
    final s = GeminiConfigService();
    expect(await s.switchProvider(key('sk-a')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-a');
    expect((await s.readEnv())['GOOGLE_GEMINI_BASE_URL'], 'https://gw.example');
    expect((await s.readEnv())['GEMINI_MODEL'], 'gemini-3-pro');
    expect(await s.switchProvider(key('sk-b', base: 'https://gw2.example')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-b');
    expect((await s.readEnv())['GOOGLE_GEMINI_BASE_URL'], 'https://gw2.example');
    expect(await s.switchToOfficial(), isTrue);
    final env = await s.readEnv();
    expect(env.containsKey('GEMINI_API_KEY'), isFalse);
    expect(env['HTTP_PROXY'], 'http://127.0.0.1:7890');
    expect(File(p.join(geminiDir, '.env')).readAsStringSync(), startsWith('# mine'));
    expect(json(p.join(geminiDir, 'settings.json'))['theme'], 'GitHub');
  });

  test('Claude Desktop', () async {
    final cfg = p.join(desktopDir, 'claude_desktop_config.json');
    File(cfg).writeAsStringSync(jsonEncode({'globalShortcut': 'Alt+Space', 'mcpServers': {'fs': {'command': 'npx'}}}));
    final s = ClaudeDesktopConfigService();
    expect(await s.switchProvider(key('sk-a')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-a');
    expect(await s.switchProvider(key('sk-b')), isTrue);
    expect(await s.getCurrentApiKey(), 'sk-b');
    final lib = Directory(p.join(home, '.config', 'Claude-3p', 'configLibrary'));
    final profiles = lib.listSync().whereType<File>().where((f) => json(f.path).containsKey('inferenceGatewayApiKey'));
    expect(profiles.length, 1, reason: '切换不留下旧 profile');
    expect(await s.switchToOfficial(), isTrue);
    expect(await s.isOfficialConfig(), isTrue);
    final doc = json(cfg);
    expect(doc['globalShortcut'], 'Alt+Space');
    expect(doc['mcpServers'], {'fs': {'command': 'npx'}});
  });
}
