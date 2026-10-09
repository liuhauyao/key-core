import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/config/provider_config.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/cloud_config.dart' hide CodexProviderConfig;
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/models/unified_provider_config.dart';
import 'package:key_core/services/claude_config_service.dart';
import 'package:key_core/services/codex_config_service.dart';
import 'package:key_core/services/gemini_config_service.dart';
import 'package:key_core/services/openclaw_config_service.dart';
import 'package:key_core/services/region_filter_service.dart';

Map<String, dynamic> _appConfig() =>
    jsonDecode(File('assets/config/app_config.json').readAsStringSync()) as Map<String, dynamic>;

AIKey _key({
  String name = 'k',
  PlatformType platform = PlatformType.custom,
  String? claudeBaseUrl,
  String? codexBaseUrl,
  String? codexModel,
  String? geminiBaseUrl,
  String? geminiModel,
  Map<String, dynamic>? codexConfig,
  Map<String, dynamic>? claudeCodeConfig,
}) {
  final now = DateTime(2026, 1, 1);
  return AIKey(
    name: name,
    platform: platform.value,
    platformType: platform,
    keyValue: 'sk-x',
    tags: const [],
    createdAt: now,
    updatedAt: now,
    claudeCodeBaseUrl: claudeBaseUrl,
    codexBaseUrl: codexBaseUrl,
    codexModel: codexModel,
    geminiBaseUrl: geminiBaseUrl,
    geminiModel: geminiModel,
    codexConfig: codexConfig,
    claudeCodeConfig: claudeCodeConfig,
  );
}

void main() {
  group('app_config.json presets', () {
    final json = _appConfig();
    final data = CloudConfigData.fromJson(json['config'] as Map<String, dynamic>);
    final presets = data.providers;

    test('parses and contains the CC Switch v4.0.6 vendors', () {
      expect(presets.length, greaterThanOrEqualTo(130));
      final ids = presets.map((p) => p.id).toSet();
      expect(ids, containsAll(['deepSeek', 'zhipu', 'kimi', 'minimax', 'openRouter', 'siliconFlow']));
    });

    test('ids and platformTypes are unique', () {
      final ids = presets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      final types = presets.map((p) => p.platformType).toList();
      expect(types.toSet().length, types.length);
    });

    test('all tool endpoints are https URLs', () {
      for (final p in presets) {
        for (final url in [
          p.claudeCode?.baseUrl,
          p.codex?.baseUrl,
          p.gemini?.baseUrl,
          p.openclaw?.baseUrl,
          p.claudeDesktop?.baseUrl,
        ].whereType<String>()) {
          final uri = Uri.parse(url.replaceAll(RegExp(r'\{[A-Z_]+\}'), 'x'));
          // 本地服务（Ollama / LM Studio 等）允许 http
          final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
          expect(uri.scheme, local ? anyOf('http', 'https') : 'https', reason: '${p.id}: $url');
          expect(uri.host, isNotEmpty, reason: '${p.id}: $url');
        }
      }
    });

    test('no new preset is hit by the China compliance filter', () {
      final restricted = presets
          .where((p) => RegionFilterService.isKeyRestrictedInChina(
                platformId: p.platformType,
                platformName: p.name,
                codexBaseUrl: p.codex?.baseUrl,
                claudeCodeBaseUrl: p.claudeCode?.baseUrl,
              ))
          .map((p) => p.id)
          .toSet();
      // 仅原有的 OpenAI / Azure OpenAI 预设命中（运行时按设置过滤），新增预设不得命中
      expect(restricted.difference({'openAI', 'azureOpenAI'}), isEmpty);
    });

    test('preset icons exist in assets/icons/platforms', () {
      for (final p in presets) {
        final icon = (json['config']['providers'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((e) => e['id'] == p.id)['icon'];
        if (icon is String && icon.isNotEmpty) {
          expect(File('assets/icons/platforms/$icon').existsSync(), isTrue, reason: '${p.id}: $icon');
        }
      }
    });

    test('Claude Desktop direct presets only use claude-* model names', () {
      for (final p in presets.where((p) => p.claudeDesktop != null)) {
        final m = p.claudeDesktop!.modelConfig;
        for (final model in [m.sonnetModel, m.haikuModel, m.opusModel].whereType<String>()) {
          if (model.isEmpty) continue;
          expect(model.toLowerCase(), contains('claude'), reason: p.id);
        }
      }
    });

    test('codexAuthConfig: typo fixed, responses API, bearer token for third parties', () {
      final auth = data.codexAuthConfig;
      expect(auth.defaultRule.envKeyName, 'CODEX_API_KEY');
      expect(auth.defaultRule.wireApi, 'responses');
      expect(auth.defaultRule.keyPlacement, 'bearerToken');
      for (final r in auth.rules) {
        expect(r.wireApi, 'responses', reason: r.platformType);
      }
      expect(auth.rules.firstWhere((r) => r.platformType == 'openAI').keyPlacement, 'authJson');
    });

    test('preset json round-trips new fields', () {
      final withEnv = presets.firstWhere((p) => p.claudeCode?.env?.isNotEmpty ?? false);
      final again = UnifiedProviderConfig.fromJson(jsonDecode(jsonEncode(withEnv.toJson())) as Map<String, dynamic>);
      expect(again.claudeCode!.env, withEnv.claudeCode!.env);
      expect(again.claudeCode!.apiKeyField, withEnv.claudeCode!.apiKeyField);
    });

    test('old clients: CodexAuthRule without keyPlacement derives it from legacy fields', () {
      final r = CodexAuthRule.fromJson({'supportsAuthJson': true, 'requiresOpenaiAuth': true, 'authJsonKey': 'OPENAI_API_KEY'});
      expect(r.keyPlacement, isNull);
      const cfg = CodexProviderConfig(supportsAuthJson: true, requiresOpenaiAuth: true, authJsonKey: 'OPENAI_API_KEY');
      expect(cfg.keyPlacement, 'authJson');
      const env = CodexProviderConfig(supportsAuthJson: false, requiresOpenaiAuth: false, envKeyName: 'X_KEY');
      expect(env.keyPlacement, 'env');
      expect(env.needsEnvVar, isTrue);
    });
  });

  group('Claude Code apiKeyField / extra env', () {
    test('writes the key into apiKeyField and extra env, then cleans up on switch', () {
      final settings = <String, dynamic>{
        'env': {'ANTHROPIC_AUTH_TOKEN': 'old', 'HTTPS_PROXY': 'p'}
      };
      final key = _key(claudeBaseUrl: 'https://x.example/anthropic', claudeCodeConfig: {
        'apiKeyField': 'ANTHROPIC_API_KEY',
        'env': {'AWS_REGION': 'us-west-2', 'ANTHROPIC_AUTH_TOKEN': 'nope'},
      });
      final state = ClaudeConfigService.applyProviderToSettings(settings, key, 'sk-new');
      final env = settings['env'] as Map;
      expect(env['ANTHROPIC_API_KEY'], 'sk-new');
      expect(env.containsKey('ANTHROPIC_AUTH_TOKEN'), isFalse);
      expect(env['AWS_REGION'], 'us-west-2');
      expect(env['HTTPS_PROXY'], 'p');
      expect(state, {
        'apiKeyField': 'ANTHROPIC_API_KEY',
        'extraEnv': {'AWS_REGION': 'us-west-2'},
      });

      // 切到普通供应商：清理上一把的 ANTHROPIC_API_KEY 与未被用户改动的附加 env
      final next = ClaudeConfigService.applyProviderToSettings(
          settings, _key(claudeBaseUrl: 'https://y.example'), 'sk-y',
          previous: state);
      expect(env['ANTHROPIC_AUTH_TOKEN'], 'sk-y');
      expect(env.containsKey('ANTHROPIC_API_KEY'), isFalse);
      expect(env.containsKey('AWS_REGION'), isFalse);
      expect(next, isEmpty);
    });

    test('user-modified extra env survives switching away', () {
      final settings = <String, dynamic>{'env': <String, dynamic>{}};
      final key = _key(claudeCodeConfig: {
        'env': {'CLAUDE_CODE_MAX_OUTPUT_TOKENS': '32000'}
      });
      final state = ClaudeConfigService.applyProviderToSettings(settings, key, 'a');
      (settings['env'] as Map)['CLAUDE_CODE_MAX_OUTPUT_TOKENS'] = '64000';
      ClaudeConfigService.applyOfficialToSettings(settings, null, previous: state);
      expect((settings['env'] as Map)['CLAUDE_CODE_MAX_OUTPUT_TOKENS'], '64000');
    });

    test('switching to official removes a non-default key field', () {
      final settings = <String, dynamic>{'env': <String, dynamic>{}};
      final state = ClaudeConfigService.applyProviderToSettings(
          settings, _key(claudeCodeConfig: {'apiKeyField': 'AWS_BEARER_TOKEN_BEDROCK'}), 'bedrock');
      expect((settings['env'] as Map)['AWS_BEARER_TOKEN_BEDROCK'], 'bedrock');
      ClaudeConfigService.applyOfficialToSettings(settings, 'sk-official', previous: state);
      expect(settings['env'], {'ANTHROPIC_AUTH_TOKEN': 'sk-official'});
    });

    test('unknown apiKeyField falls back to ANTHROPIC_AUTH_TOKEN', () {
      final settings = <String, dynamic>{};
      ClaudeConfigService.applyProviderToSettings(settings, _key(claudeCodeConfig: {'apiKeyField': 'PATH'}), 'k');
      expect(settings['env'], {'ANTHROPIC_AUTH_TOKEN': 'k'});
    });
  });

  group('Gemini third-party endpoints', () {
    test('providerEnv writes base url and model when set', () {
      expect(
        GeminiConfigService.providerEnv(
            _key(geminiBaseUrl: 'https://g.example', geminiModel: 'gemini-x'), 'AIza'),
        {'GEMINI_API_KEY': 'AIza', 'GOOGLE_GEMINI_BASE_URL': 'https://g.example', 'GEMINI_MODEL': 'gemini-x'},
      );
      expect(GeminiConfigService.providerEnv(_key(), 'AIza'), {'GEMINI_API_KEY': 'AIza'});
    });

    test('settings select api-key auth and keep other fields', () {
      final s = <String, dynamic>{
        'apiKey': 'leak',
        'security': {
          'auth': {'selectedType': 'oauth-personal', 'useExternal': false}
        },
      };
      GeminiConfigService.applyProviderToSettings(s);
      expect(s['apiKey'], '');
      expect(s['security'], {
        'auth': {'selectedType': 'gemini-api-key', 'useExternal': false}
      });
    });
  });

  group('Codex config.toml', () {
    const bearer = CodexProviderConfig(
      supportsAuthJson: false,
      requiresOpenaiAuth: false,
      wireApi: 'responses',
      keyPlacement: 'bearerToken',
    );

    test('bearer token is written into the fixed keycore table', () {
      final toml = CodexConfigService.buildConfigToml(
        _key(name: 'My "Key"', codexBaseUrl: 'https://c.example/v1', codexModel: 'm1',
            codexConfig: {'reasoningEffort': 'medium'}),
        bearer,
        apiKey: 'sk-"quoted"',
      );
      expect(toml, contains('model_provider = "keycore"'));
      expect(toml, contains('model_reasoning_effort = "medium"'));
      expect(toml, contains('[model_providers.keycore]'));
      expect(toml, contains('name = "My \\"Key\\""'));
      expect(toml, contains('wire_api = "responses"'));
      expect(toml, contains('requires_openai_auth = false'));
      expect(toml, contains('experimental_bearer_token = "sk-\\"quoted\\""'));
      expect(toml, isNot(contains('env_key')));
      expect(CodexConfigService.readBearerToken(toml), 'sk-"quoted"');

      final withLogin = CodexConfigService.buildConfigToml(_key(), bearer, apiKey: 'k', loginOnDisk: true);
      expect(withLogin, contains('requires_openai_auth = true'));
    });

    test('key-level overrides win over the rule', () {
      final cfg = bearer.withKeyOverrides({'wireApi': 'chat', 'keyPlacement': 'env'});
      expect(cfg.wireApi, 'chat');
      expect(cfg.keyPlacement, 'env');
      expect(bearer.withKeyOverrides({'keyPlacement': 'bogus'}).keyPlacement, 'bearerToken');
    });

    test('merge keeps user provider tables, user top-level keys and removes legacy keycore tables', () {
      const user = 'approval_policy = "never"\n'
          'model_provider = "my-key"\n'
          'model = "old"\n'
          '\n'
          '[model_providers.my-key]\n'
          'name = "my-key"\n'
          'base_url = "https://legacy.example/v1"\n'
          'wire_api = "chat"\n'
          'requires_openai_auth = false\n'
          '\n'
          '[model_providers.azure]\n'
          'name = "Azure"\n'
          'base_url = "https://x.azure.com"\n'
          'query_params = { api-version = "2025-04-01-preview" }\n'
          'env_key = "AZURE_KEY"\n'
          '\n'
          '[mcp_servers.fs]\n'
          'command = "npx"\n';
      final ours = CodexConfigService.buildConfigToml(
          _key(codexBaseUrl: 'https://new.example/v1'), bearer, apiKey: 'sk-1');
      final merged = CodexConfigService.mergeConfigToml(user, ours);

      // 用户的顶层设置必须仍在第一张表之前（旧实现会把它们挪进我们的 provider 表）
      final firstTable = merged.indexOf('\n[');
      expect(merged.indexOf('approval_policy = "never"'), lessThan(firstTable));
      expect(RegExp(r'^model_provider = ', multiLine: true).allMatches(merged), hasLength(1));
      // 旧版按密钥名生成的表被清理
      expect(merged, isNot(contains('legacy.example')));
      // 用户自己的 provider 表完整保留（旧实现会把 query_params 遗留到上一张表里）
      expect(merged, contains('[model_providers.azure]\nname = "Azure"\nbase_url = "https://x.azure.com"\n'
          'query_params = { api-version = "2025-04-01-preview" }\nenv_key = "AZURE_KEY"'));
      expect(merged, contains('[mcp_servers.fs]\ncommand = "npx"'));

      // 再次切换是幂等的
      final again = CodexConfigService.mergeConfigToml(merged, ours);
      expect(again, merged);

      // 切回官方：只剩用户内容
      final official = CodexConfigService.cleanConfigTomlForOfficial(merged);
      expect(official, isNot(contains('keycore')));
      expect(official, isNot(contains('sk-1')));
      expect(official, contains('approval_policy = "never"'));
      expect(official, contains('[model_providers.azure]'));
    });

    test('table headers inside multi-line strings are not treated as tables', () {
      const user = 'instructions = """\n[not.a.table]\n"""\n\n[mcp_servers.a]\ncommand = "x"\n';
      final merged = CodexConfigService.mergeConfigToml(
          user, CodexConfigService.buildConfigToml(_key(), bearer, apiKey: 'k'));
      expect(merged.indexOf('[not.a.table]'), lessThan(merged.indexOf('[model_providers.keycore]')));
    });
  });

  group('OpenClaw dynamic platform info from presets', () {
    final data = CloudConfigData.fromJson(_appConfig()['config'] as Map<String, dynamic>);
    setUp(() => ProviderConfig.debugSetPresets(data.providers));

    test('every preset with an openclaw block becomes applicable', () {
      final withOpenClaw = data.providers.where((p) => p.openclaw != null).toList();
      expect(withOpenClaw.length, greaterThan(40));
      for (final p in withOpenClaw) {
        final info = OpenClawConfigService.platformInfoFor(p.platformType);
        expect(info, isNotNull, reason: p.id);
        expect(info!.envKey, matches(RegExp(r'^[A-Z0-9_]+$')), reason: p.id);
        if (!OpenClawConfigService.platformMapping.containsKey(p.platformType)) {
          expect(info.envKey, endsWith('_API_KEY'), reason: p.id);
        }
        expect(info.openclawProviderId, matches(RegExp(r'^[a-z0-9-]+$')), reason: p.id);
        expect(info.models, isNotEmpty, reason: p.id);
      }
    });

    test('builtin mapping still wins', () {
      expect(OpenClawConfigService.platformInfoFor('anthropic')!.envKey, 'ANTHROPIC_API_KEY');
      expect(OpenClawConfigService.platformInfoFor('kimi')!.openclawProviderId, 'moonshot');
    });

    test('derived ids are stable', () {
      final info = OpenClawConfigService.platformInfoFromPreset(UnifiedProviderConfig.fromJson({
        'id': 'xiaomiMimoTokenPlanCn',
        'name': 'Xiaomi MiMo',
        'platformType': 'xiaomiMimoTokenPlanCn',
        'categories': ['openclaw'],
        'providerCategory': 'cnOfficial',
        'websiteUrl': 'https://x.example',
        'openclaw': {'baseUrl': 'https://x.example/v1', 'model': 'mimo', 'api': 'anthropic-messages'},
      }))!;
      expect(info.openclawProviderId, 'xiaomi-mimo-token-plan-cn');
      expect(info.envKey, 'XIAOMI_MIMO_TOKEN_PLAN_CN_API_KEY');
      expect(info.apiType, 'anthropic-messages');
      expect(info.models.single.id, 'mimo');
    });
  });
}
