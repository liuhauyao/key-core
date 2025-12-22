import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import '../services/platform_registry.dart';
import '../services/region_filter_service.dart';
import '../models/unified_provider_config.dart';

/// 平台预设信息
class PlatformPreset {
  final PlatformType platformType;
  final String? managementUrl;
  final String? apiEndpoint;
  final String? defaultName;

  PlatformPreset({
    required this.platformType,
    this.managementUrl,
    this.apiEndpoint,
    this.defaultName,
  });
}

/// 平台预设信息管理
class PlatformPresets {
  static final CloudConfigService _configService = CloudConfigService();
  static Map<PlatformType, PlatformPreset>? _cachedPresets;

  /// 初始化配置（从云端或本地加载）
  static Future<void> init({bool forceRefresh = false}) async {
    await _configService.init();
    await _loadPresets(forceRefresh: forceRefresh);
  }

  /// 加载平台预设配置
  static Future<void> _loadPresets({bool forceRefresh = false}) async {
    try {
      // 确保 PlatformRegistry 已初始化
      if (!PlatformRegistry.isInitialized) {
        PlatformRegistry.initBuiltinPlatforms();
      }
      
      final configData = await _configService.getConfigData(forceRefresh: forceRefresh);
      if (configData != null && configData.providers.isNotEmpty) {
        await _loadFromUnifiedProviders(configData.providers);
      } else {
        print('PlatformPresets: 配置数据为空或供应商列表为空');
      }
    } catch (e) {
      print('PlatformPresets: 加载平台预设配置失败: $e');
      // 加载失败时，缓存保持为 null，getter 会返回默认配置
    }
  }

  /// 从统一供应商配置加载平台预设
  static Future<void> _loadFromUnifiedProviders(List<UnifiedProviderConfig> providers) async {
    final loadedPresets = <PlatformType, PlatformPreset>{};
    int loadedCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    int filteredCount = 0;
    final List<String> skippedPlatforms = [];
    final List<String> filteredPlatforms = [];

    // 检查是否启用中国地区过滤
    final isChinaFilterEnabled = await RegionFilterService.isChinaRegionFilterEnabled();

    for (final provider in providers) {
      try {
        if (provider.platform != null) {
          // 使用 platformType（平台ID）来查找平台类型
          final platformTypeId = provider.platformType;
          final platformType = PlatformRegistry.fromString(platformTypeId);
          final customType = PlatformRegistry.get('custom');

          // 如果找不到平台类型，记录警告
          if (platformType == customType && platformTypeId != 'custom') {
            skippedCount++;
            skippedPlatforms.add(platformTypeId);
            continue;
          }

          // 检查是否为中国大陆受限平台
          if (isChinaFilterEnabled &&
              (RegionFilterService.isPlatformRestrictedInChina(platformTypeId) ||
               RegionFilterService.isPlatformRestrictedInChina(provider.name))) {
            filteredCount++;
            filteredPlatforms.add(platformTypeId);
            continue;
          }

          if (platformType != customType) {
            loadedPresets[platformType] = PlatformPreset(
              platformType: platformType,
              managementUrl: provider.platform!.managementUrl,
              apiEndpoint: provider.platform!.apiEndpoint,
              defaultName: provider.platform!.defaultName,
            );
            loadedCount++;
          }
        }
      } catch (e) {
        errorCount++;
      }
    }
    
    if (loadedPresets.isNotEmpty) {
      _cachedPresets = loadedPresets;
      if (skippedCount > 0 || errorCount > 0 || filteredCount > 0) {
        final filterMsg = isChinaFilterEnabled && filteredCount > 0
            ? ', 地区过滤: $filteredCount${filteredPlatforms.isNotEmpty ? ' (${filteredPlatforms.join(', ')})' : ''}'
            : '';
        print('PlatformPresets: 加载完成 - 配置文件供应商总数: ${providers.length}, 成功加载: $loadedCount, 跳过: $skippedCount${skippedPlatforms.isNotEmpty ? ' (${skippedPlatforms.join(', ')})' : ''}, 错误: $errorCount$filterMsg');
      }
    } else {
      print('PlatformPresets: 加载失败 - 配置文件供应商总数: ${providers.length}, 成功加载: $loadedCount, 跳过: $skippedCount, 错误: $errorCount');
    }
  }

  /// 获取平台预设信息
  static PlatformPreset? getPreset(PlatformType platformType) {
    if (_cachedPresets != null) {
      return _cachedPresets![platformType];
    }
    // 如果还未加载，返回 null（完全依赖配置文件）
    return null;
  }

  /// 获取所有预设的平台（排除自定义）
  static List<PlatformType> get presetPlatforms {
    if (_cachedPresets != null) {
      return _cachedPresets!.keys.where((p) => p != PlatformType.custom).toList();
    }
    // 如果还未加载，返回空列表（完全依赖配置文件）
    return [];
  }
}

