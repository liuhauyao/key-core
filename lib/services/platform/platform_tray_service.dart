import 'dart:io';

// 导入平台特定实现（在文件末尾导入，避免循环依赖）
import 'macos_tray_service.dart';
import 'windows_tray_service.dart';
import 'linux_tray_service.dart';

/// 托盘菜单项数据模型
class TrayMenuItem {
  final String id;
  final String label;
  final bool enabled;
  final bool checked;
  final List<TrayMenuItem>? submenu;

  const TrayMenuItem({
    required this.id,
    required this.label,
    this.enabled = true,
    this.checked = false,
    this.submenu,
  });
}

/// 托盘服务抽象接口
/// 提供跨平台的托盘菜单管理功能
abstract class PlatformTrayService {
  /// 初始化托盘服务
  /// [onMenuItemClick] 菜单项点击回调，参数为菜单项 ID
  Future<void> init({
    required Function(String menuItemId) onMenuItemClick,
    String? iconPath,
  });

  /// 更新托盘菜单
  /// [items] 菜单项列表
  Future<void> updateMenu(List<TrayMenuItem> items);

  /// 显示主窗口
  Future<void> showWindow();

  /// 隐藏主窗口
  Future<void> hideWindow();

  /// 退出应用
  Future<void> quit();

  /// 设置托盘图标
  Future<void> setIcon(String iconPath);

  /// 设置托盘提示文本
  Future<void> setToolTip(String tooltip);

  /// 销毁托盘服务
  Future<void> destroy();
}

/// 托盘服务工厂
/// 根据当前平台创建对应的托盘服务实例
PlatformTrayService createPlatformTrayService() {
  if (Platform.isMacOS) {
    return MacOSTrayService();
  } else if (Platform.isWindows) {
    return WindowsTrayService();
  } else if (Platform.isLinux) {
    return LinuxTrayService();
  } else {
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

