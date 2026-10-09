import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:key_core/views/widgets/kc_drawer.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/test_app.dart';

void main() {
  setUpAll(installTestPlatformMocks);
  for (final dark in [false, true]) {
    testWidgets('统一抽屉：实色底（${dark ? '暗' : '亮'}色）、固定底栏、关闭', (tester) async {
      await setSurface(tester, const Size(1200, 800));
      await tester.pumpWidget(buildTestApp(
        viewModel: FakeKeyManagerViewModel(const []),
        brightness: dark ? Brightness.dark : Brightness.light,
        home: Scaffold(body: Builder(builder: (context) {
          return Center(
            child: ShadButton(
              onPressed: () => showKcDrawer(
                context: context,
                builder: (_) => KcDrawerSurface(
                  key: const ValueKey('d'),
                  header: const KcDrawerHeader(title: Text('T')),
                  body: ListView(children: List.generate(40, (i) => SizedBox(height: 40, child: Text('row $i')))),
                  footer: const KcDrawerFooter(trailing: [Text('OK')]),
                ),
              ),
              child: const Text('open'),
            ),
          );
        })),
      ));
      await settle(tester, rounds: 2);
      await tester.tap(find.text('open'));
      await settle(tester, rounds: 3);

      final ctx = tester.element(find.byKey(const ValueKey('d')));
      final box = tester.widget<Container>(
          find.descendant(of: find.byKey(const ValueKey('d')), matching: find.byType(Container)).first);
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, isNotNull, reason: '面板必须有实色填充，否则阴影透进来发灰');
      expect(deco.color!.a, 1.0);
      expect(deco.color, ShadTheme.of(ctx).colorScheme.background);
      expect(tester.getSize(find.byKey(const ValueKey('d'))).width, kcDrawerWidth);

      // 底栏固定在底部：滚动正文后位置不变
      final y0 = tester.getTopLeft(find.byKey(const ValueKey('kcDrawer.footer'))).dy;
      await tester.drag(find.text('row 3'), const Offset(0, -600));
      await settle(tester, rounds: 3);
      expect(tester.getTopLeft(find.byKey(const ValueKey('kcDrawer.footer'))).dy, y0);
      expect(y0 + 56, closeTo(800, 1));

      await tester.tap(find.byKey(const ValueKey('kcDrawer.close')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('d')), findsNothing);
    });
  }
}
