import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mcp_server.dart';
import 'ai_tool_config_service.dart';

/// OpenClaw 模型定义（写入 openclaw.json 的 models.providers[id].models 数组）
class OpenClawModelDef {
  final String id;
  final String name;
  final bool reasoning;
  final List<String> input;
  final double costInput;
  final double costOutput;
  final double costCacheRead;
  final double costCacheWrite;
  final int contextWindow;
  final int maxTokens;
  final Map<String, dynamic>? compat;

  const OpenClawModelDef({
    required this.id,
    required this.name,
    this.reasoning = false,
    this.input = const ['text'],
    this.costInput = 0,
    this.costOutput = 0,
    this.costCacheRead = 0,
    this.costCacheWrite = 0,
    required this.contextWindow,
    required this.maxTokens,
    this.compat,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'reasoning': reasoning,
        'input': input,
        'cost': {
          'input': costInput,
          'output': costOutput,
          'cacheRead': costCacheRead,
          'cacheWrite': costCacheWrite,
        },
        'contextWindow': contextWindow,
        'maxTokens': maxTokens,
        if (compat != null) 'compat': compat,
      };
}

/// OpenClaw 平台兼容信息（keycore platformType.id → OpenClaw 供应商配置）
class OpenClawPlatformInfo {
  final String envKey;
  /// openclaw.json 中使用的 provider ID（所有供应商都需要）
  final String openclawProviderId;
  final bool isBuiltin;
  final String? baseUrl;
  final String apiType;
  final String displayName;
  /// 该供应商的预设模型列表（用于生成 models.providers 配置）
  final List<OpenClawModelDef> models;

  const OpenClawPlatformInfo({
    required this.envKey,
    required this.openclawProviderId,
    required this.isBuiltin,
    this.baseUrl,
    this.apiType = 'openai-completions',
    required this.displayName,
    this.models = const [],
  });

  /// 兼容旧字段：customProviderId → openclawProviderId（非内置）
  String? get customProviderId => isBuiltin ? null : openclawProviderId;
}

/// OpenClaw 支持的模型供应商
class OpenClawProvider {
  final String id;
  final String displayName;
  final String envKey;
  final String defaultBaseUrl;

  const OpenClawProvider({
    required this.id,
    required this.displayName,
    required this.envKey,
    required this.defaultBaseUrl,
  });

  static const List<OpenClawProvider> builtinProviders = [
    OpenClawProvider(
      id: 'anthropic',
      displayName: 'Anthropic',
      envKey: 'ANTHROPIC_API_KEY',
      defaultBaseUrl: 'https://api.anthropic.com',
    ),
    OpenClawProvider(
      id: 'openai',
      displayName: 'OpenAI',
      envKey: 'OPENAI_API_KEY',
      defaultBaseUrl: 'https://api.openai.com/v1',
    ),
    OpenClawProvider(
      id: 'google',
      displayName: 'Google / Gemini',
      envKey: 'GEMINI_API_KEY',
      defaultBaseUrl: 'https://generativelanguage.googleapis.com',
    ),
    OpenClawProvider(
      id: 'openrouter',
      displayName: 'OpenRouter',
      envKey: 'OPENROUTER_API_KEY',
      defaultBaseUrl: 'https://openrouter.ai/api/v1',
    ),
    OpenClawProvider(
      id: 'groq',
      displayName: 'Groq',
      envKey: 'GROQ_API_KEY',
      defaultBaseUrl: 'https://api.groq.com/openai/v1',
    ),
    OpenClawProvider(
      id: 'moonshot',
      displayName: 'Moonshot (Kimi)',
      envKey: 'MOONSHOT_API_KEY',
      defaultBaseUrl: 'https://api.moonshot.cn/v1',
    ),
  ];
}

/// 自定义 Provider 配置
class OpenClawCustomProvider {
  final String id;
  final String baseUrl;
  final String apiType;
  final List<String> models;

  const OpenClawCustomProvider({
    required this.id,
    required this.baseUrl,
    required this.apiType,
    required this.models,
  });

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'api': apiType,
        if (models.isNotEmpty)
          'models': models.map((m) => {'id': m}).toList(),
      };

  factory OpenClawCustomProvider.fromJson(String id, Map<String, dynamic> json) {
    final modelsList = (json['models'] as List?)
            ?.map((m) => (m is Map ? m['id'] as String? : m?.toString()) ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    return OpenClawCustomProvider(
      id: id,
      baseUrl: json['baseUrl'] as String? ?? '',
      apiType: json['api'] as String? ?? 'openai-completions',
      models: modelsList,
    );
  }
}

/// 模型别名配置
class OpenClawModelAlias {
  final String modelId;
  final String alias;

  const OpenClawModelAlias({required this.modelId, required this.alias});
}

/// OpenClaw 模型配置数据
class OpenClawModelConfig {
  final String primaryModel;
  final List<String> fallbackModels;
  final List<OpenClawModelAlias> modelAliases;
  final List<OpenClawCustomProvider> customProviders;
  final int gatewayPort;

  const OpenClawModelConfig({
    this.primaryModel = '',
    this.fallbackModels = const [],
    this.modelAliases = const [],
    this.customProviders = const [],
    this.gatewayPort = 18789,
  });
}

/// OpenClaw 配置服务
/// 管理 ~/.openclaw/openclaw.json 和 ~/.openclaw/.env 的读写
class OpenClawConfigService {
  static const String _configFileName = 'openclaw.json';
  static const String _envFileName = '.env';
  static const String _prefPrefix = 'openclaw_applied_key_';

  /// keycore platformType.id → OpenClaw 供应商配置映射
  static const Map<String, OpenClawPlatformInfo> platformMapping = {
    'anthropic': OpenClawPlatformInfo(
      envKey: 'ANTHROPIC_API_KEY',
      openclawProviderId: 'anthropic',
      isBuiltin: true,
      baseUrl: 'https://api.anthropic.com',
      apiType: 'anthropic-messages',
      displayName: 'Anthropic',
      models: [
        OpenClawModelDef(
          id: 'claude-opus-4-5',
          name: 'Claude Opus 4.5',
          reasoning: true,
          input: ['text', 'image'],
          contextWindow: 200000,
          maxTokens: 32000,
        ),
      ],
    ),
    'openAI': OpenClawPlatformInfo(
      envKey: 'OPENAI_API_KEY',
      openclawProviderId: 'openai',
      isBuiltin: true,
      baseUrl: 'https://api.openai.com/v1',
      apiType: 'openai-completions',
      displayName: 'OpenAI',
      models: [
        OpenClawModelDef(
          id: 'gpt-4o',
          name: 'GPT-4o',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 128000,
          maxTokens: 16384,
        ),
      ],
    ),
    'google': OpenClawPlatformInfo(
      envKey: 'GEMINI_API_KEY',
      openclawProviderId: 'google',
      isBuiltin: true,
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      apiType: 'openai-completions',
      displayName: 'Google / Gemini',
      models: [
        OpenClawModelDef(
          id: 'gemini-2.5-pro',
          name: 'Gemini 2.5 Pro',
          reasoning: true,
          input: ['text', 'image'],
          contextWindow: 1000000,
          maxTokens: 65536,
        ),
      ],
    ),
    'openRouter': OpenClawPlatformInfo(
      envKey: 'OPENROUTER_API_KEY',
      openclawProviderId: 'openrouter',
      isBuiltin: true,
      baseUrl: 'https://openrouter.ai/api/v1',
      apiType: 'openai-completions',
      displayName: 'OpenRouter',
      models: [
        OpenClawModelDef(
          id: 'auto',
          name: 'OpenRouter Auto',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 200000,
          maxTokens: 8192,
        ),
      ],
    ),
    'kimi': OpenClawPlatformInfo(
      envKey: 'MOONSHOT_API_KEY',
      openclawProviderId: 'moonshot',
      isBuiltin: false,
      baseUrl: 'https://api.moonshot.ai/v1',
      apiType: 'openai-completions',
      displayName: 'Moonshot (Kimi)',
      models: [
        OpenClawModelDef(
          id: 'kimi-k2.5',
          name: 'Kimi K2.5',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 262144,
          maxTokens: 262144,
        ),
        OpenClawModelDef(
          id: 'kimi-k2-thinking',
          name: 'Kimi K2 Thinking',
          reasoning: true,
          input: ['text'],
          contextWindow: 262144,
          maxTokens: 262144,
        ),
      ],
    ),
    'mistral': OpenClawPlatformInfo(
      envKey: 'MISTRAL_API_KEY',
      openclawProviderId: 'mistral',
      isBuiltin: false,
      baseUrl: 'https://api.mistral.ai/v1',
      apiType: 'openai-completions',
      displayName: 'Mistral',
      models: [
        OpenClawModelDef(
          id: 'mistral-large-latest',
          name: 'Mistral Large',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 131072,
          maxTokens: 4096,
        ),
        OpenClawModelDef(
          id: 'codestral-latest',
          name: 'Codestral',
          reasoning: false,
          input: ['text'],
          contextWindow: 262144,
          maxTokens: 4096,
        ),
      ],
    ),
    'deepSeek': OpenClawPlatformInfo(
      envKey: 'DEEPSEEK_API_KEY',
      openclawProviderId: 'deepseek',
      isBuiltin: false,
      baseUrl: 'https://api.deepseek.com/v1',
      apiType: 'openai-completions',
      displayName: 'DeepSeek',
      models: [
        OpenClawModelDef(
          id: 'deepseek-chat',
          name: 'DeepSeek Chat',
          reasoning: false,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 8192,
          compat: {'supportsUsageInStreaming': true},
        ),
        OpenClawModelDef(
          id: 'deepseek-reasoner',
          name: 'DeepSeek Reasoner',
          reasoning: true,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 65536,
          compat: {'supportsUsageInStreaming': true},
        ),
      ],
    ),
    'siliconFlow': OpenClawPlatformInfo(
      envKey: 'SILICONFLOW_API_KEY',
      openclawProviderId: 'siliconflow',
      isBuiltin: false,
      baseUrl: 'https://api.siliconflow.cn/v1',
      apiType: 'openai-completions',
      displayName: 'SiliconFlow',
      models: [
        OpenClawModelDef(
          id: 'deepseek-ai/DeepSeek-V3',
          name: 'DeepSeek V3',
          reasoning: false,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 8192,
        ),
        OpenClawModelDef(
          id: 'deepseek-ai/DeepSeek-R1',
          name: 'DeepSeek R1',
          reasoning: true,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 32768,
        ),
      ],
    ),
    'minimax': OpenClawPlatformInfo(
      envKey: 'MINIMAX_API_KEY',
      openclawProviderId: 'minimax',
      isBuiltin: false,
      baseUrl: 'https://api.minimax.io/anthropic',
      apiType: 'anthropic-messages',
      displayName: 'MiniMax',
      models: [
        OpenClawModelDef(
          id: 'MiniMax-M2.7',
          name: 'MiniMax M2.7',
          reasoning: true,
          input: ['text'],
          costInput: 0.3,
          costOutput: 1.2,
          costCacheRead: 0.03,
          costCacheWrite: 0.12,
          contextWindow: 200000,
          maxTokens: 8192,
        ),
        OpenClawModelDef(
          id: 'MiniMax-M2.7-highspeed',
          name: 'MiniMax M2.7 Highspeed',
          reasoning: true,
          input: ['text'],
          costInput: 0.3,
          costOutput: 1.2,
          costCacheRead: 0.03,
          costCacheWrite: 0.12,
          contextWindow: 200000,
          maxTokens: 8192,
        ),
      ],
    ),
    'xiaomiMimo': OpenClawPlatformInfo(
      envKey: 'XIAOMI_API_KEY',
      openclawProviderId: 'xiaomi',
      isBuiltin: false,
      baseUrl: 'https://api.xiaomimimo.com/v1',
      apiType: 'openai-completions',
      displayName: '小米 MiMo',
      models: [
        OpenClawModelDef(
          id: 'mimo-v2-flash',
          name: 'Xiaomi MiMo V2 Flash',
          reasoning: false,
          input: ['text'],
          contextWindow: 262144,
          maxTokens: 8192,
        ),
        OpenClawModelDef(
          id: 'mimo-v2-pro',
          name: 'Xiaomi MiMo V2 Pro',
          reasoning: true,
          input: ['text'],
          contextWindow: 1048576,
          maxTokens: 32000,
        ),
        OpenClawModelDef(
          id: 'mimo-v2-omni',
          name: 'Xiaomi MiMo V2 Omni',
          reasoning: true,
          input: ['text', 'image'],
          contextWindow: 262144,
          maxTokens: 32000,
        ),
      ],
    ),
    'xai': OpenClawPlatformInfo(
      envKey: 'XAI_API_KEY',
      openclawProviderId: 'xai',
      isBuiltin: false,
      baseUrl: 'https://api.x.ai/v1',
      apiType: 'openai-completions',
      displayName: 'xAI (Grok)',
      models: [
        OpenClawModelDef(
          id: 'grok-4',
          name: 'Grok 4',
          reasoning: true,
          input: ['text', 'image'],
          contextWindow: 1048576,
          maxTokens: 65536,
        ),
        OpenClawModelDef(
          id: 'grok-4-fast-reasoning',
          name: 'Grok 4 Fast',
          reasoning: true,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 65536,
        ),
      ],
    ),
    'ollama': OpenClawPlatformInfo(
      envKey: 'OLLAMA_API_KEY',
      openclawProviderId: 'ollama',
      isBuiltin: false,
      baseUrl: 'http://localhost:11434/v1',
      apiType: 'openai-completions',
      displayName: 'Ollama',
      models: [
        OpenClawModelDef(
          id: 'llama3.2',
          name: 'Llama 3.2',
          reasoning: false,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 8192,
        ),
      ],
    ),
    'volcengine': OpenClawPlatformInfo(
      envKey: 'VOLCANO_ENGINE_API_KEY',
      openclawProviderId: 'volcengine',
      isBuiltin: false,
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      apiType: 'openai-completions',
      displayName: '火山引擎',
      models: [
        OpenClawModelDef(
          id: 'doubao-seed-1-8',
          name: 'Doubao Seed 1.8',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 131072,
          maxTokens: 8192,
        ),
        OpenClawModelDef(
          id: 'doubao-seed-code-preview',
          name: 'Doubao Seed Code',
          reasoning: false,
          input: ['text'],
          contextWindow: 131072,
          maxTokens: 8192,
        ),
      ],
    ),
    'huggingFace': OpenClawPlatformInfo(
      envKey: 'HUGGING_FACE_HUB_TOKEN',
      openclawProviderId: 'huggingface',
      isBuiltin: false,
      baseUrl: 'https://api-inference.huggingface.co/v1',
      apiType: 'openai-completions',
      displayName: 'Hugging Face',
      models: [
        OpenClawModelDef(
          id: 'Qwen/Qwen3-235B-A22B-Instruct-2507',
          name: 'Qwen3 235B Instruct',
          reasoning: false,
          input: ['text'],
          contextWindow: 262144,
          maxTokens: 8192,
        ),
      ],
    ),
    'baidu': OpenClawPlatformInfo(
      envKey: 'QIANFAN_API_KEY',
      openclawProviderId: 'qianfan',
      isBuiltin: false,
      baseUrl: 'https://qianfan.baidubce.com/v2',
      apiType: 'openai-completions',
      displayName: '百度千帆',
      models: [
        OpenClawModelDef(
          id: 'deepseek-v3.2',
          name: 'DEEPSEEK V3.2',
          reasoning: true,
          input: ['text'],
          contextWindow: 98304,
          maxTokens: 32768,
        ),
        OpenClawModelDef(
          id: 'ernie-5.0-thinking-preview',
          name: 'ERNIE-5.0-Thinking-Preview',
          reasoning: true,
          input: ['text', 'image'],
          contextWindow: 119000,
          maxTokens: 64000,
        ),
      ],
    ),
    'bailian': OpenClawPlatformInfo(
      envKey: 'DASHSCOPE_API_KEY',
      openclawProviderId: 'modelstudio',
      isBuiltin: false,
      baseUrl: 'https://coding-intl.dashscope.aliyuncs.com/v1',
      apiType: 'openai-completions',
      displayName: 'Alibaba DashScope',
      models: [
        OpenClawModelDef(
          id: 'qwen3.5-plus',
          name: 'Qwen3.5 Plus',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 1000000,
          maxTokens: 65536,
        ),
        OpenClawModelDef(
          id: 'qwen3-coder-plus',
          name: 'Qwen3 Coder Plus',
          reasoning: false,
          input: ['text'],
          contextWindow: 1000000,
          maxTokens: 65536,
        ),
      ],
    ),
    'zai': OpenClawPlatformInfo(
      envKey: 'ZAI_API_KEY',
      openclawProviderId: 'zai',
      isBuiltin: false,
      baseUrl: 'https://api.z.ai/api/paas/v4',
      apiType: 'openai-completions',
      displayName: 'Z.AI (GLM)',
      models: [
        OpenClawModelDef(
          id: 'glm-5',
          name: 'GLM-5',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 202752,
          maxTokens: 16384,
        ),
        OpenClawModelDef(
          id: 'glm-4.7',
          name: 'GLM-4.7',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 202752,
          maxTokens: 16384,
        ),
      ],
    ),
  };

  /// 获取记录的"已应用"密钥 ID（SharedPreferences 中存的 envKey → keyId）
  Future<Map<String, int>> getAppliedKeyIds() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, int>{};
    for (final info in platformMapping.values) {
      final keyId = prefs.getInt('$_prefPrefix${info.envKey}');
      if (keyId != null) {
        result[info.envKey] = keyId;
      }
    }
    return result;
  }

  /// 记录某个 envKey 对应的已应用密钥 ID（null 表示清除）
  Future<void> _setAppliedKeyId(String envKey, int? keyId) async {
    final prefs = await SharedPreferences.getInstance();
    if (keyId == null) {
      await prefs.remove('$_prefPrefix$envKey');
    } else {
      await prefs.setInt('$_prefPrefix$envKey', keyId);
    }
  }

  /// 将密钥写入 OpenClaw 配置（对标 openclaw configure 向导写入逻辑）：
  ///   1. 写入 .env（envKey=decryptedKey）
  ///   2. 写入 auth.profiles[providerId:default]
  ///   3. 写入 models.providers[providerId]（含完整模型定义）
  ///   4. 确保 models.mode = "merge"
  Future<void> applyProviderKey({
    required int keyId,
    required String decryptedKey,
    required String platformId,
    String? openclawBaseUrl,
    String? openclawModel,
  }) async {
    final info = platformMapping[platformId];
    if (info == null) return;

    // 1. 写入 .env
    await writeEnvKeys({info.envKey: decryptedKey});

    final config = await readConfig();
    final providerId = info.openclawProviderId;

    // 2. 写入 auth.profiles
    final authRoot = Map<String, dynamic>.from(
        (config['auth'] as Map<String, dynamic>?) ?? {});
    final profiles = Map<String, dynamic>.from(
        (authRoot['profiles'] as Map<String, dynamic>?) ?? {});
    profiles['$providerId:default'] = {
      'provider': providerId,
      'mode': 'api_key',
    };
    authRoot['profiles'] = profiles;
    config['auth'] = authRoot;

    // 3. 写入 models.providers（含完整模型定义）
    final effectiveBaseUrl = (openclawBaseUrl != null && openclawBaseUrl.isNotEmpty)
        ? openclawBaseUrl
        : info.baseUrl;

    if (effectiveBaseUrl != null) {
      final modelsRoot = Map<String, dynamic>.from(
          (config['models'] as Map<String, dynamic>?) ?? {});
      // 确保 models.mode = "merge"
      modelsRoot['mode'] ??= 'merge';

      final providersMap = Map<String, dynamic>.from(
          (modelsRoot['providers'] as Map<String, dynamic>?) ?? {});

      // 构建模型定义列表
      final List<Map<String, dynamic>> modelDefs = _buildModelDefs(
        info: info,
        selectedModelId: openclawModel,
      );

      providersMap[providerId] = {
        'baseUrl': effectiveBaseUrl,
        'api': info.apiType,
        if (modelDefs.isNotEmpty) 'models': modelDefs,
      };
      modelsRoot['providers'] = providersMap;
      config['models'] = modelsRoot;
    }

    await writeConfig(config);
    await _setAppliedKeyId(info.envKey, keyId);
  }

  /// 构建写入 openclaw.json 的模型定义列表
  List<Map<String, dynamic>> _buildModelDefs({
    required OpenClawPlatformInfo info,
    String? selectedModelId,
  }) {
    if (info.models.isEmpty) return [];

    if (selectedModelId != null && selectedModelId.isNotEmpty) {
      // 优先写入用户选定的模型；若注册表中有完整定义则使用，否则构造最小定义
      final found = info.models.where((m) => m.id == selectedModelId).firstOrNull;
      if (found != null) return [found.toJson()];
      // 用户填写了不在注册表中的自定义模型 ID
      return [
        {
          'id': selectedModelId,
          'name': selectedModelId,
          'reasoning': false,
          'input': ['text'],
          'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
          'contextWindow': 131072,
          'maxTokens': 8192,
        }
      ];
    }
    // 未指定模型时写入全部注册模型（供 openclaw 选择）
    return info.models.map((m) => m.toJson()).toList();
  }

  /// 从 OpenClaw 配置中移除密钥：
  ///   1. 清除 .env 中的 envKey
  ///   2. 移除 auth.profiles[providerId:default]
  ///   3. 移除 models.providers[providerId]
  Future<void> removeProviderKey({required String platformId}) async {
    final info = platformMapping[platformId];
    if (info == null) return;

    await writeEnvKeys({info.envKey: ''});

    final config = await readConfig();
    final providerId = info.openclawProviderId;

    // 移除 auth.profiles 条目
    final authRoot = config['auth'] as Map<String, dynamic>?;
    if (authRoot != null) {
      final profiles = authRoot['profiles'] as Map<String, dynamic>?;
      profiles?.remove('$providerId:default');
    }

    // 移除 models.providers 条目
    final modelsRoot = config['models'] as Map<String, dynamic>?;
    if (modelsRoot != null) {
      final providersMap = modelsRoot['providers'] as Map<String, dynamic>?;
      providersMap?.remove(providerId);
    }

    await writeConfig(config);
    await _setAppliedKeyId(info.envKey, null);
  }

  String? _cachedConfigDir;

  /// 获取配置目录
  Future<String> _getConfigDir() async {
    if (_cachedConfigDir != null) return _cachedConfigDir!;
    final toolConfigService = AiToolConfigService();
    final dir = await toolConfigService.getConfigDir(AiToolType.openclaw);
    _cachedConfigDir = dir;
    return dir;
  }

  Future<String> _getConfigFilePath() async {
    return path.join(await _getConfigDir(), _configFileName);
  }

  Future<String> _getEnvFilePath() async {
    return path.join(await _getConfigDir(), _envFileName);
  }

  /// 检查 OpenClaw 配置目录是否存在（判断是否已安装）
  Future<Map<String, dynamic>> checkConfigExists() async {
    final configDir = await _getConfigDir();
    final configFilePath = await _getConfigFilePath();

    final dirObj = Directory(configDir);
    bool dirExists = false;
    bool configFileExists = false;

    try {
      dirExists = await dirObj.exists();
      if (dirExists) {
        configFileExists = await File(configFilePath).exists();
      }
    } catch (_) {}

    return {
      'dirExists': dirExists,
      'configExists': configFileExists,
      'configDir': configDir,
      'configPath': configFilePath,
    };
  }

  /// JSON5 预处理：剥离单行注释、块注释、尾随逗号，使标准 json.decode 可解析
  static String _preprocessJson5(String content) {
    // 移除块注释 /* ... */
    final blockCommentRegex = RegExp(r'/\*[\s\S]*?\*/', multiLine: true);
    content = content.replaceAll(blockCommentRegex, '');

    // 逐行移除单行注释 //（字符串内的不处理，做简单处理够用）
    final lines = content.split('\n');
    final processed = lines.map((line) {
      // 找到 // 的位置，跳过字符串内的（简单启发：统计引号数量为偶数则在字符串外）
      int pos = 0;
      int quoteCount = 0;
      while (pos < line.length - 1) {
        final ch = line[pos];
        if (ch == '"' && (pos == 0 || line[pos - 1] != '\\')) {
          quoteCount++;
        }
        if (ch == '/' && line[pos + 1] == '/' && quoteCount % 2 == 0) {
          return line.substring(0, pos).trimRight();
        }
        pos++;
      }
      return line;
    }).join('\n');

    // 移除尾随逗号（JSON 不允许）
    final trailingCommaRegex = RegExp(r',\s*([}\]])');
    return processed.replaceAllMapped(trailingCommaRegex, (m) => m.group(1)!);
  }

  /// 读取 openclaw.json，返回解析后的 Map，文件不存在则返回空 Map
  Future<Map<String, dynamic>> readConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);
      if (!await file.exists()) return {};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return {};
      final cleaned = _preprocessJson5(raw);
      final decoded = json.decode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 写入 openclaw.json，使用 merge 策略：仅修改目标节点，保留其他字段
  Future<void> writeConfig(Map<String, dynamic> config) async {
    final configPath = await _getConfigFilePath();
    final configDir = await _getConfigDir();
    final dir = Directory(configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File(configPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  /// 读取 .env 文件，返回 Map<envKey, value>
  Future<Map<String, String>> readEnv() async {
    try {
      final envPath = await _getEnvFilePath();
      final file = File(envPath);
      if (!await file.exists()) return {};
      final lines = await file.readAsLines();
      final result = <String, String>{};
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx <= 0) continue;
        final key = trimmed.substring(0, eqIdx).trim();
        var value = trimmed.substring(eqIdx + 1).trim();
        // 去掉引号
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        result[key] = value;
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  /// 写入 .env 文件（仅更新指定的 key，保留其他行）
  Future<void> writeEnvKeys(Map<String, String> updates) async {
    final envPath = await _getEnvFilePath();
    final configDir = await _getConfigDir();
    final dir = Directory(configDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final file = File(envPath);
    List<String> lines = [];
    if (await file.exists()) {
      lines = await file.readAsLines();
    }

    final updatedKeys = <String>{};
    final newLines = lines.map((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) return line;
      final eqIdx = trimmed.indexOf('=');
      if (eqIdx <= 0) return line;
      final key = trimmed.substring(0, eqIdx).trim();
      if (updates.containsKey(key)) {
        updatedKeys.add(key);
        final val = updates[key]!;
        if (val.isEmpty) return '# $key=';
        return '$key=$val';
      }
      return line;
    }).toList();

    // 追加未出现过的 key
    for (final entry in updates.entries) {
      if (!updatedKeys.contains(entry.key) && entry.value.isNotEmpty) {
        newLines.add('${entry.key}=${entry.value}');
      }
    }

    await file.writeAsString(newLines.join('\n') + '\n');
  }

  /// 读取当前模型配置
  Future<OpenClawModelConfig> readModelConfig() async {
    final config = await readConfig();

    // agents.defaults.model.primary
    final agents = config['agents'] as Map<String, dynamic>? ?? {};
    final defaults = agents['defaults'] as Map<String, dynamic>? ?? {};
    final modelBlock = defaults['model'];
    String primary = '';
    List<String> fallbacks = [];
    if (modelBlock is Map<String, dynamic>) {
      primary = modelBlock['primary'] as String? ?? '';
      final fb = modelBlock['fallbacks'];
      if (fb is List) {
        fallbacks = fb.map((e) => e.toString()).toList();
      }
    } else if (modelBlock is String) {
      primary = modelBlock;
    }

    // agents.defaults.models（别名列表）
    final modelsMap = defaults['models'] as Map<String, dynamic>? ?? {};
    final aliases = modelsMap.entries.map((e) {
      final alias = (e.value is Map) ? (e.value as Map)['alias'] as String? ?? '' : '';
      return OpenClawModelAlias(modelId: e.key, alias: alias);
    }).toList();

    // models.providers（自定义 Provider）
    final modelsRoot = config['models'] as Map<String, dynamic>? ?? {};
    final providersMap = modelsRoot['providers'] as Map<String, dynamic>? ?? {};
    final builtinIds = OpenClawProvider.builtinProviders.map((p) => p.id).toSet();
    final customProviders = providersMap.entries
        .where((e) => !builtinIds.contains(e.key) && e.value is Map<String, dynamic>)
        .map((e) => OpenClawCustomProvider.fromJson(e.key, e.value as Map<String, dynamic>))
        .toList();

    // gateway.port
    final gateway = config['gateway'] as Map<String, dynamic>? ?? {};
    final gatewayPort = gateway['port'] as int? ?? 18789;

    return OpenClawModelConfig(
      primaryModel: primary,
      fallbackModels: fallbacks,
      modelAliases: aliases,
      customProviders: customProviders,
      gatewayPort: gatewayPort,
    );
  }

  /// 保存模型配置（merge 策略，不破坏其他字段）
  Future<void> saveModelConfig(OpenClawModelConfig modelConfig) async {
    final config = await readConfig();

    // agents.defaults.model
    final agents = (config['agents'] as Map<String, dynamic>?) ?? {};
    final defaults = (agents['defaults'] as Map<String, dynamic>?) ?? {};

    if (modelConfig.primaryModel.isNotEmpty) {
      defaults['model'] = {
        'primary': modelConfig.primaryModel,
        if (modelConfig.fallbackModels.isNotEmpty) 'fallbacks': modelConfig.fallbackModels,
      };
    }

    // agents.defaults.models（别名）
    if (modelConfig.modelAliases.isNotEmpty) {
      final modelsMap = <String, dynamic>{};
      for (final alias in modelConfig.modelAliases) {
        modelsMap[alias.modelId] = {'alias': alias.alias};
      }
      defaults['models'] = modelsMap;
    }

    agents['defaults'] = defaults;
    config['agents'] = agents;

    // models.providers（自定义 Provider）
    if (modelConfig.customProviders.isNotEmpty) {
      final modelsRoot = (config['models'] as Map<String, dynamic>?) ?? {};
      final providersMap = (modelsRoot['providers'] as Map<String, dynamic>?) ?? {};
      for (final cp in modelConfig.customProviders) {
        providersMap[cp.id] = cp.toJson();
      }
      modelsRoot['providers'] = providersMap;
      config['models'] = modelsRoot;
    }

    // gateway.port
    if (modelConfig.gatewayPort != 18789) {
      final gateway = (config['gateway'] as Map<String, dynamic>?) ?? {};
      gateway['port'] = modelConfig.gatewayPort;
      config['gateway'] = gateway;
    }

    await writeConfig(config);
  }

  /// 删除自定义 Provider
  Future<void> removeCustomProvider(String providerId) async {
    final config = await readConfig();
    final modelsRoot = config['models'] as Map<String, dynamic>?;
    if (modelsRoot == null) return;
    final providersMap = modelsRoot['providers'] as Map<String, dynamic>?;
    if (providersMap == null) return;
    providersMap.remove(providerId);
    modelsRoot['providers'] = providersMap;
    config['models'] = modelsRoot;
    await writeConfig(config);
  }

  /// 读取内置供应商的 API Key（从 .env 文件）
  Future<Map<String, String>> readProviderApiKeys() async {
    final env = await readEnv();
    final result = <String, String>{};
    for (final p in OpenClawProvider.builtinProviders) {
      result[p.id] = env[p.envKey] ?? '';
    }
    return result;
  }

  /// 保存内置供应商的 API Key（写入 .env 文件）
  Future<void> saveProviderApiKeys(Map<String, String> keys) async {
    final updates = <String, String>{};
    for (final p in OpenClawProvider.builtinProviders) {
      if (keys.containsKey(p.id)) {
        updates[p.envKey] = keys[p.id]!;
      }
    }
    await writeEnvKeys(updates);
  }

  /// 保存自定义供应商的 API Key（写入 .env）
  Future<void> saveCustomProviderApiKey(String providerId, String apiKey) async {
    final envKey = '${providerId.toUpperCase()}_API_KEY';
    await writeEnvKeys({envKey: apiKey});
  }

  /// 读取自定义供应商的 API Key
  Future<String> readCustomProviderApiKey(String providerId) async {
    final envKey = '${providerId.toUpperCase()}_API_KEY';
    final env = await readEnv();
    return env[envKey] ?? '';
  }
}
