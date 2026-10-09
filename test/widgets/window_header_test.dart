// 红绿灯对齐（form_v3.md §10）：统一顶栏高 52；macOS 非全屏内缩 96，全屏 / Windows / Linux 为 20。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/platform/window_chrome.dart';
import 'package:key_core/theme/kc_tokens.dart';
import 'package:key_core/views/widgets/kc_window_header.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _host(Widget child) => ShadTheme(
      data: KcTheme.shad(Brightness.light),
      child: MaterialApp(home: Scaffold(appBar: child as PreferredSizeWidget, body: const SizedBox())),
    );

void main() {
  tearDown(() {
    WindowChrome.debugIsMacOS = null;
    WindowChrome.isFullScreen.value = false;
  });

  Future<double> titleLeft(WidgetTester tester) async {
    await tester.pumpWidget(_host(KcWindowHeader(title: '添加密钥', onClose: () {})));
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('kcWindowHeader'))).height, KcSize.toolbar);
    return tester.getTopLeft(find.text('添加密钥')).dx;
  }

  testWidgets('macOS 非全屏：标题从 x = 96 开始，避开红绿灯', (tester) async {
    WindowChrome.debugIsMacOS = true;
    expect(await titleLeft(tester), KcSize.macTrafficInset);
    expect(WindowChrome.sidebarTopInset, 52);
  });

  testWidgets('macOS 全屏：红绿灯隐藏，内缩恢复为 20；侧栏拖动条 12', (tester) async {
    WindowChrome.debugIsMacOS = true;
    WindowChrome.isFullScreen.value = true;
    expect(await titleLeft(tester), 20);
    expect(WindowChrome.sidebarTopInset, 12);
  });

  testWidgets('Windows / Linux：系统原生标题栏，不内缩', (tester) async {
    WindowChrome.debugIsMacOS = false;
    expect(await titleLeft(tester), 20);
    expect(WindowChrome.sidebarTopInset, 10);
  });

  testWidgets('全屏切换时顶栏实时更新', (tester) async {
    WindowChrome.debugIsMacOS = true;
    expect(await titleLeft(tester), 96);
    WindowChrome.isFullScreen.value = true;
    await tester.pump();
    expect(tester.getTopLeft(find.text('添加密钥')).dx, 20);
  });

  test('页头统一为 52，与红绿灯中心线 y = 26 对齐', () {
    expect(KcSize.pageHeader, 52);
    expect(KcSize.toolbar / 2, 26);
  });
}
