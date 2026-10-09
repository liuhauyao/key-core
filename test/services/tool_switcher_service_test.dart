import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/provider.dart';
import 'package:key_core/services/provider_manager_service.dart';
import 'package:key_core/services/tool_switcher_service.dart';
import 'package:path/path.dart' as p;

Provider _provider({
  String id = 'deepseek-official-1791520569415',
  String? endpoint = 'https://api.deepseek.com/anthropic',
  String? apiKey = 'sk-test-123',
  List<String> tools = const ['claude_code', 'gemini_cli', 'openclaw', 'grok_build'],
}) {
  final now = DateTime(2026, 10, 9);
  return Provider(
    id: id,
    name: 'DeepSeek',
    nameZh: '深度求索',
    providerType: 'official',
    apiEndpoint: endpoint,
    apiKey: apiKey,
    models: const [
      ProviderModel(id: 'deepseek-v4-pro', displayName: 'DeepSeek V4 Pro', contextWindow: 128000),
      ProviderModel(id: 'deepseek-v4-flash', displayName: 'DeepSeek V4 Flash'),
    ],
    supportedTools: tools,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory home;
  late ToolSwitcherService service;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('tool_switcher_');
    service = ToolSwitcherService.withResolver((tool) async {
      switch (tool) {
        case 'claude_code':
          return p.join(home.path, '.claude');
        case 'gemini_cli':
          return p.join(home.path, '.gemini');
        case 'openclaw':
          return p.join(home.path, '.openclaw');
        case 'grok_build':
          return p.join(home.path, '.grok');
      }
      throw UnsupportedError(tool);
    });
  });

  tearDown(() async {
    if (home.existsSync()) await home.delete(recursive: true);
  });

  group('Claude Code', () {
    test('writes env into settings.json and preserves other fields', () async {
      final file = File(p.join(home.path, '.claude', 'settings.json'));
      await file.create(recursive: true);
      await file.writeAsString(json.encode({
        'permissions': {'allow': ['Bash']},
        'env': {'FOO': 'bar', 'ANTHROPIC_DEFAULT_OPUS_MODEL': 'old'},
      }));

      await service.switchClaudeCode(_provider());

      final config = json.decode(await file.readAsString()) as Map<String, dynamic>;
      expect(config['permissions'], {'allow': ['Bash']});
      final env = config['env'] as Map<String, dynamic>;
      expect(env['FOO'], 'bar');
      expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-test-123');
      expect(env['ANTHROPIC_BASE_URL'], 'https://api.deepseek.com/anthropic');
      expect(env['ANTHROPIC_MODEL'], 'deepseek-v4-pro');
      expect(env.containsKey('ANTHROPIC_DEFAULT_OPUS_MODEL'), isFalse);

      // 写入前自动备份
      final backups = await service.listBackups('claude_code');
      expect(backups, hasLength(1));
      expect(backups.first.createdAt, isNotNull);

      final live = await service.readLiveState('claude_code');
      expect(live.configExists, isTrue);
      expect(live.hasApiKey, isTrue);
      expect(live.model, 'deepseek-v4-pro');
    });

    test('creates settings.json when missing', () async {
      await service.switchClaudeCode(_provider());
      final created = File(p.join(home.path, '.claude', 'settings.json'));
      expect(created.existsSync(), isTrue);
      if (!Platform.isWindows) {
        // 新建的配置文件包含 API Key，仅当前用户可读写
        expect(created.statSync().mode & 0x1FF, 0x180);
      }
      expect(await service.listBackups('claude_code'), isEmpty);
    });

    test('refuses providers without api key or tool support', () async {
      expect(() => service.switchClaudeCode(_provider(apiKey: '')), throwsStateError);
      expect(() => service.switchClaudeCode(_provider(tools: const ['gemini_cli'])), throwsStateError);
    });

    test('does not overwrite an unparsable settings.json', () async {
      final file = File(p.join(home.path, '.claude', 'settings.json'));
      await file.create(recursive: true);
      await file.writeAsString('{ not json');
      await expectLater(service.switchClaudeCode(_provider()), throwsFormatException);
      expect(await file.readAsString(), '{ not json');
    });
  });

  group('Gemini CLI', () {
    test('merges .env keeping comments and other vars', () async {
      final file = File(p.join(home.path, '.gemini', '.env'));
      await file.create(recursive: true);
      await file.writeAsString('# my env\nOTHER=1\nGEMINI_API_KEY=old\n');

      await service.switchGeminiCli(_provider(endpoint: 'https://relay.example.com'));

      final content = await file.readAsString();
      expect(content, contains('# my env'));
      expect(content, contains('OTHER=1'));
      final env = ToolSwitcherService.parseDotEnv(content);
      expect(env['GEMINI_API_KEY'], 'sk-test-123');
      expect(env['GOOGLE_GEMINI_BASE_URL'], 'https://relay.example.com');
      expect(env['GEMINI_MODEL'], 'deepseek-v4-pro');
    });

    test('official endpoint removes custom base url', () async {
      final file = File(p.join(home.path, '.gemini', '.env'));
      await file.create(recursive: true);
      await file.writeAsString('GOOGLE_GEMINI_BASE_URL=https://relay\n');
      await service.switchGeminiCli(
        _provider(endpoint: 'https://generativelanguage.googleapis.com'),
      );
      final env = ToolSwitcherService.parseDotEnv(await file.readAsString());
      expect(env.containsKey('GOOGLE_GEMINI_BASE_URL'), isFalse);
    });
  });

  group('OpenClaw', () {
    test('writes provider entry, env key and primary model', () async {
      final file = File(p.join(home.path, '.openclaw', 'openclaw.json'));
      await file.create(recursive: true);
      await file.writeAsString('{\n  // comment\n  "gateway": {"port": 18789},\n}\n');

      await service.switchOpenClaw(_provider());

      final config = json.decode(await file.readAsString()) as Map<String, dynamic>;
      expect(config['gateway'], {'port': 18789});
      final entry = config['models']['providers']['keycore-deepseek-official'] as Map;
      expect(entry['baseUrl'], 'https://api.deepseek.com/anthropic');
      expect(entry['api'], 'anthropic-messages');
      expect(entry['apiKey'], r'${KEYCORE_DEEPSEEK_OFFICIAL_API_KEY}');
      expect(config['agents']['defaults']['model']['primary'],
          'keycore-deepseek-official/deepseek-v4-pro');

      final env = ToolSwitcherService.parseDotEnv(
        await File(p.join(home.path, '.openclaw', '.env')).readAsString(),
      );
      expect(env['KEYCORE_DEEPSEEK_OFFICIAL_API_KEY'], 'sk-test-123');
      // 主配置文件中没有明文密钥
      expect(await file.readAsString(), isNot(contains('sk-test-123')));
    });
  });

  group('Grok Build', () {
    test('writes managed model table and keeps user content', () async {
      final file = File(p.join(home.path, '.grok', 'config.toml'));
      await file.create(recursive: true);
      await file.writeAsString(
        '# my config\n[models]\ndefault = "mine"\n\n[model.mine]\nmodel = "grok-4"\n\n[mcp_servers.fs]\ncommand = "npx"\n',
      );

      await service.switchGrokBuild(_provider());
      final content = await file.readAsString();
      expect(content, contains('# my config'));
      expect(content, contains('[model.mine]'));
      expect(content, contains('[mcp_servers.fs]'));
      expect(content, contains('default = "keycore"'));
      expect(content, isNot(contains('default = "mine"')));
      expect(content, contains('[model.keycore]'));

      // 再次切换不会产生重复的受管表
      await service.switchGrokBuild(_provider(apiKey: 'sk-new'));
      final again = await file.readAsString();
      expect('[model.keycore]'.allMatches(again), hasLength(1));
      expect(again, contains('api_key = "sk-new"'));

      final live = await service.readLiveState('grok_build');
      expect(live.model, 'deepseek-v4-pro');
      expect(live.hasApiKey, isTrue);
    });

    test('creates [models] section when absent without capturing top-level keys', () {
      final out = GrokTomlEditor.apply('theme = "dark"\n', 'keycore', {'model': 'm'});
      final parsed = GrokTomlEditor.parseSimple(out);
      expect(parsed['']?['theme'], 'dark');
      expect(parsed['models']?['default'], 'keycore');
      expect(parsed['model.keycore']?['model'], 'm');
    });
  });

  group('Backups', () {
    test('restore puts back previous content and is itself reversible', () async {
      final file = File(p.join(home.path, '.claude', 'settings.json'));
      await file.create(recursive: true);
      await file.writeAsString('{"env": {"ANTHROPIC_AUTH_TOKEN": "original"}}');

      await service.switchClaudeCode(_provider());
      final backups = await service.listBackups('claude_code');
      await service.restoreBackup('claude_code', backups.first.path);

      expect(await file.readAsString(), contains('original'));
      // 恢复前的状态也被备份
      expect(await service.listBackups('claude_code'), hasLength(2));
    });

    test('rejects backup paths that do not belong to the tool', () async {
      final other = File(p.join(home.path, 'evil.json'));
      await other.writeAsString('{}');
      expect(
        () => service.restoreBackup('claude_code', other.path),
        throwsArgumentError,
      );
    });
  });

  group('ProviderManagerService.toDbMap', () {
    test('serializes lists as JSON and never stores plaintext api_key column', () {
      final map = ProviderManagerService.toDbMap(_provider(), storedApiKey: '{"data":"x","iv":"y"}');
      expect(map.containsKey('api_key'), isFalse);
      expect(map['api_key_encrypted'], '{"data":"x","iv":"y"}');
      expect(map['models'], isA<String>());
      expect(map['supported_tools'], isA<String>());
      expect(json.decode(map['supported_tools'] as String), contains('claude_code'));
    });
  });
}
