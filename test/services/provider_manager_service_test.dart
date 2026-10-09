import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/provider_manager_service.dart';
import 'package:key_core/models/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProviderManagerService', () {
    late ProviderManagerService service;

    setUp(() {
      service = ProviderManagerService.instance;
    });

    test('should load presets from JSON', () async {
      final presets = await service.loadPresets();
      
      expect(presets, isNotEmpty);
      expect(presets.length, greaterThanOrEqualTo(10));
      
      // 验证第一个预设的结构
      final firstPreset = presets.first;
      expect(firstPreset.id, isNotEmpty);
      expect(firstPreset.name, isNotEmpty);
      expect(firstPreset.providerType, isNotEmpty);
    });

    test('should find OpenAI official preset', () async {
      final presets = await service.loadPresets();
      
      final openai = presets.firstWhere(
        (p) => p.id == 'openai-official',
        orElse: () => throw Exception('OpenAI preset not found'),
      );
      
      expect(openai.name, 'OpenAI Official');
      expect(openai.providerType, 'official');
      expect(openai.supportedTools, contains('claude_code'));
      expect(openai.supportedTools, contains('codex'));
    });

    test('should find Anthropic official preset', () async {
      final presets = await service.loadPresets();
      
      final anthropic = presets.firstWhere(
        (p) => p.id == 'anthropic-official',
        orElse: () => throw Exception('Anthropic preset not found'),
      );
      
      expect(anthropic.name, 'Anthropic Official');
      expect(anthropic.nameZh, 'Anthropic 官方');
      expect(anthropic.providerType, 'official');
      expect(anthropic.models, isNotEmpty);
    });

    test('should have Chinese names for Chinese providers', () async {
      final presets = await service.loadPresets();
      
      final deepseek = presets.firstWhere(
        (p) => p.id == 'deepseek-official',
        orElse: () => throw Exception('DeepSeek preset not found'),
      );
      
      expect(deepseek.nameZh, '深度求索');
      expect(deepseek.region, 'cn');
    });

    test('should identify sponsored providers', () async {
      final presets = await service.loadPresets();
      
      final sponsored = presets.where((p) => p.isSponsored).toList();
      
      expect(sponsored, isNotEmpty);
      
      // 验证赞助商有描述
      for (final provider in sponsored) {
        expect(provider.description, isNotNull);
        expect(provider.description, isNotEmpty);
      }
    });

    test('provider models should have metadata', () async {
      final presets = await service.loadPresets();
      
      // 找一个有模型的供应商
      final withModels = presets.firstWhere(
        (p) => p.models.isNotEmpty,
        orElse: () => throw Exception('No provider with models found'),
      );
      
      final model = withModels.models.first;
      expect(model.id, isNotEmpty);
      expect(model.displayName, isNotEmpty);
      expect(model.contextWindow, greaterThan(0));
    });

    test('should cache presets after first load', () async {
      // 第一次加载
      final presets1 = await service.loadPresets();
      
      // 第二次加载应该使用缓存
      final presets2 = await service.loadPresets();
      
      expect(identical(presets1, presets2), isTrue);
    });

    test('clearCache should invalidate preset cache', () async {
      // 加载预设
      final presets1 = await service.loadPresets();
      
      // 清除缓存
      service.clearCache();
      
      // 重新加载
      final presets2 = await service.loadPresets();
      
      // 应该是不同的实例
      expect(identical(presets1, presets2), isFalse);
      
      // 但内容应该相同
      expect(presets1.length, presets2.length);
    });
  });
}
