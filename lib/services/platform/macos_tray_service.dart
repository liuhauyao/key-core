import 'dart:io';
import 'package:flutter/services.dart';
import 'platform_tray_service.dart';

/// macOS 托盘服务实现
/// 优先使用现有的 MethodChannel 方式（向后兼容）
/// 可选：使用 tray_manager 插件（统一实现）
class MacOSTrayService implements PlatformTrayService {
  static const MethodChannel _channel = MethodChannel('cn.dlrow.keycore/window');
  Function(String)? _onMenuItemClick;

  @override
  Future<void> init({
    required Function(String menuItemId) onMenuItemClick,
    String? iconPath,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('MacOSTrayService can only be used on macOS');
    }

    _onMenuItemClick = onMenuItemClick;

    // macOS 使用现有的 MethodChannel 方式
    // 托盘菜单通过原生代码管理，这里只需要确保桥接已初始化
    // 实际的托盘创建在 AppDelegate.swift 中完成
  }

  @override
  Future<void> updateMenu(List<TrayMenuItem> items) async {
    if (!Platform.isMacOS) return;

    // 通知原生端更新状态栏菜单
    // macOS 的原生代码会通过 MethodChannel 调用 Flutter 获取菜单数据
    try {
      await _channel.invokeMethod('updateStatusBarMenu');
    } catch (e) {
      if (e is MissingPluginException) {
        // MethodChannel 可能还未注册，延迟重试
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _channel.invokeMethod('updateStatusBarMenu');
          } catch (_) {
            // 忽略重试失败
          }
        });
      }
    }
  }

  @override
  Future<void> showWindow() async {
    if (!Platform.isMacOS) return;

    // macOS 窗口显示通过原生代码处理
    // 这里可以通过 MethodChannel 调用原生代码，或者直接使用 Flutter 窗口 API
    // 由于 macOS 已经有完整的原生实现，这里暂时不实现
    // 实际的窗口显示逻辑在 AppDelegate.swift 中
  }

  @override
  Future<void> hideWindow() async {
    if (!Platform.isMacOS) return;

    // macOS 窗口隐藏通过原生代码处理
    // 实际的窗口隐藏逻辑在 MainFlutterWindow.swift 中
  }

  @override
  Future<void> quit() async {
    if (!Platform.isMacOS) return;

    // macOS 退出通过原生代码处理
    // 实际的退出逻辑在 AppDelegate.swift 中
    exit(0);
  }

  @override
  Future<void> setIcon(String iconPath) async {
    if (!Platform.isMacOS) return;

    // macOS 图标设置通过原生代码处理
    // 实际的图标设置逻辑在 AppDelegate.swift 中
  }

  @override
  Future<void> setToolTip(String tooltip) async {
    if (!Platform.isMacOS) return;

    // macOS 提示文本设置通过原生代码处理
    // 实际的提示文本设置逻辑在 AppDelegate.swift 中
  }

  @override
  Future<void> destroy() async {
    if (!Platform.isMacOS) return;

    // macOS 托盘销毁通过原生代码处理
    // 实际的销毁逻辑在 AppDelegate.swift 中
  }
}

