import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/ai_key.dart';
import '../models/platform_type.dart';
import '../services/platform_registry.dart';
import '../services/auth_service.dart';
import '../services/crypt_service.dart';
import '../services/settings_service.dart';
import '../services/cloud_config_service.dart';
import '../models/cloud_config.dart' as cloud;
import '../services/platform_config_path_service.dart';

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

  const CodexProviderConfig({
    required this.supportsAuthJson,
    this.envKeyName,
    required this.requiresOpenaiAuth,
    this.authJsonKey,
    this.wireApi = 'chat',
  });
}

/// Codex 配置服务
/// 管理 ~/.codex/config.toml 和 ~/.codex/auth.json 的读写
class CodexConfigService {
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
              final rulePlatformType = PlatformRegistry.fromString(rule.platformType!);
              platformMatches = rulePlatformType == platformType;
            } catch (e) {
              print('CodexConfigService: 无法解析平台类型 ${rule.platformType}: $e');
              platformMatches = false;
            }
          }
          
          // 检查 baseUrl 模式匹配
          if (rule.baseUrlPatterns != null && rule.baseUrlPatterns!.isNotEmpty) {
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
            print('CodexConfigService: 匹配到规则 platformType=${rule.platformType}, baseUrlPatterns=${rule.baseUrlPatterns}');
            return CodexProviderConfig(
              supportsAuthJson: rule.supportsAuthJson,
              envKeyName: rule.envKeyName,
              requiresOpenaiAuth: rule.requiresOpenaiAuth,
              authJsonKey: rule.authJsonKey,
              wireApi: rule.wireApi,
            );
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
        );
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
          final domain = hostParts[hostParts.length > 2 ? hostParts.length - 2 : 0];
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
      print('CodexConfigService: 创建默认 config.toml: $configPath');
      
      // 创建默认的 auth.json
      final defaultAuth = <String, dynamic>{
        'OPENAI_API_KEY': '',
      };
      await authFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultAuth),
      );
      print('CodexConfigService: 创建默认 auth.json: $authPath');
      
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
  Future<String> _generateConfigToml(AIKey key) async {
    final baseUrl = key.codexBaseUrl ?? 'https://api.openai.com/v1';
    final model = key.codexModel ?? 'gpt-5-codex';
    
    // 获取供应商配置
    final providerConfig = await _getProviderConfig(key);
    
    // 清理供应商名称，确保符合TOML键名规范
    final providerName = key.name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    
    final cleanProviderName = providerName.isEmpty ? 'custom' : providerName;
    
    final buffer = StringBuffer();
    // 顶层配置（必须在文件开头）
    buffer.writeln('model_provider = "$cleanProviderName"');
    buffer.writeln('model = "$model"');
    buffer.writeln('model_reasoning_effort = "high"');
    buffer.writeln('disable_response_storage = true');
    buffer.writeln('');
    // model_providers section
    buffer.writeln('[model_providers.$cleanProviderName]');
    buffer.writeln('name = "$cleanProviderName"');
    buffer.writeln('base_url = "$baseUrl"');
    buffer.writeln('wire_api = "${providerConfig.wireApi}"');
    buffer.writeln('requires_openai_auth = ${providerConfig.requiresOpenaiAuth}');
    
    // 如果不支持 auth.json，设置 env_key（只写变量名，不写值）
    if (!providerConfig.supportsAuthJson && providerConfig.envKeyName != null) {
      buffer.writeln('env_key = "${providerConfig.envKeyName}"');
    }
    
    return buffer.toString();
  }

  /// 写入配置（切换使用的密钥）
  /// 只更新我们添加的配置项，保留用户的其他配置
  Future<bool> switchProvider(AIKey key) async {
    try {
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
      
      // 读取现有的 auth.json，保留用户的其他密钥
      final authPath = await _getAuthFilePath();
      final authFile = File(authPath);
      Map<String, dynamic> auth = {};
      
      if (await authFile.exists()) {
        try {
          final existingContent = await authFile.readAsString();
          auth = jsonDecode(existingContent) as Map<String, dynamic>;
        } catch (e) {
          print('CodexConfigService: 读取现有 auth.json 失败，将创建新文件: $e');
          auth = {};
        }
      }
      
      // 根据供应商类型处理 auth.json
      if (providerConfig.supportsAuthJson && providerConfig.authJsonKey != null) {
        // 支持 auth.json 的供应商：更新对应的 key
        auth[providerConfig.authJsonKey!] = apiKey;
        print('CodexConfigService: 使用 auth.json 配置，key: ${providerConfig.authJsonKey}');
      } else {
        // 必须使用环境变量的供应商：清除之前可能存在的相关 key
        // 清除常见的 API key 字段，避免冲突
        final keysToRemove = [
          'OPENAI_API_KEY',
          'OPENROUTER_API_KEY',
          'GLM_API_KEY',
          'KIMI_API_KEY',
          'AZURE_OPENAI_API_KEY',
          'ANTHROPIC_API_KEY',
          'GOOGLE_GEMINI_API_KEY',
        ];
        for (final keyToRemove in keysToRemove) {
          auth.remove(keyToRemove);
        }
        print('CodexConfigService: 使用环境变量配置，env_key: ${providerConfig.envKeyName}');
        print('CodexConfigService: 提示：需要在系统环境变量中设置 ${providerConfig.envKeyName}');
      }
      
      // 读取现有的 config.toml，保留用户的其他配置
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      String existingConfig = '';
      
      if (await configFile.exists()) {
        try {
          existingConfig = await configFile.readAsString();
        } catch (e) {
          print('CodexConfigService: 读取现有 config.toml 失败: $e');
        }
      }
      
      // 生成新的 config.toml（我们添加的配置）
      final newConfigToml = await _generateConfigToml(key);
      
      // 合并配置：先删除我们之前添加的配置，然后添加新的配置
      String mergedConfig = _removeOurConfig(existingConfig);
      
      // 清理合并后配置末尾的空行
      mergedConfig = mergedConfig.trimRight();
      
      // 将新配置添加到文件开头（符合 TOML 规范：顶层配置应在文件开头）
      // _generateConfigToml 已经在末尾包含了空行
      if (mergedConfig.isNotEmpty) {
        // 如果现有配置不为空，在新配置后添加一个换行符作为分隔符
        mergedConfig = newConfigToml + '\n' + mergedConfig;
      } else {
        // 如果现有配置为空，直接使用新配置
        mergedConfig = newConfigToml;
      }
      
      // 确保配置目录存在
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入 auth.json（保留用户的其他密钥）
      await authFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(auth),
      );
      
      // 写入 config.toml（合并后的配置）
      await configFile.writeAsString(mergedConfig);
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      return true;
    } catch (e) {
      print('CodexConfigService: 切换配置失败: $e');
      return false;
    }
  }

  /// 备份当前配置
  Future<bool> backupConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      
      if (await configFile.exists()) {
        final backupPath = '$configPath.bak';
        await configFile.copy(backupPath);
      }
      
      final authPath = await _getAuthFilePath();
      final authFile = File(authPath);
      
      if (await authFile.exists()) {
        final authBackupPath = '$authPath.bak';
        await authFile.copy(authBackupPath);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前使用的 API Key
  /// 优先从 auth.json 读取（支持多种 key）
  /// 如果使用环境变量，返回 null（无法从应用内读取系统环境变量）
  Future<String?> getCurrentApiKey() async {
    try {
      final auth = await readAuth();
      if (auth == null) {
        print('CodexConfigService: 无法读取 auth.json');
        return null;
      }
      
      // 按优先级尝试读取不同的 API key
      final keysToTry = [
        'OPENAI_API_KEY',      // OpenAI（已确认支持）
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
          print('CodexConfigService: 从 auth.json 找到 API Key ($key, 长度: ${cleanedApiKey.length})');
          return cleanedApiKey;
        }
      }
      
      print('CodexConfigService: auth.json 中没有找到任何 API key');
      print('CodexConfigService: 可能使用环境变量配置，无法从应用内读取');
      return null;
    } catch (e) {
      print('CodexConfigService: 获取 API Key 失败: $e');
      return null;
    }
  }
  
  /// 获取指定密钥的供应商配置信息
  /// 返回供应商配置对象，用于判断是否支持 auth.json
  Future<CodexProviderConfig> getProviderConfig(AIKey key) async {
    return await _getProviderConfig(key);
  }
  
  /// 生成环境变量设置命令
  /// 根据平台类型返回对应的命令（macOS/Linux 使用 export，Windows 使用 set）
  /// [permanent] 如果为 true，返回永久设置命令（添加到配置文件）；如果为 false，返回临时设置命令（仅当前会话）
  /// 返回格式：
  /// - 临时：export ENV_KEY_NAME="api_key_value"
  /// - 永久：echo 'export ENV_KEY_NAME="api_key_value"' >> ~/.zshrc
  Future<String?> generateEnvVarCommand(AIKey key, {bool permanent = false}) async {
    try {
      final providerConfig = await _getProviderConfig(key);
      
      // 如果不支持 auth.json，需要环境变量
      if (!providerConfig.supportsAuthJson && providerConfig.envKeyName != null) {
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
          final escapedApiKey = apiKey.replaceAll('"', '\\"').replaceAll('\$', '\\\$');
          
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
      
      final lines = configText.split('\n');
      String? modelProvider;
      String? baseUrl;
      String? currentProviderSection;
      bool inProviderSection = false;
      
      for (final line in lines) {
        final trimmed = line.trim();
        
        // 解析 model_provider
        if (trimmed.startsWith('model_provider =') || trimmed.startsWith('model_provider=')) {
          final match = RegExp(r'model_provider\s*=\s*"([^"]+)"').firstMatch(trimmed);
          if (match != null) {
            modelProvider = match.group(1);
          }
        }
        
        // 检测进入 provider section
        if (trimmed.startsWith('[model_providers.') && trimmed.endsWith(']')) {
          final match = RegExp(r'\[model_providers\.([^\]]+)\]').firstMatch(trimmed);
          if (match != null) {
            currentProviderSection = match.group(1);
            inProviderSection = true;
          }
        }
        
        // 如果在 provider section 中，解析 base_url
        if (inProviderSection && (trimmed.startsWith('base_url =') || trimmed.startsWith('base_url='))) {
          final match = RegExp(r'base_url\s*=\s*"([^"]+)"').firstMatch(trimmed);
          if (match != null) {
            baseUrl = match.group(1);
          }
        }
        
        // 检测离开 provider section（遇到新的 section）
        if (inProviderSection && trimmed.isNotEmpty) {
          // 如果遇到新的 section 头（但不是 model_providers section），说明离开了当前 section
          if (trimmed.startsWith('[') && !trimmed.startsWith('[model_providers.')) {
            inProviderSection = false;
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

  /// 移除我们添加的配置项
  /// 只删除我们生成的配置，保留用户的其他配置
  /// 同时清理配置块前后的空行，避免空行累积
  String _removeOurConfig(String configContent) {
    if (configContent.trim().isEmpty) {
      return configContent;
    }
    
    final lines = configContent.split('\n');
    final result = <String>[];
    bool inOurProviderSection = false;
    int providerSectionIndent = 0;
    bool inLegacyConfigBlock = false; // 标记是否在遗留的配置块中
    int emptyLinesBeforeBlock = 0; // 配置块前的空行数
    bool justEndedBlock = false; // 刚刚结束配置块
    
    // 我们添加的顶层配置项
    final ourTopLevelKeys = {
      'model_provider',
      'model',
      'model_reasoning_effort',
      'disable_response_storage',
    };
    
    // 我们添加的 provider section 内的配置项
    final ourProviderKeys = {
      'name',
      'base_url',
      'wire_api',
      'requires_openai_auth',
      'env_key', // 新增：环境变量名配置
    };
    
    /// 检查一行是否是我们添加的配置项
    bool isOurConfigKey(String trimmed, Set<String> keys) {
      for (final key in keys) {
        if (trimmed.startsWith('$key =') || trimmed.startsWith('$key=')) {
          return true;
        }
      }
      return false;
    }
    
    /// 检查下一行是否是我们添加的配置项
    bool isNextOurConfig(List<String> lines, int currentIndex, Set<String> keys) {
      for (int j = currentIndex + 1; j < lines.length; j++) {
        final nextTrimmed = lines[j].trim();
        if (nextTrimmed.isEmpty) {
          continue; // 跳过连续的空行
        }
        if (nextTrimmed.startsWith('#')) {
          return false; // 遇到注释，不是我们的配置
        }
        return isOurConfigKey(nextTrimmed, keys);
      }
      return false;
    }
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      
      // 检查是否是section头 [xxx]
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        final sectionName = trimmed.substring(1, trimmed.length - 1).trim();
        
        // 结束遗留配置块
        if (inLegacyConfigBlock || justEndedBlock) {
          // 清理配置块后的空行
          while (result.isNotEmpty && result.last.trim().isEmpty) {
            result.removeLast();
          }
          justEndedBlock = false;
        }
        inLegacyConfigBlock = false;
        emptyLinesBeforeBlock = 0;
        
        // 检查是否是我们的model_providers section
        if (sectionName.startsWith('model_providers.')) {
          inOurProviderSection = true;
          providerSectionIndent = _getIndentLevel(line);
          // 清理section前的空行（如果存在）
          while (result.isNotEmpty && result.last.trim().isEmpty) {
            result.removeLast();
          }
          // 跳过这个section头
          continue;
        } else {
          // 遇到其他section，结束我们的section
          inOurProviderSection = false;
          result.add(line);
          continue;
        }
      }
      
      // 如果在我们添加的provider section中，跳过所有行
      if (inOurProviderSection) {
        final currentIndent = _getIndentLevel(line);
        // 如果缩进小于等于section头的缩进，说明已经离开了这个section
        if (currentIndent <= providerSectionIndent && trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          inOurProviderSection = false;
          // 清理section后的空行
          while (result.isNotEmpty && result.last.trim().isEmpty) {
            result.removeLast();
          }
          // 不跳过这一行，继续处理
        } else {
          // 仍在我们的section中，跳过这一行
          continue;
        }
      }
      
      // 处理遗留的配置块（没有section头，但包含我们的配置项）
      if (trimmed.isEmpty) {
        // 空行：如果在遗留配置块中，检查下一行是否还是我们的配置
        if (inLegacyConfigBlock) {
          // 检查下一行是否还是我们的配置项
          bool nextIsOurConfig = isNextOurConfig(lines, i, ourProviderKeys);
          
          if (!nextIsOurConfig) {
            // 下一行不是我们的配置，结束配置块
            inLegacyConfigBlock = false;
            justEndedBlock = true;
            // 跳过这个空行（不保留，因为是我们添加的配置块后的空行）
            continue;
          }
          // 如果在配置块中且下一行还是我们的配置，跳过这个空行
          continue;
        } else if (justEndedBlock) {
          // 刚刚结束配置块，跳过后续的空行
          continue;
        } else {
          // 检查下一行是否是我们配置的开始
          bool nextIsOurConfig = isNextOurConfig(lines, i, ourProviderKeys) ||
              isNextOurConfig(lines, i, ourTopLevelKeys);
          
          if (nextIsOurConfig) {
            // 下一行是我们的配置，记录这个空行，但不立即添加
            emptyLinesBeforeBlock++;
            continue;
          } else {
            // 不在配置块中，保留空行
            result.add(line);
            continue;
          }
        }
      }
      
      // 检查是否是注释
      if (trimmed.startsWith('#')) {
        // 注释会结束遗留配置块
        if (inLegacyConfigBlock || justEndedBlock) {
          // 清理配置块后的空行
          while (result.isNotEmpty && result.last.trim().isEmpty) {
            result.removeLast();
          }
          inLegacyConfigBlock = false;
          justEndedBlock = false;
          emptyLinesBeforeBlock = 0;
        }
        result.add(line);
        continue;
      }
      
      // 检查是否是我们的顶层配置项（无论出现在哪里，包括在 MCP 服务器节中）
      // 这些配置项应该只在文件顶层，如果出现在其他地方（如 MCP 服务器节中），也应该删除
      if (isOurConfigKey(trimmed, ourTopLevelKeys)) {
        // 清理配置块前的空行
        emptyLinesBeforeBlock = 0;
        // 跳过顶层配置项（无论出现在哪里）
        continue;
      }
      
      // 检查是否是我们的provider配置项
      if (isOurConfigKey(trimmed, ourProviderKeys)) {
        // 清理配置块前的空行（不保留）
        emptyLinesBeforeBlock = 0;
        // 开始或继续遗留配置块
        inLegacyConfigBlock = true;
        justEndedBlock = false;
        // 跳过这一行
        continue;
      }
      
      // 不是我们的配置项
      if (inLegacyConfigBlock || justEndedBlock) {
        // 遇到非我们的配置项，结束配置块
        inLegacyConfigBlock = false;
        justEndedBlock = false;
        emptyLinesBeforeBlock = 0;
        // 清理配置块后的空行
        while (result.isNotEmpty && result.last.trim().isEmpty) {
          result.removeLast();
        }
      }
      
      // 保留这一行
      result.add(line);
    }
    
    // 清理末尾的空行
    while (result.isNotEmpty && result.last.trim().isEmpty) {
      result.removeLast();
    }
    
    return result.join('\n');
  }
  
  /// 获取行的缩进级别（空格数）
  int _getIndentLevel(String line) {
    int indent = 0;
    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        indent++;
      } else if (line[i] == '\t') {
        indent += 4; // 将tab视为4个空格
      } else {
        break;
      }
    }
    return indent;
  }

  /// 切换回官方配置
  /// 删除我们添加的配置项，并写入本地存储的官方 API Key（如果有）
  /// 保留用户的其他配置
  Future<bool> switchToOfficial() async {
    try {
      print('CodexConfigService: 切换到官方配置');
      
      // 备份当前配置
      await backupConfig();
      
      // 确保 SettingsService 已初始化
      await _settingsService.init();
      
      // 读取本地存储的官方 API Key
      final officialApiKey = _settingsService.getOfficialCodexApiKey();
      
      // 读取现有的 config.toml，只删除我们添加的配置项
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      
      if (await configFile.exists()) {
        final currentContent = await configFile.readAsString();
        final cleanedContent = _removeOurConfig(currentContent);
        
        // 如果清理后内容为空或只有空白/注释，则清空文件
        final trimmedCleaned = cleanedContent.trim();
        if (trimmedCleaned.isEmpty || 
            trimmedCleaned.split('\n').every((line) => 
              line.trim().isEmpty || line.trim().startsWith('#'))) {
          await configFile.writeAsString('');
          print('CodexConfigService: 删除我们添加的配置后，config.toml 为空，已清空文件');
        } else {
          await configFile.writeAsString(cleanedContent);
          print('CodexConfigService: 已删除我们添加的配置项，保留其他配置');
        }
      } else {
        print('CodexConfigService: config.toml 不存在，无需处理');
      }
      
      // 处理 auth.json：清除我们添加的所有可能的 API key，然后写入官方 API Key
      final authPath = await _getAuthFilePath();
      final authFile = File(authPath);
      Map<String, dynamic> auth = {};
      
      if (await authFile.exists()) {
        try {
          final existingContent = await authFile.readAsString();
          auth = jsonDecode(existingContent) as Map<String, dynamic>;
        } catch (e) {
          print('CodexConfigService: 读取 auth.json 失败: $e');
          auth = {};
        }
      }
      
      // 移除我们可能添加的所有 API key（支持多种供应商）
      final keysToRemove = [
        'OPENAI_API_KEY',
        'OPENROUTER_API_KEY',
        'GLM_API_KEY',
        'KIMI_API_KEY',
        'AZURE_OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'GOOGLE_GEMINI_API_KEY',
      ];
      for (final keyToRemove in keysToRemove) {
        auth.remove(keyToRemove);
      }
      
      // 根据本地存储的官方 API Key 设置或删除 OPENAI_API_KEY
      if (officialApiKey != null && officialApiKey.isNotEmpty) {
        // 如果本地有存储的官方 API Key，写入到 auth.json
        auth['OPENAI_API_KEY'] = officialApiKey;
        print('CodexConfigService: 使用本地存储的官方 Codex API Key');
      } else {
        // 如果本地没有存储官方 API Key，确保清空（已经remove了）
        print('CodexConfigService: 本地未存储官方 Codex API Key，已清空 OPENAI_API_KEY');
      }
      
      // 写入 auth.json
      if (auth.isEmpty) {
        // 如果只有我们添加的密钥且没有官方 API Key，保留空对象
        await authFile.writeAsString('{}');
        print('CodexConfigService: auth.json 为空，写入空对象');
      } else {
        // 保留其他密钥或写入官方 API Key
        await authFile.writeAsString(
          const JsonEncoder.withIndent('  ').convert(auth),
        );
        print('CodexConfigService: 已更新 auth.json');
      }
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      print('CodexConfigService: 切换到官方配置成功');
      return true;
    } catch (e) {
      print('CodexConfigService: 切换到官方配置失败: $e');
      return false;
    }
  }
}

