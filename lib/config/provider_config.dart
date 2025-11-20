import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
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
  static Future<void> init() async {
    await _configService.init();
    await _loadProviders();
  }

  /// 加载供应商配置
  static Future<void> _loadProviders() async {
    try {
      final configData = await _configService.getConfigData();
      if (configData != null && configData.providers.isNotEmpty) {
        await _loadFromUnifiedProviders(configData.providers);
      } else {
        print('ProviderConfig: 配置数据为空或供应商列表为空，使用默认配置');
      }
    } catch (e, stackTrace) {
      print('ProviderConfig: 加载供应商配置失败: $e');
      print('ProviderConfig: 堆栈跟踪: $stackTrace');
      // 加载失败时，缓存保持为 null，getter 会返回默认配置
    }
  }

  /// 从统一供应商配置加载
  static Future<void> _loadFromUnifiedProviders(List<UnifiedProviderConfig> providers) async {
    final claudeCodeProvidersList = <ClaudeCodeProvider>[];
    final codexProvidersList = <CodexProvider>[];
    
    for (final provider in providers) {
      try {
        final platformType = PlatformType.fromString(provider.platformType);
        
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
        print('ProviderConfig: 解析统一供应商配置失败 ${provider.id}: $e');
      }
    }
    
    if (claudeCodeProvidersList.isNotEmpty) {
      _cachedClaudeCodeProviders = claudeCodeProvidersList;
      final platformTypes = claudeCodeProvidersList
          .where((p) => p.platformType != null)
          .map((p) => p.platformType!.name)
          .toSet()
          .toList();
      print('ProviderConfig: 从统一配置成功加载 ${_cachedClaudeCodeProviders!.length} 个 ClaudeCode 供应商');
      print('ProviderConfig: ClaudeCode 平台类型: $platformTypes');
    }
    
    if (codexProvidersList.isNotEmpty) {
      _cachedCodexProviders = codexProvidersList;
      final platformTypes = codexProvidersList
          .where((p) => p.platformType != null)
          .map((p) => p.platformType!.name)
          .toSet()
          .toList();
      print('ProviderConfig: 从统一配置成功加载 ${_cachedCodexProviders!.length} 个 Codex 供应商');
      print('ProviderConfig: Codex 平台类型: $platformTypes');
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
    // 如果还未加载，返回默认配置（向后兼容）
    return _defaultClaudeCodeProviders;
  }

  /// 默认 ClaudeCode 供应商预设列表（向后兼容）
  static const List<ClaudeCodeProvider> _defaultClaudeCodeProviders = [
    // 官方供应商
    ClaudeCodeProvider(
      name: 'Claude Official',
      websiteUrl: 'https://www.anthropic.com/claude-code',
      baseUrl: 'https://api.anthropic.com',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用系统默认模型
      ),
      category: ProviderCategory.official,
      isOfficial: true,
      platformType: PlatformType.anthropic,
    ),
    
    // 国内官方供应商
    ClaudeCodeProvider(
      name: 'DeepSeek',
      websiteUrl: 'https://platform.deepseek.com',
      baseUrl: 'https://api.deepseek.com/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'DeepSeek-V3.2-Exp',
        haikuModel: 'DeepSeek-V3.2-Exp',
        sonnetModel: 'DeepSeek-V3.2-Exp',
        opusModel: 'DeepSeek-V3.2-Exp',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.deepSeek,
    ),
    ClaudeCodeProvider(
      name: 'Zhipu GLM',
      websiteUrl: 'https://open.bigmodel.cn',
      apiKeyUrl: 'https://www.bigmodel.cn/claude-code?ic=RRVJPB5SII',
      baseUrl: 'https://open.bigmodel.cn/api/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'glm-4.6',
        haikuModel: 'glm-4.5-air',
        sonnetModel: 'glm-4.6',
        opusModel: 'glm-4.6',
      ),
      category: ProviderCategory.cnOfficial,
      isPartner: true,
      platformType: PlatformType.zhipu,
    ),
    ClaudeCodeProvider(
      name: 'Z.ai GLM',
      websiteUrl: 'https://z.ai',
      apiKeyUrl: 'https://z.ai/subscribe?ic=8JVLJQFSKB',
      baseUrl: 'https://api.z.ai/api/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'glm-4.6',
        haikuModel: 'glm-4.5-air',
        sonnetModel: 'glm-4.6',
        opusModel: 'glm-4.6',
      ),
      category: ProviderCategory.cnOfficial,
      isPartner: true,
      platformType: PlatformType.zai,
    ),
    ClaudeCodeProvider(
      name: 'Qwen Coder',
      websiteUrl: 'https://bailian.console.aliyun.com',
      baseUrl: 'https://dashscope.aliyuncs.com/api/v2/apps/claude-code-proxy',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'qwen3-max',
        haikuModel: 'qwen3-max',
        sonnetModel: 'qwen3-max',
        opusModel: 'qwen3-max',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.qwen,
    ),
    ClaudeCodeProvider(
      name: 'Kimi k2',
      websiteUrl: 'https://platform.moonshot.cn/console',
      baseUrl: 'https://api.moonshot.cn/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'kimi-k2-thinking',
        haikuModel: 'kimi-k2-thinking',
        sonnetModel: 'kimi-k2-thinking',
        opusModel: 'kimi-k2-thinking',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.kimi,
    ),
    ClaudeCodeProvider(
      name: 'Kimi For Coding',
      websiteUrl: 'https://www.kimi.com/coding/docs/',
      baseUrl: 'https://api.kimi.com/coding/',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'kimi-for-coding',
        haikuModel: 'kimi-for-coding',
        sonnetModel: 'kimi-for-coding',
        opusModel: 'kimi-for-coding',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.kimi,
    ),
    ClaudeCodeProvider(
      name: 'KAT-Coder',
      websiteUrl: 'https://console.streamlake.ai',
      apiKeyUrl: 'https://console.streamlake.ai/console/api-key',
      baseUrl: 'https://vanchin.streamlake.ai/api/gateway/v1/endpoints/{ENDPOINT_ID}/claude-code-proxy',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'KAT-Coder-Pro V1',
        haikuModel: 'KAT-Coder-Air V1',
        sonnetModel: 'KAT-Coder-Pro V1',
        opusModel: 'KAT-Coder-Pro V1',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.katCoder,
    ),
    ClaudeCodeProvider(
      name: 'Longcat',
      websiteUrl: 'https://longcat.chat/platform',
      apiKeyUrl: 'https://longcat.chat/platform/api_keys',
      baseUrl: 'https://api.longcat.chat/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'LongCat-Flash-Chat',
        haikuModel: 'LongCat-Flash-Chat',
        sonnetModel: 'LongCat-Flash-Chat',
        opusModel: 'LongCat-Flash-Chat',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.longcat,
    ),
    ClaudeCodeProvider(
      name: 'MiniMax',
      websiteUrl: 'https://platform.minimaxi.com',
      apiKeyUrl: 'https://platform.minimaxi.com/user-center/basic-information',
      baseUrl: 'https://api.minimaxi.com/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'MiniMax-M2',
        haikuModel: 'MiniMax-M2',
        sonnetModel: 'MiniMax-M2',
        opusModel: 'MiniMax-M2',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.minimax,
    ),
    ClaudeCodeProvider(
      name: 'BaiLing',
      websiteUrl: 'https://alipaytbox.yuque.com/sxs0ba/ling/get_started',
      baseUrl: 'https://api.tbox.cn/api/anthropic',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'Ling-1T',
        haikuModel: 'Ling-1T',
        sonnetModel: 'Ling-1T',
        opusModel: 'Ling-1T',
      ),
      category: ProviderCategory.cnOfficial,
      platformType: PlatformType.bailing,
    ),
    
    // 聚合平台
    ClaudeCodeProvider(
      name: 'ModelScope',
      websiteUrl: 'https://modelscope.cn',
      baseUrl: 'https://api-inference.modelscope.cn',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: 'ZhipuAI/GLM-4.6',
        haikuModel: 'ZhipuAI/GLM-4.6',
        sonnetModel: 'ZhipuAI/GLM-4.6',
        opusModel: 'ZhipuAI/GLM-4.6',
      ),
      category: ProviderCategory.aggregator,
      platformType: PlatformType.modelScope,
    ),
    ClaudeCodeProvider(
      name: 'OpenRouter',
      websiteUrl: 'https://openrouter.ai',
      apiKeyUrl: 'https://openrouter.ai/keys',
      baseUrl: 'https://openrouter.ai/api/v1',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用默认模型，用户需要手动配置模型名称
      ),
      category: ProviderCategory.aggregator,
      platformType: PlatformType.openRouter,
    ),
    ClaudeCodeProvider(
      name: 'Hugging Face',
      websiteUrl: 'https://huggingface.co',
      apiKeyUrl: 'https://huggingface.co/settings/tokens',
      baseUrl: 'https://api-inference.huggingface.co',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用默认模型，用户需要手动配置模型名称
      ),
      category: ProviderCategory.aggregator,
      platformType: PlatformType.huggingFace,
    ),
    ClaudeCodeProvider(
      name: 'AiHubMix',
      websiteUrl: 'https://aihubmix.com',
      apiKeyUrl: 'https://aihubmix.com',
      baseUrl: 'https://aihubmix.com',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用默认模型，该供应商使用 ANTHROPIC_API_KEY
      ),
      category: ProviderCategory.aggregator,
      platformType: PlatformType.aihubmix,
      endpointCandidates: [
        'https://aihubmix.com',
        'https://api.aihubmix.com',
      ],
    ),
    ClaudeCodeProvider(
      name: 'DMXAPI',
      websiteUrl: 'https://www.dmxapi.cn',
      apiKeyUrl: 'https://www.dmxapi.cn',
      baseUrl: 'https://www.dmxapi.cn',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用默认模型，该供应商使用 ANTHROPIC_API_KEY
      ),
      category: ProviderCategory.aggregator,
      platformType: PlatformType.dmxapi,
      endpointCandidates: [
        'https://www.dmxapi.cn',
      ],
    ),
    
    // 第三方供应商
    ClaudeCodeProvider(
      name: 'PackyCode',
      websiteUrl: 'https://www.packyapi.com',
      apiKeyUrl: 'https://www.packyapi.com/register?aff=cc-switch',
      baseUrl: 'https://www.packyapi.com',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用默认模型
      ),
      category: ProviderCategory.thirdParty,
      isPartner: true,
      platformType: PlatformType.packycode,
      endpointCandidates: [
        'https://www.packyapi.com',
        'https://api-slb.packyapi.com',
      ],
    ),
    ClaudeCodeProvider(
      name: 'AnyRouter',
      websiteUrl: 'https://anyrouter.top',
      apiKeyUrl: 'https://anyrouter.top/register?aff=PCel',
      baseUrl: 'https://anyrouter.top',
      modelConfig: ClaudeCodeModelConfig(
        mainModel: '', // 使用默认模型
      ),
      category: ProviderCategory.thirdParty,
      platformType: PlatformType.anyrouter,
      endpointCandidates: [
        'https://q.quuvv.cn',
        'https://pmpjfbhq.cn-nb1.rainapp.top',
        'https://anyrouter.top',
      ],
    ),
  ];

  /// Codex 供应商预设列表（从云端配置加载）
  static List<CodexProvider> get codexProviders {
    if (_cachedCodexProviders != null) {
      return _cachedCodexProviders!;
    }
    // 如果还未加载，返回默认配置（向后兼容）
    return _defaultCodexProviders;
  }

  /// 默认 Codex 供应商预设列表（向后兼容）
  static const List<CodexProvider> _defaultCodexProviders = [
    // 官方供应商
    CodexProvider(
      name: 'OpenAI Official',
      websiteUrl: 'https://chatgpt.com/codex',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.official,
      isOfficial: true,
      platformType: PlatformType.openAI,
    ),
    CodexProvider(
      name: 'Azure OpenAI',
      websiteUrl: 'https://learn.microsoft.com/azure/ai-services/openai/how-to/overview',
      baseUrl: 'https://YOUR_RESOURCE_NAME.openai.azure.com/openai',
      model: 'gpt-5-codex',
      category: ProviderCategory.thirdParty,
      isOfficial: true,
      platformType: PlatformType.azureOpenAI,
      endpointCandidates: [
        'https://YOUR_RESOURCE_NAME.openai.azure.com/openai',
      ],
    ),
    
    // 聚合平台
    CodexProvider(
      name: 'AiHubMix',
      websiteUrl: 'https://aihubmix.com',
      baseUrl: 'https://aihubmix.com/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.aggregator,
      platformType: PlatformType.aihubmix,
      endpointCandidates: [
        'https://aihubmix.com/v1',
        'https://api.aihubmix.com/v1',
      ],
    ),
    CodexProvider(
      name: 'OpenRouter',
      websiteUrl: 'https://openrouter.ai',
      apiKeyUrl: 'https://openrouter.ai/keys',
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.aggregator,
      platformType: PlatformType.openRouter,
    ),
    CodexProvider(
      name: 'Hugging Face',
      websiteUrl: 'https://huggingface.co',
      apiKeyUrl: 'https://huggingface.co/settings/tokens',
      baseUrl: 'https://api-inference.huggingface.co/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.aggregator,
      platformType: PlatformType.huggingFace,
    ),
    CodexProvider(
      name: 'DMXAPI',
      websiteUrl: 'https://www.dmxapi.cn',
      baseUrl: 'https://www.dmxapi.cn/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.aggregator,
      platformType: PlatformType.dmxapi,
      endpointCandidates: [
        'https://www.dmxapi.cn/v1',
      ],
    ),
    
    // 第三方供应商
    CodexProvider(
      name: 'PackyCode',
      websiteUrl: 'https://www.packyapi.com',
      apiKeyUrl: 'https://www.packyapi.com/register?aff=cc-switch',
      baseUrl: 'https://www.packyapi.com/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.thirdParty,
      isPartner: true,
      platformType: PlatformType.packycode,
      endpointCandidates: [
        'https://www.packyapi.com/v1',
        'https://api-slb.packyapi.com/v1',
      ],
    ),
    CodexProvider(
      name: 'AnyRouter',
      websiteUrl: 'https://anyrouter.top',
      baseUrl: 'https://anyrouter.top/v1',
      model: 'gpt-5-codex',
      category: ProviderCategory.thirdParty,
      platformType: PlatformType.anyrouter,
      endpointCandidates: [
        'https://anyrouter.top/v1',
        'https://q.quuvv.cn/v1',
        'https://pmpjfbhq.cn-nb1.rainapp.top/v1',
      ],
    ),
  ];

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

