import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import '../models/unified_provider_config.dart';

/// 平台预设信息
class PlatformPreset {
  final PlatformType platformType;
  final String? managementUrl;
  final String? apiEndpoint;
  final String? defaultName;

  const PlatformPreset({
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
  static Future<void> init() async {
    await _configService.init();
    await _loadPresets();
  }

  /// 加载平台预设配置
  static Future<void> _loadPresets() async {
    try {
      final configData = await _configService.getConfigData();
      if (configData != null && configData.providers.isNotEmpty) {
        await _loadFromUnifiedProviders(configData.providers);
      } else {
        print('PlatformPresets: 配置数据为空或供应商列表为空，使用默认配置');
      }
    } catch (e, stackTrace) {
      print('PlatformPresets: 加载平台预设配置失败: $e');
      print('PlatformPresets: 堆栈跟踪: $stackTrace');
      // 加载失败时，缓存保持为 null，getter 会返回默认配置
    }
  }

  /// 从统一供应商配置加载平台预设
  static Future<void> _loadFromUnifiedProviders(List<UnifiedProviderConfig> providers) async {
    final loadedPresets = <PlatformType, PlatformPreset>{};
    int loadedCount = 0;
    
    for (final provider in providers) {
      try {
        if (provider.platform != null) {
          final platformType = PlatformType.fromString(provider.platformType);
          if (platformType != PlatformType.custom) {
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
        print('PlatformPresets: 解析统一供应商配置失败 ${provider.id}: $e');
      }
    }
    
    if (loadedPresets.isNotEmpty) {
      _cachedPresets = loadedPresets;
      print('PlatformPresets: 从统一配置成功加载 $loadedCount 个平台预设');
    } else {
      print('PlatformPresets: 平台预设列表为空，使用默认配置');
    }
  }

  /// 获取平台预设信息
  static PlatformPreset? getPreset(PlatformType platformType) {
    if (_cachedPresets != null) {
      return _cachedPresets![platformType];
    }
    // 如果还未加载，返回默认配置（向后兼容）
    return _defaultPresets[platformType];
  }

  /// 获取所有预设的平台（排除自定义）
  static List<PlatformType> get presetPlatforms {
    if (_cachedPresets != null) {
      return _cachedPresets!.keys.where((p) => p != PlatformType.custom).toList();
    }
    return _defaultPresets.keys.where((p) => p != PlatformType.custom).toList();
  }

  /// 默认平台预设信息（向后兼容）
  static const Map<PlatformType, PlatformPreset> _defaultPresets = {
    PlatformType.openAI: PlatformPreset(
      platformType: PlatformType.openAI,
      managementUrl: 'https://platform.openai.com/api-keys',
      apiEndpoint: 'https://api.openai.com/v1',
      defaultName: 'OpenAI API Key',
    ),
    PlatformType.anthropic: PlatformPreset(
      platformType: PlatformType.anthropic,
      managementUrl: 'https://console.anthropic.com/settings/keys',
      apiEndpoint: 'https://api.anthropic.com/v1',
      defaultName: 'Anthropic API Key',
    ),
    PlatformType.google: PlatformPreset(
      platformType: PlatformType.google,
      managementUrl: 'https://makersuite.google.com/app/apikey',
      apiEndpoint: 'https://generativelanguage.googleapis.com/v1',
      defaultName: 'Google AI API Key',
    ),
    PlatformType.azureOpenAI: PlatformPreset(
      platformType: PlatformType.azureOpenAI,
      managementUrl: 'https://portal.azure.com',
      apiEndpoint: 'https://{resource-name}.openai.azure.com',
      defaultName: 'Azure OpenAI Key',
    ),
    PlatformType.aws: PlatformPreset(
      platformType: PlatformType.aws,
      managementUrl: 'https://console.aws.amazon.com',
      apiEndpoint: 'https://bedrock-runtime.{region}.amazonaws.com',
      defaultName: 'AWS API Key',
    ),
    // 国产平台预设
    PlatformType.minimax: PlatformPreset(
      platformType: PlatformType.minimax,
      managementUrl: 'https://platform.minimaxi.com/',
      apiEndpoint: 'https://api.minimax.chat/v1',
      defaultName: 'MiniMax API Key',
    ),
    PlatformType.deepSeek: PlatformPreset(
      platformType: PlatformType.deepSeek,
      managementUrl: 'https://platform.deepseek.com',
      apiEndpoint: 'https://api.deepseek.com/v1',
      defaultName: 'DeepSeek API Key',
    ),
    PlatformType.siliconFlow: PlatformPreset(
      platformType: PlatformType.siliconFlow,
      managementUrl: 'https://siliconflow.cn',
      apiEndpoint: 'https://api.siliconflow.cn/v1',
      defaultName: 'SiliconFlow API Key',
    ),
    PlatformType.zhipu: PlatformPreset(
      platformType: PlatformType.zhipu,
      managementUrl: 'https://open.bigmodel.cn',
      apiEndpoint: 'https://open.bigmodel.cn/api/paas/v4',
      defaultName: '智谱AI API Key',
    ),
    PlatformType.bailian: PlatformPreset(
      platformType: PlatformType.bailian,
      managementUrl: 'https://dashscope.console.aliyun.com',
      apiEndpoint: 'https://dashscope.aliyuncs.com/api/v1',
      defaultName: '百炼云 API Key',
    ),
    PlatformType.baidu: PlatformPreset(
      platformType: PlatformType.baidu,
      managementUrl: 'https://console.bce.baidu.com/qianfan',
      apiEndpoint: 'https://aip.baidubce.com',
      defaultName: '百度千帆 API Key',
    ),
    PlatformType.qwen: PlatformPreset(
      platformType: PlatformType.qwen,
      managementUrl: 'https://dashscope.console.aliyun.com',
      apiEndpoint: 'https://dashscope.aliyuncs.com/api/v1',
      defaultName: '通义千问 API Key',
    ),
    // 其他AI平台预设
    PlatformType.n8n: PlatformPreset(
      platformType: PlatformType.n8n,
      managementUrl: 'https://app.n8n.cloud/settings/api',
      apiEndpoint: 'https://{name}.app.n8n.cloud/api/v1',
      defaultName: 'n8n API Key',
    ),
    PlatformType.dify: PlatformPreset(
      platformType: PlatformType.dify,
      managementUrl: 'https://dify.ai/settings/api-keys',
      apiEndpoint: 'https://api.dify.ai/v1',
      defaultName: 'Dify API Key',
    ),
    PlatformType.openRouter: PlatformPreset(
      platformType: PlatformType.openRouter,
      managementUrl: 'https://openrouter.ai/keys',
      apiEndpoint: 'https://openrouter.ai/api/v1',
      defaultName: 'OpenRouter API Key',
    ),
    PlatformType.huggingFace: PlatformPreset(
      platformType: PlatformType.huggingFace,
      managementUrl: 'https://huggingface.co/settings/tokens',
      apiEndpoint: 'https://api-inference.huggingface.co',
      defaultName: 'Hugging Face API Token',
    ),
    PlatformType.qdrant: PlatformPreset(
      platformType: PlatformType.qdrant,
      managementUrl: 'https://cloud.qdrant.io/',
      apiEndpoint: 'https://{cluster}.qdrant.io',
      defaultName: 'Qdrant API Key',
    ),
    PlatformType.volcengine: PlatformPreset(
      platformType: PlatformType.volcengine,
      managementUrl: 'https://console.volcengine.com/ark/keymanage',
      apiEndpoint: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultName: '火山引擎 API Key',
    ),
    // 国际LLM提供商预设
    PlatformType.mistral: PlatformPreset(
      platformType: PlatformType.mistral,
      managementUrl: 'https://console.mistral.ai/api-keys',
      apiEndpoint: 'https://api.mistral.ai',
      defaultName: 'Mistral AI API Key',
    ),
    PlatformType.cohere: PlatformPreset(
      platformType: PlatformType.cohere,
      managementUrl: 'https://dashboard.cohere.com/api-keys',
      apiEndpoint: 'https://api.cohere.ai/v1',
      defaultName: 'Cohere API Key',
    ),
    PlatformType.perplexity: PlatformPreset(
      platformType: PlatformType.perplexity,
      managementUrl: 'https://www.perplexity.ai/settings/api',
      apiEndpoint: 'https://api.perplexity.ai',
      defaultName: 'Perplexity API Key',
    ),
    PlatformType.gemini: PlatformPreset(
      platformType: PlatformType.gemini,
      managementUrl: 'https://makersuite.google.com/app/apikey',
      apiEndpoint: 'https://generativelanguage.googleapis.com/v1',
      defaultName: 'Gemini API Key',
    ),
    PlatformType.xai: PlatformPreset(
      platformType: PlatformType.xai,
      managementUrl: 'https://console.x.ai/',
      apiEndpoint: 'https://api.x.ai/v1',
      defaultName: 'xAI API Key',
    ),
    PlatformType.ollama: PlatformPreset(
      platformType: PlatformType.ollama,
      managementUrl: 'https://ollama.ai/',
      apiEndpoint: 'http://localhost:11434/api',
      defaultName: 'Ollama API Key',
    ),
    // 国产LLM提供商预设
    PlatformType.moonshot: PlatformPreset(
      platformType: PlatformType.moonshot,
      managementUrl: 'https://platform.moonshot.cn/console/api-keys',
      apiEndpoint: 'https://api.moonshot.cn/v1',
      defaultName: '月之暗面 API Key',
    ),
    PlatformType.zeroOne: PlatformPreset(
      platformType: PlatformType.zeroOne,
      managementUrl: 'https://platform.01.ai/console/api-keys',
      apiEndpoint: 'https://api.01.ai/v1',
      defaultName: '零一万物 API Key',
    ),
    PlatformType.baichuan: PlatformPreset(
      platformType: PlatformType.baichuan,
      managementUrl: 'https://platform.baichuan-ai.com/console/api-keys',
      apiEndpoint: 'https://api.baichuan-ai.com/v1',
      defaultName: '百川智能 API Key',
    ),
    PlatformType.wenxin: PlatformPreset(
      platformType: PlatformType.wenxin,
      managementUrl: 'https://console.bce.baidu.com/qianfan/ais/console/applicationConsole/application',
      apiEndpoint: 'https://aip.baidubce.com/rpc/2.0/ai_custom/v1/wenxinworkshop',
      defaultName: '文心一言 API Key',
    ),
    PlatformType.kimi: PlatformPreset(
      platformType: PlatformType.kimi,
      managementUrl: 'https://platform.moonshot.cn/console/api-keys',
      apiEndpoint: 'https://api.moonshot.cn/v1',
      defaultName: 'Kimi API Key',
    ),
    PlatformType.nova: PlatformPreset(
      platformType: PlatformType.nova,
      managementUrl: 'https://platform.doubao.com/console/api-keys',
      apiEndpoint: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultName: 'Nova API Key',
    ),
    // 云服务平台预设
    PlatformType.tencent: PlatformPreset(
      platformType: PlatformType.tencent,
      managementUrl: 'https://console.cloud.tencent.com/cam/capi',
      apiEndpoint: 'https://hunyuan.tencentcloudapi.com',
      defaultName: '腾讯云 API Key',
    ),
    PlatformType.alibaba: PlatformPreset(
      platformType: PlatformType.alibaba,
      managementUrl: 'https://ram.console.aliyun.com/manage/ak',
      apiEndpoint: 'https://dashscope.aliyuncs.com/api/v1',
      defaultName: '阿里云 API Key',
    ),
    // 向量数据库预设
    PlatformType.pinecone: PlatformPreset(
      platformType: PlatformType.pinecone,
      managementUrl: 'https://app.pinecone.io/',
      apiEndpoint: 'https://{index}.svc.{environment}.pinecone.io',
      defaultName: 'Pinecone API Key',
    ),
    PlatformType.weaviate: PlatformPreset(
      platformType: PlatformType.weaviate,
      managementUrl: 'https://console.weaviate.io/',
      apiEndpoint: 'https://{cluster}.weaviate.network/v1',
      defaultName: 'Weaviate API Key',
    ),
    // 后端即服务预设
    PlatformType.supabase: PlatformPreset(
      platformType: PlatformType.supabase,
      managementUrl: 'https://app.supabase.com/project/_/settings/api',
      apiEndpoint: 'https://{project-ref}.supabase.co/rest/v1',
      defaultName: 'Supabase API Key',
    ),
    PlatformType.notion: PlatformPreset(
      platformType: PlatformType.notion,
      managementUrl: 'https://www.notion.so/my-integrations',
      apiEndpoint: 'https://api.notion.com/v1',
      defaultName: 'Notion API Key',
    ),
    PlatformType.bytedance: PlatformPreset(
      platformType: PlatformType.bytedance,
      managementUrl: 'https://console.volcengine.com/',
      apiEndpoint: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultName: '字节跳动 API Key',
    ),
    // 工具平台预设
    PlatformType.github: PlatformPreset(
      platformType: PlatformType.github,
      managementUrl: 'https://github.com/settings/tokens',
      apiEndpoint: 'https://api.github.com',
      defaultName: 'GitHub Token',
    ),
    PlatformType.githubCopilot: PlatformPreset(
      platformType: PlatformType.githubCopilot,
      managementUrl: 'https://github.com/settings/copilot',
      apiEndpoint: 'https://api.githubcopilot.com',
      defaultName: 'GitHub Copilot Token',
    ),
    PlatformType.gitee: PlatformPreset(
      platformType: PlatformType.gitee,
      managementUrl: 'https://gitee.com/profile/personal_access_tokens',
      apiEndpoint: 'https://gitee.com/api/v5',
      defaultName: 'Gitee Token',
    ),
    // ClaudeCode 专用供应商预设
    PlatformType.zai: PlatformPreset(
      platformType: PlatformType.zai,
      managementUrl: 'https://z.ai',
      apiEndpoint: 'https://api.z.ai/api/anthropic',
      defaultName: 'Z.ai GLM API Key',
    ),
    PlatformType.katCoder: PlatformPreset(
      platformType: PlatformType.katCoder,
      managementUrl: 'https://console.streamlake.ai',
      apiEndpoint: 'https://vanchin.streamlake.ai/api/gateway/v1/endpoints/{ENDPOINT_ID}/claude-code-proxy',
      defaultName: 'KAT-Coder API Key',
    ),
    PlatformType.longcat: PlatformPreset(
      platformType: PlatformType.longcat,
      managementUrl: 'https://longcat.chat/platform',
      apiEndpoint: 'https://api.longcat.chat/anthropic',
      defaultName: 'Longcat API Key',
    ),
    PlatformType.bailing: PlatformPreset(
      platformType: PlatformType.bailing,
      managementUrl: 'https://alipaytbox.yuque.com/sxs0ba/ling/get_started',
      apiEndpoint: 'https://api.tbox.cn/api/anthropic',
      defaultName: 'BaiLing API Key',
    ),
    PlatformType.modelScope: PlatformPreset(
      platformType: PlatformType.modelScope,
      managementUrl: 'https://modelscope.cn',
      apiEndpoint: 'https://api-inference.modelscope.cn',
      defaultName: 'ModelScope API Key',
    ),
    PlatformType.aihubmix: PlatformPreset(
      platformType: PlatformType.aihubmix,
      managementUrl: 'https://aihubmix.com',
      apiEndpoint: 'https://aihubmix.com',
      defaultName: 'AiHubMix API Key',
    ),
    PlatformType.dmxapi: PlatformPreset(
      platformType: PlatformType.dmxapi,
      managementUrl: 'https://www.dmxapi.cn',
      apiEndpoint: 'https://www.dmxapi.cn',
      defaultName: 'DMXAPI API Key',
    ),
    PlatformType.packycode: PlatformPreset(
      platformType: PlatformType.packycode,
      managementUrl: 'https://www.packyapi.com',
      apiEndpoint: 'https://www.packyapi.com',
      defaultName: 'PackyCode API Key',
    ),
    PlatformType.anyrouter: PlatformPreset(
      platformType: PlatformType.anyrouter,
      managementUrl: 'https://anyrouter.top',
      apiEndpoint: 'https://anyrouter.top',
      defaultName: 'AnyRouter API Key',
    ),
    PlatformType.coze: PlatformPreset(
      platformType: PlatformType.coze,
      managementUrl: 'https://www.coze.com',
      apiEndpoint: 'https://api.coze.com',
      defaultName: 'Coze API Key',
    ),
    PlatformType.figma: PlatformPreset(
      platformType: PlatformType.figma,
      managementUrl: 'https://www.figma.com/developers/api#access-tokens',
      apiEndpoint: 'https://api.figma.com/v1',
      defaultName: 'Figma API Key',
    ),
    // Jina AI (从 n8n 提取)
    // PlatformType.jinaAI: PlatformPreset(
    //   platformType: PlatformType.jinaAI,
    //   managementUrl: 'https://jina.ai/dashboard',
    //   apiEndpoint: 'https://r.jina.ai', // Reader endpoint
    //   defaultName: 'Jina AI API Key',
    // ),
    PlatformType.v0: PlatformPreset(
      platformType: PlatformType.v0,
      managementUrl: 'https://v0.dev',
      apiEndpoint: 'https://api.v0.dev',
      defaultName: 'v0 API Key',
    ),
    PlatformType.custom: PlatformPreset(
      platformType: PlatformType.custom,
      defaultName: 'Custom API Key',
    ),
  };
}

