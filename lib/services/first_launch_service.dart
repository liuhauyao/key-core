import 'dart:io';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';
import 'macos_bookmark_service.dart';
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
  static const String _keyHasPromptedHomeDir = 'has_prompted_home_dir';

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

  /// 检查是否需要统一目录授权（首次启动时）
  /// 如果用户主目录无法访问，返回 true，表示需要授权
  Future<bool> needsHomeDirAuthorization() async {
    // macOS: 先检查是否有保存的 Security-Scoped Bookmark
    if (Platform.isMacOS) {
      final bookmarkService = MacOSBookmarkService();
      final hasBookmark = await bookmarkService.hasHomeDirAuthorization();
      if (hasBookmark) {
        // 有保存的 bookmark，尝试恢复访问权限
        final restored = await bookmarkService.restoreHomeDirAccess();
        if (restored) {
          // 权限已恢复，检查是否已经提示过
          if (!hasPromptedForTool(_keyHasPromptedHomeDir)) {
            // 如果权限已恢复但还没提示过，标记为已提示（避免重复提示）
            await markHomeDirPrompted();
          }
          return false; // 权限已恢复，不需要授权
        } else {
          // bookmark 存在但无法恢复，可能需要重新授权
          print("FirstLaunchService: Security-Scoped Bookmark 存在但无法恢复，可能需要重新授权");
        }
      }
    }
    
    // 如果已经提示过，不再提示
    if (hasPromptedForTool(_keyHasPromptedHomeDir)) {
      return false;
    }

    try {
      final homeDir = await SettingsService.getUserHomeDir();
      // 尝试访问用户主目录
      return !await canAccessConfigDir(homeDir);
    } catch (e) {
      // 如果出现异常，说明需要授权
      return true;
    }
  }

  /// 标记已提示过用户主目录授权
  Future<void> markHomeDirPrompted() async {
    await markToolPrompted(_keyHasPromptedHomeDir);
  }

  /// 检测用户主目录下的所有工具配置目录
  /// 返回检测到的工具配置目录信息
  Future<List<ToolConfigDetected>> detectToolConfigsInHomeDir(String homeDir) async {
    final detected = <ToolConfigDetected>[];

    // 定义所有工具的配置目录
    final toolConfigs = [
      _ToolConfigInfo(
        toolType: null, // Claude 使用特殊处理
        toolName: 'Claude',
        configDir: '$homeDir/.claude',
        configFile: '$homeDir/.claude/config.json',
      ),
      _ToolConfigInfo(
        toolType: null, // Codex 使用特殊处理
        toolName: 'Codex',
        configDir: '$homeDir/.codex',
        configFile: '$homeDir/.codex/config.toml',
      ),
      _ToolConfigInfo(
        toolType: AiToolType.gemini,
        toolName: 'Gemini',
        configDir: '$homeDir/.gemini',
        configFile: '$homeDir/.gemini/settings.json',
      ),
      _ToolConfigInfo(
        toolType: AiToolType.cursor,
        toolName: 'Cursor',
        configDir: '$homeDir/.cursor',
        configFile: '$homeDir/.cursor/mcp.json',
      ),
      _ToolConfigInfo(
        toolType: AiToolType.windsurf,
        toolName: 'Windsurf',
        configDir: '$homeDir/.codeium/windsurf',
        configFile: '$homeDir/.codeium/windsurf/mcp_config.json',
      ),
    ];

    for (final config in toolConfigs) {
      try {
        final dir = Directory(config.configDir);
        final dirExists = await dir.exists();
        
        if (dirExists) {
          // 检查目录是否可访问
          final canAccess = await canAccessConfigDir(config.configDir);
          if (canAccess) {
            detected.add(ToolConfigDetected(
              toolName: config.toolName,
              toolType: config.toolType,
              configDir: config.configDir,
              configFile: config.configFile,
            ));
          }
        }
      } catch (e) {
        // 忽略错误，继续检测下一个
        print('FirstLaunchService: 检测工具配置失败 ${config.toolName}: $e');
      }
    }

    return detected;
  }
}

/// 工具配置信息（内部使用）
class _ToolConfigInfo {
  final AiToolType? toolType;
  final String toolName;
  final String configDir;
  final String configFile;

  _ToolConfigInfo({
    this.toolType,
    required this.toolName,
    required this.configDir,
    required this.configFile,
  });
}

/// 检测到的工具配置信息
class ToolConfigDetected {
  final String toolName;
  final AiToolType? toolType;
  final String configDir;
  final String configFile;

  ToolConfigDetected({
    required this.toolName,
    this.toolType,
    required this.configDir,
    required this.configFile,
  });
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

