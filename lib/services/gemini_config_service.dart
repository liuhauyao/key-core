import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/ai_key.dart';
import '../services/auth_service.dart';
import '../services/crypt_service.dart';
import '../services/settings_service.dart';
import '../services/platform_config_path_service.dart';
import 'ai_tool_config_service.dart';

/// Gemini 配置服务
/// 管理 ~/.gemini/settings.json 和 ~/.gemini/.env 的读写
class GeminiConfigService {
  static const String _settingsFileName = 'settings.json';
  static const String _envFileName = '.env';
  
  final AuthService _authService = AuthService();
  final CryptService _cryptService = CryptService();
  final SettingsService _settingsService = SettingsService();

  // 缓存配置目录，避免重复获取和打印日志
  String? _cachedConfigDir;

  /// 获取 Gemini 配置目录路径
  /// 优先使用自定义路径，否则使用平台默认路径
  /// macOS/Linux: ~/.gemini
  /// Windows: %APPDATA%\.gemini
  Future<String> _getConfigDir() async {
    // 如果已缓存，直接返回
    if (_cachedConfigDir != null) {
      return _cachedConfigDir!;
    }

    // 检查是否有自定义路径
    final customDir = _settingsService.getGeminiConfigDir();
    
    // 使用统一的配置路径服务
    final configDir = await PlatformConfigPathService.getGeminiConfigDir(
      customDir: customDir,
    );
    
    // 缓存结果
    _cachedConfigDir = configDir;
    return configDir;
  }

  /// 获取 settings.json 路径
  Future<String> _getSettingsFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _settingsFileName);
  }

  /// 获取 .env 文件路径
  Future<String> _getEnvFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _envFileName);
  }

  /// 检测配置文件是否存在
  /// 返回配置文件路径和是否存在
  /// 如果目录存在但配置文件不存在，会自动创建默认配置文件
  Future<Map<String, dynamic>> checkConfigExists() async {
    final configDir = await _getConfigDir();
    final settingsPath = await _getSettingsFilePath();
    final envPath = await _getEnvFilePath();
    
    final configDirObj = Directory(configDir);
    final settingsFile = File(settingsPath);
    final envFile = File(envPath);
    
    final dirExists = await configDirObj.exists();
    final settingsExists = await settingsFile.exists();
    final envExists = await envFile.exists();
    
    // 如果目录存在但配置文件不存在，自动创建默认配置文件
    if (dirExists && !settingsExists && !envExists) {
      print('GeminiConfigService: 检测到目录存在但配置文件不存在，自动创建默认配置文件');
      await ensureConfigFilesIfDirExists();
      // 重新检查文件是否存在
      final settingsExistsAfter = await settingsFile.exists();
      final envExistsAfter = await envFile.exists();
      return {
        'configDir': configDir,
        'settingsPath': settingsPath,
        'envPath': envPath,
        'settingsExists': settingsExistsAfter,
        'envExists': envExistsAfter,
        'anyExists': settingsExistsAfter || envExistsAfter,
      };
    }
    
    return {
      'configDir': configDir,
      'settingsPath': settingsPath,
      'envPath': envPath,
      'settingsExists': settingsExists,
      'envExists': envExists,
      'anyExists': settingsExists || envExists,
    };
  }

  /// 如果目录存在但配置文件不存在，创建默认配置文件
  Future<bool> ensureConfigFilesIfDirExists() async {
    try {
      final configDir = await _getConfigDir();
      final configDirObj = Directory(configDir);
      
      // 检查目录是否存在
      if (!await configDirObj.exists()) {
        print('GeminiConfigService: 配置目录不存在，跳过创建配置文件');
        return false;
      }
      
      final settingsPath = await _getSettingsFilePath();
      final envPath = await _getEnvFilePath();
      
      final settingsFile = File(settingsPath);
      final envFile = File(envPath);
      
      // 如果配置文件已存在，不创建
      if (await settingsFile.exists() || await envFile.exists()) {
        print('GeminiConfigService: 配置文件已存在，跳过创建');
        return false;
      }
      
      // 创建默认的 settings.json
      final defaultSettings = <String, dynamic>{
        'apiKey': '',
        'mcpServers': <String, dynamic>{},
      };
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultSettings),
      );
      
      // 创建默认的 .env 文件（空文件）
      await envFile.writeAsString('');
      
      return true;
    } catch (e) {
      print('GeminiConfigService: 创建默认配置文件失败: $e');
      return false;
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
      print('GeminiConfigService: 读取 settings.json 失败: $e');
      return null;
    }
  }

  /// 解析 .env 文件内容为键值对
  Future<Map<String, String>> _parseEnvFile(String content) async {
    final map = <String, String>{};

    for (final line in content.split('\n')) {
      final trimmed = line.trim();

      // 跳过空行和注释
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      // 解析 KEY=VALUE
      if (trimmed.contains('=')) {
        final parts = trimmed.split('=');
        if (parts.length >= 2) {
          final key = parts[0].trim();
          final value = parts.sublist(1).join('=').trim();
          
          // 验证 key 是否有效（不为空，只包含字母、数字和下划线）
          if (key.isNotEmpty && key.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '').length == key.length) {
            map[key] = value;
          }
        }
      }
    }

    return map;
  }

  /// 将键值对序列化为 .env 格式
  String _serializeEnvFile(Map<String, String> map) {
    final lines = <String>[];

    // 按键排序以保证输出稳定
    final keys = map.keys.toList()..sort();

    for (final key in keys) {
      if (map[key] != null) {
        lines.add('$key=${map[key]}');
      }
    }

    return lines.join('\n');
  }

  /// 读取 .env 文件
  Future<Map<String, String>> readEnv() async {
    try {
      final envPath = await _getEnvFilePath();
      final file = File(envPath);
      
      if (!await file.exists()) {
        return {};
      }

      final content = await file.readAsString();
      return await _parseEnvFile(content);
    } catch (e) {
      print('GeminiConfigService: 读取 .env 文件失败: $e');
      return {};
    }
  }

  /// 写入 .env 文件（原子操作）
  Future<bool> writeEnv(Map<String, String> envMap) async {
    try {
      final envPath = await _getEnvFilePath();
      
      // 确保目录存在
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      final content = _serializeEnvFile(envMap);
      final file = File(envPath);
      await file.writeAsString(content);
      
      // 设置文件权限为 600（仅所有者可读写）
      if (Platform.isMacOS || Platform.isLinux) {
        try {
          await Process.run('chmod', ['600', envPath]);
        } catch (e) {
          print('GeminiConfigService: 设置 .env 文件权限失败: $e');
        }
      }
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 写入配置（切换使用的密钥）
  /// 优先使用 .env 文件存储 API 密钥
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

      // 读取或创建 settings.json
      final settings = await readSettings() ?? {};
      
      // 确保 mcpServers 字段存在
      if (!settings.containsKey('mcpServers')) {
        settings['mcpServers'] = <String, dynamic>{};
      }
      
      // 清除 settings.json 中的 apiKey（优先使用 .env 文件）
      settings['apiKey'] = '';
      
      // 读取或创建 .env 文件
      final env = await readEnv();
      
      // 设置 GEMINI_API_KEY（Gemini 只支持官方 API，只写入 API Key）
      env['GEMINI_API_KEY'] = apiKey;
      
      // 清除可能存在的第三方配置字段（确保使用官方配置）
      env.remove('GEMINI_BASE_URL');
      env.remove('GEMINI_MODEL');
      
      
      // 确保配置目录存在
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入 settings.json
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings),
      );
      
      // 写入 .env 文件
      await writeEnv(env);
      
      return true;
    } catch (e) {
      print('GeminiConfigService: 切换配置失败: $e');
      return false;
    }
  }

  /// 备份当前配置
  Future<bool> backupConfig() async {
    try {
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      
      if (await settingsFile.exists()) {
        final backupPath = '$settingsPath.bak';
        await settingsFile.copy(backupPath);
      }
      
      final envPath = await _getEnvFilePath();
      final envFile = File(envPath);
      
      if (await envFile.exists()) {
        final envBackupPath = '$envPath.bak';
        await envFile.copy(envBackupPath);
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取当前使用的 API Key
  /// 优先从 .env 文件读取 GEMINI_API_KEY
  /// 如果没有，则尝试从 settings.json 的 apiKey 字段读取
  Future<String?> getCurrentApiKey() async {
    try {
      // 首先尝试从 .env 文件读取
      final env = await readEnv();
      var apiKey = env['GEMINI_API_KEY'];
      
      if (apiKey != null && apiKey.isNotEmpty) {
        apiKey = apiKey.trim();
        return apiKey;
      }
      
      // 如果 .env 文件中没有，尝试从 settings.json 读取
      final settings = await readSettings();
      if (settings != null) {
        final settingsApiKey = settings['apiKey'] as String?;
        if (settingsApiKey != null && settingsApiKey.isNotEmpty && settingsApiKey != '') {
          final apiKeyFromSettings = settingsApiKey.trim();
          return apiKeyFromSettings;
        }
      }
      
      print('GeminiConfigService: 未找到 API Key');
      return null;
    } catch (e) {
      print('GeminiConfigService: 获取 API Key 失败: $e');
      return null;
    }
  }

  /// 判断当前是否是官方配置
  /// 官方配置的判断逻辑：
  /// 1. 如果 .env 文件中没有 GEMINI_API_KEY，且 settings.json 中也没有 apiKey，则认为是官方配置
  /// 2. 如果 .env 文件中的 GEMINI_API_KEY 与本地存储的官方 API Key 匹配，则认为是官方配置
  /// 3. 如果 .env 文件中的 GEMINI_API_KEY 与任何密钥都不匹配，但匹配官方存储的 API Key，则认为是官方配置
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
      final env = await readEnv();
      final apiKey = env['GEMINI_API_KEY'];
      
      // 如果 .env 中没有 API Key，检查 settings.json
      if (apiKey == null || apiKey.isEmpty) {
        final settings = await readSettings();
        final settingsApiKey = settings?['apiKey'] as String?;
        if (settingsApiKey == null || settingsApiKey.isEmpty || settingsApiKey == '') {
          _cachedIsOfficial = true;
          _cachedIsOfficialTime = DateTime.now();
          return _cachedIsOfficial!;
        }
        // settings.json 中有 API Key，需要检查是否是官方存储的
        await _settingsService.init();
        final officialApiKey = _settingsService.getOfficialGeminiApiKey();
        if (officialApiKey != null && officialApiKey.isNotEmpty && settingsApiKey.trim() == officialApiKey.trim()) {
          _cachedIsOfficial = true;
          _cachedIsOfficialTime = DateTime.now();
          return _cachedIsOfficial!;
        }
        _cachedIsOfficial = false;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }
      
      // .env 中有 API Key，检查是否匹配官方存储的 API Key
      await _settingsService.init();
      final officialApiKey = _settingsService.getOfficialGeminiApiKey();
      if (officialApiKey != null && officialApiKey.isNotEmpty) {
        final isOfficial = apiKey.trim() == officialApiKey.trim();
        _cachedIsOfficial = isOfficial;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }
      
      // 没有官方存储的 API Key，但有 .env 中的 API Key，视为第三方配置
      _cachedIsOfficial = false;
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

  /// 切换回官方配置
  /// 清除第三方密钥的配置
  /// 如果本地存储有官方API Key，则写入；没有则清空
  Future<bool> switchToOfficial() async {
    try {
      // 备份当前配置
      await backupConfig();

      // 读取或创建 .env 文件
      final env = await readEnv();
      
      // 清除第三方密钥的配置
      // 1. 清除 URL 配置
      env.remove('GEMINI_BASE_URL');
      
      // 2. 清除模型配置
      env.remove('GEMINI_MODEL');
      
      // 3. 清除第三方密钥配置
      env.remove('GEMINI_API_KEY');
      
      // 确保 SettingsService 已初始化
      await _settingsService.init();
      
      // 读取本地存储的官方API Key
      final officialApiKey = _settingsService.getOfficialGeminiApiKey();
      
      // 根据本地存储的官方API Key设置或删除 GEMINI_API_KEY
      if (officialApiKey != null && officialApiKey.isNotEmpty) {
        // 如果本地有存储的官方API Key，写入到 .env 文件
        env['GEMINI_API_KEY'] = officialApiKey;
      } else {
        // 如果本地没有存储官方API Key，确保清空（已经remove了）
      }
      
      // 读取或创建 settings.json
      final settings = await readSettings() ?? {};
      
      // 清除 settings.json 中的 apiKey（优先使用 .env 文件）
      settings['apiKey'] = '';
      
      // 确保配置目录存在
      final configDir = await _getConfigDir();
      final dir = Directory(configDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 写入 settings.json
      final settingsPath = await _getSettingsFilePath();
      final settingsFile = File(settingsPath);
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(settings),
      );
      
      // 写入 .env 文件
      await writeEnv(env);
      
      // 清除官方配置缓存
      _clearOfficialConfigCache();
      
      return true;
    } catch (e) {
      print('GeminiConfigService: 切换官方配置失败: $e');
      return false;
    }
  }
}

