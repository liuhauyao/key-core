import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/ai_key.dart';
import '../services/auth_service.dart';
import '../services/crypt_service.dart';
import '../services/settings_service.dart';
import '../services/platform_config_path_service.dart';

/// Claude 配置服务
/// 管理 ~/.claude/config.json 的读写
class ClaudeConfigService {
  static const String _configFileName = 'config.json';
  static const String _settingsFileName = 'settings.json';
  
  final AuthService _authService = AuthService();
  final CryptService _cryptService = CryptService();
  final SettingsService _settingsService = SettingsService();

  // 缓存配置目录，避免重复获取和打印日志
  String? _cachedConfigDir;

  /// 获取 Claude 配置目录路径
  /// 优先使用自定义路径，否则使用平台默认路径
  /// macOS/Linux: ~/.claude
  /// Windows: %APPDATA%\.claude
  Future<String> _getConfigDir() async {
    // 如果已缓存，直接返回
    if (_cachedConfigDir != null) {
      return _cachedConfigDir!;
    }

    // 检查是否有自定义路径
    final customDir = _settingsService.getClaudeConfigDir();
    
    // 使用统一的配置路径服务
    final configDir = await PlatformConfigPathService.getClaudeConfigDir(
      customDir: customDir,
    );
    
    // 缓存结果
    _cachedConfigDir = configDir;
    return configDir;
  }

  /// 获取配置文件路径
  Future<String> _getConfigFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _configFileName);
  }

  /// 获取 settings.json 路径
  Future<String> _getSettingsFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _settingsFileName);
  }

  /// 检测配置文件是否存在
  /// 返回配置文件路径和是否存在
  /// 如果目录存在但配置文件不存在，会自动创建默认配置文件
  /// 注意：在 App Store 沙盒环境中，如果无法访问目录，dirExists 会返回 false
  Future<Map<String, dynamic>> checkConfigExists() async {
    final configDir = await _getConfigDir();
    final configPath = await _getConfigFilePath();
    final settingsPath = await _getSettingsFilePath();
    
    final configDirObj = Directory(configDir);
    final configFile = File(configPath);
    final settingsFile = File(settingsPath);
    
    // 尝试检查目录和文件是否存在
    // 在沙盒环境中，如果没有权限访问，exists() 会返回 false（不会抛出异常）
    bool dirExists = false;
    bool configExists = false;
    bool settingsExists = false;
    
    try {
      dirExists = await configDirObj.exists();
      if (dirExists) {
        configExists = await configFile.exists();
        settingsExists = await settingsFile.exists();
      }
    } catch (e) {
      // 如果访问被拒绝（沙盒权限问题），dirExists 保持为 false
      // 这不会抛出异常，exists() 方法会返回 false
    }
    
    // 如果目录存在但配置文件不存在，自动创建默认配置文件
    if (dirExists && !configExists && !settingsExists) {
      print('ClaudeConfigService: 检测到目录存在但配置文件不存在，自动创建默认配置文件');
      await ensureConfigFilesIfDirExists();
      // 重新检查文件是否存在
      final configExistsAfter = await configFile.exists();
      final settingsExistsAfter = await settingsFile.exists();
      return {
        'configDir': configDir,
        'configPath': configPath,
        'settingsPath': settingsPath,
        'configExists': configExistsAfter,
        'settingsExists': settingsExistsAfter,
        'anyExists': configExistsAfter || settingsExistsAfter,
      };
    }
    
    return {
      'configDir': configDir,
      'configPath': configPath,
      'settingsPath': settingsPath,
      'configExists': configExists,
      'settingsExists': settingsExists,
      'anyExists': configExists || settingsExists,
    };
  }

  /// 如果目录存在但配置文件不存在，创建默认配置文件
  Future<bool> ensureConfigFilesIfDirExists() async {
    try {
      final configDir = await _getConfigDir();
      final configDirObj = Directory(configDir);
      
      // 检查目录是否存在
      if (!await configDirObj.exists()) {
        print('ClaudeConfigService: 配置目录不存在，跳过创建配置文件');
        return false;
      }
      
      final configPath = await _getConfigFilePath();
      final settingsPath = await _getSettingsFilePath();
      
      final configFile = File(configPath);
      final settingsFile = File(settingsPath);
      
      // 如果配置文件已存在，不创建
      if (await configFile.exists() || await settingsFile.exists()) {
        print('ClaudeConfigService: 配置文件已存在，跳过创建');
        return false;
      }
      
      // 创建默认的 config.json
      final defaultConfig = <String, dynamic>{};
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultConfig),
      );
      print('ClaudeConfigService: 创建默认 config.json: $configPath');
      
      // 创建默认的 settings.json
      final defaultSettings = <String, dynamic>{
        'env': <String, dynamic>{},
      };
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultSettings),
      );
      print('ClaudeConfigService: 创建默认 settings.json: $settingsPath');
      
      return true;
    } catch (e) {
      print('ClaudeConfigService: 创建默认配置文件失败: $e');
      return false;
    }
  }

  /// 读取配置文件
  Future<Map<String, dynamic>?> readConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);
      
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 读取 settings.json
  Future<Map<String, dynamic>?> readSettings() async {
    try {
      final settingsPath = await _getSettingsFilePath();
      final file = File(settingsPath);
      
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      
      // 确保返回的是 Map 类型
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        // 处理 Map<dynamic, dynamic> 的情况
        return Map<String, dynamic>.from(decoded);
      }
      
      return null;
    } catch (e) {
      print('读取 settings.json 失败: $e');
      return null;
    }
  }

  /// 写入配置（切换使用的密钥）
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

      // 读取或创建 config.json
      final config = await readConfig() ?? {};
      
      // 读取或创建 settings.json
      final settings = await readSettings() ?? {};
      
      // 更新 settings.json 中的配置
      if (!settings.containsKey('env')) {
        settings['env'] = <String, dynamic>{};
      }
      
      // 确保 env 是 Map 类型
      final env = (settings['env'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      settings['env'] = env;
      
      // 设置 ANTHROPIC_AUTH_TOKEN
      env['ANTHROPIC_AUTH_TOKEN'] = apiKey;
      
      // 设置 ANTHROPIC_BASE_URL（如果提供了）
      if (key.claudeCodeBaseUrl != null && key.claudeCodeBaseUrl!.isNotEmpty) {
        env['ANTHROPIC_BASE_URL'] = key.claudeCodeBaseUrl;
      } else {
        // 如果没有提供 Base URL，使用默认的官方地址
        env.remove('ANTHROPIC_BASE_URL');
        print('ClaudeConfigService: 移除 BASE_URL（使用官方地址）');
      }
      
      // 设置 ANTHROPIC_MODEL（主模型，如果提供了）
      if (key.claudeCodeModel != null && key.claudeCodeModel!.isNotEmpty) {
        env['ANTHROPIC_MODEL'] = key.claudeCodeModel;
      } else {
        env.remove('ANTHROPIC_MODEL');
      }
      
      // 设置 ANTHROPIC_DEFAULT_HAIKU_MODEL（Haiku 模型，如果提供了）
      if (key.claudeCodeHaikuModel != null && key.claudeCodeHaikuModel!.isNotEmpty) {
        env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = key.claudeCodeHaikuModel;
        print('ClaudeConfigService: 设置 HAIKU_MODEL = ${key.claudeCodeHaikuModel}');
      } else {
        env.remove('ANTHROPIC_DEFAULT_HAIKU_MODEL');
      }
      
      // 设置 ANTHROPIC_DEFAULT_SONNET_MODEL（Sonnet 模型，如果提供了）
      if (key.claudeCodeSonnetModel != null && key.claudeCodeSonnetModel!.isNotEmpty) {
        env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = key.claudeCodeSonnetModel;
        print('ClaudeConfigService: 设置 SONNET_MODEL = ${key.claudeCodeSonnetModel}');
      } else {
        env.remove('ANTHROPIC_DEFAULT_SONNET_MODEL');
      }
      
      // 设置 ANTHROPIC_DEFAULT_OPUS_MODEL（Opus 模型，如果提供了）
      if (key.claudeCodeOpusModel != null && key.claudeCodeOpusModel!.isNotEmpty) {
        env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = key.claudeCodeOpusModel;
        print('ClaudeConfigService: 设置 OPUS_MODEL = ${key.claudeCodeOpusModel}');
      } else {
        env.remove('ANTHROPIC_DEFAULT_OPUS_MODEL');
      }
      
      // 设置 primaryApiKey（用于插件联动）
      config['primaryApiKey'] = apiKey;
      
      // 确保配置目录存在
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入 config.json
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );
      
      // 写入 settings.json
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings),
      );
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      return true;
    } catch (e) {
      print('ClaudeConfigService: 切换配置失败: $e');
      return false;
    }
  }

  /// 备份当前配置
  Future<bool> backupConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      
      if (!await configFile.exists()) {
        return true; // 没有配置文件，不需要备份
      }
      
      final backupPath = '$configPath.bak';
      await configFile.copy(backupPath);
      
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      
      if (await settingsFile.exists()) {
        final settingsBackupPath = '$settingsPath.bak';
        await settingsFile.copy(settingsBackupPath);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前使用的 API Key
  /// 优先从 settings.json 的 env.ANTHROPIC_AUTH_TOKEN 读取
  /// 如果没有，则尝试从 config.json 的 primaryApiKey 读取
  Future<String?> getCurrentApiKey() async {
    try {
      // 首先尝试从 settings.json 读取
      final settings = await readSettings();
      if (settings != null) {
        final env = settings['env'];
        if (env != null && env is Map) {
          final envMap = env as Map<String, dynamic>;
          // 尝试 ANTHROPIC_AUTH_TOKEN
          var apiKey = envMap['ANTHROPIC_AUTH_TOKEN'] as String?;
          // 如果没有，尝试 ANTHROPIC_API_KEY（兼容性）
          if ((apiKey == null || apiKey.isEmpty) && envMap.containsKey('ANTHROPIC_API_KEY')) {
            apiKey = envMap['ANTHROPIC_API_KEY'] as String?;
          }
          
          if (apiKey != null && apiKey.isNotEmpty) {
            // 清理 API Key（去除首尾空白）
            apiKey = apiKey.trim();
            return apiKey;
          }
        }
      }
      
      // 如果 settings.json 中没有，尝试从 config.json 读取 primaryApiKey
      final config = await readConfig();
      if (config != null) {
        final primaryApiKey = config['primaryApiKey'] as String?;
        if (primaryApiKey != null && primaryApiKey.isNotEmpty && primaryApiKey != 'any') {
          final apiKey = primaryApiKey.trim();
          return apiKey;
        }
      }
      
      print('ClaudeConfigService: 未找到 API Key');
      return null;
    } catch (e) {
      print('ClaudeConfigService: 获取 API Key 失败: $e');
      return null;
    }
  }

  /// 判断当前是否是官方配置
  /// 官方配置的特征：没有 ANTHROPIC_BASE_URL 或 ANTHROPIC_BASE_URL 为空
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
      final settings = await readSettings();
      if (settings == null) {
        _cachedIsOfficial = true; // 没有配置文件，视为官方配置
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }
      
      final env = settings['env'];
      if (env == null || env is! Map) {
        _cachedIsOfficial = true;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }
      
      final envMap = env as Map<String, dynamic>;
      
      // 如果没有设置 ANTHROPIC_BASE_URL，或者为空，则认为是官方配置
      final baseUrl = envMap['ANTHROPIC_BASE_URL'] as String?;
      final isOfficial = baseUrl == null || baseUrl.isEmpty;
      
      // 缓存结果
      _cachedIsOfficial = isOfficial;
      _cachedIsOfficialTime = DateTime.now();
      
      return isOfficial;
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

  /// 切换回官方配置
  /// 清除第三方密钥的模型配置、密钥配置、URL配置
  /// 如果本地存储有官方API Key，则写入；没有则清空
  Future<bool> switchToOfficial() async {
    try {
      // 备份当前配置
      await backupConfig();

      // 读取或创建 settings.json
      final settings = await readSettings() ?? {};
      
      // 更新 settings.json 中的配置
      if (!settings.containsKey('env')) {
        settings['env'] = <String, dynamic>{};
      }
      
      final env = settings['env'] as Map<String, dynamic>;
      
      // 清除第三方密钥的配置
      // 1. 清除 URL 配置
      env.remove('ANTHROPIC_BASE_URL');
      
      // 2. 清除模型配置
      const modelKeys = [
        'ANTHROPIC_MODEL',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL',
        'ANTHROPIC_DEFAULT_SONNET_MODEL',
        'ANTHROPIC_DEFAULT_OPUS_MODEL',
      ];
      for (final key in modelKeys) {
        env.remove(key);
      }
      
      // 3. 清除第三方密钥配置，然后设置官方API Key
      env.remove('ANTHROPIC_AUTH_TOKEN');
      
      // 确保 SettingsService 已初始化
      await _settingsService.init();
      
      // 读取本地存储的官方API Key
      final officialApiKey = _settingsService.getOfficialClaudeApiKey();
      
      // 根据本地存储的官方API Key设置或删除 ANTHROPIC_AUTH_TOKEN
      if (officialApiKey != null && officialApiKey.isNotEmpty) {
        // 如果本地有存储的官方API Key，写入到settings.json
        env['ANTHROPIC_AUTH_TOKEN'] = officialApiKey;
      } else {
        // 如果本地没有存储官方API Key，确保清空（已经remove了）
      }
      
      // 读取或创建 config.json
      final config = await readConfig() ?? {};
      
      // 如果存在 ANTHROPIC_AUTH_TOKEN，更新 primaryApiKey
      if (env['ANTHROPIC_AUTH_TOKEN'] != null && 
          (env['ANTHROPIC_AUTH_TOKEN'] as String).isNotEmpty) {
        config['primaryApiKey'] = env['ANTHROPIC_AUTH_TOKEN'];
      } else {
        config.remove('primaryApiKey');
      }
      
      // 确保配置目录存在
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入 config.json
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );
      
      // 写入 settings.json
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings),
      );
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      return true;
    } catch (e) {
      print('ClaudeConfigService: 切换官方配置失败: $e');
      return false;
    }
  }

  /// 更新官方配置的 env 环境变量
  /// [envVars] 要更新的环境变量映射，如果值为空字符串则删除该变量
  /// API Key保存到本地存储，env配置直接写入到settings.json（不管当前是否是官方配置）
  /// 只修改env配置，不修改密钥、URL、模型配置，不执行切换操作
  Future<bool> updateOfficialConfigEnv(Map<String, String> envVars) async {
    try {
      // 确保 SettingsService 已初始化
      await _settingsService.init();
      
      // 1. 保存API Key到本地存储
      if (envVars.containsKey('ANTHROPIC_AUTH_TOKEN')) {
        final apiKey = envVars['ANTHROPIC_AUTH_TOKEN']!.trim();
        if (apiKey.isEmpty) {
          await _settingsService.setOfficialClaudeApiKey(null);
        } else {
          await _settingsService.setOfficialClaudeApiKey(apiKey);
        }
        // 从envVars中移除，避免写入到settings.json（API Key只在切换时写入）
        envVars.remove('ANTHROPIC_AUTH_TOKEN');
      }
      
      // 模型配置字段列表（不保存，直接忽略）
      const modelKeys = [
        'ANTHROPIC_MODEL',
        'ANTHROPIC_DEFAULT_HAIKU_MODEL',
        'ANTHROPIC_DEFAULT_SONNET_MODEL',
        'ANTHROPIC_DEFAULT_OPUS_MODEL',
      ];
      
      // 移除模型配置，不保存
      for (final key in modelKeys) {
        envVars.remove(key);
      }
      
      // 直接写入env配置到settings.json（不管当前是否是官方配置）
      final settings = await readSettings() ?? {};
      
      if (!settings.containsKey('env')) {
        settings['env'] = <String, dynamic>{};
      }
      
      final env = settings['env'] as Map<String, dynamic>;
      
      // 保存当前的关键配置，避免被覆盖
      final currentAuthToken = env['ANTHROPIC_AUTH_TOKEN'];
      final currentBaseUrl = env['ANTHROPIC_BASE_URL'];
      final currentModelKeys = <String, dynamic>{};
      for (final key in modelKeys) {
        if (env.containsKey(key)) {
          currentModelKeys[key] = env[key];
        }
      }
      
      // 记录所有应该保留的自定义env变量（从envVars中获取）
      final customEnvKeysToKeep = <String>{};
      
      // 更新其他环境变量到settings.json（只更新自定义env变量）
      envVars.forEach((key, value) {
        // 跳过关键配置
        if (key == 'ANTHROPIC_AUTH_TOKEN' || 
            key == 'ANTHROPIC_BASE_URL' || 
            modelKeys.contains(key)) {
          return;
        }
        
        if (value.isEmpty) {
          // 如果值为空，删除该环境变量
          env.remove(key);
        } else {
          // 否则更新或添加该环境变量
          env[key] = value;
          customEnvKeysToKeep.add(key);
        }
      });
      
      // 删除那些不在envVars中的自定义env变量（用户从表单中删除的）
      final keysToRemove = <String>[];
      env.forEach((key, value) {
        // 跳过关键配置
        if (key == 'ANTHROPIC_AUTH_TOKEN' || 
            key == 'ANTHROPIC_BASE_URL' || 
            modelKeys.contains(key)) {
          return;
        }
        
        // 如果这个key不在要保留的列表中，标记为删除
        if (!customEnvKeysToKeep.contains(key)) {
          keysToRemove.add(key);
        }
      });
      
      // 执行删除
      for (final key in keysToRemove) {
        env.remove(key);
      }
      
      // 恢复关键配置（确保不被修改）
      if (currentAuthToken != null) {
        env['ANTHROPIC_AUTH_TOKEN'] = currentAuthToken;
      }
      if (currentBaseUrl != null) {
        env['ANTHROPIC_BASE_URL'] = currentBaseUrl;
      }
      currentModelKeys.forEach((key, value) {
        env[key] = value;
      });
      
      // 2. 写入env配置到settings.json
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings),
      );
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      return true;
    } catch (e) {
      print('ClaudeConfigService: 更新官方配置失败: $e');
      return false;
    }
  }
}

