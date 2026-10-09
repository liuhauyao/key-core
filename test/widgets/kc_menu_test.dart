import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/views/widgets/kc_menu.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/test_app.dart';

void main() {
  setUpAll(installTestPlatformMocks);

  Future<List<String>> pumpMenu(WidgetTester tester, {required bool dark}) async {
    final picked = <String>[];
    await setSurface(tester, const Size(900, 600));
    await tester.pumpWidget(buildTestApp(
      viewModel: FakeKeyManagerViewModel(const []),
      brightness: dark ? Brightness.dark : Brightness.light,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: KcMenuButton<String>(
            key: const ValueKey('btn'),
            onSelected: picked.add,
            entries: () => const [
              KcMenuHeader('G'),
              KcMenuItem(value: 'a', label: 'Alpha', icon: Icons.add),
              KcMenuItem(value: 'b', label: 'Beta', enabled: false),
              KcMenuItem(value: 'c', label: 'Gamma'),
              KcMenuDivider(),
              KcMenuItem(value: 'd', label: 'Delete', danger: true),
            ],
            child: const SizedBox(width: 80, height: 32, child: Text('open')),
          ),
        ),
      ),
    ));
    await settle(tester, rounds: 2);
    return picked;
  }

  for (final dark in [false, true]) {
    testWidgets('KcMenu 实色面板 + 锚定在触发器下方（${dark ? '暗' : '亮'}）', (tester) async {
      await pumpMenu(tester, dark: dark);
      await tester.tap(find.text('open'));
      await settle(tester, rounds: 3);
      final panel = find.byKey(const ValueKey('kcMenu.panel'));
      expect(panel, findsOneWidget);
      final deco = tester.widget<Container>(panel).decoration! as BoxDecoration;
      expect(deco.color!.a, 1.0, reason: '菜单底色必须是实色');
      if (dark) expect(deco.color, const Color(0xFF1C1C1E));
      expect(deco.borderRadius, BorderRadius.circular(10));
      final trig = tester.getRect(find.byKey(const ValueKey('btn')));
      expect(tester.getRect(panel).top, greaterThanOrEqualTo(trig.bottom));
    });
  }

  testWidgets('KcMenu 键盘：↓ 跳过禁用项，Enter 选中，Esc 关闭', (tester) async {
    final picked = await pumpMenu(tester, dark: false);
    await tester.tap(find.text('open'));
    await settle(tester, rounds: 3);
    // 初始无高亮；↓ → Alpha，再 ↓ 跳过禁用的 Beta 到 Gamma
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 500));
    expect(picked, ['c']);
    expect(find.byKey(const ValueKey('kcMenu.panel')), findsNothing);

    await tester.tap(find.text('open'));
    await settle(tester, rounds: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('kcMenu.panel')), findsNothing);
    expect(picked, ['c']);
  });
}
