import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/cloud_config.dart';
import 'package:key_core/services/cloud_config_service.dart';
import 'package:key_core/services/region_filter_service.dart';

/// app_config.json 结构校验（相当于一份手写 JSON Schema）。
///
/// 这份文件会被远程下发给所有已安装版本，任何必填字段缺失 / 类型错误都会让
/// 旧版本整份配置解析失败，所以每次改数据都必须过这组测试。
void main() {
  final raw = jsonDecode(File('assets/config/app_config.json').readAsStringSync()) as Map<String, dynamic>;
  final cfg = raw['config'] as Map<String, dynamic>;
  final providers = (cfg['providers'] as List).cast<Map<String, dynamic>>();
  final templates = (cfg['mcpServerTemplates'] as List).cast<Map<String, dynamic>>();
  final iconFiles = Directory('assets/icons/platforms').listSync().map((e) => e.uri.pathSegments.last).toSet();

  const allowedCategories = {'popular', 'claudeCode', 'codex', 'openclaw', 'llm', 'cloud', 'tools', 'vector'};
  const providerCategories = {'official', 'cnOfficial', 'thirdParty', 'aggregator'};
  const openclawApis = {'openai-completions', 'anthropic-messages', 'openai-responses'};
  const codexWireApis = {'responses', 'chat'};
  final idPattern = RegExp(r'^[A-Za-z][A-Za-z0-9]*$');

  bool isHttps(Object? v) => v is String && Uri.tryParse(v)?.scheme == 'https' && Uri.parse(v).host.isNotEmpty;
  bool isHttpUrl(Object? v) =>
      v is String && (Uri.tryParse(v)?.scheme == 'https' || Uri.tryParse(v)?.scheme == 'http') && Uri.parse(v).host.isNotEmpty;

  group('根对象', () {
    test('version / schemaVersion / lastUpdated', () {
      expect(raw['version'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
      expect(raw['schemaVersion'], isA<int>());
      expect(raw['schemaVersion'], lessThanOrEqualTo(CloudConfigService.maxSupportedSchemaVersion),
          reason: '自带配置的 schemaVersion 不能高于本版本能理解的值');
      expect(DateTime.tryParse(raw['lastUpdated'] as String), isNotNull);
      expect(cfg['codexAuthConfig'], isA<Map>(), reason: '旧版本 CloudConfigData.fromJson 把它当必填');
      expect(raw['version'], CloudConfigService.bundledConfigVersion, reason: '改了 app_config.json 要同步常量');
      expect(raw['lastUpdated'], CloudConfigService.bundledConfigLastUpdated, reason: '改了 app_config.json 要同步常量');
    });

    test('当前模型能完整解析（旧版本也走同一个 fromJson）', () {
      final parsed = CloudConfig.fromJson(raw);
      expect(parsed.config.providers.length, providers.length);
      expect(parsed.config.mcpServerTemplates.length, templates.length);
      // 缓存要原样保存：toJson 不能丢掉任何字段
      expect(jsonEncode(parsed.toJson()), jsonEncode(raw));
    });
  });

  group('供应商预设', () {
    test('id / platformType 唯一且格式正确', () {
      final ids = <String>{};
      final types = <String>{};
      for (final p in providers) {
        expect(p['id'], matches(idPattern), reason: '${p['id']}');
        expect(ids.add(p['id'] as String), isTrue, reason: '重复 id ${p['id']}');
        expect(types.add(p['platformType'] as String), isTrue, reason: '重复 platformType ${p['platformType']}');
      }
    });

    for (final p in providers) {
      final id = p['id'];
      test('[$id] 必填字段与各工具块', () {
        // 必填（旧版本 fromJson 用 `as String` 强转）
        for (final k in ['id', 'name', 'platformType', 'websiteUrl']) {
          expect(p[k], isA<String>(), reason: '$id.$k');
          expect((p[k] as String).isNotEmpty, isTrue, reason: '$id.$k');
        }
        expect(p['categories'], isA<List>(), reason: '$id.categories');
        expect(allowedCategories.containsAll((p['categories'] as List).cast<String>()), isTrue,
            reason: '$id.categories=${p['categories']}');
        expect(providerCategories, contains(p['providerCategory']), reason: '$id.providerCategory');
        expect(p['isOfficial'], isA<bool>());
        expect(p['isPartner'], isA<bool>());
        expect(isHttpUrl(p['websiteUrl']), isTrue, reason: '$id.websiteUrl');
        if (p['apiKeyUrl'] != null) expect(isHttpUrl(p['apiKeyUrl']), isTrue, reason: '$id.apiKeyUrl');
        if (p['icon'] != null) expect(iconFiles, contains(p['icon']), reason: '$id.icon 缺少图标文件');

        final platform = p['platform'] as Map<String, dynamic>?;
        expect(platform, isNotNull, reason: '$id.platform');
        expect(platform!['defaultName'], isA<String>());
        expect(isHttpUrl(platform['apiEndpoint']), isTrue, reason: '$id.platform.apiEndpoint');

        // 工具分类与工具块一致：有分类就必须有块，反之亦然
        for (final tool in ['claudeCode', 'codex', 'openclaw']) {
          expect((p['categories'] as List).contains(tool), p[tool] != null, reason: '$id: 分类 $tool 与配置块不一致');
        }

        final cc = p['claudeCode'] as Map<String, dynamic>?;
        if (cc != null) {
          expect(isHttpUrl(cc['baseUrl']), isTrue, reason: '$id.claudeCode.baseUrl');
          final mc = cc['modelConfig'] as Map<String, dynamic>?;
          // 中转站常留空，表示沿用 Claude Code 默认模型；有值时必须是字符串
          if (mc != null) {
            for (final k in ['mainModel', 'haikuModel', 'sonnetModel', 'opusModel']) {
              expect(mc[k] == null || mc[k] is String, isTrue, reason: '$id.claudeCode.$k');
            }
          }
        }
        final cx = p['codex'] as Map<String, dynamic>?;
        if (cx != null) {
          expect(isHttpUrl(cx['baseUrl']), isTrue, reason: '$id.codex.baseUrl');
          expect((cx['model'] as String?)?.isNotEmpty, isTrue, reason: '$id.codex.model');
          if (cx['wireApi'] != null) expect(codexWireApis, contains(cx['wireApi']), reason: '$id.codex.wireApi');
        }
        final oc = p['openclaw'] as Map<String, dynamic>?;
        if (oc != null) {
          expect(isHttpUrl(oc['baseUrl']), isTrue, reason: '$id.openclaw.baseUrl');
          if (oc['api'] != null) expect(openclawApis, contains(oc['api']), reason: '$id.openclaw.api');
          final models = (oc['models'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final mids = models.map((m) => m['id']).toList();
          expect(mids.toSet().length, mids.length, reason: '$id.openclaw.models 有重复 id');
          for (final m in models) {
            expect((m['id'] as String?)?.isNotEmpty, isTrue, reason: '$id.openclaw.models.id');
            if (m['contextWindow'] != null) expect(m['contextWindow'], isA<int>());
          }
        }
        final gm = p['gemini'] as Map<String, dynamic>?;
        if (gm != null) {
          if (gm['baseUrl'] != null) expect(isHttpUrl(gm['baseUrl']), isTrue, reason: '$id.gemini.baseUrl');
        }
        final cd = p['claudeDesktop'] as Map<String, dynamic>?;
        if (cd != null && cd['baseUrl'] != null) {
          expect(isHttps(cd['baseUrl']), isTrue, reason: '$id.claudeDesktop.baseUrl 必须是 https（Desktop 不接受 http）');
        }

        final v = p['validation'] as Map<String, dynamic>?;
        if (v != null) {
          expect(v['type'], isA<String>());
          expect(v['endpoint'], isA<String>());
          expect(['GET', 'POST'], contains(v['method']), reason: '$id.validation.method');
          expect(v['successStatus'], isA<List>());
          for (final k in ['endpoint', 'modelsEndpoint', 'balanceEndpoint']) {
            final e = v[k];
            if (e != null) expect((e as String).startsWith('/'), isTrue, reason: '$id.validation.$k=$e');
          }
          for (final k in ['baseUrlSource', 'modelsBaseUrlSource', 'balanceBaseUrlSource']) {
            final src = v[k];
            if (src != null) {
              expect(src, anyOf('platform.apiEndpoint', 'claudeCode.baseUrl', 'codex.baseUrl'), reason: '$id.validation.$k');
            }
          }
        }
      });
    }

    test('中国大陆合规：直连 OpenAI 的预设都能被地区过滤识别', () {
      for (final p in providers) {
        final urls = <String?>[
          p['websiteUrl'] as String?,
          (p['platform'] as Map?)?['apiEndpoint'] as String?,
          (p['codex'] as Map?)?['baseUrl'] as String?,
          (p['openclaw'] as Map?)?['baseUrl'] as String?,
        ];
        final hitsRestricted = urls.any((u) => u != null && Uri.parse(u).host.endsWith('openai.com'));
        if (hitsRestricted) {
          expect(RegionFilterService.isPlatformRestrictedInChina(p['platformType'] as String), isTrue,
              reason: '${p['id']} 指向 OpenAI 官方域名，但地区过滤识别不到');
        }
      }
    });
  });

  group('MCP 模板', () {
    test('字段完整且 id 唯一', () {
      final ids = <String>{};
      for (final t in templates) {
        final id = t['serverId'] as String;
        expect(ids.add(id), isTrue, reason: '重复 serverId $id');
        expect(t['name'], isA<String>());
        expect(t['category'], isA<String>());
        expect(['stdio', 'http', 'sse'], contains(t['serverType']), reason: id);
        if (t['serverType'] == 'stdio') {
          expect(['npx', 'uvx', 'docker', 'node', 'python'], contains(t['command']), reason: id);
          expect(t['args'], isA<List>(), reason: id);
        } else {
          expect(isHttps(t['url']), isTrue, reason: '$id.url');
        }
        if (t['icon'] != null) expect(iconFiles, contains(t['icon']), reason: '$id.icon');
      }
    });
  });
}
