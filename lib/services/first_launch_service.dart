import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';
import 'claude_config_service.dart';
import 'codex_config_service.dart';
import 'gemini_config_service.dart';
import 'ai_tool_config_service.dart';
import '../models/mcp_server.dart';

/// 首次启动检测服务
/// 用于检测配置目录访问权限，并在首次启动时提示用户选择目录
class FirstLaunchService {
  static const String _keyHasCheckedPermissions = 'has_checked_config_permissions';
  static const String _keyHasPromptedClaude = 'has_prompted_claude_dir';
  static const String _keyHasPromptedCodex = 'has_prompted_codex_dir';
  static const String _keyHasPromptedGemini = 'has_prompted_gemini_dir';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 检查是否已经检查过权限
  bool hasCheckedPermissions() {
    return _prefs?.getBool(_keyHasCheckedPermissions) ?? false;
  }

  /// 标记已检查过权限
  Future<void> markPermissionsChecked() async {
    await _prefs?.setBool(_keyHasCheckedPermissions, true);
  }

  /// 检查是否已经提示过某个工具的目录选择
  bool hasPromptedForTool(String toolKey) {
    return _prefs?.getBool(toolKey) ?? false;
  }

  /// 标记已提示过某个工具的目录选择
  Future<void> markToolPrompted(String toolKey) async {
    await _prefs?.setBool(toolKey, true);
  }

  /// 检查配置目录是否可访问
  /// 在沙盒环境中，如果目录无法访问，会返回 false
  Future<bool> canAccessConfigDir(String configDir) async {
    try {
      final dir = Directory(configDir);
      // 尝试检查目录是否存在
      final exists = await dir.exists();
      if (!exists) {
        return false;
      }
      
      // 尝试列出目录内容（这会触发权限检查）
      // 如果无法访问，会抛出异常
      await dir.list().first.timeout(
        const Duration(seconds: 1),
        onTimeout: () => throw TimeoutException('Directory access timeout'),
      );
      return true;
    } catch (e) {
      // 如果出现任何异常，说明无法访问
      return false;
    }
  }

  /// 检查 Claude 配置目录访问权限
  Future<bool> checkClaudeConfigAccess() async {
    final settingsService = SettingsService();
    await settingsService.init();
    
    final customDir = settingsService.getClaudeConfigDir();
    final claudeService = ClaudeConfigService();
    
    // 获取配置目录路径
    String configDir;
    if (customDir != null && customDir.isNotEmpty) {
      configDir = customDir;
    } else {
      final homeDir = await SettingsService.getUserHomeDir();
      configDir = '$homeDir/.claude';
    }
    
    return await canAccessConfigDir(configDir);
  }

  /// 检查 Codex 配置目录访问权限
  Future<bool> checkCodexConfigAccess() async {
    final settingsService = SettingsService();
    await settingsService.init();
    
    final customDir = settingsService.getCodexConfigDir();
    final codexService = CodexConfigService();
    
    // 获取配置目录路径
    String configDir;
    if (customDir != null && customDir.isNotEmpty) {
      configDir = customDir;
    } else {
      final homeDir = await SettingsService.getUserHomeDir();
      configDir = '$homeDir/.codex';
    }
    
    return await canAccessConfigDir(configDir);
  }

  /// 检查 Gemini 配置目录访问权限
  Future<bool> checkGeminiConfigAccess() async {
    final settingsService = SettingsService();
    await settingsService.init();
    
    final customDir = settingsService.getGeminiConfigDir();
    final geminiService = GeminiConfigService();
    
    // 获取配置目录路径
    String configDir;
    if (customDir != null && customDir.isNotEmpty) {
      configDir = customDir;
    } else {
      final homeDir = await SettingsService.getUserHomeDir();
      configDir = '$homeDir/.gemini';
    }
    
    return await canAccessConfigDir(configDir);
  }

  /// 检查 AI 工具配置目录访问权限
  Future<bool> checkToolConfigAccess(AiToolType tool) async {
    final toolConfigService = AiToolConfigService();
    final configDir = await toolConfigService.getConfigDir(tool);
    return await canAccessConfigDir(configDir);
  }

  /// 获取需要提示的配置目录列表
  /// 返回需要用户选择目录的工具列表
  Future<List<ConfigDirCheckResult>> checkAllConfigDirs() async {
    final results = <ConfigDirCheckResult>[];
    
    // 检查 Claude
    if (!hasPromptedForTool(_keyHasPromptedClaude)) {
      final canAccess = await checkClaudeConfigAccess();
      if (!canAccess) {
        results.add(ConfigDirCheckResult(
          toolName: 'Claude',
          toolKey: _keyHasPromptedClaude,
          defaultPath: await _getDefaultClaudePath(),
        ));
      }
    }
    
    // 检查 Codex
    if (!hasPromptedForTool(_keyHasPromptedCodex)) {
      final canAccess = await checkCodexConfigAccess();
      if (!canAccess) {
        results.add(ConfigDirCheckResult(
          toolName: 'Codex',
          toolKey: _keyHasPromptedCodex,
          defaultPath: await _getDefaultCodexPath(),
        ));
      }
    }
    
    // 检查 Gemini
    if (!hasPromptedForTool(_keyHasPromptedGemini)) {
      final canAccess = await checkGeminiConfigAccess();
      if (!canAccess) {
        results.add(ConfigDirCheckResult(
          toolName: 'Gemini',
          toolKey: _keyHasPromptedGemini,
          defaultPath: await _getDefaultGeminiPath(),
        ));
      }
    }
    
    // 检查其他 AI 工具
    for (final tool in AiToolType.values) {
      final toolKey = 'has_prompted_${tool.name}_dir';
      if (!hasPromptedForTool(toolKey)) {
        final canAccess = await checkToolConfigAccess(tool);
        if (!canAccess) {
          final homeDir = await SettingsService.getUserHomeDir();
          final defaultPath = AiToolConfigService.getDefaultConfigDir(tool, homeDir: homeDir);
          results.add(ConfigDirCheckResult(
            toolName: tool.displayName,
            toolKey: toolKey,
            defaultPath: defaultPath,
            toolType: tool,
          ));
        }
      }
    }
    
    return results;
  }

  Future<String> _getDefaultClaudePath() async {
    final homeDir = await SettingsService.getUserHomeDir();
    return '$homeDir/.claude';
  }

  Future<String> _getDefaultCodexPath() async {
    final homeDir = await SettingsService.getUserHomeDir();
    return '$homeDir/.codex';
  }

  Future<String> _getDefaultGeminiPath() async {
    final homeDir = await SettingsService.getUserHomeDir();
    return '$homeDir/.gemini';
  }
}

/// 配置目录检查结果
class ConfigDirCheckResult {
  final String toolName;
  final String toolKey;
  final String defaultPath;
  final AiToolType? toolType;

  ConfigDirCheckResult({
    required this.toolName,
    required this.toolKey,
    required this.defaultPath,
    this.toolType,
  });
}

