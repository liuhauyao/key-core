import 'dart:io';
import '../models/mcp_server.dart';
import '../services/tool_enable_service.dart';
import '../services/settings_service.dart';
import '../viewmodels/key_manager_viewmodel.dart';
import '../services/platform/platform_tray_service.dart' as platform;
import 'status_bar_menu_bridge.dart' as legacy;

/// 跨平台托盘菜单桥接服务
/// 统一管理 macOS/Windows/Linux 的托盘菜单
/// macOS: 保留现有的 MethodChannel 方式（向后兼容）
/// Windows/Linux: 使用 tray_manager 插件
class TrayMenuBridge {
  static platform.PlatformTrayService? _trayService;
  static KeyManagerViewModel? _keyManagerViewModel;
  static SettingsService? _settingsService;
  static bool _initialized = false;

  /// 初始化托盘菜单桥接
  /// 根据平台选择对应的实现方式
  static Future<void> init(KeyManagerViewModel keyManagerViewModel) async {
    if (_initialized) return;

    _keyManagerViewModel = keyManagerViewModel;
    _settingsService = SettingsService();
    await _settingsService?.init();

    if (Platform.isMacOS) {
      // macOS: 使用现有的 StatusBarMenuBridge（向后兼容）
      await legacy.StatusBarMenuBridge.init(keyManagerViewModel);
    } else {
      // Windows/Linux: 使用新的 PlatformTrayService
      _trayService = platform.createPlatformTrayService();
      await _trayService?.init(
        onMenuItemClick: _handleMenuItemClick,
        iconPath: null, // 使用默认图标
      );
    }

    _initialized = true;
  }

  /// 处理菜单项点击事件
  static void _handleMenuItemClick(String menuItemId) {
    if (_keyManagerViewModel == null) return;

    switch (menuItemId) {
      case 'show_main':
        _showMainWindow();
        break;
      case 'quit':
        _quitApplication();
        break;
      default:
        // 处理密钥切换事件
        _handleKeySwitch(menuItemId);
        break;
    }
  }

  /// 处理密钥切换事件
  /// 菜单项 ID 格式: "claudecode_<keyId>", "codex_<keyId>", "gemini_<keyId>"
  static Future<void> _handleKeySwitch(String menuItemId) async {
    if (_keyManagerViewModel == null) return;

    final parts = menuItemId.split('_');
    if (parts.length != 2) return;

    final tool = parts[0];
    final keyIdStr = parts[1];
    final keyId = int.tryParse(keyIdStr);

    if (keyId == null) return;

    switch (tool) {
      case 'claudecode':
        if (keyId == -1) {
          await _keyManagerViewModel!.switchToOfficialClaudeCode();
        } else {
          await _keyManagerViewModel!.switchClaudeCodeProvider(keyId);
        }
        break;
      case 'codex':
        if (keyId == -1) {
          await _keyManagerViewModel!.switchToOfficialCodex();
        } else {
          await _keyManagerViewModel!.switchCodexProvider(keyId);
        }
        break;
      case 'gemini':
        if (keyId == -1) {
          await _keyManagerViewModel!.switchToOfficialGemini();
        } else {
          await _keyManagerViewModel!.switchGeminiProvider(keyId);
        }
        break;
    }

    // 更新菜单以反映新的选择状态
    await updateTrayMenu();
  }

  /// 显示主窗口
  static void _showMainWindow() {
    if (Platform.isMacOS) {
      // macOS: 通过 StatusBarMenuBridge 显示窗口（原生代码处理）
      // 这里不需要额外处理，原生代码会处理窗口显示
    } else {
      // Windows/Linux: 通过 PlatformTrayService 显示窗口
      _trayService?.showWindow();
    }
  }

  /// 退出应用
  static void _quitApplication() {
    _trayService?.quit();
  }

  /// 更新托盘菜单
  /// 根据当前平台调用对应的更新方法
  static Future<void> updateTrayMenu() async {
    if (!_initialized) return;

    if (Platform.isMacOS) {
      // macOS: 使用现有的 StatusBarMenuBridge
      await legacy.StatusBarMenuBridge.updateStatusBarMenu();
    } else {
      // Windows/Linux: 构建菜单并更新
      final menuItems = await _buildMenuItems();
      await _trayService?.updateMenu(menuItems);
    }
  }

  /// 构建菜单项列表
  static Future<List<platform.TrayMenuItem>> _buildMenuItems() async {
    if (_keyManagerViewModel == null || _settingsService == null) {
      return [];
    }

    final items = <platform.TrayMenuItem>[];

    // 显示窗口
    items.add(platform.TrayMenuItem(
      id: 'show_main',
      label: _getLocalizedText('show_main'),
    ));

    // 分隔符（tray_manager 使用特殊类型）
    // 注意：tray_manager 可能不支持文本分隔符，需要在转换时处理

    // Claude Code 密钥切换
    final claudeEnabled = await _isToolEnabled('claudecode');
    if (claudeEnabled) {
      items.add(platform.TrayMenuItem(
        id: 'claude_header',
        label: '─── Claude ───',
        enabled: false,
      ));

      final claudeKeys = await _getClaudeCodeKeys();
      if (claudeKeys.isEmpty) {
        items.add(platform.TrayMenuItem(
          id: 'claude_empty',
          label: '  (无密钥，请在主界面添加)',
          enabled: false,
        ));
      } else {
        final currentClaudeKeyId = await _getCurrentClaudeCodeKeyId();
        for (final key in claudeKeys) {
          final keyId = key['id'] as int;
          final keyName = key['name'] as String;
          items.add(platform.TrayMenuItem(
            id: 'claudecode_$keyId',
            label: keyName,
            checked: keyId == currentClaudeKeyId,
          ));
        }
      }

      items.add(platform.TrayMenuItem(
        id: 'separator_claude',
        label: '─────────',
        enabled: false,
      ));
    }

    // Codex 密钥切换
    final codexEnabled = await _isToolEnabled('codex');
    if (codexEnabled) {
      items.add(platform.TrayMenuItem(
        id: 'codex_header',
        label: '─── Codex ───',
        enabled: false,
      ));

      final codexKeys = await _getCodexKeys();
      if (codexKeys.isEmpty) {
        items.add(platform.TrayMenuItem(
          id: 'codex_empty',
          label: '  (无密钥，请在主界面添加)',
          enabled: false,
        ));
      } else {
        final currentCodexKeyId = await _getCurrentCodexKeyId();
        for (final key in codexKeys) {
          final keyId = key['id'] as int;
          final keyName = key['name'] as String;
          items.add(platform.TrayMenuItem(
            id: 'codex_$keyId',
            label: keyName,
            checked: keyId == currentCodexKeyId,
          ));
        }
      }

      items.add(platform.TrayMenuItem(
        id: 'separator_codex',
        label: '─────────',
        enabled: false,
      ));
    }

    // Gemini 密钥切换
    final geminiEnabled = await _isToolEnabled('gemini');
    if (geminiEnabled) {
      items.add(platform.TrayMenuItem(
        id: 'gemini_header',
        label: '─── Gemini ───',
        enabled: false,
      ));

      final geminiKeys = await _getGeminiKeys();
      if (geminiKeys.isEmpty) {
        items.add(platform.TrayMenuItem(
          id: 'gemini_empty',
          label: '  (无密钥，请在主界面添加)',
          enabled: false,
        ));
      } else {
        final currentGeminiKeyId = await _getCurrentGeminiKeyId();
        for (final key in geminiKeys) {
          final keyId = key['id'] as int;
          final keyName = key['name'] as String;
          items.add(platform.TrayMenuItem(
            id: 'gemini_$keyId',
            label: keyName,
            checked: keyId == currentGeminiKeyId,
          ));
        }
      }

      items.add(platform.TrayMenuItem(
        id: 'separator_gemini',
        label: '─────────',
        enabled: false,
      ));
    }

    // 退出
    items.add(platform.TrayMenuItem(
      id: 'quit',
      label: _getLocalizedText('quit'),
    ));

    return items;
  }

  /// 获取本地化文本
  static String _getLocalizedText(String key) {
    final language = _settingsService?.getLanguage() ?? 'zh';
    const Map<String, Map<String, String>> localizedValues = {
      'zh': {
        'show_main': '显示窗口',
        'quit': '退出',
      },
      'en': {
        'show_main': 'Show Window',
        'quit': 'Quit',
      },
    };
    return localizedValues[language]?[key] ?? localizedValues['zh']![key]!;
  }

  /// 检查工具是否启用
  static Future<bool> _isToolEnabled(String toolValue) async {
    final toolEnableService = ToolEnableService();
    await toolEnableService.init();

    AiToolType tool;
    switch (toolValue) {
      case 'claudecode':
        tool = AiToolType.claudecode;
        break;
      case 'codex':
        tool = AiToolType.codex;
        break;
      case 'gemini':
        tool = AiToolType.gemini;
        break;
      default:
        return false;
    }

    return await toolEnableService.isToolEnabled(tool);
  }

  /// 获取 ClaudeCode 密钥列表
  static Future<List<Map<String, dynamic>>> _getClaudeCodeKeys() async {
    if (_keyManagerViewModel == null) return [];
    final keys = await _keyManagerViewModel!.getClaudeCodeKeys();
    final result = keys.map((key) => {
      'id': key.id,
      'name': key.name,
      'platform': key.platform,
    }).toList();

    // 添加官方配置选项
    result.insert(0, {
      'id': -1,
      'name': _getOfficialConfigText(),
      'platform': 'official',
    });

    return result;
  }

  /// 获取 Codex 密钥列表
  static Future<List<Map<String, dynamic>>> _getCodexKeys() async {
    if (_keyManagerViewModel == null) return [];
    final keys = await _keyManagerViewModel!.getCodexKeys();
    final result = keys.map((key) => {
      'id': key.id,
      'name': key.name,
      'platform': key.platform,
    }).toList();

    // 添加官方配置选项
    result.insert(0, {
      'id': -1,
      'name': _getOfficialConfigText(),
      'platform': 'official',
    });

    return result;
  }

  /// 获取 Gemini 密钥列表
  static Future<List<Map<String, dynamic>>> _getGeminiKeys() async {
    if (_keyManagerViewModel == null) return [];
    final keys = await _keyManagerViewModel!.getGeminiKeys();
    final result = keys.map((key) => {
      'id': key.id,
      'name': key.name,
      'platform': key.platform,
    }).toList();

    // 添加官方配置选项
    result.insert(0, {
      'id': -1,
      'name': _getOfficialConfigText(),
      'platform': 'official',
    });

    return result;
  }

  /// 获取当前 ClaudeCode 使用的密钥ID
  static Future<int?> _getCurrentClaudeCodeKeyId() async {
    if (_keyManagerViewModel == null) return null;
    final isOfficial = await _keyManagerViewModel!.isOfficialClaudeCodeConfig();
    if (isOfficial) {
      return -1;
    }
    final currentKey = await _keyManagerViewModel!.getCurrentClaudeCodeKey();
    return currentKey?.id;
  }

  /// 获取当前 Codex 使用的密钥ID
  static Future<int?> _getCurrentCodexKeyId() async {
    if (_keyManagerViewModel == null) return null;
    final isOfficial = await _keyManagerViewModel!.isOfficialCodexConfig();
    if (isOfficial) {
      return -1;
    }
    final currentKey = await _keyManagerViewModel!.getCurrentCodexKey();
    return currentKey?.id;
  }

  /// 获取当前 Gemini 使用的密钥ID
  static Future<int?> _getCurrentGeminiKeyId() async {
    if (_keyManagerViewModel == null) return null;
    final isOfficial = await _keyManagerViewModel!.isOfficialGeminiConfig();
    if (isOfficial) {
      return -1;
    }
    final currentKey = await _keyManagerViewModel!.getCurrentGeminiKey();
    return currentKey?.id;
  }

  /// 获取官方配置的国际化文本
  static String _getOfficialConfigText() {
    final language = _settingsService?.getLanguage() ?? 'zh';
    const Map<String, Map<String, String>> localizedValues = {
      'zh': {
        'official_config': '官方配置',
      },
      'en': {
        'official_config': 'Official Config',
      },
    };
    return localizedValues[language]?['official_config'] ??
        localizedValues['zh']!['official_config']!;
  }
}

