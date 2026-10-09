import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/claude_config_service.dart';
import 'package:key_core/services/claude_desktop_config_service.dart';
import 'package:key_core/services/codex_config_service.dart';
import 'package:key_core/services/gemini_config_service.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';
import 'package:key_core/services/mcp_sync_service.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 各配置服务经 LiveConfigWriter 写入真实格式文件的行为测试。
/// 所有路径都指向临时目录（自定义配置目录 + 覆盖 HOME），不会触碰真实用户配置。

AIKey _key({
  String keyValue = 'sk-new',
  String? claudeBaseUrl,
  String? claudeModel,
  String? desktopBaseUrl,
}) {
  final now = DateTime(2026, 1, 1);
  return AIKey(
    name: 'test',
    platform: 'Anthropic',
    platformType: PlatformType.anthropic,
    keyValue: keyValue,
    tags: const [],
    createdAt: now,
    updatedAt: now,
    enableClaudeCode: true,
    claudeCodeBaseUrl: claudeBaseUrl,
    claudeCodeModel: claudeModel,
    claudeDesktopBaseUrl: desktopBaseUrl,
  );
}

int _mode(String path) => File(path).statSync().mode & 0x1FF;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String home;
  late String claudeDir;
  late String geminiDir;
  late String desktopDir;
  late String cursorDir;
  late String codexDir;

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('live_services_test_');
    home = p.join(tmp.path, 'home');
    claudeDir = p.join(home, '.claude');
    geminiDir = p.join(home, '.gemini');
    desktopDir = p.join(home, '.config', 'Claude');
    cursorDir = p.join(home, '.cursor');
    codexDir = p.join(home, '.codex');
    for (final d in [claudeDir, geminiDir, desktopDir, cursorDir, codexDir]) {
      Directory(d).createSync(recursive: true);
    }

    SharedPreferences.setMockInitialValues({
      'claude_config_dir': claudeDir,
      'gemini_config_dir': geminiDir,
      'claude_desktop_config_dir': desktopDir,
      'ai_tool_config_dir_cursor': cursorDir,
      'ai_tool_config_dir_codex': codexDir,
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

  group('ClaudeConfigService', () {
    const settingsFixture = '{\n'
        '  "permissions": {\n    "allow": [\n      "Bash(npm test)"\n    ]\n  },\n'
        '  "env": {\n'
        '    "DISABLE_TELEMETRY": "1",\n'
        '    "ANTHROPIC_AUTH_TOKEN": "sk-old",\n'
        '    "ANTHROPIC_API_KEY": "sk-stale",\n'
        '    "ANTHROPIC_SMALL_FAST_MODEL": "old-haiku",\n'
        '    "CLAUDE_CODE_USE_BEDROCK": "1",\n'
        '    "ANTHROPIC_MODEL": "old-model",\n'
        '    "HTTPS_PROXY": "http://127.0.0.1:7890"\n'
        '  },\n'
        '  "hooks": {},\n'
        '  "model": "opus"\n'
        '}\n';

    test('switchProvider replaces only key fields and preserves everything else', () async {
      final settingsPath = p.join(claudeDir, 'settings.json');
      final configPath = p.join(claudeDir, 'config.json');
      File(settingsPath).writeAsStringSync(settingsFixture);
      File(configPath).writeAsStringSync('{\n  "theme": "dark",\n  "primaryApiKey": "sk-old"\n}\n');

      final ok = await ClaudeConfigService()
          .switchProvider(_key(claudeBaseUrl: 'https://proxy.example/api', claudeModel: 'm1'));
      expect(ok, isTrue);

      final settings = readJson(settingsPath);
      expect(settings.keys.toList(), ['permissions', 'env', 'hooks', 'model']);
      expect(settings['permissions'], {
        'allow': ['Bash(npm test)']
      });
      final env = settings['env'] as Map;
      expect(env, {
        'DISABLE_TELEMETRY': '1',
        'ANTHROPIC_AUTH_TOKEN': 'sk-new',
        'HTTPS_PROXY': 'http://127.0.0.1:7890',
        'ANTHROPIC_BASE_URL': 'https://proxy.example/api',
        'ANTHROPIC_MODEL': 'm1',
      });
      expect(env.keys.toList().sublist(0, 3), ['DISABLE_TELEMETRY', 'ANTHROPIC_AUTH_TOKEN', 'HTTPS_PROXY']);
      expect(File(settingsPath).readAsStringSync().endsWith('}\n'), isTrue);

      expect(readJson(configPath), {'theme': 'dark', 'primaryApiKey': 'sk-new'});
      if (!Platform.isWindows) {
        expect(_mode(settingsPath), 0x180);
        expect(_mode(configPath), 0x180);
      }

      // 首写备份保留了切换前的原文件
      final first = await LiveConfigWriter.instance.firstWriteBackupPath(AiToolType.claudecode, settingsPath);
      expect(File(first).readAsStringSync(), settingsFixture);
      // 不再生成旧的单份 .bak 文件
      expect(Directory(claudeDir).listSync().map((e) => p.basename(e.path)).where((n) => n.contains('.bak')),
          isEmpty);
    });

    test('unparsable settings.json aborts both files', () async {
      final settingsPath = p.join(claudeDir, 'settings.json');
      final configPath = p.join(claudeDir, 'config.json');
      const broken = '{\n  "env": {\n    "ANTHROPIC_AUTH_TOKEN": "sk-old",\n  }\n  // comment\n}';
      File(settingsPath).writeAsStringSync(broken);
      File(configPath).writeAsStringSync('{"primaryApiKey": "sk-old"}');

      expect(await ClaudeConfigService().switchProvider(_key()), isFalse);
      expect(File(settingsPath).readAsStringSync(), broken);
      expect(File(configPath).readAsStringSync(), '{"primaryApiKey": "sk-old"}');
    });

    test('switchToOfficial uses the keychain-stored official key and keeps custom env', () async {
      final settingsPath = p.join(claudeDir, 'settings.json');
      final configPath = p.join(claudeDir, 'config.json');
      File(settingsPath).writeAsStringSync(
          '{"env": {"HTTPS_PROXY": "p", "ANTHROPIC_AUTH_TOKEN": "sk-3p", "ANTHROPIC_BASE_URL": "u", "ANTHROPIC_MODEL": "m"}}');
      File(configPath).writeAsStringSync('{"primaryApiKey": "sk-3p"}');

      final settingsService = SettingsService();
      await settingsService.init();
      await settingsService.setOfficialClaudeApiKey('sk-official');

      expect(await ClaudeConfigService().switchToOfficial(), isTrue);
      expect(readJson(settingsPath)['env'], {'HTTPS_PROXY': 'p', 'ANTHROPIC_AUTH_TOKEN': 'sk-official'});
      expect(readJson(configPath), {'primaryApiKey': 'sk-official'});
    });

    test('switchToOfficial without an official key removes the third-party key', () async {
      final settingsPath = p.join(claudeDir, 'settings.json');
      final configPath = p.join(claudeDir, 'config.json');
      File(settingsPath).writeAsStringSync('{"env": {"ANTHROPIC_AUTH_TOKEN": "sk-3p", "KEEP": "1"}}');
      File(configPath).writeAsStringSync('{"primaryApiKey": "sk-3p", "other": true}');

      expect(await ClaudeConfigService().switchToOfficial(), isTrue);
      expect(readJson(settingsPath)['env'], {'KEEP': '1'});
      expect(readJson(configPath), {'other': true});
    });

    test('updateOfficialConfigEnv stores the key in the keychain and edits only custom env', () async {
      final settingsPath = p.join(claudeDir, 'settings.json');
      File(settingsPath).writeAsStringSync(
          '{"env": {"ANTHROPIC_BASE_URL": "u", "OLD_CUSTOM": "x", "KEEP": "1"}, "model": "opus"}');

      final ok = await ClaudeConfigService().updateOfficialConfigEnv({
        'ANTHROPIC_AUTH_TOKEN': 'sk-official',
        'KEEP': '2',
        'NEW': 'n',
      });
      expect(ok, isTrue);
      expect(readJson(settingsPath), {
        'env': {'ANTHROPIC_BASE_URL': 'u', 'KEEP': '2', 'NEW': 'n'},
        'model': 'opus',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('official_claude_api_key'), isNull);
      expect(await const FlutterSecureStorage().read(key: 'official_api_key.claude'), 'sk-official');
    });
  });

  group('GeminiConfigService', () {
    test('switchProvider patches .env in place and keeps settings.json fields', () async {
      final envPath = p.join(geminiDir, '.env');
      final settingsPath = p.join(geminiDir, 'settings.json');
      File(envPath).writeAsStringSync(
          '# my gemini env\nZZZ=last-alpha\nGEMINI_API_KEY=old\nGEMINI_BASE_URL=https://proxy\nAAA=first-alpha\nGEMINI_MODEL=x\n');
      File(settingsPath).writeAsStringSync(
          '{\n  "theme": "GitHub",\n  "mcpServers": {\n    "fs": {\n      "command": "npx"\n    }\n  },\n  "apiKey": "leak"\n}\n');

      expect(await GeminiConfigService().switchProvider(_key(keyValue: 'AIza-new')), isTrue);

      expect(File(envPath).readAsStringSync(),
          '# my gemini env\nZZZ=last-alpha\nGEMINI_API_KEY=AIza-new\nAAA=first-alpha\n');
      expect(readJson(settingsPath), {
        'theme': 'GitHub',
        'mcpServers': {
          'fs': {'command': 'npx'}
        },
        'apiKey': '',
      });
      if (!Platform.isWindows) expect(_mode(envPath), 0x180);
    });

    test('unparsable settings.json aborts and leaves .env untouched', () async {
      final envPath = p.join(geminiDir, '.env');
      final settingsPath = p.join(geminiDir, 'settings.json');
      File(envPath).writeAsStringSync('GEMINI_API_KEY=old\n');
      File(settingsPath).writeAsStringSync('{"theme": "GitHub",}');

      expect(await GeminiConfigService().switchProvider(_key(keyValue: 'new')), isFalse);
      expect(File(envPath).readAsStringSync(), 'GEMINI_API_KEY=old\n');
      expect(File(settingsPath).readAsStringSync(), '{"theme": "GitHub",}');
    });

    test('switchToOfficial writes the official key or removes the third-party key', () async {
      final envPath = p.join(geminiDir, '.env');
      File(p.join(geminiDir, 'settings.json')).writeAsStringSync('{}');
      File(envPath).writeAsStringSync('A=1\nGEMINI_API_KEY=3p\nGEMINI_MODEL=m\n');

      expect(await GeminiConfigService().switchToOfficial(), isTrue);
      expect(File(envPath).readAsStringSync(), 'A=1\n');

      final settings = SettingsService();
      await settings.init();
      await settings.setOfficialGeminiApiKey('AIza-official');
      expect(await GeminiConfigService().switchToOfficial(), isTrue);
      expect(File(envPath).readAsStringSync(), 'A=1\nGEMINI_API_KEY=AIza-official\n');
    });

    test('writeEnv keeps comments and order of existing lines', () async {
      final envPath = p.join(geminiDir, '.env');
      File(envPath).writeAsStringSync('# c\nB=1\nA=2\nDROP=x\n');
      expect(await GeminiConfigService().writeEnv({'B': '1', 'A': '3', 'C': '4'}), isTrue);
      expect(File(envPath).readAsStringSync(), '# c\nB=1\nA=3\nC=4\n');
    });
  });

  group('ClaudeDesktopConfigService', () {
    late String libraryDir;
    setUp(() {
      // Linux 下 3p 目录位于 ~/.config/Claude-3p/configLibrary
      libraryDir = p.join(home, '.config', 'Claude-3p', 'configLibrary');
    });

    test('switchProvider writes 3p mode, profile (0600) and meta; keeps other config keys', () async {
      final configPath = p.join(desktopDir, 'claude_desktop_config.json');
      File(configPath).writeAsStringSync(
          '{\n  "mcpServers": {\n    "fs": {\n      "command": "npx"\n    },\n    "key-core-env": {\n      "command": "x"\n    }\n  },\n  "globalShortcut": "Alt+Space"\n}\n');

      final ok = await ClaudeDesktopConfigService()
          .switchProvider(_key(keyValue: 'sk-desk', desktopBaseUrl: 'https://gw.example'));
      expect(ok, isTrue);

      final config = readJson(configPath);
      expect(config['mcpServers'], {
        'fs': {'command': 'npx'}
      });
      expect(config['globalShortcut'], 'Alt+Space');
      expect(config['deploymentMode'], '3p');
      expect(config['configLibraryReference'], isA<Map>());
      expect(readJson(p.join(libraryDir, 'claude_desktop_config.json')), config);

      final profileFile = Directory(libraryDir)
          .listSync()
          .whereType<File>()
          .where((f) => readJson(f.path).containsKey('inferenceGatewayApiKey'))
          .single;
      final profile = readJson(profileFile.path);
      expect(profile['inferenceGatewayApiKey'], 'sk-desk');
      expect(profile['inferenceGatewayBaseUrl'], 'https://gw.example');
      if (!Platform.isWindows) expect(_mode(profileFile.path), 0x180);

      final meta = readJson(p.join(libraryDir, 'meta.json'));
      expect(meta['appliedId'], (config['configLibraryReference'] as Map)['id']);
      // _meta.json 不存在时不会被创建（沿用既有行为，见 PR 待确认事项）
      expect(File(p.join(libraryDir, '_meta.json')).existsSync(), isFalse);
    });

    test('unparsable main config aborts the whole switch', () async {
      final configPath = p.join(desktopDir, 'claude_desktop_config.json');
      File(configPath).writeAsStringSync('{"mcpServers": {"fs": {}},}');
      expect(await ClaudeDesktopConfigService().switchProvider(_key()), isFalse);
      expect(File(configPath).readAsStringSync(), '{"mcpServers": {"fs": {}},}');
      expect(Directory(libraryDir).existsSync(), isFalse);
    });

    test('switchToOfficial restores 1p, deletes profile and keeps other meta entries', () async {
      final configPath = p.join(desktopDir, 'claude_desktop_config.json');
      File(configPath).writeAsStringSync('{"globalShortcut": "Alt+Space"}');
      final service = ClaudeDesktopConfigService();
      expect(await service.switchProvider(_key()), isTrue);

      final metaPath = p.join(libraryDir, 'meta.json');
      final meta = readJson(metaPath);
      (meta['entries'] as List).add({'id': 'other-profile', 'name': 'Other'});
      File(metaPath).writeAsStringSync(jsonEncode(meta));

      expect(await ClaudeDesktopConfigService().switchToOfficial(), isTrue);
      expect(readJson(configPath), {'globalShortcut': 'Alt+Space', 'deploymentMode': '1p'});
      expect(readJson(metaPath), {
        'entries': [
          {'id': 'other-profile', 'name': 'Other'}
        ]
      });
      final remaining = Directory(libraryDir).listSync().map((e) => p.basename(e.path)).toList();
      expect(remaining, ['meta.json']);
    });
  });

  group('CodexConfigService (auth.json + config.toml)', () {
    const userToml = '# my codex config\n'
        'model_provider = "old"\n'
        'model = "gpt-old"\n'
        'model_reasoning_effort = "high"\n'
        'disable_response_storage = true\n'
        '\n'
        '[model_providers.old]\n'
        'name = "old"\n'
        'base_url = "https://old.example/v1"\n'
        'wire_api = "chat"\n'
        '\n'
        '[mcp_servers.fs]\n'
        'command = "npx"\n'
        'args = ["-y", "@modelcontextprotocol/server-filesystem"]\n'
        '\n'
        '[projects."/Users/me/repo"]\n'
        'trust_level = "trusted"\n';

    const ourBlock = 'model_provider = "keycore"\n'
        'model = "gpt-5"\n'
        'model_reasoning_effort = "high"\n'
        'disable_response_storage = true\n'
        '\n'
        '[model_providers.keycore]\n'
        'name = "keycore"\n'
        'base_url = "https://new.example/v1"\n'
        'wire_api = "chat"\n';

    test('mergeConfigToml replaces our block and keeps user tables', () {
      final merged = CodexConfigService.mergeConfigToml(userToml, ourBlock);
      expect(merged.startsWith(ourBlock), isTrue);
      expect(merged, contains('[mcp_servers.fs]\ncommand = "npx"'));
      expect(merged, contains('[projects."/Users/me/repo"]\ntrust_level = "trusted"'));
      expect(merged, isNot(contains('old.example')));
      expect(merged, isNot(contains('[model_providers.old]')));
      expect(RegExp(r'^model_provider = ', multiLine: true).allMatches(merged), hasLength(1));
    });

    test('cleanConfigTomlForOfficial keeps user tables and empties a file with only our config', () {
      final cleaned = CodexConfigService.cleanConfigTomlForOfficial(userToml);
      expect(cleaned, contains('[mcp_servers.fs]'));
      expect(cleaned, isNot(contains('model_provider')));
      expect(CodexConfigService.cleanConfigTomlForOfficial(ourBlock), '');
    });

    test('applyProviderToAuth sets the provider key and keeps other auth fields', () {
      final auth = <String, dynamic>{'tokens': {'id_token': 'x'}, 'OPENAI_API_KEY': 'old'};
      CodexConfigService.applyProviderToAuth(auth, apiKey: 'sk-new', authJsonKey: 'OPENAI_API_KEY');
      expect(auth, {'tokens': {'id_token': 'x'}, 'OPENAI_API_KEY': 'sk-new'});

      final envOnly = <String, dynamic>{'OPENAI_API_KEY': 'old', 'GLM_API_KEY': 'g', 'last_refresh': 't'};
      CodexConfigService.applyProviderToAuth(envOnly, apiKey: 'sk-new', authJsonKey: null);
      expect(envOnly, {'last_refresh': 't'});
    });

    test('auth.json + config.toml are one operation: bad auth.json leaves config.toml untouched', () async {
      final authPath = p.join(codexDir, 'auth.json');
      final tomlPath = p.join(codexDir, 'config.toml');
      File(authPath).writeAsStringSync('{"OPENAI_API_KEY": "old",');
      File(tomlPath).writeAsStringSync(userToml);

      await expectLater(
        LiveConfigWriter.instance.apply(AiToolType.codex, [
          LiveEdit.json(
            authPath,
            (auth) => CodexConfigService.applyProviderToAuth(auth, apiKey: 'sk', authJsonKey: 'OPENAI_API_KEY'),
            containsSecrets: true,
          ),
          LiveEdit.text(tomlPath, (c) => CodexConfigService.mergeConfigToml(c, ourBlock)),
        ]),
        throwsA(isA<LiveConfigParseException>()),
      );
      expect(File(tomlPath).readAsStringSync(), userToml);
      expect(File(authPath).readAsStringSync(), '{"OPENAI_API_KEY": "old",');
    });
  });

  group('McpSyncService', () {
    test('deleting a server from ~/.claude.json keeps all other Claude Code state', () async {
      final path = p.join(home, '.claude.json');
      const original = '{\n'
          '  "numStartups": 42,\n'
          '  "oauthAccount": {\n    "emailAddress": "me@example.com"\n  },\n'
          '  "mcpServers": {\n    "a": {\n      "command": "x"\n    },\n    "b": {\n      "command": "y"\n    }\n  },\n'
          '  "projects": {\n    "/repo": {\n      "allowedTools": []\n    }\n  }\n'
          '}\n';
      File(path).writeAsStringSync(original);

      expect(await McpSyncService().deleteFromTool(AiToolType.claudecode, {'a'}), isTrue);

      final doc = readJson(path);
      expect(doc.keys.toList(), ['numStartups', 'oauthAccount', 'mcpServers', 'projects']);
      expect(doc['mcpServers'], {
        'b': {'command': 'y'}
      });
      expect(doc['oauthAccount'], {'emailAddress': 'me@example.com'});
      expect(File('$path.backup').existsSync(), isFalse);
    });

    test('unparsable ~/.claude.json is never replaced by an empty object', () async {
      final path = p.join(home, '.claude.json');
      const broken = '{"numStartups": 42, "mcpServers": {"a": {}}';
      File(path).writeAsStringSync(broken);
      expect(await McpSyncService().deleteFromTool(AiToolType.claudecode, {'a'}), isFalse);
      expect(File(path).readAsStringSync(), broken);
    });

    test('cursor mcp.json delete keeps other servers and top-level keys', () async {
      final path = p.join(cursorDir, 'mcp.json');
      File(path).writeAsStringSync('{"mcpServers": {"a": {}, "b": {}}, "other": 1}');
      expect(await McpSyncService().deleteFromTool(AiToolType.cursor, {'a'}), isTrue);
      expect(readJson(path), {
        'mcpServers': {'b': {}},
        'other': 1,
      });
    });

    test('codex TOML delete removes only that server and keeps the provider config', () async {
      final path = p.join(codexDir, 'config.toml');
      const toml = 'model_provider = "keycore"\n'
          'model = "gpt-5"\n'
          '\n'
          '[model_providers.keycore]\n'
          'name = "keycore"\n'
          'base_url = "https://new.example/v1"\n'
          '\n'
          '[mcp_servers.a]\n'
          'command = "x"\n'
          '\n'
          '[mcp_servers.b]\n'
          'command = "y"\n';
      File(path).writeAsStringSync(toml);

      expect(await McpSyncService().deleteFromTool(AiToolType.codex, {'a'}), isTrue);
      final out = File(path).readAsStringSync();
      expect(out, contains('model_provider = "keycore"'));
      expect(out, contains('[model_providers.keycore]'));
      expect(out, contains('[mcp_servers.b]'));
      expect(out, isNot(contains('[mcp_servers.a]')));
      final first = await LiveConfigWriter.instance.firstWriteBackupPath(AiToolType.codex, path);
      expect(File(first).readAsStringSync(), toml);
    });
  });
}
