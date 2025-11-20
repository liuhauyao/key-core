import 'dart:io';
import 'package:flutter/services.dart';

/// macOS 偏好设置桥接服务
/// 用于在 Flutter 和 macOS 原生代码之间同步设置
class MacOSPreferencesBridge {
  static const String _bundleId = 'com.example.keyCore';
  static const MethodChannel _channel = MethodChannel('com.example.keyCore/window');

  /// 同步最小化到托盘设置到 macOS UserDefaults
  /// 注意：在沙箱环境中，通过 MethodChannel 直接同步到原生代码更可靠
  static Future<void> syncMinimizeToTray(bool value) async {
    if (!Platform.isMacOS) return;

    print('MacOSPreferencesBridge: syncMinimizeToTray 被调用，值: $value');
    try {
      // 优先使用 MethodChannel 同步（更可靠，支持沙箱环境）
      print('MacOSPreferencesBridge: 调用 MethodChannel syncMinimizeToTray');
      await _channel.invokeMethod('syncMinimizeToTray', {'value': value});
      print('MacOSPreferencesBridge: MethodChannel syncMinimizeToTray 调用成功');
    } catch (e) {
      print('MacOSPreferencesBridge: MethodChannel syncMinimizeToTray 调用失败: $e');
      // 如果 MethodChannel 失败，尝试使用命令行（非沙箱环境）
      if (e is MissingPluginException) {
        // MethodChannel 还未准备好，延迟重试
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _channel.invokeMethod('syncMinimizeToTray', {'value': value});
          } catch (_) {
            // 如果还是失败，尝试命令行方式（非沙箱环境）
            try {
              await Process.run('defaults', [
                'write',
                _bundleId,
                'minimize_to_tray',
                value ? '-bool' : '-bool',
                value ? 'YES' : 'NO',
              ]);
            } catch (_) {
              // 忽略所有错误
            }
          }
        });
      } else {
        // 其他错误，尝试命令行方式
        try {
          await Process.run('defaults', [
            'write',
            _bundleId,
            'minimize_to_tray',
            value ? '-bool' : '-bool',
            value ? 'YES' : 'NO',
          ]);
        } catch (_) {
          // 忽略错误
        }
      }
    }
  }

  /// 从 macOS UserDefaults 读取最小化到托盘设置
  static Future<bool?> readMinimizeToTray() async {
    if (!Platform.isMacOS) return null;

    try {
      final result = await Process.run('defaults', [
        'read',
        _bundleId,
        'minimize_to_tray',
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString().trim();
        return output == '1' || output.toLowerCase() == 'yes';
      }
    } catch (e) {
      // 忽略错误
    }
    
    return null;
  }

  /// 更新窗口标题栏主题
  /// themeMode: 'light', 'dark', or 'system'
  static Future<void> updateWindowTheme(String themeMode) async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('updateWindowTheme', {'themeMode': themeMode});
    } catch (e) {
      // 忽略 MissingPluginException，因为 MethodChannel 可能还未注册
      // 这在应用启动时是正常的，主题同步不是关键功能
      if (e is MissingPluginException) {
        // MethodChannel 还未准备好，延迟重试（使用 unawaited 避免警告）
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _channel.invokeMethod('updateWindowTheme', {'themeMode': themeMode});
          } catch (_) {
            // 忽略重试失败，静默处理
          }
        });
      }
      // 其他错误静默忽略，不打印日志
    }
  }

  /// 通知原生代码立即更新状态栏
  static Future<void> updateStatusBar() async {
    if (!Platform.isMacOS) return;

    print('MacOSPreferencesBridge: updateStatusBar 被调用');
    try {
      print('MacOSPreferencesBridge: 调用 MethodChannel updateStatusBar');
      await _channel.invokeMethod('updateStatusBar');
      print('MacOSPreferencesBridge: MethodChannel updateStatusBar 调用成功');
    } catch (e) {
      print('MacOSPreferencesBridge: MethodChannel updateStatusBar 调用失败: $e');
      // 忽略 MissingPluginException，因为 MethodChannel 可能还未注册
      if (e is MissingPluginException) {
        // MethodChannel 还未准备好，延迟重试
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _channel.invokeMethod('updateStatusBar');
          } catch (_) {
            // 忽略重试失败，静默处理
          }
        });
      }
      // 其他错误静默忽略，不打印日志
    }
  }
}

