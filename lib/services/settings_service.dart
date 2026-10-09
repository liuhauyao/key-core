import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'secure_storage_service.dart';

/// 设置服务
class SettingsService {
  static const String _keyLanguage = 'language';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyMinimizeToTray = 'minimize_to_tray';
  static const String _keyClaudeConfigDir = 'claude_config_dir';
  static const String _keyCodexConfigDir = 'codex_config_dir';
  static const String _keyOfficialApiKey = 'official_claude_api_key';
  static const String _keyOfficialConfigEnv = 'official_claude_config_env';
  static const String _keyOfficialCodexApiKey = 'official_codex_api_key';
  static const String _keyGeminiConfigDir = 'gemini_config_dir';
  static const String _keyOfficialGeminiApiKey = 'official_gemini_api_key';
  static const String _keyClaudeDesktopConfigDir = 'claude_desktop_config_dir';
  static const String _keyOfficialClaudeDesktopApiKey = 'official_claude_desktop_api_key';

  static const String _defaultLanguage = 'zh';
  static const String _defaultThemeMode = 'system';
  static const bool _defaultMinimizeToTray = true;

  SharedPreferences? _prefs;

  /// 官方 API Key 在系统钥匙串（SecureStorage）中的键名，按旧的 SharedPreferences 键索引
  static const Map<String, String> _officialKeySecureNames = {
    _keyOfficialApiKey: 'official_api_key.claude',
    _keyOfficialCodexApiKey: 'official_api_key.codex',
    _keyOfficialGeminiApiKey: 'official_api_key.gemini',
    _keyOfficialClaudeDesktopApiKey: 'official_api_key.claude_desktop',
  };

  /// 官方 API Key 的内存缓存（同步 getter 从这里读取）。null 表示尚未从钥匙串加载
  static Map<String, String>? _officialKeyCache;
  static Future<void>? _officialKeysLoading;

  /// 测试用：替换钥匙串实现
  @visibleForTesting
  static SecureStorageService secureStorage = SecureStorageService();

  /// 测试用：重置官方 Key 缓存，使下一次 [init] 重新加载/迁移
  @visibleForTesting
  static void debugResetOfficialKeyCache() {
    _officialKeyCache = null;
    _officialKeysLoading = null;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _officialKeysLoading ??= _loadOfficialKeys(_prefs!);
    await _officialKeysLoading;
  }

  /// 从系统钥匙串加载官方 API Key，并把旧版本存放在 SharedPreferences 中的明文 Key 迁移过去。
  ///
  /// 迁移步骤：写入钥匙串 → 读回校验一致 → 删除 SharedPreferences 中的明文。
  /// 任一步失败（例如未签名的开发构建无法访问钥匙串）都保留明文、不丢数据，下次启动再试。
  static Future<void> _loadOfficialKeys(SharedPreferences prefs) async {
    final cache = <String, String>{};
    for (final entry in _officialKeySecureNames.entries) {
      final prefsKey = entry.key;
      final secureKey = entry.value;
      final legacy = prefs.getString(prefsKey)?.trim();
      try {
        if (legacy != null && legacy.isNotEmpty) {
          await secureStorage.writeSecret(secureKey, legacy);
          final verified = await secureStorage.readSecret(secureKey);
          if (verified == legacy) {
            await prefs.remove(prefsKey);
            cache[prefsKey] = legacy;
            continue;
          }
          cache[prefsKey] = legacy;
          continue;
        }
        final stored = await secureStorage.readSecret(secureKey);
        if (stored != null && stored.isNotEmpty) cache[prefsKey] = stored;
      } catch (e) {
        print('SettingsService: 访问系统钥匙串失败，官方 API Key 暂存于本地设置: $e');
        if (legacy != null && legacy.isNotEmpty) cache[prefsKey] = legacy;
      }
    }
    _officialKeyCache = cache;
  }

  /// 读取官方 API Key（来自钥匙串缓存；尚未加载时回退到旧的本地设置）
  String? _getOfficialKey(String prefsKey) {
    final cache = _officialKeyCache;
    if (cache != null) return cache[prefsKey];
    return _prefs?.getString(prefsKey);
  }

  /// 保存官方 API Key 到系统钥匙串；钥匙串不可用时退回本地设置（与旧版本相同的存储方式）
  Future<void> _setOfficialKey(String prefsKey, String? apiKey) async {
    if (_prefs == null) {
      await init();
    }
    final secureKey = _officialKeySecureNames[prefsKey]!;
    final value = apiKey?.trim();
    final cache = _officialKeyCache ??= <String, String>{};

    if (value == null || value.isEmpty) {
      try {
        await secureStorage.deleteSecret(secureKey);
      } catch (e) {
        print('SettingsService: 从系统钥匙串删除官方 API Key 失败: $e');
      }
      await _prefs!.remove(prefsKey);
      cache.remove(prefsKey);
      return;
    }

    try {
      await secureStorage.writeSecret(secureKey, value);
      await _prefs!.remove(prefsKey);
    } catch (e) {
      print('SettingsService: 写入系统钥匙串失败，官方 API Key 暂存于本地设置: $e');
      final result = await _prefs!.setString(prefsKey, value);
      if (!result) {
        throw Exception('Failed to save official API key');
      }
    }
    cache[prefsKey] = value;
  }

  /// 获取当前语言
  String getLanguage() {
    return _prefs?.getString(_keyLanguage) ?? _defaultLanguage;
  }

  /// 设置语言
  Future<void> setLanguage(String language) async {
    await _prefs?.setString(_keyLanguage, language);
  }

  /// 获取主题模式
  ThemeMode getThemeMode() {
    final mode = _prefs?.getString(_keyThemeMode) ?? _defaultThemeMode;
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    String modeString;
    switch (mode) {
      case ThemeMode.light:
        modeString = 'light';
        break;
      case ThemeMode.dark:
        modeString = 'dark';
        break;
      case ThemeMode.system:
      default:
        modeString = 'system';
        break;
    }
    await _prefs?.setString(_keyThemeMode, modeString);
  }

  /// 获取是否最小化到托盘
  bool getMinimizeToTray() {
    return _prefs?.getBool(_keyMinimizeToTray) ?? _defaultMinimizeToTray;
  }

  /// 设置是否最小化到托盘
  Future<void> setMinimizeToTray(bool value) async {
    await _prefs?.setBool(_keyMinimizeToTray, value);
  }

  /// 获取 Claude 配置目录（自定义路径或默认路径）
  String? getClaudeConfigDir() {
    return _prefs?.getString(_keyClaudeConfigDir);
  }

  /// 设置 Claude 配置目录
  Future<void> setClaudeConfigDir(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs?.remove(_keyClaudeConfigDir);
    } else {
      await _prefs?.setString(_keyClaudeConfigDir, path.trim());
    }
  }

  /// 获取 Codex 配置目录（自定义路径或默认路径）
  String? getCodexConfigDir() {
    return _prefs?.getString(_keyCodexConfigDir);
  }

  /// 设置 Codex 配置目录
  Future<void> setCodexConfigDir(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs?.remove(_keyCodexConfigDir);
    } else {
      await _prefs?.setString(_keyCodexConfigDir, path.trim());
    }
  }

  /// 获取通用设置值
  String? getSetting(String key) {
    return _prefs?.getString(key);
  }

  /// 设置通用设置值
  Future<void> setSetting(String key, String value) async {
    await _prefs?.setString(key, value);
  }

  /// 移除通用设置值
  Future<void> removeSetting(String key) async {
    await _prefs?.remove(key);
  }

  /// 获取官方 Claude API Key（存于系统钥匙串）
  String? getOfficialClaudeApiKey() => _getOfficialKey(_keyOfficialApiKey);

  /// 设置官方 Claude API Key（存于系统钥匙串）
  Future<void> setOfficialClaudeApiKey(String? apiKey) => _setOfficialKey(_keyOfficialApiKey, apiKey);

  /// 获取官方配置的所有环境变量（本地存储）
  Map<String, String> getOfficialConfigEnv() {
    final jsonStr = _prefs?.getString(_keyOfficialConfigEnv);
    if (jsonStr == null || jsonStr.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      print('SettingsService: 解析官方配置环境变量失败: $e');
      return {};
    }
  }

  /// 设置官方配置的所有环境变量（本地存储）
  Future<void> setOfficialConfigEnv(Map<String, String> envVars) async {
    if (envVars.isEmpty) {
      await _prefs?.remove(_keyOfficialConfigEnv);
    } else {
      final jsonStr = jsonEncode(envVars);
      await _prefs?.setString(_keyOfficialConfigEnv, jsonStr);
    }
  }

  /// 获取官方 Codex API Key（存于系统钥匙串）
  String? getOfficialCodexApiKey() => _getOfficialKey(_keyOfficialCodexApiKey);

  /// 设置官方 Codex API Key（存于系统钥匙串）
  Future<void> setOfficialCodexApiKey(String? apiKey) => _setOfficialKey(_keyOfficialCodexApiKey, apiKey);

  /// 获取 Gemini 配置目录（自定义路径或默认路径）
  String? getGeminiConfigDir() {
    return _prefs?.getString(_keyGeminiConfigDir);
  }

  /// 设置 Gemini 配置目录
  Future<void> setGeminiConfigDir(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs?.remove(_keyGeminiConfigDir);
    } else {
      await _prefs?.setString(_keyGeminiConfigDir, path.trim());
    }
  }

  /// 获取官方 Gemini API Key（存于系统钥匙串）
  String? getOfficialGeminiApiKey() => _getOfficialKey(_keyOfficialGeminiApiKey);

  /// 设置官方 Gemini API Key（存于系统钥匙串）
  Future<void> setOfficialGeminiApiKey(String? apiKey) => _setOfficialKey(_keyOfficialGeminiApiKey, apiKey);

  /// 获取 Claude Desktop 配置目录（自定义路径或默认路径）
  String? getClaudeDesktopConfigDir() {
    return _prefs?.getString(_keyClaudeDesktopConfigDir);
  }

  /// 设置 Claude Desktop 配置目录
  Future<void> setClaudeDesktopConfigDir(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs?.remove(_keyClaudeDesktopConfigDir);
    } else {
      await _prefs?.setString(_keyClaudeDesktopConfigDir, path.trim());
    }
  }

  /// 获取官方 Claude Desktop API Key（存于系统钥匙串）
  String? getOfficialClaudeDesktopApiKey() => _getOfficialKey(_keyOfficialClaudeDesktopApiKey);

  /// 设置官方 Claude Desktop API Key（存于系统钥匙串）
  Future<void> setOfficialClaudeDesktopApiKey(String? apiKey) => _setOfficialKey(_keyOfficialClaudeDesktopApiKey, apiKey);

  /// 清除所有设置
  Future<void> clearAllSettings() async {
    await _prefs?.clear();
    for (final secureKey in _officialKeySecureNames.values) {
      try {
        await secureStorage.deleteSecret(secureKey);
      } catch (_) {}
    }
    _officialKeyCache = <String, String>{};
  }

  // 缓存用户主目录，避免重复获取
  static String? _cachedHomeDir;

  /// 测试用：覆盖用户主目录
  @visibleForTesting
  static String? debugHomeDirOverride;

  /// 获取用户主目录路径（跨平台）
  /// 在沙盒环境中，优先使用命令获取真正的用户主目录
  /// 使用缓存机制避免重复获取
  static Future<String> getUserHomeDir() async {
    final override = debugHomeDirOverride;
    if (override != null) return override;

    // 如果已缓存，直接返回
    if (_cachedHomeDir != null) {
      return _cachedHomeDir!;
    }

    String? homeDir;
    
    if (Platform.isMacOS || Platform.isLinux) {
      // 优先通过命令获取真正的用户主目录（避免沙盒路径）
      try {
        final result = await Process.run('sh', ['-c', r'echo $HOME']);
        if (result.exitCode == 0) {
          final homePath = result.stdout.toString().trim();
          if (homePath.isNotEmpty && 
              !homePath.contains('/Containers/') && 
              !homePath.contains('/Library/Application Support/') &&
              Directory(homePath).existsSync()) {
            homeDir = homePath;
          }
        }
      } catch (e) {
        // 静默处理错误，继续尝试其他方法
      }
      
      // 如果第一种方法失败，尝试通过用户名构建路径
      if (homeDir == null) {
        try {
          final userResult = await Process.run('whoami', []);
          if (userResult.exitCode == 0) {
            final username = userResult.stdout.toString().trim();
            final homePath = '/Users/$username';
            if (Directory(homePath).existsSync()) {
              homeDir = homePath;
            }
          }
        } catch (e) {
          // 静默处理错误，继续尝试其他方法
        }
      }
      
      // 如果前两种方法都失败，尝试从环境变量获取（但排除沙盒路径）
      if (homeDir == null) {
        final homeEnv = Platform.environment['HOME'];
        if (homeEnv != null && homeEnv.isNotEmpty) {
          // 检查是否是沙盒路径（包含 Containers）
          if (!homeEnv.contains('/Containers/') && 
              !homeEnv.contains('/Library/Application Support/')) {
            homeDir = homeEnv;
          }
        }
      }
    } else if (Platform.isWindows) {
      final homeDrive = Platform.environment['HOMEDRIVE'];
      final homePath = Platform.environment['HOMEPATH'];
      if (homeDrive != null && homePath != null) {
        homeDir = '$homeDrive$homePath';
      }
    }
    
    // 最后的回退：使用应用支持目录的父目录
    // 这不应该发生，但如果发生了，至少应用能运行
    if (homeDir == null) {
      final appSupportDir = await getApplicationSupportDirectory();
      homeDir = appSupportDir.path;
    }
    
    // 缓存结果
    _cachedHomeDir = homeDir;
    return homeDir;
  }
}

