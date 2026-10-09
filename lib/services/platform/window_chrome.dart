import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../theme/kc_tokens.dart';

/// 窗口外观（form_v3.md §0 / §10）。
///
/// - macOS：原生把红绿灯移到 52px 顶栏中垂直居中（MainFlutterWindow.swift），
///   Flutter 侧在非全屏时把顶栏内容左内缩 [KcSize.macTrafficInset]；
///   全屏时红绿灯隐藏，内缩恢复为 20。
/// - Windows / Linux：使用系统原生标题栏，不需要内缩。
class WindowChrome {
  WindowChrome._();

  static const MethodChannel _window = MethodChannel('cn.dlrow.keycore/window');
  static const MethodChannel _events = MethodChannel('cn.dlrow.keycore/window_events');

  /// 当前是否全屏（只对 macOS 有意义）。
  static final ValueNotifier<bool> isFullScreen = ValueNotifier<bool>(false);

  /// 测试用：强制按 macOS 布局。
  @visibleForTesting
  static bool? debugIsMacOS;

  static bool get isMacOS => debugIsMacOS ?? (!kIsWeb && Platform.isMacOS);

  static bool _initialized = false;

  /// 在 main() 里调用一次。
  static Future<void> init() async {
    if (_initialized || !isMacOS || debugIsMacOS != null) return;
    _initialized = true;
    _events.setMethodCallHandler((call) async {
      if (call.method == 'fullscreenChanged') {
        isFullScreen.value = call.arguments == true;
      }
      return null;
    });
    try {
      final fs = await _window.invokeMethod<bool>('isFullScreen');
      isFullScreen.value = fs ?? false;
    } catch (_) {}
  }

  /// 是否需要给红绿灯让位。
  static bool get needsTrafficInset => isMacOS && !isFullScreen.value;

  /// 顶栏内容的左内边距。
  static double get leadingInset => needsTrafficInset ? KcSize.macTrafficInset : 20;

  /// 侧栏顶部拖动条高度：macOS 非全屏 52；全屏 12；Windows / Linux 10。
  static double get sidebarTopInset {
    if (!isMacOS) return 10;
    return isFullScreen.value ? 12 : KcSize.toolbar;
  }

  /// 在顶栏空白处按下时开始拖动窗口（macOS）。
  static Future<void> startDrag() async {
    if (!isMacOS || debugIsMacOS != null) return;
    try {
      await _window.invokeMethod('performDrag');
    } catch (_) {}
  }

  /// 双击顶栏：按系统偏好缩放 / 最小化（macOS）。
  static Future<void> doubleClick() async {
    if (!isMacOS || debugIsMacOS != null) return;
    try {
      await _window.invokeMethod('titleBarDoubleClick');
    } catch (_) {}
  }
}
