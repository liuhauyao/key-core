import 'package:flutter/material.dart';
import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';

/// 平台注册表
/// 管理所有平台类型（内置 + 云端动态加载）
class PlatformRegistry {
  static final Map<String, PlatformType> _platforms = {};
  static final Map<String, List<String>> _platformCategories = {}; // platformId -> categories
  static bool _builtinInitialized = false;
  static bool _dynamicInitialized = false;

  /// 初始化内置平台
  static void initBuiltinPlatforms() {
    if (_builtinInitialized) return;
    
    
    // 注册所有内置平台常量
    _registerBuiltin(PlatformType.openAI);
    _registerBuiltin(PlatformType.anthropic);
    _registerBuiltin(PlatformType.google);
    _registerBuiltin(PlatformType.azureOpenAI);
    _registerBuiltin(PlatformType.aws);
    _registerBuiltin(PlatformType.minimax);
    _registerBuiltin(PlatformType.deepSeek);
    _registerBuiltin(PlatformType.siliconFlow);
    _registerBuiltin(PlatformType.zhipu);
    _registerBuiltin(PlatformType.bailian);
    _registerBuiltin(PlatformType.baidu);
    _registerBuiltin(PlatformType.n8n);
    _registerBuiltin(PlatformType.dify);
    _registerBuiltin(PlatformType.openRouter);
    _registerBuiltin(PlatformType.huggingFace);
    _registerBuiltin(PlatformType.qdrant);
    _registerBuiltin(PlatformType.volcengine);
    _registerBuiltin(PlatformType.mistral);
    _registerBuiltin(PlatformType.cohere);
    _registerBuiltin(PlatformType.perplexity);
    _registerBuiltin(PlatformType.gemini);
    _registerBuiltin(PlatformType.xai);
    _registerBuiltin(PlatformType.ollama);
    _registerBuiltin(PlatformType.zeroOne);
    _registerBuiltin(PlatformType.baichuan);
    _registerBuiltin(PlatformType.moonshot);
    _registerBuiltin(PlatformType.kimi);
    _registerBuiltin(PlatformType.nova);
    _registerBuiltin(PlatformType.zai);
    _registerBuiltin(PlatformType.katCoder);
    _registerBuiltin(PlatformType.longcat);
    _registerBuiltin(PlatformType.bailing);
    _registerBuiltin(PlatformType.modelScope);
    _registerBuiltin(PlatformType.aihubmix);
    _registerBuiltin(PlatformType.dmxapi);
    _registerBuiltin(PlatformType.packycode);
    _registerBuiltin(PlatformType.anyrouter);
    _registerBuiltin(PlatformType.tencent);
    _registerBuiltin(PlatformType.alibaba);
    _registerBuiltin(PlatformType.pinecone);
    _registerBuiltin(PlatformType.weaviate);
    _registerBuiltin(PlatformType.supabase);
    _registerBuiltin(PlatformType.notion);
    _registerBuiltin(PlatformType.bytedance);
    _registerBuiltin(PlatformType.github);
    _registerBuiltin(PlatformType.githubCopilot);
    _registerBuiltin(PlatformType.gitee);
    _registerBuiltin(PlatformType.coze);
    _registerBuiltin(PlatformType.figma);
    _registerBuiltin(PlatformType.v0);
    _registerBuiltin(PlatformType.custom);
    
    _builtinInitialized = true;
  }

  /// 从云端配置加载动态平台
  static Future<void> loadDynamicPlatforms(CloudConfigService cloudConfigService) async {

    final configData = await cloudConfigService.getConfigData();
    if (configData == null || configData.providers.isEmpty) {
      print('PlatformRegistry: 云端配置为空或没有供应商配置');
      _dynamicInitialized = true;
      return;
    }

    final providers = configData.providers;
    
    int addedCount = 0;
    int updatedCategoriesCount = 0;
    int skippedCount = 0;

    for (var provider in providers) {
      // 如果是内置平台，更新其 categories 信息
      if (_platforms.containsKey(provider.platformType)) {
        // 保存/更新内置平台的分类信息
        if (provider.categories != null && provider.categories!.isNotEmpty) {
          _platformCategories[provider.platformType] = provider.categories!;
          updatedCategoriesCount++;
        } else {
          skippedCount++;
        }
      } else {
        // 添加云端独有的动态平台
        final platform = PlatformType.dynamic(
          id: provider.platformType,
          value: provider.name, // 使用 provider 的名称作为显示名称
          iconName: 'cloud', // 默认图标
          color: Colors.blueGrey, // 默认颜色
        );

        _platforms[platform.id] = platform;

        // 保存分类信息
        if (provider.categories != null && provider.categories!.isNotEmpty) {
          _platformCategories[platform.id] = provider.categories!;
        }

        addedCount++;
      }
    }

    _dynamicInitialized = true;
    print('PlatformRegistry: 加载完成 - 配置文件供应商总数: ${providers.length}, 新增动态平台: $addedCount, 更新内置平台分类: $updatedCategoriesCount, 跳过: $skippedCount, 总计平台: ${_platforms.length}');
  }

  /// 注册内置平台
  static void _registerBuiltin(PlatformType platform) {
    _platforms[platform.id] = platform;
  }

  /// 获取平台（通过ID）
  static PlatformType? get(String id) {
    return _platforms[id];
  }

  /// 从字符串获取平台类型（兼容原枚举的 fromString 方法）
  static PlatformType fromString(String str) {
    // 1. 尝试通过 ID 精确匹配
    if (_platforms.containsKey(str)) {
      return _platforms[str]!;
    }
    
    // 2. 尝试通过 value 匹配（不区分大小写）
    final byValue = _platforms.values.where(
      (p) => p.value == str || p.value.toLowerCase() == str.toLowerCase(),
    );
    if (byValue.isNotEmpty) {
      return byValue.first;
    }
    
    // 3. 默认返回 custom
    return PlatformType.custom;
  }

  /// 获取所有平台（兼容原枚举的 values）
  static List<PlatformType> get values {
    return _platforms.values.toList();
  }

  /// 获取所有平台（兼容原枚举的 all）
  static List<PlatformType> get all {
    return values;
  }

  /// 检查是否已初始化
  static bool get isInitialized => _builtinInitialized;
  
  /// 检查动态平台是否已加载
  static bool get isDynamicInitialized => _dynamicInitialized;

  /// 重新加载动态平台（用于配置更新时）
  static Future<void> reloadDynamicPlatforms(CloudConfigService cloudConfigService) async {
    
    // 移除所有动态平台
    _platforms.removeWhere((key, value) => !value.isBuiltin);
    
    // 清除分类缓存中的动态平台
    _platformCategories.removeWhere((key, value) {
      final platform = _platforms[key];
      return platform == null || !platform.isBuiltin;
    });
    
    _dynamicInitialized = false;
    
    // 重新加载
    await loadDynamicPlatforms(cloudConfigService);
  }

  /// 获取平台总数
  static int get count => _platforms.length;

  /// 获取内置平台数量
  static int get builtinCount => _platforms.values.where((p) => p.isBuiltin).length;

  /// 获取动态平台数量
  static int get dynamicCount => _platforms.values.where((p) => !p.isBuiltin).length;

  /// 获取指定分类的所有平台（内置和动态）
  /// 从配置文件的 categories 字段读取
  static List<PlatformType> getPlatformsByCategory(String category) {
    final platforms = <PlatformType>[];

    for (var entry in _platformCategories.entries) {
      if (entry.value.contains(category)) {
        final platform = _platforms[entry.key];
        if (platform != null) {
          platforms.add(platform);
        }
      }
    }

    return platforms;
  }

  /// 获取指定分类的动态平台
  /// 从缓存的分类信息中读取
  static List<PlatformType> getDynamicPlatformsByCategory(String category) {
    final dynamicPlatforms = <PlatformType>[];

    for (var entry in _platformCategories.entries) {
      if (entry.value.contains(category)) {
        final platform = _platforms[entry.key];
        if (platform != null && !platform.isBuiltin) {
          dynamicPlatforms.add(platform);
        }
      }
    }

    return dynamicPlatforms;
  }
}

