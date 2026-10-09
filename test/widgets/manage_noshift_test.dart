// 管理 / 排序模式零布局位移（form_v3.md §13）：页头、筛选行、主按钮槽、卡片在两种模式下几何完全一致；
// 不插入横幅；批量操作在底部悬浮栏。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/widgets/kc_manage_scaffold.dart';
import 'package:key_core/views/widgets/key_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

void main() {
  setUpAll(installTestPlatformMocks);

  Future<FakeKeyManagerViewModel> pump(WidgetTester tester) async {
    await setSurface(tester, const Size(1280, 820));
    final vm = FakeKeyManagerViewModel(buildFakeKeys().take(9).toList());
    await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen()));
    await settle(tester);
    return vm;
  }

  Map<String, Rect> geometry(WidgetTester tester) {
    final cards = tester.widgetList<KeyCard>(find.byType(KeyCard)).toList();
    return {
      'search': tester.getRect(find.byKey(const ValueKey('keyGrid.search'))),
      'primary': tester.getRect(find.byKey(const ValueKey('keyGrid.primarySlot'))),
      'manage': tester.getRect(find.byKey(const ValueKey('keyGrid.manageToggle'))),
      'refresh': tester.getRect(find.byKey(const ValueKey('keyGrid.refresh'))),
      'subtitle': tester.getRect(find.byKey(const ValueKey('keyGrid.subtitle'))),
      for (final c in cards.take(6)) 'card${c.aiKey.id}': tester.getRect(find.byWidget(c)),
    };
  }

  testWidgets('进入管理模式：页头 / 主按钮槽 / 卡片几何完全不变，无横幅', (tester) async {
    await pump(tester);
    final before = geometry(tester);
    expect(find.text('管理密钥'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('keyGrid.manageToggle')));
    await tester.pump();
    await settle(tester, rounds: 2);

    final after = geometry(tester);
    for (final k in before.keys) {
      expect(after[k], before[k], reason: '$k 发生了位移');
    }
    // 标题不变、不插横幅；主按钮原位变为「完成」；底部悬浮栏出现
    expect(find.text('管理密钥'), findsNothing);
    expect(find.byKey(const ValueKey('keyGrid.manageNotice')), findsNothing);
    expect(find.byKey(const ValueKey('keyGrid.done')), findsOneWidget);
    expect(find.byType(KcFloatingSelectionBar), findsOneWidget);
  });

  testWidgets('勾选卡片 → 悬浮栏显示数量；Esc / 完成退出并清空选择', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('keyGrid.manageToggle')));
    await settle(tester, rounds: 2);
    final first = tester.widgetList<KeyCard>(find.byType(KeyCard)).first.aiKey.id;
    await tester.tap(find.byKey(ValueKey('keyCard.select.$first')));
    await tester.pump();
    expect(find.byKey(const ValueKey('kcFloatingSelectionBar.count')), findsOneWidget);
    expect(find.text('1 个已选'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kcFloatingSelectionBar.selectAll')));
    await tester.pump();
    expect(find.text('9 个已选'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kcFloatingSelectionBar.done')));
    await settle(tester, rounds: 2);
    expect(find.byType(KcFloatingSelectionBar), findsNothing);
    expect(find.byKey(const ValueKey('keyGrid.add')), findsOneWidget);
  });

  testWidgets('批量置顶：按显示顺序保持相对顺序', (tester) async {
    final vm = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('keyGrid.manageToggle')));
    await settle(tester, rounds: 2);
    final ids = tester.widgetList<KeyCard>(find.byType(KeyCard)).map((c) => c.aiKey.id!).toList();
    await tester.tap(find.byKey(ValueKey('keyCard.select.${ids[3]}')));
    await tester.tap(find.byKey(ValueKey('keyCard.select.${ids[5]}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('keyGrid.batch.top')));
    await settle(tester, rounds: 2);
    expect(vm.keys.take(2).map((k) => k.id).toList(), [ids[3], ids[5]]);
  });
}
