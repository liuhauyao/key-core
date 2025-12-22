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
}
























