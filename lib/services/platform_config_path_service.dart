import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'settings_service.dart';

/// 平台配置路径服务
/// 统一管理 Claude/Codex/Gemini 等工具的配置目录路径
/// 支持跨平台（macOS/Windows/Linux）
class PlatformConfigPathService {
  /// 获取 Claude 配置目录路径
  /// 
  /// 平台路径规则：
  /// - macOS/Linux: ~/.claude
  /// - Windows: %APPDATA%\.claude
  static Future<String> getClaudeConfigDir({String? customDir}) async {
    if (customDir != null && customDir.trim().isNotEmpty) {
      final dir = Directory(customDir.trim());
      if (await dir.exists()) {
        return customDir.trim();
      }
    }
    
    if (Platform.isWindows) {
      // Windows: 使用 %APPDATA%\.claude
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, '.claude');
      }
      // 回退：使用应用支持目录
      final appSupportDir = await getApplicationSupportDirectory();
      return path.join(appSupportDir.parent.path, '.claude');
    } else {
      // macOS/Linux: 使用 ~/.claude
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, '.claude');
    }
  }

  /// 获取 Codex 配置目录路径
  /// 
  /// 平台路径规则：
  /// - macOS/Linux: ~/.codex
  /// - Windows: %APPDATA%\.codex
  static Future<String> getCodexConfigDir({String? customDir}) async {
    if (customDir != null && customDir.trim().isNotEmpty) {
      final dir = Directory(customDir.trim());
      if (await dir.exists()) {
        return customDir.trim();
      }
    }
    
    if (Platform.isWindows) {
      // Windows: 使用 %APPDATA%\.codex
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, '.codex');
      }
      // 回退：使用应用支持目录
      final appSupportDir = await getApplicationSupportDirectory();
      return path.join(appSupportDir.parent.path, '.codex');
    } else {
      // macOS/Linux: 使用 ~/.codex
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, '.codex');
    }
  }

  /// 获取 Claude Desktop 配置目录路径
  ///
  /// 平台路径规则：
  /// - macOS: ~/Library/Application Support/Claude
  /// - Windows: %APPDATA%\Claude
  /// - Linux: ~/.config/Claude
  static Future<String> getClaudeDesktopConfigDir({String? customDir}) async {
    if (customDir != null && customDir.trim().isNotEmpty) {
      final dir = Directory(customDir.trim());
      if (await dir.exists()) {
        return customDir.trim();
      }
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, 'Claude');
      }
      final appSupportDir = await getApplicationSupportDirectory();
      return path.join(appSupportDir.parent.path, 'Claude');
    } else if (Platform.isMacOS) {
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, 'Library', 'Application Support', 'Claude');
    } else {
      // Linux
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, '.config', 'Claude');
    }
  }

  /// 获取 Gemini 配置目录路径
  ///
  /// 平台路径规则：
  /// - macOS/Linux: ~/.gemini
  /// - Windows: %APPDATA%\.gemini
  static Future<String> getGeminiConfigDir({String? customDir}) async {
    if (customDir != null && customDir.trim().isNotEmpty) {
      final dir = Directory(customDir.trim());
      if (await dir.exists()) {
        return customDir.trim();
      }
    }
    
    if (Platform.isWindows) {
      // Windows: 使用 %APPDATA%\.gemini
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, '.gemini');
      }
      // 回退：使用应用支持目录
      final appSupportDir = await getApplicationSupportDirectory();
      return path.join(appSupportDir.parent.path, '.gemini');
    } else {
      // macOS/Linux: 使用 ~/.gemini
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, '.gemini');
    }
  }

  // ========== Claude Desktop 3-Profile 系统 ==========

  /// Claude Desktop 3-Profile UUID（固定值，CC Switch 使用的标准 UUID）
  static const String claudeDesktopProfileId = '00000000-0000-4000-8000-000000157210';

  /// 获取 Claude Desktop 3-Profile configLibrary 目录
  ///
  /// 平台路径规则：
  /// - macOS: ~/Library/Application Support/Claude-3p/configLibrary
  /// - Windows: %APPDATA%\Claude-3p\configLibrary
  static Future<String> getClaudeDesktop3pConfigLibraryDir() async {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return path.join(appData, 'Claude-3p', 'configLibrary');
      }
      final appSupportDir = await getApplicationSupportDirectory();
      return path.join(appSupportDir.parent.path, 'Claude-3p', 'configLibrary');
    } else if (Platform.isMacOS) {
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, 'Library', 'Application Support', 'Claude-3p', 'configLibrary');
    } else {
      // Linux
      final homeDir = await SettingsService.getUserHomeDir();
      return path.join(homeDir, '.config', 'Claude-3p', 'configLibrary');
    }
  }

  /// 获取 Claude Desktop 3-Profile 文件路径
  static Future<String> getClaudeDesktopProfilePath() async {
    final libraryDir = await getClaudeDesktop3pConfigLibraryDir();
    return path.join(libraryDir, '$claudeDesktopProfileId.json');
  }

  /// 获取 Claude Desktop 3-Profile meta.json 路径
  static Future<String> getClaudeDesktopMetaPath() async {
    final libraryDir = await getClaudeDesktop3pConfigLibraryDir();
    return path.join(libraryDir, 'meta.json');
  }
}


























