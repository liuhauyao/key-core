import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import '../services/platform_registry.dart';
import '../models/unified_provider_config.dart';

/// ClaudeCode/Codex 供应商分类
enum ProviderCategory {
  official, // 官方
  cnOfficial, // 国内官方
  thirdParty, // 第三方
  aggregator, // 聚合平台
}

/// ClaudeCode 模型配置
class ClaudeCodeModelConfig {
  /// 主模型
  final String mainModel;
  
  /// Haiku 模型（轻量级）
  final String? haikuModel;
  
  /// Sonnet 模型（默认）
  final String? sonnetModel;
  
  /// Opus 模型（高性能）
  final String? opusModel;

  const ClaudeCodeModelConfig({
    required this.mainModel,
    this.haikuModel,
    this.sonnetModel,
    this.opusModel,
  });
}

/// ClaudeCode 供应商配置
class ClaudeCodeProvider {
  /// 供应商名称
  final String name;
  
  /// 网站地址
  final String websiteUrl;
  
  /// API Key 获取地址（可选）
  final String? apiKeyUrl;
  
  /// 基础 URL（API 地址）
  final String baseUrl;
  
  /// 模型配置
  final ClaudeCodeModelConfig modelConfig;
  
  /// 供应商分类
  final ProviderCategory category;
  
  /// 是否为官方供应商
  final bool isOfficial;
  
  /// 是否为合作伙伴
  final bool isPartner;
  
  /// 请求地址候选列表（用于地址管理/测速）
  final List<String>? endpointCandidates;
  
  /// 对应的平台类型（用于匹配密钥编辑页面的平台选择）
  final PlatformType? platformType;

  const ClaudeCodeProvider({
    required this.name,
    required this.websiteUrl,
    this.apiKeyUrl,
    required this.baseUrl,
    required this.modelConfig,
    required this.category,
    this.isOfficial = false,
    this.isPartner = false,
    this.endpointCandidates,
    this.platformType,
  });
}

/// Codex 供应商配置
class CodexProvider {
  /// 供应商名称
  final String name;
  
  /// 网站地址
  final String websiteUrl;
  
  /// API Key 获取地址（可选）
  final String? apiKeyUrl;
  
  /// 基础 URL（API 地址）
  final String baseUrl;
  
  /// 模型名称
  final String model;
  
  /// 供应商分类
  final ProviderCategory category;
  
  /// 是否为官方供应商
  final bool isOfficial;
  
  /// 是否为合作伙伴
  final bool isPartner;
  
  /// 请求地址候选列表（用于地址管理/测速）
  final List<String>? endpointCandidates;
  
  /// 对应的平台类型（用于匹配密钥编辑页面的平台选择）
  final PlatformType? platformType;

  const CodexProvider({
    required this.name,
    required this.websiteUrl,
    this.apiKeyUrl,
    required this.baseUrl,
    required this.model,
    required this.category,
    this.isOfficial = false,
    this.isPartner = false,
    this.endpointCandidates,
    this.platformType,
  });
}

/// 供应商配置管理
class ProviderConfig {
  static final CloudConfigService _configService = CloudConfigService();
  static List<ClaudeCodeProvider>? _cachedClaudeCodeProviders;
  static List<CodexProvider>? _cachedCodexProviders;

  /// 初始化配置（从云端或本地加载）
  static Future<void> init({bool forceRefresh = false}) async {
    await _configService.init();
    await _loadProviders(forceRefresh: forceRefresh);
  }

  /// 加载供应商配置
  static Future<void> _loadProviders({bool forceRefresh = false}) async {
    try {
      final configData = await _configService.getConfigData(forceRefresh: forceRefresh);
      if (configData != null && configData.providers.isNotEmpty) {
        await _loadFromUnifiedProviders(configData.providers);
      } else {
        print('ProviderConfig: 配置数据为空或供应商列表为空，使用默认配置');
      }
    } catch (e, stackTrace) {
      print('ProviderConfig: 加载供应商配置失败: $e');
      // 加载失败时，缓存保持为 null，getter 会返回默认配置
    }
  }

  /// 从统一供应商配置加载
  static Future<void> _loadFromUnifiedProviders(List<UnifiedProviderConfig> providers) async {
    final claudeCodeProvidersList = <ClaudeCodeProvider>[];
    final codexProvidersList = <CodexProvider>[];
    int errorCount = 0;
    
    for (final provider in providers) {
      try {
        final platformType = PlatformRegistry.fromString(provider.platformType);
        
        // 加载 ClaudeCode 供应商（只要有配置就加载）
        if (provider.claudeCode != null) {
          claudeCodeProvidersList.add(ClaudeCodeProvider(
            name: provider.name,
            websiteUrl: provider.websiteUrl,
            apiKeyUrl: provider.apiKeyUrl,
            baseUrl: provider.claudeCode!.baseUrl,
            modelConfig: ClaudeCodeModelConfig(
              mainModel: provider.claudeCode!.modelConfig.mainModel,
              haikuModel: provider.claudeCode!.modelConfig.haikuModel,
              sonnetModel: provider.claudeCode!.modelConfig.sonnetModel,
              opusModel: provider.claudeCode!.modelConfig.opusModel,
            ),
            category: _parseCategory(provider.providerCategory.toString().split('.').last),
            isOfficial: provider.isOfficial,
            isPartner: provider.isPartner,
            endpointCandidates: provider.claudeCode!.endpointCandidates,
            platformType: platformType == PlatformType.custom ? null : platformType,
          ));
        }
        
        // 加载 Codex 供应商（只要有配置就加载）
        if (provider.codex != null) {
          codexProvidersList.add(CodexProvider(
            name: provider.name,
            websiteUrl: provider.websiteUrl,
            apiKeyUrl: provider.apiKeyUrl,
            baseUrl: provider.codex!.baseUrl,
            model: provider.codex!.model,
            category: _parseCategory(provider.providerCategory.toString().split('.').last),
            isOfficial: provider.isOfficial,
            isPartner: provider.isPartner,
            endpointCandidates: provider.codex!.endpointCandidates,
            platformType: platformType == PlatformType.custom ? null : platformType,
          ));
        }
      } catch (e) {
        errorCount++;
      }
    }
    
    if (claudeCodeProvidersList.isNotEmpty) {
      _cachedClaudeCodeProviders = claudeCodeProvidersList;
    }
    
    if (codexProvidersList.isNotEmpty) {
      _cachedCodexProviders = codexProvidersList;
    }
    
    if (errorCount > 0 || claudeCodeProvidersList.isNotEmpty || codexProvidersList.isNotEmpty) {
      print('ProviderConfig: 加载完成 - 配置文件供应商总数: ${providers.length}, ClaudeCode供应商: ${claudeCodeProvidersList.length}, Codex供应商: ${codexProvidersList.length}, 错误: $errorCount');
    }
  }

  /// 解析分类枚举
  static ProviderCategory _parseCategory(String category) {
    switch (category) {
      case 'official':
        return ProviderCategory.official;
      case 'cnOfficial':
        return ProviderCategory.cnOfficial;
      case 'thirdParty':
        return ProviderCategory.thirdParty;
      case 'aggregator':
        return ProviderCategory.aggregator;
      default:
        return ProviderCategory.thirdParty;
    }
  }

  /// ClaudeCode 供应商预设列表（从云端配置加载）
  static List<ClaudeCodeProvider> get claudeCodeProviders {
    if (_cachedClaudeCodeProviders != null) {
      return _cachedClaudeCodeProviders!;
    }
    // 如果还未加载，返回空列表（完全依赖配置文件）
    return [];
  }

  /// Codex 供应商预设列表（从云端配置加载）
  static List<CodexProvider> get codexProviders {
    if (_cachedCodexProviders != null) {
      return _cachedCodexProviders!;
    }
    // 如果还未加载，返回空列表（完全依赖配置文件）
    return [];
  }

  /// 根据平台类型获取 ClaudeCode 供应商
  static ClaudeCodeProvider? getClaudeCodeProviderByPlatform(PlatformType platformType) {
    try {
      return claudeCodeProviders.firstWhere(
        (provider) => provider.platformType == platformType,
      );
    } catch (e) {
      return null;
    }
  }

  /// 根据平台类型获取 Codex 供应商
  static CodexProvider? getCodexProviderByPlatform(PlatformType platformType) {
    try {
      return codexProviders.firstWhere(
        (provider) => provider.platformType == platformType,
      );
    } catch (e) {
      return null;
    }
  }

  /// 获取支持 ClaudeCode 的平台类型列表
  static List<PlatformType> get supportedClaudeCodePlatforms {
    return claudeCodeProviders
        .where((provider) => provider.platformType != null)
        .map((provider) => provider.platformType!)
        .toSet()
        .toList();
  }

  /// 获取支持 Codex 的平台类型列表
  static List<PlatformType> get supportedCodexPlatforms {
    return codexProviders
        .where((provider) => provider.platformType != null)
        .map((provider) => provider.platformType!)
        .toSet()
        .toList();
  }

  /// 检查平台是否支持 ClaudeCode
  static bool isPlatformSupportedForClaudeCode(PlatformType platformType) {
    return claudeCodeProviders.any(
      (provider) => provider.platformType == platformType,
    );
  }

  /// 检查平台是否支持 Codex
  static bool isPlatformSupportedForCodex(PlatformType platformType) {
    return codexProviders.any(
      (provider) => provider.platformType == platformType,
    );
  }
}

