import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/mcp_server.dart';
import 'settings_service.dart';

/// AI 工具配置服务
/// 管理各 AI 工具的配置目录路径
class AiToolConfigService {
  static const String _configKeyPrefix = 'ai_tool_config_dir_';

  /// 获取工具的默认配置目录路径
  /// 注意：此方法使用 Platform.environment，如果需要更准确的用户主目录，请使用 SettingsService.getUserHomeDir()
  static String getDefaultConfigDir(AiToolType tool, {String? homeDir}) {
    final home = homeDir ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '~';
    switch (tool) {
      case AiToolType.cursor:
        return path.join(home, '.cursor');
      case AiToolType.claudecode:
        // claudecode 的配置文件在 ~/.claude 目录下
        return path.join(home, '.claude');
      case AiToolType.codex:
        return path.join(home, '.codex');
      case AiToolType.windsurf:
        // Windsurf 的配置文件在 ~/.codeium/windsurf 目录下
        return path.join(home, '.codeium', 'windsurf');
      case AiToolType.cline:
        // Cline 的配置文件在 VS Code 扩展的 globalStorage 目录下
        if (Platform.isMacOS) {
          return path.join(home, 'Library', 'Application Support', 'Code', 'User', 'globalStorage', 'saoudrizwan.claude-dev', 'settings');
        } else if (Platform.isWindows) {
          final appData = Platform.environment['APPDATA'] ?? home;
          return path.join(appData, 'Code', 'User', 'globalStorage', 'saoudrizwan.claude-dev', 'settings');
        } else {
          // Linux 或其他平台
          return path.join(home, '.config', 'Code', 'User', 'globalStorage', 'saoudrizwan.claude-dev', 'settings');
        }
      case AiToolType.gemini:
        // Gemini 的配置文件在 ~/.gemini 目录下
        return path.join(home, '.gemini');
    }
  }

  /// 获取工具的配置文件路径
  static String getConfigFilePath(AiToolType tool, {String? customConfigDir, String? homeDir}) {
    final configDir = customConfigDir ?? getDefaultConfigDir(tool, homeDir: homeDir);
    switch (tool) {
      case AiToolType.cursor:
        return path.join(configDir, 'mcp.json');
      case AiToolType.claudecode:
        // claudecode 的配置文件是 config.json，在配置目录（~/.claude）下
        return path.join(configDir, 'config.json');
      case AiToolType.codex:
        // Codex 使用 config.toml 文件，TOML 格式
        return path.join(configDir, 'config.toml');
      case AiToolType.windsurf:
        // Windsurf 使用 mcp_config.json 文件
        return path.join(configDir, 'mcp_config.json');
      case AiToolType.cline:
        // Cline 使用 cline_mcp_settings.json 文件
        return path.join(configDir, 'cline_mcp_settings.json');
      case AiToolType.gemini:
        // Gemini 使用 settings.json 文件
        return path.join(configDir, 'settings.json');
    }
  }

  // 缓存配置目录，避免重复获取和打印日志
  final Map<AiToolType, String> _cachedConfigDirs = {};

  /// 获取工具的配置目录路径（从设置中读取，如果没有则返回默认值）
  Future<String> getConfigDir(AiToolType tool) async {
    // 如果已缓存，直接返回
    if (_cachedConfigDirs.containsKey(tool)) {
      return _cachedConfigDirs[tool]!;
    }

    final settingsService = SettingsService();
    await settingsService.init();
    final key = '$_configKeyPrefix${tool.value}';
    final customDir = settingsService.getSetting(key);
    
    String configDir;
    
    // 如果有自定义目录，使用自定义目录
    if (customDir != null && customDir.isNotEmpty) {
      configDir = customDir;
    } else {
      // 否则使用默认目录（使用 SettingsService.getUserHomeDir() 获取更准确的用户主目录）
      final homeDir = await SettingsService.getUserHomeDir();
      configDir = getDefaultConfigDir(tool, homeDir: homeDir);
    }
    
    // 缓存结果
    _cachedConfigDirs[tool] = configDir;
    return configDir;
  }

  /// 设置工具的配置目录路径
  Future<void> setConfigDir(AiToolType tool, String configDir) async {
    final settingsService = SettingsService();
    await settingsService.init();
    final key = '$_configKeyPrefix${tool.value}';
    await settingsService.setSetting(key, configDir);
  }

  /// 重置工具的配置目录路径为默认值
  Future<void> resetConfigDir(AiToolType tool) async {
    final settingsService = SettingsService();
    await settingsService.init();
    final key = '$_configKeyPrefix${tool.value}';
    await settingsService.removeSetting(key);
  }

  /// 展开路径中的 ~ 符号
  static String expandPath(String pathStr) {
    if (pathStr.startsWith('~')) {
      final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '~';
      return pathStr.replaceFirst('~', homeDir);
    }
    return pathStr;
  }

  /// 确保配置目录存在
  Future<void> ensureConfigDirExists(AiToolType tool, {String? customConfigDir}) async {
    final configDir = customConfigDir ?? await getConfigDir(tool);
    final expandedDir = expandPath(configDir);
    final dir = Directory(expandedDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}

