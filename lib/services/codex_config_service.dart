import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/ai_key.dart';
import '../models/platform_type.dart';
import '../services/platform_registry.dart';
import '../services/auth_service.dart';
import '../services/crypt_service.dart';
import '../services/settings_service.dart';
import '../services/cloud_config_service.dart';
import '../services/region_filter_service.dart';
import '../services/platform_config_path_service.dart';
import '../models/mcp_server.dart' show AiToolType;
import 'live_config/key_field_floor.dart';
import 'live_config/live_config_writer.dart';

/// Codex 供应商配置
class CodexProviderConfig {
  /// 是否支持 auth.json
  final bool supportsAuthJson;

  /// 环境变量名（如果不支持 auth.json）
  final String? envKeyName;

  /// 是否需要 OpenAI 认证
  final bool requiresOpenaiAuth;

  /// auth.json 中的 key 名（如果支持 auth.json）
  final String? authJsonKey;

  /// wire_api 值
  final String wireApi;

  /// 密钥放在哪里：
  /// - `bearerToken`：写入 provider 表的 `experimental_bearer_token`（Codex ≥ 0.149 的自定义
  ///   provider 不再读 auth.json 里的 Key，CC Switch v4 也采用此写法）；
  /// - `authJson`：写入 auth.json（旧版 Codex / 官方 OpenAI）；
  /// - `env`：只写 `env_key`，由用户在环境变量中提供。
  final String keyPlacement;

  const CodexProviderConfig({
    required this.supportsAuthJson,
    this.envKeyName,
    required this.requiresOpenaiAuth,
    this.authJsonKey,
    this.wireApi = 'chat',
    String? keyPlacement,
  }) : keyPlacement = keyPlacement ??
            (supportsAuthJson && authJsonKey != null ? 'authJson' : 'env');

  bool get useBearerToken => keyPlacement == 'bearerToken';

  /// 是否需要用户自行设置环境变量
  bool get needsEnvVar => keyPlacement == 'env' && envKeyName != null;

  /// 按密钥自身的设置（`AIKey.codexConfig`）覆盖规则
  CodexProviderConfig withKeyOverrides(Map<String, dynamic>? overrides) {
    if (overrides == null) return this;
    final placement = overrides['keyPlacement'];
    final wire = overrides['wireApi'];
    return CodexProviderConfig(
      supportsAuthJson: supportsAuthJson,
      envKeyName: envKeyName,
      requiresOpenaiAuth: requiresOpenaiAuth,
      authJsonKey: authJsonKey,
      wireApi: wire is String && wire.isNotEmpty ? wire : wireApi,
      keyPlacement: placement is String && const {'bearerToken', 'authJson', 'env'}.contains(placement)
          ? placement
          : keyPlacement,
    );
  }
}

/// Codex 配置服务
/// 管理 ~/.codex/config.toml 和 ~/.codex/auth.json 的读写
class CodexConfigService {
  /// 最近一次 switchProvider / switchToOfficial 失败的原因（成功时清空），供 UI 显示失败原因。
  Object? lastSwitchError;

  static const String _configFileName = 'config.toml';
  static const String _authFileName = 'auth.json';

  final AuthService _authService = AuthService();
  final CryptService _cryptService = CryptService();
  final SettingsService _settingsService = SettingsService();
  static final CloudConfigService _cloudConfigService = CloudConfigService();

  /// 供应商配置映射表
  /// 根据 platformType 和 baseUrl 识别供应商类型
  ///
  /// 判断规则：
  /// 1. **代理转发平台**（如 AnyRouter）：完全兼容 OpenAI API，支持 auth.json
  /// 2. **模型聚合平台**（如 OpenRouter）：虽然兼容 OpenAI API，但可能需要环境变量
  /// 3. **官方供应商**（如 OpenAI）：支持 auth.json
  /// 4. **Gemini/Claude**：Codex 本身不支持直接使用，需要通过聚合平台或代理平台
  /// 5. **其他第三方**：根据实际情况判断
  ///
  /// 注意：
  /// - Codex 是 OpenAI 的产品，主要支持 OpenAI 兼容的 API
  /// - Gemini 和 Claude 需要通过 OpenRouter 等聚合平台或代理转发平台使用
  /// - 如果通过聚合平台使用，按照聚合平台的配置方式处理
  Future<CodexProviderConfig> _getProviderConfig(AIKey key) async {
    final baseUrl = key.codexBaseUrl ?? '';
    final platformType = key.platformType;
    final baseUrlLower = baseUrl.toLowerCase();

    // 尝试从云端配置加载规则
    try {
      await _cloudConfigService.init();
      final configData = await _cloudConfigService.getConfigData();
      if (configData != null) {
        final authConfig = configData.codexAuthConfig;

        // 遍历规则，查找匹配的规则
        for (final rule in authConfig.rules) {
          bool platformMatches = true;
          bool urlMatches = true;

          // 检查平台类型匹配
          if (rule.platformType != null) {
            try {
              final rulePlatformType =
                  PlatformRegistry.fromString(rule.platformType!);
              platformMatches = rulePlatformType == platformType;
            } catch (e) {
              print('CodexConfigService: 无法解析平台类型 ${rule.platformType}: $e');
              platformMatches = false;
            }
          }

          // 检查 baseUrl 模式匹配
          if (rule.baseUrlPatterns != null &&
              rule.baseUrlPatterns!.isNotEmpty) {
            urlMatches = false;
            for (final pattern in rule.baseUrlPatterns!) {
              if (baseUrlLower.contains(pattern.toLowerCase())) {
                urlMatches = true;
                break;
              }
            }
          }

          // 只有当平台类型和 URL 都匹配时，才使用该规则
          if (platformMatches && urlMatches) {
            print(
                'CodexConfigService: 匹配到规则 platformType=${rule.platformType}, baseUrlPatterns=${rule.baseUrlPatterns}');
            return CodexProviderConfig(
              supportsAuthJson: rule.supportsAuthJson,
              envKeyName: rule.envKeyName,
              requiresOpenaiAuth: rule.requiresOpenaiAuth,
              authJsonKey: rule.authJsonKey,
              wireApi: rule.wireApi,
              keyPlacement: rule.keyPlacement,
            ).withKeyOverrides(key.codexConfig);
          }
        }

        // 如果没有匹配的规则，使用默认规则
        print('CodexConfigService: 未匹配到规则，使用默认规则');
        final defaultRule = authConfig.defaultRule;
        return CodexProviderConfig(
          supportsAuthJson: defaultRule.supportsAuthJson,
          envKeyName: defaultRule.envKeyName,
          requiresOpenaiAuth: defaultRule.requiresOpenaiAuth,
          authJsonKey: defaultRule.authJsonKey,
          wireApi: defaultRule.wireApi,
          keyPlacement: defaultRule.keyPlacement,
        ).withKeyOverrides(key.codexConfig);
      }
    } catch (e, stackTrace) {
      // 如果云端配置加载失败，使用硬编码逻辑（向后兼容）
      print('CodexConfigService: 从云端配置加载失败，使用默认逻辑: $e');
      print('CodexConfigService: 堆栈跟踪: $stackTrace');
    }

    // 硬编码逻辑（向后兼容，当云端配置不可用时使用）

    // OpenAI 官方：支持 auth.json
    // 注意：有消息称 Codex 支持 openai_api_key（小写），但目前使用 OPENAI_API_KEY（大写）已确认可用
    if (platformType == PlatformType.openAI ||
        baseUrlLower.contains('api.openai.com')) {
      return const CodexProviderConfig(
        supportsAuthJson: true,
        requiresOpenaiAuth: true,
        authJsonKey: 'OPENAI_API_KEY', // 使用已确认的大写格式
        wireApi: 'chat',
      );
    }

    // 代理转发平台：支持 auth.json（完全兼容 OpenAI API）
    // AnyRouter - 代理转发平台，支持 auth.json（已确认）
    // 注意：AnyRouter 使用 wire_api = "responses" 而不是 "chat"
    if (platformType == PlatformType.anyrouter ||
        baseUrlLower.contains('anyrouter.top') ||
        baseUrlLower.contains('anyrouter')) {
      return const CodexProviderConfig(
        supportsAuthJson: true,
        requiresOpenaiAuth: true,
        authJsonKey: 'OPENAI_API_KEY', // 使用已确认的格式
        wireApi: 'responses', // AnyRouter 使用 responses 而不是 chat
      );
    }

    // PackyCode - 代理转发平台，不支持 auth.json，需要使用环境变量
    if (platformType == PlatformType.packycode ||
        baseUrlLower.contains('packyapi.com') ||
        baseUrlLower.contains('packycode')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'PACKYCODE_API_KEY',
        requiresOpenaiAuth: true,
        wireApi: 'responses',
      );
    }

    // AiHubMix - 代理转发平台，支持 auth.json（已确认）
    if (platformType == PlatformType.aihubmix ||
        baseUrlLower.contains('aihubmix.com')) {
      return const CodexProviderConfig(
        supportsAuthJson: true,
        requiresOpenaiAuth: true,
        authJsonKey: 'OPENAI_API_KEY', // 使用已确认的格式
        wireApi: 'responses',
      );
    }

    // DMXAPI - 代理转发平台，支持 auth.json（已确认）
    if (platformType == PlatformType.dmxapi ||
        baseUrlLower.contains('dmxapi.cn')) {
      return const CodexProviderConfig(
        supportsAuthJson: true,
        requiresOpenaiAuth: true,
        authJsonKey: 'OPENAI_API_KEY', // 使用已确认的格式
        wireApi: 'responses',
      );
    }

    // Azure OpenAI：必须使用环境变量（企业级部署）
    if (platformType == PlatformType.azureOpenAI ||
        baseUrlLower.contains('azure.com') ||
        baseUrlLower.contains('openai.azure.com')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'AZURE_OPENAI_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'responses',
      );
    }

    // 模型聚合平台：必须使用环境变量
    // OpenRouter - 模型聚合平台，不支持 auth.json
    // 注意：OpenRouter 可以访问 Gemini 和 Claude 模型，但需要通过 OpenRouter 的 API
    if (platformType == PlatformType.openRouter ||
        baseUrlLower.contains('openrouter.ai')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'OPENROUTER_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // Hugging Face - 模型聚合平台
    if (platformType == PlatformType.huggingFace ||
        baseUrlLower.contains('huggingface.co')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'HUGGINGFACE_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // Google Gemini：Codex 本身不支持直接使用 Gemini API
    // 注意：有消息称 Codex 可能支持在 auth.json 中添加 google_api_key，但未找到官方文档确认
    // 目前保持使用环境变量的配置方式，待官方文档确认后再调整
    if (platformType == PlatformType.gemini ||
        baseUrlLower.contains('generativelanguage.googleapis.com') ||
        baseUrlLower.contains('googleapis.com/generativelanguage')) {
      // Gemini API 格式与 OpenAI 不兼容，Codex 可能不支持
      // 建议通过 OpenRouter 或代理平台使用
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'GOOGLE_GEMINI_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // Anthropic Claude：Codex 本身不支持直接使用 Claude API
    // 注意：有消息称 Codex 可能支持在 auth.json 中添加 anthropic_api_key，但未找到官方文档确认
    // 目前保持使用环境变量的配置方式，待官方文档确认后再调整
    if (platformType == PlatformType.anthropic ||
        baseUrlLower.contains('api.anthropic.com')) {
      // Claude API 格式与 OpenAI 不兼容，Codex 可能不支持
      // 建议通过 OpenRouter 或代理平台使用
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'ANTHROPIC_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // 智谱GLM：必须使用环境变量
    if (platformType == PlatformType.zhipu ||
        baseUrlLower.contains('bigmodel.cn') ||
        baseUrlLower.contains('open.bigmodel.cn')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'GLM_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // Kimi：必须使用环境变量
    if (platformType == PlatformType.kimi ||
        baseUrlLower.contains('moonshot.cn') ||
        baseUrlLower.contains('api.moonshot.cn')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: 'KIMI_API_KEY',
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // Ollama（本地）：通常无需 API 密钥
    if (platformType == PlatformType.ollama ||
        baseUrlLower.contains('localhost') ||
        baseUrlLower.contains('127.0.0.1')) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: null, // 本地运行通常无需密钥
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }

    // 其他第三方供应商：根据 baseUrl 特征判断
    // 如果 baseUrl 包含常见的代理转发平台特征，尝试使用 auth.json
    // 否则使用环境变量
    final isProxyPlatform = baseUrlLower.contains('/v1') &&
        (baseUrlLower.contains('api') ||
            baseUrlLower.contains('proxy') ||
            baseUrlLower.contains('gateway'));

    if (isProxyPlatform) {
      // 可能是代理转发平台，尝试使用 auth.json
      // 代理转发平台通常使用 wire_api = "responses"
      return const CodexProviderConfig(
        supportsAuthJson: true,
        requiresOpenaiAuth: true,
        authJsonKey: 'OPENAI_API_KEY', // 使用已确认的格式
        wireApi: 'responses', // 代理转发平台使用 responses
      );
    }

    // 默认：使用环境变量
    // 根据 baseUrl 尝试推断环境变量名
    String? inferredEnvKey;
    if (baseUrl.isNotEmpty) {
      // 尝试从 baseUrl 提取域名并生成环境变量名
      final uri = Uri.tryParse(baseUrl);
      if (uri != null && uri.host.isNotEmpty) {
        // 提取主域名并转换为环境变量格式
        final hostParts = uri.host.split('.');
        if (hostParts.isNotEmpty) {
          final domain =
              hostParts[hostParts.length > 2 ? hostParts.length - 2 : 0];
          inferredEnvKey = '${domain.toUpperCase()}_API_KEY';
        }
      }
    }

    // 默认配置：使用环境变量，环境变量名根据供应商名称或 baseUrl 推断
    return CodexProviderConfig(
      supportsAuthJson: false,
      envKeyName: inferredEnvKey ?? 'CODX_API_KEY', // 默认环境变量名
      requiresOpenaiAuth: false,
      wireApi: 'chat',
    );
  }

  // 缓存配置目录，避免重复获取和打印日志
  String? _cachedConfigDir;

  /// 获取 Codex 配置目录路径
  /// 优先使用自定义路径，否则使用平台默认路径
  /// macOS/Linux: ~/.codex
  /// Windows: %APPDATA%\.codex
  Future<String> _getConfigDir() async {
    // 如果已缓存，直接返回
    if (_cachedConfigDir != null) {
      return _cachedConfigDir!;
    }

    // 检查是否有自定义路径
    final customDir = _settingsService.getCodexConfigDir();

    // 使用统一的配置路径服务
    final configDir = await PlatformConfigPathService.getCodexConfigDir(
      customDir: customDir,
    );

    // 缓存结果
    _cachedConfigDir = configDir;
    return configDir;
  }

  /// 获取 config.toml 路径
  Future<String> _getConfigFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _configFileName);
  }

  /// 获取 auth.json 路径
  Future<String> _getAuthFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _authFileName);
  }

  /// 检测配置文件是否存在
  /// 返回配置文件路径和是否存在
  /// 如果目录存在但配置文件不存在，会自动创建默认配置文件
  Future<Map<String, dynamic>> checkConfigExists() async {
    final configDir = await _getConfigDir();
    final configPath = await _getConfigFilePath();
    final authPath = await _getAuthFilePath();

    final configDirObj = Directory(configDir);
    final configFile = File(configPath);
    final authFile = File(authPath);

    final dirExists = await configDirObj.exists();
    final configExists = await configFile.exists();
    final authExists = await authFile.exists();

    // 如果目录存在但配置文件不存在，自动创建默认配置文件
    if (dirExists && !configExists && !authExists) {
      print('CodexConfigService: 检测到目录存在但配置文件不存在，自动创建默认配置文件');
      await ensureConfigFilesIfDirExists();
      // 重新检查文件是否存在
      final configExistsAfter = await configFile.exists();
      final authExistsAfter = await authFile.exists();
      return {
        'configDir': configDir,
        'configPath': configPath,
        'authPath': authPath,
        'configExists': configExistsAfter,
        'authExists': authExistsAfter,
        'anyExists': configExistsAfter || authExistsAfter,
      };
    }

    return {
      'configDir': configDir,
      'configPath': configPath,
      'authPath': authPath,
      'configExists': configExists,
      'authExists': authExists,
      'anyExists': configExists || authExists,
    };
  }

  /// 如果目录存在但配置文件不存在，创建默认配置文件
  Future<bool> ensureConfigFilesIfDirExists() async {
    try {
      final configDir = await _getConfigDir();
      final configDirObj = Directory(configDir);

      // 检查目录是否存在
      if (!await configDirObj.exists()) {
        print('CodexConfigService: 配置目录不存在，跳过创建配置文件');
        return false;
      }

      final configPath = await _getConfigFilePath();
      final authPath = await _getAuthFilePath();

      final configFile = File(configPath);
      final authFile = File(authPath);

      // 如果配置文件已存在，不创建
      if (await configFile.exists() || await authFile.exists()) {
        print('CodexConfigService: 配置文件已存在，跳过创建');
        return false;
      }

      // 创建默认的 config.toml（空文件或最小配置）
      // Codex 的 config.toml 可以为空，官方配置不需要它
      await configFile.writeAsString('');

      // 创建默认的 auth.json
      final defaultAuth = <String, dynamic>{
        'OPENAI_API_KEY': '',
      };
      await authFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultAuth),
      );

      return true;
    } catch (e) {
      print('CodexConfigService: 创建默认配置文件失败: $e');
      return false;
    }
  }

  /// 读取 config.toml
  Future<String?> readConfigToml() async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);

      if (!await file.exists()) {
        return null;
      }

      return await file.readAsString();
    } catch (e) {
      return null;
    }
  }

  /// 读取 auth.json
  Future<Map<String, dynamic>?> readAuth() async {
    try {
      final authPath = await _getAuthFilePath();
      final file = File(authPath);

      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 生成 config.toml 内容
  /// 返回的配置包含：
  /// 1. 顶层配置（model_provider, model, model_reasoning_effort, disable_response_storage）
  /// 2. model_providers section
  /// 注意：末尾不包含空行，由调用者决定如何添加分隔符
  /// 从 config.toml 读取 Key Core provider 表中的 experimental_bearer_token（纯函数）
  static String? readBearerToken(String toml) {
    for (final t in _splitToml(toml).tables) {
      if (t.name != 'model_providers.$keycoreProviderId') continue;
      for (final l in t.lines) {
        if (_assignedKey(l) != 'experimental_bearer_token') continue;
        final m = RegExp(r'=\s*"((?:[^"\\]|\\.)*)"').firstMatch(l);
        if (m == null) return null;
        final v = m.group(1)!.replaceAllMapped(RegExp(r'\\(.)'), (x) => x.group(1) == 'n' ? '\n' : x.group(1)!);
        return v.trim().isEmpty ? null : v.trim();
      }
    }
    return null;
  }

  /// TOML 基本字符串转义
  static String _tomlString(String v) =>
      '"${v.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')}"';

  /// 生成 Key Core 的 config.toml 片段（纯函数，便于测试）
  ///
  /// - 路由表固定为 `[model_providers.keycore]`；
  /// - `bearerToken` 模式把密钥写成 `experimental_bearer_token`，`requires_openai_auth`
  ///   只有在 auth.json 中仍有 ChatGPT 登录时才为 true（否则 Codex 会卡在登录页，
  ///   规则同 CC Switch `live/project/codex.rs`）；
  /// - `model_reasoning_effort` 优先取密钥的 `codexConfig.reasoningEffort`。
  static String buildConfigToml(
    AIKey key,
    CodexProviderConfig providerConfig, {
    String? apiKey,
    bool loginOnDisk = false,
  }) {
    final baseUrl = key.codexBaseUrl ?? 'https://api.openai.com/v1';
    final model = key.codexModel ?? 'gpt-5-codex';
    final effortRaw = key.codexConfig?['reasoningEffort'];
    final effort = effortRaw is String && effortRaw.trim().isNotEmpty ? effortRaw.trim() : 'high';
    const id = keycoreProviderId;

    final buffer = StringBuffer();
    // 顶层配置（必须在文件开头）
    buffer.writeln('model_provider = "$id"');
    buffer.writeln('model = ${_tomlString(model)}');
    buffer.writeln('model_reasoning_effort = ${_tomlString(effort)}');
    buffer.writeln('disable_response_storage = true');
    buffer.writeln('');
    buffer.writeln('[model_providers.$id]');
    buffer.writeln('name = ${_tomlString(key.name.trim().isEmpty ? id : key.name.trim())}');
    buffer.writeln('base_url = ${_tomlString(baseUrl)}');
    buffer.writeln('wire_api = "${providerConfig.wireApi}"');
    if (providerConfig.useBearerToken && apiKey != null && apiKey.isNotEmpty) {
      buffer.writeln('requires_openai_auth = $loginOnDisk');
      buffer.writeln('experimental_bearer_token = ${_tomlString(apiKey)}');
    } else {
      buffer.writeln('requires_openai_auth = ${providerConfig.requiresOpenaiAuth}');
      // 不使用 auth.json 时设置 env_key（只写变量名，不写值）
      if (providerConfig.keyPlacement == 'env' && providerConfig.envKeyName != null) {
        buffer.writeln('env_key = "${providerConfig.envKeyName}"');
      }
    }
    return buffer.toString();
  }

  /// 写入配置（切换使用的密钥）
  /// 只更新我们添加的配置项，保留用户的其他配置
  Future<bool> switchProvider(AIKey key) async {
    lastSwitchError = null;
    try {
      if (await _isChinaRestrictedKey(key)) {
        lastSwitchError = '已开启地区限制，该供应商在当前地区不可用';
        return false;
      }

      // 解密密钥值
      String apiKey = key.keyValue;
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword && apiKey.startsWith('{')) {
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey != null) {
          apiKey = await _cryptService.decrypt(apiKey, encryptionKey);
        }
      }

      // 获取供应商配置
      final providerConfig = await _getProviderConfig(key);

      if (providerConfig.keyPlacement == 'env') {
        print(
            'CodexConfigService: 提示：需要在系统环境变量中设置 ${providerConfig.envKeyName}');
      }

      final authPath = await _getAuthFilePath();
      final configPath = await _getConfigFilePath();
      var loginOnDisk = false;

      // auth.json 与 config.toml 作为一次操作提交：任一文件读取/解析失败则都不写入
      await LiveConfigWriter.instance.apply(AiToolType.codex, [
        LiveEdit.json(
          authPath,
          (auth) {
            applyProviderToAuth(
              auth,
              apiKey: apiKey,
              authJsonKey: providerConfig.keyPlacement == 'authJson' ? providerConfig.authJsonKey : null,
            );
            loginOnDisk = auth['tokens'] is Map && (auth['tokens'] as Map).isNotEmpty;
          },
          containsSecrets: true,
        ),
        LiveEdit.text(
          configPath,
          (existing) => mergeConfigToml(
            existing,
            buildConfigToml(key, providerConfig, apiKey: apiKey, loginOnDisk: loginOnDisk),
          ),
          // bearerToken 模式下 config.toml 含密钥
          containsSecrets: providerConfig.useBearerToken,
        ),
      ]);

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      lastSwitchError = e;
      print('CodexConfigService: 切换配置失败: $e');
      return false;
    }
  }

  /// auth.json 中的密钥字段（纯函数，便于测试）
  ///
  /// - 供应商支持 auth.json：写入对应字段，其他键保持不变；
  /// - 需要环境变量的供应商：清除 Key Core 可能写过的密钥字段，避免冲突。
  static void applyProviderToAuth(
    Map<String, dynamic> auth, {
    required String apiKey,
    required String? authJsonKey,
  }) {
    if (authJsonKey != null) {
      auth[authJsonKey] = apiKey;
    } else {
      for (final k in KeyFieldFloor.codexAuthKeys) {
        auth.remove(k);
      }
    }
  }

  /// 删除 config.toml 中我们之前写入的配置，并把新的配置放到文件开头（纯函数）
  ///
  /// TOML 规定顶层键必须位于第一个表之前，因此新片段置顶；用户的其他配置逐行保留。
  static String mergeConfigToml(String existing, String newConfigToml) {
    final ours = _splitToml(newConfigToml.trimRight());
    // 用户已设置的通用偏好（如 model_reasoning_effort）沿用用户的值，不被预设覆盖（位置不变，保证幂等）
    final userPrefLines = <String, String>{
      for (final l in _splitToml(existing).preamble)
        if (_userPreferenceKeys.contains(_assignedKey(l))) _assignedKey(l)!: l,
    };
    final rest = _splitToml(_removeOurConfig(existing));
    final out = <String>[
      for (final l in _trimBlank(ours.preamble)) userPrefLines[_assignedKey(l)] ?? l,
    ];
    final ourKeys = ours.preamble.map(_assignedKey).toSet();
    out.addAll(userPrefLines.entries.where((e) => !ourKeys.contains(e.key)).map((e) => e.value));
    final userTop = _trimBlank(rest.preamble);
    if (userTop.isNotEmpty) {
      out
        ..add('')
        ..addAll(userTop);
    }
    // 顶层键必须位于第一张表之前：先写全部顶层键，再写我们的 provider 表，最后是用户的表
    for (final t in [...ours.tables, ...rest.tables]) {
      out
        ..add('')
        ..addAll(_trimBlank(t.lines));
    }
    return '${out.join('\n')}\n';
  }

  /// 备份当前配置
  ///
  /// 保留该方法以兼容调用方。备份现在由 [LiveConfigWriter] 在每次写入前自动完成
  /// （首写备份 + 滚动备份，位于 `~/.keycore/backups/live`）。
  Future<bool> backupConfig() async => true;

  /// 获取当前使用的 API Key
  /// 优先从 auth.json 读取（支持多种 key）
  /// 如果使用环境变量，返回 null（无法从应用内读取系统环境变量）
  Future<String?> getCurrentApiKey() async {
    try {
      // bearerToken 模式：密钥在 config.toml 的 Key Core provider 表里
      try {
        final configFile = File(await _getConfigFilePath());
        if (await configFile.exists()) {
          final bearer = readBearerToken(await configFile.readAsString());
          if (bearer != null) return bearer;
        }
      } catch (_) {}

      final auth = await readAuth();
      if (auth == null) {
        print('CodexConfigService: 无法读取 auth.json');
        return null;
      }

      // 按优先级尝试读取不同的 API key
      final keysToTry = [
        'OPENAI_API_KEY', // OpenAI（已确认支持）
        'OPENROUTER_API_KEY',
        'GLM_API_KEY',
        'KIMI_API_KEY',
        'AZURE_OPENAI_API_KEY',
        // 注意：以下 key 的支持情况未确认，暂时不读取
        // 'anthropic_api_key', 'ANTHROPIC_API_KEY',
        // 'google_api_key', 'GOOGLE_API_KEY',
      ];

      for (final key in keysToTry) {
        final apiKey = auth[key] as String?;
        if (apiKey != null && apiKey.isNotEmpty) {
          // 清理 API Key（去除首尾空白）
          final cleanedApiKey = apiKey.trim();
          return cleanedApiKey;
        }
      }

      print('CodexConfigService: auth.json 中没有找到任何 API key');
      return null;
    } catch (e) {
      print('CodexConfigService: 获取 API Key 失败: $e');
      return null;
    }
  }

  /// 获取指定密钥的供应商配置信息
  /// 返回供应商配置对象，用于判断是否支持 auth.json
  Future<CodexProviderConfig> getProviderConfig(AIKey key) async {
    if (await _isChinaRestrictedKey(key)) {
      return const CodexProviderConfig(
        supportsAuthJson: false,
        envKeyName: null,
        requiresOpenaiAuth: false,
        wireApi: 'chat',
      );
    }
    return await _getProviderConfig(key);
  }

  /// 生成环境变量设置命令
  /// 根据平台类型返回对应的命令（macOS/Linux 使用 export，Windows 使用 set）
  /// [permanent] 如果为 true，返回永久设置命令（添加到配置文件）；如果为 false，返回临时设置命令（仅当前会话）
  /// 返回格式：
  /// - 临时：export ENV_KEY_NAME="api_key_value"
  /// - 永久：echo 'export ENV_KEY_NAME="api_key_value"' >> ~/.zshrc
  Future<String?> generateEnvVarCommand(AIKey key,
      {bool permanent = false}) async {
    try {
      final providerConfig = await _getProviderConfig(key);

      // 如果不支持 auth.json，需要环境变量
      if (providerConfig.needsEnvVar) {
        // 解密密钥值
        String apiKey = key.keyValue;
        final hasPassword = await _authService.hasMasterPassword();
        if (hasPassword && apiKey.startsWith('{')) {
          final encryptionKey = await _authService.getEncryptionKey();
          if (encryptionKey != null) {
            apiKey = await _cryptService.decrypt(apiKey, encryptionKey);
          }
        }

        // 检测操作系统类型
        final isWindows = Platform.isWindows;
        final envKeyName = providerConfig.envKeyName!;

        if (isWindows) {
          if (permanent) {
            // Windows 永久设置：通过 setx 命令
            return 'setx $envKeyName "$apiKey"';
          } else {
            // Windows 临时设置：set ENV_KEY_NAME=api_key_value
            return 'set $envKeyName=$apiKey';
          }
        } else {
          // macOS/Linux
          // 转义特殊字符
          final escapedApiKey =
              apiKey.replaceAll('"', '\\"').replaceAll('\$', '\\\$');

          if (permanent) {
            // 检测 shell 类型（优先 zsh，然后是 bash）
            final shell = Platform.environment['SHELL'] ?? '/bin/zsh';
            String configFile;
            if (shell.contains('zsh')) {
              configFile = '~/.zshrc';
            } else {
              configFile = '~/.bashrc';
            }

            // 永久设置：添加到配置文件
            return 'echo \'export $envKeyName="$escapedApiKey"\' >> $configFile && source $configFile';
          } else {
            // 临时设置：export ENV_KEY_NAME="api_key_value"
            return 'export $envKeyName="$escapedApiKey"';
          }
        }
      }

      return null; // 支持 auth.json，不需要环境变量
    } catch (e) {
      print('CodexConfigService: 生成环境变量命令失败: $e');
      return null;
    }
  }

  /// 从 config.toml 解析当前配置信息
  /// 返回包含 model_provider 名称和 base_url 的 Map
  /// 如果解析失败或不是我们的配置，返回 null
  Future<Map<String, String>?> getCurrentConfigInfo() async {
    try {
      final configText = await readConfigToml();
      if (configText == null || configText.trim().isEmpty) {
        return null;
      }

      // 只读取 model_provider 指向的那张表的 base_url（旧实现会取到最后一张 provider 表）
      final parsed = _splitToml(configText);
      final modelProvider = parsed.preamble
          .where((l) => _assignedKey(l) == 'model_provider')
          .map((l) => RegExp(r'=\s*"([^"]+)"').firstMatch(l)?.group(1))
          .whereType<String>()
          .firstOrNull;
      String? baseUrl;
      if (modelProvider != null) {
        for (final t in parsed.tables) {
          var id = t.name.startsWith('model_providers.') ? t.name.substring(16).trim() : null;
          if (id != null && id.startsWith('"') && id.endsWith('"')) id = id.substring(1, id.length - 1);
          if (id == modelProvider) {
            baseUrl = _stringValue(t.lines, 'base_url');
            break;
          }
        }
      }

      if (modelProvider != null && baseUrl != null) {
        return {
          'model_provider': modelProvider,
          'base_url': baseUrl,
        };
      }

      return null;
    } catch (e) {
      print('CodexConfigService: 解析 config.toml 失败: $e');
      return null;
    }
  }

  /// 获取当前供应商配置信息（从配置文件读取）
  /// 返回供应商配置对象，用于判断是否支持 auth.json
  /// 注意：此方法需要完整的 key 信息才能准确判断，建议使用 getProviderConfig(AIKey key)
  Future<CodexProviderConfig?> getCurrentProviderConfig() async {
    try {
      final configText = await readConfigToml();
      if (configText == null || configText.trim().isEmpty) {
        return null; // 官方配置
      }

      // 尝试从 config.toml 中提取信息
      // 这里简化处理，实际应该解析完整的 config.toml
      // 由于需要完整的 key 信息才能准确判断，这里返回 null
      // 调用者应该传入完整的 AIKey 对象来获取配置
      return null;
    } catch (e) {
      print('CodexConfigService: 获取供应商配置失败: $e');
      return null;
    }
  }

  /// 判断当前是否是官方配置
  /// 官方配置的特征：没有我们添加的配置项（model_provider 或 model_providers.xxx section）
  // 缓存官方配置检查结果，避免重复读取文件
  bool? _cachedIsOfficial;
  DateTime? _cachedIsOfficialTime;
  static const _cacheTimeout = Duration(seconds: 5); // 缓存5秒

  Future<bool> isOfficialConfig() async {
    // 检查缓存是否有效
    if (_cachedIsOfficial != null &&
        _cachedIsOfficialTime != null &&
        DateTime.now().difference(_cachedIsOfficialTime!) < _cacheTimeout) {
      return _cachedIsOfficial!;
    }

    try {
      final configText = await readConfigToml();

      // 如果 config.toml 不存在或为空，视为官方配置
      if (configText == null || configText.trim().isEmpty) {
        _cachedIsOfficial = true;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }

      // 检查是否包含我们添加的配置项
      // 我们添加的配置项包括：
      // 1. 顶层配置：model_provider, model, model_reasoning_effort, disable_response_storage
      // 2. model_providers.xxx section
      final trimmedConfig = configText.trim();

      // 检查是否有 model_provider 配置（我们添加的顶层配置）
      if (trimmedConfig.contains('model_provider =') ||
          trimmedConfig.contains('model_provider=')) {
        _cachedIsOfficial = false;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }

      // 检查是否有 model_providers.xxx section（我们添加的 provider section）
      // 使用正则表达式匹配 [model_providers.xxx] 格式
      final providerSectionPattern = RegExp(r'\[model_providers\.[^\]]+\]');
      if (providerSectionPattern.hasMatch(trimmedConfig)) {
        _cachedIsOfficial = false;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }

      // 如果没有我们添加的配置项，视为官方配置
      _cachedIsOfficial = true;
      _cachedIsOfficialTime = DateTime.now();
      return _cachedIsOfficial!;
    } catch (e) {
      // 出错时返回 false，不缓存错误结果
      return false;
    }
  }

  /// 清除官方配置缓存（在配置更新后调用）
  void _clearOfficialConfigCache() {
    _cachedIsOfficial = null;
    _cachedIsOfficialTime = null;
  }

  /// Key Core 写入 config.toml 的路由表 id（固定，与 CC Switch 的 `custom` 同理：
  /// 切换密钥不改变表 id，Codex 的会话历史不会因换密钥而分桶）
  static const String keycoreProviderId = 'keycore';

  /// 我们写入的顶层键
  /// 通用偏好：切换时保留用户已有的值，切回官方时也保留（对官方同样有效）
  static const Set<String> _userPreferenceKeys = {'model_reasoning_effort'};

  static const Set<String> _ourTopLevelKeys = {
    'model_provider',
    'model',
    'model_reasoning_effort',
    'disable_response_storage',
  };

  /// 旧版本 Key Core 写入 provider 表的全部键（用于识别并清理旧版按密钥名命名的表）
  static const Set<String> _legacyProviderKeys = {
    'name',
    'base_url',
    'wire_api',
    'requires_openai_auth',
    'env_key',
    'experimental_bearer_token',
  };

  static final RegExp _tableHeader = RegExp(r'^\s*\[\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$');
  static final RegExp _assignment = RegExp(r'^\s*([A-Za-z0-9_\-]+|"[^"]*")\s*=');

  /// 把 config.toml 切成“顶层区”与若干“表”（表头行 + 表体），逐行保留原文。
  static ({List<String> preamble, List<({String name, List<String> lines})> tables}) _splitToml(
      String content) {
    final preamble = <String>[];
    final tables = <({String name, List<String> lines})>[];
    List<String>? current;
    var inMultiline = false;
    for (final line in content.split('\n')) {
      final header = inMultiline ? null : _tableHeader.firstMatch(line);
      if (header != null) {
        current = [line];
        tables.add((name: header.group(1)!.trim(), lines: current));
      } else {
        (current ?? preamble).add(line);
      }
      // 粗略跟踪多行字符串/数组，避免把其中的 "[x]" 误认为表头
      final quotes = '"""'.allMatches(line).length + "'''".allMatches(line).length;
      if (quotes.isOdd) inMultiline = !inMultiline;
    }
    return (preamble: preamble, tables: tables);
  }

  static String? _assignedKey(String line) {
    final t = line.trimLeft();
    if (t.isEmpty || t.startsWith('#')) return null;
    final m = _assignment.firstMatch(line);
    if (m == null) return null;
    var k = m.group(1)!;
    if (k.startsWith('"')) k = k.substring(1, k.length - 1);
    return k;
  }

  static String? _stringValue(List<String> lines, String key) {
    for (final l in lines) {
      if (_assignedKey(l) == key) {
        final m = RegExp(r'=\s*"([^"]*)"').firstMatch(l);
        return m?.group(1);
      }
    }
    return null;
  }

  /// 是否为 Key Core 写入的 provider 表：固定 id，或旧版“按密钥名命名、只含我们写的键”的表
  static bool _isOurProviderTable(({String name, List<String> lines}) table) {
    if (!table.name.startsWith('model_providers.')) return false;
    var id = table.name.substring('model_providers.'.length).trim();
    if (id.startsWith('"') && id.endsWith('"')) id = id.substring(1, id.length - 1);
    if (id == keycoreProviderId) return true;
    final keys = table.lines.skip(1).map(_assignedKey).whereType<String>().toSet();
    if (keys.isEmpty || !keys.every(_legacyProviderKeys.contains)) return false;
    return _stringValue(table.lines, 'name') == id;
  }

  static List<String> _trimBlank(List<String> lines) {
    var a = 0, b = lines.length;
    while (a < b && lines[a].trim().isEmpty) {
      a++;
    }
    while (b > a && lines[b - 1].trim().isEmpty) {
      b--;
    }
    return lines.sublist(a, b);
  }

  /// 移除我们添加的配置项（纯函数）
  ///
  /// - 顶层区：只删除我们写的 4 个顶层键，其余顶层设置（approval_policy 等）与注释保留；
  /// - 表：只删除 Key Core 的 provider 表；用户自己的 `[model_providers.*]`、MCP、projects 等原样保留。
  ///
  /// 旧实现会删除所有 `[model_providers.*]` 表头并把其中不认识的键遗留到上一张表里，
  /// 还会把用户的顶层设置挪到我们的 provider 表之后（变成 provider 的字段），已修复。
  static String _removeOurConfig(String configContent, {Set<String> topLevelKeys = _ourTopLevelKeys}) {
    if (configContent.trim().isEmpty) return configContent;
    final split = _splitToml(configContent);
    final out = <String>[];
    out.addAll(_trimBlank(
        split.preamble.where((l) => !topLevelKeys.contains(_assignedKey(l))).toList()));
    for (final t in split.tables) {
      if (_isOurProviderTable(t)) continue;
      final body = _trimBlank(t.lines);
      if (out.isNotEmpty) out.add('');
      out.addAll(body);
    }
    return out.join('\n');
  }

  /// 切换回官方配置
  /// 删除我们添加的配置项，并写入本地存储的官方 API Key（如果有）
  /// 保留用户的其他配置
  Future<bool> switchToOfficial() async {
    lastSwitchError = null;
    try {
      final isChinaFilterEnabled =
          await RegionFilterService.isChinaRegionFilterEnabled();
      if (isChinaFilterEnabled) {
        lastSwitchError = '已开启地区限制，无法切换到 Codex 官方配置';
        return false;
      }

      print('CodexConfigService: 切换到官方配置');

      // 确保 SettingsService 已初始化（官方 API Key 存于系统钥匙串）
      await _settingsService.init();
      final officialApiKey = _settingsService.getOfficialCodexApiKey();

      final configPath = await _getConfigFilePath();
      final authPath = await _getAuthFilePath();

      await LiveConfigWriter.instance.apply(AiToolType.codex, [
        // config.toml：只删除我们添加的配置项（文件不存在则不创建）
        LiveEdit(configPath, (current) {
          if (current == null) return null;
          return cleanConfigTomlForOfficial(current);
        }),
        // auth.json：清除我们可能写入的密钥，有官方 Key 时写入 OPENAI_API_KEY
        LiveEdit.json(
          authPath,
          (auth) {
            for (final k in KeyFieldFloor.codexAuthKeys) {
              auth.remove(k);
            }
            if (officialApiKey != null && officialApiKey.isNotEmpty) {
              auth['OPENAI_API_KEY'] = officialApiKey;
            }
          },
          containsSecrets: true,
        ),
      ]);

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      lastSwitchError = e;
      print('CodexConfigService: 切换到官方配置失败: $e');
      return false;
    }
  }

  /// 切回官方时清理 config.toml（纯函数）：删除我们添加的配置；
  /// 若剩余内容只有空白或注释则清空文件。
  static String cleanConfigTomlForOfficial(String current) {
    final cleaned = _removeOurConfig(current, topLevelKeys: _ourTopLevelKeys.difference(_userPreferenceKeys));
    final trimmed = cleaned.trim();
    if (trimmed.isEmpty ||
        trimmed.split('\n').every((line) => line.trim().isEmpty || line.trim().startsWith('#'))) {
      return '';
    }
    return cleaned;
  }

  Future<bool> _isChinaRestrictedKey(AIKey key) async {
    final isChinaFilterEnabled =
        await RegionFilterService.isChinaRegionFilterEnabled();
    if (!isChinaFilterEnabled) {
      return false;
    }

    return RegionFilterService.isKeyRestrictedInChina(
      platformId: key.platformType.id,
      platformName: key.platform,
      apiEndpoint: key.apiEndpoint,
      codexBaseUrl: key.codexBaseUrl,
      claudeCodeBaseUrl: key.claudeCodeBaseUrl,
      managementUrl: key.managementUrl,
    );
  }
}
