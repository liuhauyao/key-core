import 'package:flutter/material.dart';
import 'dart:io';
import '../services/settings_service.dart';
import '../services/macos_preferences_bridge.dart';
import '../services/ai_tool_config_service.dart';
import '../services/tool_enable_service.dart';
import '../services/status_bar_menu_bridge.dart';
import '../services/language_pack_service.dart';
import '../services/cloud_config_service.dart';
import '../models/mcp_server.dart';
import '../models/cloud_config.dart';
import 'base_viewmodel.dart';

/// 设置ViewModel
class SettingsViewModel extends BaseViewModel {
  final SettingsService _settingsService = SettingsService();
  final LanguagePackService _languagePackService = LanguagePackService();
  final CloudConfigService _cloudConfigService = CloudConfigService();

  String _currentLanguage = 'zh';
  ThemeMode _themeMode = ThemeMode.system;
  bool _minimizeToTray = false;
  String? _claudeConfigDir;
  String? _codexConfigDir;
  String? _defaultClaudeConfigDir;
  String? _defaultCodexConfigDir;

  // AI 工具配置目录
  final Map<AiToolType, String?> _toolConfigDirs = {};
  final Map<AiToolType, String> _defaultToolConfigDirs = {};
  final AiToolConfigService _toolConfigService = AiToolConfigService();
  
  // 工具启用状态
  final Map<AiToolType, bool> _toolEnabledStates = {};
  final Map<AiToolType, bool> _toolConfigValidStates = {};
  final ToolEnableService _toolEnableService = ToolEnableService();

  String get currentLanguage => _currentLanguage;
  ThemeMode get themeMode => _themeMode;
  bool get minimizeToTray => _minimizeToTray;
  String? get claudeConfigDir => _claudeConfigDir;
  String? get codexConfigDir => _codexConfigDir;
  String? get defaultClaudeConfigDir => _defaultClaudeConfigDir;
  String? get defaultCodexConfigDir => _defaultCodexConfigDir;

  /// 获取工具的配置目录
  String? getToolConfigDir(AiToolType tool) {
    return _toolConfigDirs[tool];
  }

  /// 获取工具的默认配置目录
  String getDefaultToolConfigDir(AiToolType tool) {
    return _defaultToolConfigDirs[tool] ?? '';
  }
  
  // 用于 Switch 的便捷属性
  bool get isEnglish => _currentLanguage == 'en';
  bool get isDarkTheme => _themeMode == ThemeMode.dark;
  bool get isSystemTheme => _themeMode == ThemeMode.system;
  
  /// 获取支持的语言列表（包含当前选择的语言，确保 MaterialApp 支持）
  /// 语言列表完全来自云端配置，不在应用中硬编码
  /// 这样可以在应用不更新的情况下，通过云端推送新语言
  List<SupportedLanguage> get supportedLanguages {
    final languages = _cloudConfigService.supportedLanguages;
    
    // 确保当前选择的语言在支持列表中
    // 如果配置文件中没有当前语言，但用户已经下载并选择了该语言
    // 则动态添加到列表中（使用语言代码作为显示名称的回退）
    if (!languages.any((lang) => lang.code == _currentLanguage)) {
      print('SettingsViewModel: 当前语言 $_currentLanguage 不在配置列表中，动态添加');
      return [
        ...languages,
        SupportedLanguage(
          code: _currentLanguage,
          name: _currentLanguage, // 使用语言代码作为名称
          nativeName: _currentLanguage, // 使用语言代码作为本地名称
          file: '$_currentLanguage.json',
          lastUpdated: DateTime.now().toIso8601String(),
        ),
      ];
    }
    
    return languages;
  }

  Future<void> init() async {
    print('SettingsViewModel.init: 开始初始化');
    await _settingsService.init();
    _currentLanguage = _settingsService.getLanguage();
    print('SettingsViewModel.init: 从 SharedPreferences 读取的语言: $_currentLanguage');
    _themeMode = _settingsService.getThemeMode();
    _minimizeToTray = _settingsService.getMinimizeToTray();
    _claudeConfigDir = _settingsService.getClaudeConfigDir();
    _codexConfigDir = _settingsService.getCodexConfigDir();
    
    // 获取默认路径（统一使用 SettingsService.getUserHomeDir() 确保一致性）
    final homeDir = await SettingsService.getUserHomeDir();
    _defaultClaudeConfigDir = '$homeDir/.claude'; // claudecode 配置文件在 ~/.claude 目录下
    _defaultCodexConfigDir = '$homeDir/.codex';

    // 初始化各工具的配置目录（使用统一的 homeDir）
    for (final tool in AiToolType.values) {
      _defaultToolConfigDirs[tool] = AiToolConfigService.getDefaultConfigDir(tool, homeDir: homeDir);
      _toolConfigDirs[tool] = await _toolConfigService.getConfigDir(tool);
      _toolEnabledStates[tool] = await _toolEnableService.isToolEnabled(tool);
      // 只验证已启用工具的配置文件
      if (_toolEnabledStates[tool] == true) {
        _toolConfigValidStates[tool] = await _toolEnableService.validateToolConfig(tool);
      } else {
        _toolConfigValidStates[tool] = false; // 未启用的工具不验证
      }
    }
    
    // 同步最小化到托盘设置到 macOS（延迟调用，确保 MethodChannel 已注册）
    if (Platform.isMacOS) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        // 同步设置并立即更新状态栏
        await MacOSPreferencesBridge.syncMinimizeToTray(_minimizeToTray);
        await MacOSPreferencesBridge.updateStatusBar();
      });
    }
    
    // 同步窗口标题栏主题到 macOS（延迟调用，确保 MethodChannel 已注册）
    if (Platform.isMacOS) {
      Future.delayed(const Duration(milliseconds: 300), () {
        String themeModeString;
        if (_themeMode == ThemeMode.system) {
          themeModeString = 'system'; // 传递 'system' 让原生代码处理
        } else {
          themeModeString = _themeMode == ThemeMode.dark ? 'dark' : 'light';
        }
        // 不等待结果，避免异常影响主流程
        MacOSPreferencesBridge.updateWindowTheme(themeModeString).catchError((_) {
          // 静默忽略错误
        });
      });
    }
    
    notifyListeners();
    
    // ⭐ 启动后台配置更新检查（不阻塞初始化）
    _autoCheckConfigUpdate();
  }

  Future<void> setLanguage(String language) async {
    print('SettingsViewModel.setLanguage: 开始切换语言到 $language');
    
    // 先保存语言设置
    await _settingsService.setLanguage(language);
    print('SettingsViewModel.setLanguage: 已保存语言设置到 SharedPreferences: $language');
    
    // 确保语言包已加载（强制刷新以清除缓存）
    await _languagePackService.init();
    await _languagePackService.loadLanguagePack(language, forceRefresh: true);
    print('SettingsViewModel.setLanguage: 已加载语言包: $language');
    
    // 更新当前语言
    _currentLanguage = language;
    print('SettingsViewModel.setLanguage: 已更新 _currentLanguage = $language');
    
    // 通知监听者，触发 MaterialApp 重新构建以应用新语言
    notifyListeners();
    print('SettingsViewModel.setLanguage: 已调用 notifyListeners()');
    
    // 等待一帧，确保 MaterialApp 已经重建
    await Future.delayed(const Duration(milliseconds: 50));
    print('SettingsViewModel.setLanguage: 语言切换完成: $language');
  }

  Future<void> toggleLanguage() async {
    final newLanguage = _currentLanguage == 'zh' ? 'en' : 'zh';
    await setLanguage(newLanguage);
  }

  /// 刷新云端配置（用于配置更新后刷新语言列表等）
  Future<void> refreshConfig() async {
    print('SettingsViewModel.refreshConfig: 开始刷新配置');
    
    // ⭐ 强制重新加载配置，清除所有缓存
    await _cloudConfigService.init();
    await _cloudConfigService.loadConfig(forceRefresh: true);  // 强制刷新
    await _languagePackService.init();
    
    final languages = _cloudConfigService.supportedLanguages;
    print('SettingsViewModel.refreshConfig: 配置已刷新，当前支持 ${languages.length} 种语言');
    print('SettingsViewModel.refreshConfig: 语言列表: ${languages.map((l) => l.code).join(", ")}');
    
    // 通知监听者，触发 MaterialApp 重新构建以更新 supportedLocales
    notifyListeners();
    print('SettingsViewModel.refreshConfig: 已通知监听者更新');
  }
  
  /// 自动后台检查配置更新（在 init 完成后执行）
  Future<void> _autoCheckConfigUpdate() async {
    // 延迟执行，避免影响初始化
    await Future.delayed(const Duration(milliseconds: 1000));
    
    try {
      print('SettingsViewModel: 开始后台检查配置更新...');
      // ⭐ 使用 force: true 强制检查，确保能检测到最新配置
      final hasUpdate = await _cloudConfigService.checkForUpdates(force: true);
      
      if (hasUpdate) {
        print('SettingsViewModel: 检测到配置更新，自动刷新配置');
        await refreshConfig();
        print('SettingsViewModel: 配置自动刷新完成');
      } else {
        print('SettingsViewModel: 配置已是最新版本');
      }
    } catch (e) {
      print('SettingsViewModel: 后台检查配置更新失败: $e');
      // 静默失败，不影响用户体验
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _settingsService.setThemeMode(mode);
    _themeMode = mode;
    
    // 同步窗口标题栏主题到 macOS（不等待，避免阻塞）
    if (Platform.isMacOS) {
      String themeModeString;
      if (mode == ThemeMode.system) {
        themeModeString = 'system'; // 传递 'system' 让原生代码处理
      } else {
        themeModeString = mode == ThemeMode.dark ? 'dark' : 'light';
      }
      // 不等待结果，避免异常影响主流程
      MacOSPreferencesBridge.updateWindowTheme(themeModeString).catchError((_) {
        // 静默忽略错误
      });
    }
    
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    // 在亮色、暗色、跟随系统之间循环切换
    ThemeMode newMode;
    switch (_themeMode) {
      case ThemeMode.light:
        newMode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        newMode = ThemeMode.system;
        break;
      case ThemeMode.system:
      default:
        newMode = ThemeMode.light;
        break;
    }
    await setThemeMode(newMode);
  }
  
  Future<void> setThemeLightDark(bool isDark) async {
    // 如果当前是跟随系统，切换到亮色或暗色
    if (_themeMode == ThemeMode.system) {
      await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
    } else {
      await setThemeMode(isDark ? ThemeMode.dark : ThemeMode.light);
    }
  }

  Future<void> setMinimizeToTray(bool value) async {
    print('SettingsViewModel: setMinimizeToTray 被调用，值: $value');
    await _settingsService.setMinimizeToTray(value);
    _minimizeToTray = value;
    print('SettingsViewModel: 设置已保存到 SharedPreferences');
    
    // 同步到 macOS UserDefaults
    if (Platform.isMacOS) {
      print('SettingsViewModel: 开始同步到 macOS');
      await MacOSPreferencesBridge.syncMinimizeToTray(value);
      // 立即更新状态栏（开启时添加按钮，关闭时移除按钮）
      await MacOSPreferencesBridge.updateStatusBar();
      print('SettingsViewModel: macOS 同步完成');
    }
    notifyListeners();
  }

  /// 设置 Claude 配置目录
  Future<void> setClaudeConfigDir(String? path) async {
    await _settingsService.setClaudeConfigDir(path);
    _claudeConfigDir = path;
    notifyListeners();
  }

  /// 设置 Codex 配置目录
  Future<void> setCodexConfigDir(String? path) async {
    await _settingsService.setCodexConfigDir(path);
    _codexConfigDir = path;
    notifyListeners();
  }

  /// 重置 Claude 配置目录为默认值
  Future<void> resetClaudeConfigDir() async {
    await setClaudeConfigDir(null);
  }

  /// 重置 Codex 配置目录为默认值
  Future<void> resetCodexConfigDir() async {
    await setCodexConfigDir(null);
  }

  /// 设置工具的配置目录
  Future<void> setToolConfigDir(AiToolType tool, String? configDir) async {
    if (configDir == null || configDir.trim().isEmpty) {
      await _toolConfigService.resetConfigDir(tool);
      _toolConfigDirs[tool] = null;
    } else {
      await _toolConfigService.setConfigDir(tool, configDir.trim());
      _toolConfigDirs[tool] = configDir.trim();
    }
    notifyListeners();
  }

  /// 重置工具的配置目录为默认值
  Future<void> resetToolConfigDir(AiToolType tool) async {
    await _toolConfigService.resetConfigDir(tool);
    _toolConfigDirs[tool] = null;
    // 重新验证配置
    _toolConfigValidStates[tool] = await _toolEnableService.validateToolConfig(tool);
    notifyListeners();
  }

  /// 获取工具启用状态
  bool isToolEnabled(AiToolType tool) {
    return _toolEnabledStates[tool] ?? false;
  }

  /// 获取工具配置验证状态
  bool isToolConfigValid(AiToolType tool) {
    return _toolConfigValidStates[tool] ?? false;
  }

  /// 设置工具启用状态（需要先验证配置文件）
  Future<bool> setToolEnabled(AiToolType tool, bool enabled) async {
    if (enabled) {
      // 启用前先验证配置文件是否存在
      final isValid = await _toolEnableService.validateToolConfig(tool);
      if (!isValid) {
        return false; // 配置文件不存在，无法启用
      }
      _toolConfigValidStates[tool] = true;
    }
    
    await _toolEnableService.setToolEnabled(tool, enabled);
    _toolEnabledStates[tool] = enabled;
    
    // 通知状态栏菜单更新（claudecode、codex 和 gemini 开关改变时）
    if (Platform.isMacOS && (tool == AiToolType.claudecode || tool == AiToolType.codex || tool == AiToolType.gemini)) {
      try {
        await StatusBarMenuBridge.updateStatusBarMenu();
      } catch (e) {
        // 静默忽略错误，避免影响主流程
      }
    }
    
    notifyListeners();
    return true;
  }

  /// 刷新工具配置验证状态
  Future<void> refreshToolConfigValidation(AiToolType tool) async {
    _toolConfigValidStates[tool] = await _toolEnableService.validateToolConfig(tool);
    notifyListeners();
  }

  /// 获取所有已启用的工具
  List<AiToolType> getEnabledTools() {
    return _toolEnabledStates.entries
        .where((entry) => entry.value == true)
        .map((entry) => entry.key)
        .toList();
  }
}

