import 'dart:io';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'platform_tray_service.dart';

/// Linux 托盘服务实现
/// 使用 tray_manager 插件实现跨平台托盘功能
/// 注意：Linux 需要桌面环境支持（GNOME/KDE/XFCE 等）
class LinuxTrayService implements PlatformTrayService {
  Function(String)? _onMenuItemClick;
  bool _initialized = false;

  @override
  Future<void> init({
    required Function(String menuItemId) onMenuItemClick,
    String? iconPath,
  }) async {
    if (!Platform.isLinux) {
      throw UnsupportedError('LinuxTrayService can only be used on Linux');
    }

    _onMenuItemClick = onMenuItemClick;

    // 初始化 tray_manager
    // Linux 使用 PNG 格式图标
    await trayManager.setIcon(iconPath ?? 'assets/icons/app_icon.png');
    
    // 监听菜单项点击事件
    trayManager.addListener(_TrayListener(onMenuItemClick: _handleMenuItemClick));

    _initialized = true;
  }

  void _handleMenuItemClick(String menuItemId) {
    _onMenuItemClick?.call(menuItemId);
  }

  @override
  Future<void> updateMenu(List<TrayMenuItem> items) async {
    if (!_initialized || !Platform.isLinux) return;

    // 将 TrayMenuItem 转换为 tray_manager 的 Menu 格式
    final menuItems = items
        .map((item) => _convertMenuItem(item))
        .whereType<MenuItem>()
        .toList();

    final menu = Menu(items: menuItems);

    await trayManager.setContextMenu(menu);
  }

  /// 将 TrayMenuItem 转换为 tray_manager 的 MenuItem
  MenuItem? _convertMenuItem(TrayMenuItem item) {
    // 处理分隔符（如果 label 包含多个 '-' 字符，视为分隔符）
    if (item.label.trim().replaceAll('-', '').isEmpty && !item.enabled) {
      return MenuItem.separator();
    }

    // tray_manager 0.5.2 不支持子菜单，使用扁平化结构
    // 如果有子菜单，展开为多个菜单项（这里简化处理，只返回主项）
    if (item.submenu != null && item.submenu!.isNotEmpty) {
      // 对于有子菜单的项，返回主菜单项
      // 注意：tray_manager 0.5.2 可能不支持子菜单，这里只返回主项
      return MenuItem(
        key: item.id,
        label: item.label,
      );
    } else {
      // 普通菜单项
      return MenuItem(
        key: item.id,
        label: item.label,
      );
    }
  }

  @override
  Future<void> showWindow() async {
    if (!Platform.isLinux) return;

    try {
      // 使用 window_manager 显示窗口
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setSkipTaskbar(false);
    } catch (e) {
      print('LinuxTrayService: 显示窗口失败: $e');
    }
  }

  @override
  Future<void> hideWindow() async {
    if (!Platform.isLinux) return;

    try {
      // 使用 window_manager 隐藏窗口
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    } catch (e) {
      print('LinuxTrayService: 隐藏窗口失败: $e');
    }
  }

  @override
  Future<void> quit() async {
    if (!Platform.isLinux) return;

    exit(0);
  }

  @override
  Future<void> setIcon(String iconPath) async {
    if (!Platform.isLinux) return;

    await trayManager.setIcon(iconPath);
  }

  @override
  Future<void> setToolTip(String tooltip) async {
    if (!Platform.isLinux) return;

    await trayManager.setToolTip(tooltip);
  }

  @override
  Future<void> destroy() async {
    if (!Platform.isLinux) return;

    trayManager.removeListener(_TrayListener(onMenuItemClick: _handleMenuItemClick));
    _initialized = false;
  }
}

/// tray_manager 监听器
class _TrayListener extends TrayListener {
  final Function(String) onMenuItemClick;

  _TrayListener({required this.onMenuItemClick});

  @override
  void onTrayIconMouseDown() {
    // Linux 托盘图标点击事件
  }

  @override
  void onTrayIconRightMouseDown() {
    // Linux 托盘图标右键点击事件
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    onMenuItemClick(menuItem.key ?? '');
  }
}

