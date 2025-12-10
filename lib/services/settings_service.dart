import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';

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

  static const String _defaultLanguage = 'zh';
  static const String _defaultThemeMode = 'system';
  static const bool _defaultMinimizeToTray = true;

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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

  /// 获取官方 Claude API Key（本地存储）
  String? getOfficialClaudeApiKey() {
    // 如果未初始化，返回null（不应该发生，但为了安全）
    if (_prefs == null) {
      return null;
    }
    return _prefs!.getString(_keyOfficialApiKey);
  }

  /// 设置官方 Claude API Key（本地存储）
  Future<void> setOfficialClaudeApiKey(String? apiKey) async {
    // 确保已初始化
    if (_prefs == null) {
      await init();
    }
    
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _prefs!.remove(_keyOfficialApiKey);
    } else {
      final result = await _prefs!.setString(_keyOfficialApiKey, apiKey.trim());
      if (!result) {
        throw Exception('Failed to save official API key to SharedPreferences');
      }
    }
  }

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

  /// 获取官方 Codex API Key（本地存储）
  String? getOfficialCodexApiKey() {
    // 如果未初始化，返回null（不应该发生，但为了安全）
    if (_prefs == null) {
      return null;
    }
    return _prefs!.getString(_keyOfficialCodexApiKey);
  }

  /// 设置官方 Codex API Key（本地存储）
  Future<void> setOfficialCodexApiKey(String? apiKey) async {
    // 确保已初始化
    if (_prefs == null) {
      await init();
    }
    
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _prefs!.remove(_keyOfficialCodexApiKey);
    } else {
      final result = await _prefs!.setString(_keyOfficialCodexApiKey, apiKey.trim());
      if (!result) {
        throw Exception('Failed to save official Codex API key to SharedPreferences');
      }
    }
  }

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

  /// 获取官方 Gemini API Key（本地存储）
  String? getOfficialGeminiApiKey() {
    // 如果未初始化，返回null（不应该发生，但为了安全）
    if (_prefs == null) {
      return null;
    }
    return _prefs!.getString(_keyOfficialGeminiApiKey);
  }

  /// 设置官方 Gemini API Key（本地存储）
  Future<void> setOfficialGeminiApiKey(String? apiKey) async {
    // 确保已初始化
    if (_prefs == null) {
      await init();
    }
    
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _prefs!.remove(_keyOfficialGeminiApiKey);
    } else {
      final result = await _prefs!.setString(_keyOfficialGeminiApiKey, apiKey.trim());
      if (!result) {
        throw Exception('Failed to save official Gemini API key to SharedPreferences');
      }
    }
  }

  /// 清除所有设置
  Future<void> clearAllSettings() async {
    await _prefs?.clear();
  }

  // 缓存用户主目录，避免重复获取
  static String? _cachedHomeDir;

  /// 获取用户主目录路径（跨平台）
  /// 在沙盒环境中，优先使用命令获取真正的用户主目录
  /// 使用缓存机制避免重复获取
  static Future<String> getUserHomeDir() async {
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

