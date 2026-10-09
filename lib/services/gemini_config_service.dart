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
import '../models/mcp_server.dart' show AiToolType;
import 'live_config/key_field_floor.dart';
import 'live_config/live_config_writer.dart';

/// Gemini 配置服务
/// 管理 ~/.gemini/settings.json 和 ~/.gemini/.env 的读写
class GeminiConfigService {
  /// 最近一次 switchProvider / switchToOfficial 失败的原因（成功时清空），供 UI 显示失败原因。
  Object? lastSwitchError;

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

  /// 写入 .env 文件，使 [envMap] 成为文件中的全部变量。
  ///
  /// 经 [LiveConfigWriter] 按行修改：注释、空行与变量顺序保留，原子写入，权限 0600。
  Future<bool> writeEnv(Map<String, String> envMap) async {
    try {
      final envPath = await _getEnvFilePath();
      await LiveConfigWriter.instance.apply(AiToolType.gemini, [
        LiveEdit(
          envPath,
          (current) {
            final existing = DotEnvPatch.parse(current).keys.toSet();
            return DotEnvPatch.apply(
              current,
              set: envMap,
              remove: existing.difference(envMap.keys.toSet()),
            );
          },
          containsSecrets: true,
        ),
      ]);

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      print('GeminiConfigService: 写入 .env 失败: $e');
      return false;
    }
  }

  /// 写入配置（切换使用的密钥）
  /// 优先使用 .env 文件存储 API 密钥
  Future<bool> switchProvider(AIKey key) async {
    lastSwitchError = null;
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

      final settingsPath = await _getSettingsFilePath();
      final envPath = await _getEnvFilePath();

      await LiveConfigWriter.instance.apply(AiToolType.gemini, [
        LiveEdit.json(settingsPath, (settings) => applyProviderToSettings(settings)),
        // 写入 GEMINI_API_KEY；密钥配置了第三方端点时同时写 GOOGLE_GEMINI_BASE_URL / GEMINI_MODEL，
        // 否则清除这些字段（回到官方端点）
        LiveEdit.dotenv(
          envPath,
          set: providerEnv(key, apiKey),
          remove: KeyFieldFloor.geminiClearedOnSwitch.toSet(),
        ),
      ]);

      _clearOfficialConfigCache();
      return true;
    } catch (e) {
      lastSwitchError = e;
      print('GeminiConfigService: 切换配置失败: $e');
      return false;
    }
  }

  /// 切换到某把密钥时 `.env` 中应写入的关键字段（纯函数，便于测试）
  ///
  /// 与 CC Switch 一致：第三方端点写 `GOOGLE_GEMINI_BASE_URL`，模型写 `GEMINI_MODEL`。
  static Map<String, String> providerEnv(AIKey key, String apiKey) {
    final env = <String, String>{KeyFieldFloor.geminiApiKey: apiKey};
    final baseUrl = key.geminiBaseUrl?.trim();
    if (baseUrl != null && baseUrl.isNotEmpty) env[KeyFieldFloor.geminiBaseUrl] = baseUrl;
    final model = key.geminiModel?.trim();
    if (model != null && model.isNotEmpty) env[KeyFieldFloor.geminiModel] = model;
    return env;
  }

  /// 切换到密钥时 settings.json 的修改（纯函数）
  ///
  /// `security.auth.selectedType` 必须是 `gemini-api-key`，否则之前用 Google 账号登录过的
  /// Gemini CLI 会继续走 OAuth，切换不生效（CC Switch `live/project/gemini.rs` 同样处理）。
  static void applyProviderToSettings(Map<String, dynamic> settings) {
    settings.putIfAbsent('mcpServers', () => <String, dynamic>{});
    // 清除 settings.json 中的 apiKey（优先使用 .env 文件）
    settings['apiKey'] = '';
    final security = settings['security'] is Map
        ? Map<String, dynamic>.from(settings['security'] as Map)
        : <String, dynamic>{};
    final auth = security['auth'] is Map
        ? Map<String, dynamic>.from(security['auth'] as Map)
        : <String, dynamic>{};
    auth['selectedType'] = 'gemini-api-key';
    security['auth'] = auth;
    settings['security'] = security;
  }

  /// 备份当前配置
  ///
  /// 保留该方法以兼容调用方。备份现在由 [LiveConfigWriter] 在每次写入前自动完成
  /// （首写备份 + 滚动备份，位于 `~/.keycore/backups/live`）。
  Future<bool> backupConfig() async => true;

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
    lastSwitchError = null;
    try {
      // 确保 SettingsService 已初始化（官方 API Key 存于系统钥匙串）
      await _settingsService.init();
      final officialApiKey = _settingsService.getOfficialGeminiApiKey();

      final settingsPath = await _getSettingsFilePath();
      final envPath = await _getEnvFilePath();
      final hasOfficial = officialApiKey != null && officialApiKey.isNotEmpty;

      await LiveConfigWriter.instance.apply(AiToolType.gemini, [
        LiveEdit.json(settingsPath, (settings) {
          // 清除 settings.json 中的 apiKey（优先使用 .env 文件）
          settings['apiKey'] = '';
        }),
        LiveEdit.dotenv(
          envPath,
          set: hasOfficial ? {KeyFieldFloor.geminiApiKey: officialApiKey} : const {},
          remove: {
            ...KeyFieldFloor.geminiClearedOnSwitch,
            if (!hasOfficial) KeyFieldFloor.geminiApiKey,
          },
        ),
      ]);

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      lastSwitchError = e;
      print('GeminiConfigService: 切换官方配置失败: $e');
      return false;
    }
  }
}

