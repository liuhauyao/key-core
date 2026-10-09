import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/services/ai_tool_config_service.dart';
import 'package:key_core/services/openclaw_config_service.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late OpenClawConfigService service;
  late AiToolConfigService toolConfigService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openclaw_test_');
    LiveConfigWriter.debugBackupRootOverride = '${tempDir.path}/.backups';
    SharedPreferences.setMockInitialValues({});
    toolConfigService = AiToolConfigService();
    await toolConfigService.setConfigDir(AiToolType.openclaw, tempDir.path);
    service = OpenClawConfigService();
  });

  tearDown(() async {
    LiveConfigWriter.debugBackupRootOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JSON5 解析', () {
    test('readConfig 支持注释与尾随逗号', () async {
      final configFile = File('${tempDir.path}/openclaw.json');
      await configFile.writeAsString('''
{
  // gateway port
  "gateway": { "port": 18789 },
  "agents": {
    "defaults": {
      "model": { "primary": "deepseek/deepseek-chat" },
    },
  },
}
''');

      final config = await service.readConfig();
      expect(config['gateway']?['port'], 18789);
      expect(
        config['agents']?['defaults']?['model']?['primary'],
        'deepseek/deepseek-chat',
      );
    });
  });

  group('LiveConfigWriter 安全写入', () {
    test('openclaw.json 无法解析时中止，openclaw.json 与 .env 都不被修改', () async {
      final configFile = File('${tempDir.path}/openclaw.json');
      final envFile = File('${tempDir.path}/.env');
      const broken = '{\n  // gateway\n  "gateway": { "port": 18789 \n';
      await configFile.writeAsString(broken);
      await envFile.writeAsString('# mine\nOTHER=1\n');

      await expectLater(
        service.applyProviderKey(
          keyId: 9,
          decryptedKey: 'sk-should-not-be-written',
          platformId: 'deepSeek',
        ),
        throwsA(isA<LiveConfigParseException>()),
      );
      expect(await configFile.readAsString(), broken);
      expect(await envFile.readAsString(), '# mine\nOTHER=1\n');
    });

    test('写入后 .env 为 0600，并保留注释与其他变量', () async {
      final envFile = File('${tempDir.path}/.env');
      await envFile.writeAsString('# mine\nOTHER=1\n');
      await service.applyProviderKey(keyId: 1, decryptedKey: 'sk-1', platformId: 'deepSeek');
      expect(await envFile.readAsString(), '# mine\nOTHER=1\nDEEPSEEK_API_KEY=sk-1\n');
      if (!Platform.isWindows) {
        expect((await envFile.stat()).mode & 0x1FF, 0x180);
      }
    });

    test('JSON5 配置被修改时保留未知字段（注释由首写备份保存）', () async {
      final configFile = File('${tempDir.path}/openclaw.json');
      const original = '{\n  // keep me\n  "gateway": { "port": 18789 },\n  "custom": [1, 2,],\n}\n';
      await configFile.writeAsString(original);
      await service.removeCustomProvider('nothing');
      // 无实际改动 → 不写盘
      expect(await configFile.readAsString(), original);

      await service.applyProviderKey(keyId: 1, decryptedKey: 'sk-1', platformId: 'deepSeek');
      final config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      expect(config['gateway'], {'port': 18789});
      expect(config['custom'], [1, 2]);
      final first = await LiveConfigWriter.instance
          .firstWriteBackupPath(AiToolType.openclaw, configFile.path);
      expect(await File(first).readAsString(), original);
    });
  });

  group('applyProviderKey / removeProviderKey', () {
    test('写入结构符合 OpenClaw models.providers + auth.profiles 规范', () async {
      final result = await service.applyProviderKey(
        keyId: 1,
        decryptedKey: 'sk-test-deepseek',
        platformId: 'deepSeek',
        openclawModel: 'deepseek-chat',
      );

      final config = await service.readConfig();
      expect(config['models']?['mode'], 'merge');
      expect(result.modelRef, 'deepseek/deepseek-chat');
      expect(result.allowlistUpdated, isTrue);
      expect(result.primaryModelSet, isTrue);

      final provider = config['models']?['providers']?['deepseek']
          as Map<String, dynamic>?;
      expect(provider, isNotNull);
      expect(provider!['baseUrl'], 'https://api.deepseek.com/v1');
      expect(provider['api'], 'openai-completions');

      final models = provider['models'] as List<dynamic>;
      expect(models, hasLength(1));
      expect(models.first['id'], 'deepseek-chat');
      expect(models.first['contextWindow'], isA<int>());
      expect(models.first['maxTokens'], isA<int>());
      expect(models.first['cost'], isA<Map>());

      final profile = config['auth']?['profiles']?['deepseek:default']
          as Map<String, dynamic>?;
      expect(profile?['provider'], 'deepseek');
      expect(profile?['mode'], 'api_key');

      final allowlist = config['agents']?['defaults']?['models']
          as Map<String, dynamic>?;
      expect(allowlist?['deepseek/deepseek-chat'], isNotNull);
      expect(
        config['agents']?['defaults']?['model']?['primary'],
        'deepseek/deepseek-chat',
      );

      final env = await service.readEnv();
      expect(env['DEEPSEEK_API_KEY'], 'sk-test-deepseek');

      final applied = await service.getAppliedKeyIds();
      expect(applied['DEEPSEEK_API_KEY'], 1);
    });

    test('自定义 baseUrl 与未知 model id 可写入最小模型定义', () async {
      await service.applyProviderKey(
        keyId: 2,
        decryptedKey: 'sk-custom',
        platformId: 'deepSeek',
        openclawBaseUrl: 'https://proxy.example.com/v1',
        openclawModel: 'custom-model-id',
      );

      final config = await service.readConfig();
      final provider = config['models']?['providers']?['deepseek']
          as Map<String, dynamic>?;
      expect(provider?['baseUrl'], 'https://proxy.example.com/v1');
      final model = (provider?['models'] as List).first as Map;
      expect(model['id'], 'custom-model-id');
      expect(model['name'], 'custom-model-id');
      expect(model['contextWindow'], 131072);
    });

    test('removeProviderKey 清除 env、auth profile 与 provider 条目', () async {
      await service.applyProviderKey(
        keyId: 3,
        decryptedKey: 'sk-remove-me',
        platformId: 'kimi',
        openclawModel: 'kimi-k2.5',
      );
      await service.removeProviderKey(platformId: 'kimi');

      final config = await service.readConfig();
      expect(config['models']?['providers']?['moonshot'], isNull);
      expect(config['auth']?['profiles']?['moonshot:default'], isNull);

      final env = await service.readEnv();
      expect(env.containsKey('MOONSHOT_API_KEY'), isFalse);

      final applied = await service.getAppliedKeyIds();
      expect(applied.containsKey('MOONSHOT_API_KEY'), isFalse);
    });

    test('writeConfig merge 保留未修改字段', () async {
      final configFile = File('${tempDir.path}/openclaw.json');
      await configFile.writeAsString(jsonEncode({
        'gateway': {'port': 19999},
        'channels': {'telegram': {'enabled': true}},
      }));

      await service.applyProviderKey(
        keyId: 4,
        decryptedKey: 'sk-merge',
        platformId: 'zai',
        openclawModel: 'glm-5',
      );

      final config = await service.readConfig();
      expect(config['gateway']?['port'], 19999);
      expect(config['channels']?['telegram']?['enabled'], isTrue);
      expect(config['models']?['providers']?['zai'], isNotNull);
    });
  });

  group('Anthropic / MiniMax 特殊 API 类型', () {
    test('anthropic 使用 anthropic-messages', () async {
      await service.applyProviderKey(
        keyId: 5,
        decryptedKey: 'sk-ant',
        platformId: 'anthropic',
        openclawModel: 'claude-opus-4-6',
      );
      final provider = (await service.readConfig())['models']?['providers']
          ?['anthropic'] as Map<String, dynamic>?;
      expect(provider?['api'], 'anthropic-messages');
      expect(provider?['baseUrl'], 'https://api.anthropic.com');
    });

    test('开启密钥时覆盖已有 primary 并保留 fallbacks', () async {
      final configFile = File('${tempDir.path}/openclaw.json');
      await configFile.writeAsString(jsonEncode({
        'agents': {
          'defaults': {
            'model': {
              'primary': 'anthropic/claude-opus-4-6',
              'fallbacks': ['openai/gpt-4.1'],
            },
          },
        },
      }));

      final result = await service.applyProviderKey(
        keyId: 7,
        decryptedKey: 'sk-ds',
        platformId: 'deepSeek',
        openclawModel: 'deepseek-chat',
      );

      final config = await service.readConfig();
      expect(result.primaryModelSet, isTrue);
      expect(result.allowlistUpdated, isTrue);
      expect(
        config['agents']?['defaults']?['model']?['primary'],
        'deepseek/deepseek-chat',
      );
      expect(
        config['agents']?['defaults']?['model']?['fallbacks'],
        ['openai/gpt-4.1'],
      );
      expect(
        config['agents']?['defaults']?['models']?['deepseek/deepseek-chat'],
        isNotNull,
      );
    });

    test('anthropic-messages 自动去除 baseUrl 的 /v1 后缀', () async {
      await service.applyProviderKey(
        keyId: 8,
        decryptedKey: 'sk-ant',
        platformId: 'anthropic',
        openclawBaseUrl: 'https://api.anthropic.com/v1',
        openclawModel: 'claude-opus-4-6',
      );

      final provider = (await service.readConfig())['models']?['providers']
          ?['anthropic'] as Map<String, dynamic>?;
      expect(provider?['baseUrl'], 'https://api.anthropic.com');
    });

    test('minimax 使用 anthropic-messages 兼容端点', () async {
      await service.applyProviderKey(
        keyId: 6,
        decryptedKey: 'sk-mm',
        platformId: 'minimax',
        openclawModel: 'MiniMax-M2.7',
      );
      final provider = (await service.readConfig())['models']?['providers']
          ?['minimax'] as Map<String, dynamic>?;
      expect(provider?['api'], 'anthropic-messages');
      expect(provider?['baseUrl'], 'https://api.minimax.io/anthropic');
    });
  });

  group('platformMapping 覆盖与模型 schema', () {
    test('17 个平台均在 platformMapping 中', () {
      expect(OpenClawConfigService.platformMapping.length, 17);
    });

    test('每个模型定义包含 OpenClaw 必需字段', () {
      for (final entry in OpenClawConfigService.platformMapping.entries) {
        for (final model in entry.value.models) {
          final json = model.toJson();
          expect(json['id'], isNotEmpty, reason: '${entry.key} model id');
          expect(json['name'], isNotEmpty, reason: '${entry.key} model name');
          expect(json['input'], isA<List>(), reason: '${entry.key} input');
          expect(json['cost'], isA<Map>(), reason: '${entry.key} cost');
          expect(json['contextWindow'], isA<int>());
          expect(json['maxTokens'], isA<int>());
        }
      }
    });

    test('provider id 与 envKey 唯一且非空', () {
      final envKeys = <String>{};
      for (final info in OpenClawConfigService.platformMapping.values) {
        expect(info.openclawProviderId, isNotEmpty);
        expect(info.envKey, isNotEmpty);
        expect(envKeys.add(info.envKey), isTrue,
            reason: 'duplicate envKey ${info.envKey}');
      }
    });
  });
}
