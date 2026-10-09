// 钥匙包网格「管理模式 / 拖拽排序 / 置顶 / 删除 / 边缘滚动 / 响应式列数」回归测试。
//
// UI-0 基线：在重做 KeyCard（UI-4）之前锁定现有行为，之后每个 UI PR 都必须原样通过。
// 只通过稳定的 ValueKey（keyGrid.* / keyCard.*）和组件类型定位，不依赖卡片的具体视觉结构。
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reorderables/reorderables.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/widgets/key_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Finder cardFor(int id) => find.byWidgetPredicate((w) => w is KeyCard && w.aiKey.id == id);

List<int?> visibleOrder(WidgetTester tester) {
  final cards = tester.widgetList<KeyCard>(find.byType(KeyCard)).toList();
  final withPos = cards
      .map((c) => MapEntry(c.aiKey.id, tester.getTopLeft(find.byWidget(c))))
      .toList()
    ..sort((a, b) {
      final dy = a.value.dy.compareTo(b.value.dy);
      return dy != 0 ? dy : a.value.dx.compareTo(b.value.dx);
    });
  return withPos.map((e) => e.key).toList();
}

Future<FakeKeyManagerViewModel> pumpGrid(WidgetTester tester,
    {Size size = const Size(1280, 820), int count = 12}) async {
  await setSurface(tester, size);
  final vm = FakeKeyManagerViewModel(buildFakeKeys().take(count).toList());
  await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen()));
  await settle(tester);
  return vm;
}

Future<void> enterManageMode(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('keyGrid.manageToggle')));
  await tester.pump();
  await settle(tester, rounds: 2);
}

void main() {
  setUpAll(installTestPlatformMocks);

  group('管理模式', () {
    testWidgets('普通模式用 GridView；切换后用 ReorderableWrap，并显示手柄与置顶/编辑/删除', (tester) async {
      await pumpGrid(tester);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ReorderableWrap), findsNothing);
      expect(find.byKey(const ValueKey('keyCard.dragHandle')), findsNothing);

      await enterManageMode(tester);
      expect(find.byType(ReorderableWrap), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      final n = tester.widgetList(find.byType(KeyCard)).length;
      expect(n, greaterThan(0));
      expect(find.byKey(const ValueKey('keyCard.dragHandle')), findsNWidgets(n));
      expect(find.byKey(const ValueKey('keyCard.moveToTop')), findsNWidgets(n));
      expect(find.byKey(const ValueKey('keyCard.edit')), findsNWidgets(n));
      expect(find.byKey(const ValueKey('keyCard.delete')), findsNWidgets(n));

      // 再点一次退出管理模式
      await enterManageMode(tester);
      expect(find.byType(ReorderableWrap), findsNothing);
      expect(find.byType(GridView), findsOneWidget);
    });

    testWidgets('管理模式下点击卡片主体不会打开详情，也不会触发切换', (tester) async {
      final vm = await pumpGrid(tester);
      await enterManageMode(tester);
      await tester.tap(find.text('DeepSeek 主力'));
      await settle(tester, rounds: 2);
      expect(vm.decryptCalls, isEmpty);
      expect(vm.switchCalls, isEmpty);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('普通模式下点击卡片主体打开详情（对照组）', (tester) async {
      final vm = await pumpGrid(tester);
      await tester.tap(find.text('DeepSeek 主力'));
      await settle(tester, rounds: 2);
      expect(vm.decryptCalls, [1]);
    });
  });

  group('拖拽排序', () {
    testWidgets('把第 7 张拖到第 2 张的位置：reorderKeys 收到正确顺序，界面立即更新', (tester) async {
      final vm = await pumpGrid(tester);
      await enterManageMode(tester);
      expect(visibleOrder(tester).take(8), [1, 2, 3, 4, 5, 6, 7, 8]);

      final from = tester.getCenter(cardFor(7));
      // 落在目标卡片左侧 1/5 处 = 插到它前面（ReorderableWrap 以落点所在半边决定前/后）
      final r2 = tester.getRect(cardFor(2));
      final to = Offset(r2.left + r2.width / 5, r2.center.dy);
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 20; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester, rounds: 2);

      expect(vm.reorderCalls, hasLength(1));
      final order = vm.reorderCalls.single;
      // 被拖的卡片落到第 2 / 3 位（ReorderableWrap 会在拖动时让出空位，落点在空位前或后），
      // 其余卡片相对顺序不变，且不丢失、不重复。
      expect(order.indexOf(7), inInclusiveRange(1, 2));
      expect(order.where((id) => id != 7).toList(), [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12]);
      expect(order.toSet().length, 12);
      // 界面立即按新顺序渲染
      expect(visibleOrder(tester), order);
    });

    testWidgets('拖起后放回原位：不调用 reorderKeys，顺序不变', (tester) async {
      final vm = await pumpGrid(tester);
      await enterManageMode(tester);
      final from = tester.getCenter(cardFor(3));
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(30, 10));
      await tester.pump(const Duration(milliseconds: 100));
      await g.moveTo(from);
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(vm.reorderCalls, isEmpty);
      expect(visibleOrder(tester).take(4), [1, 2, 3, 4]);
    });

    testWidgets('筛选状态下拖动：只重排筛选子集，其余密钥保持原序排在后面', (tester) async {
      final vm = await pumpGrid(tester);
      vm.setSearchQuery('a'); // 名称含 a：Anthropic 官方、MiniMax M2、Azure 公司
      await tester.pump();
      await enterManageMode(tester);
      final subset = vm.keys.map((k) => k.id).toList();
      expect(subset, [2, 10, 11]);

      final from = tester.getCenter(cardFor(11));
      // 落在目标卡片左侧 1/5 处 = 插到它前面（ReorderableWrap 以落点所在半边决定前/后）
      final r2 = tester.getRect(cardFor(2));
      final to = Offset(r2.left + r2.width / 5, r2.center.dy);
      final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 1; i <= 20; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 20)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));

      expect(vm.reorderCalls, hasLength(1));
      final subsetOrder = vm.reorderCalls.single;
      // 只把筛选子集交给 reorderKeys
      expect(subsetOrder.toSet(), {2, 10, 11});
      expect(subsetOrder.indexOf(11), lessThan(2), reason: '第 3 张被拖到前面');
      // 其余 9 把密钥保持原序排在子集之后
      expect(vm.allKeys.map((k) => k.id).skip(3).toList(), [1, 3, 4, 5, 6, 7, 8, 9, 12]);
    });

    testWidgets('拖到列表下边缘会自动滚动，松手后停止', (tester) async {
      await pumpGrid(tester, size: const Size(1280, 520));
      await enterManageMode(tester);
      // 外层 SingleChildScrollView（_keyListScrollController）是 ReorderableWrap 最近的祖先 Scrollable
      final scrollable = find.ancestor(of: find.byType(ReorderableWrap), matching: find.byType(Scrollable)).first;
      final pos = tester.state<ScrollableState>(scrollable).position;
      expect(pos.pixels, 0);
      expect(pos.maxScrollExtent, greaterThan(0));

      final listRect = tester.getRect(scrollable);
      final g = await tester.startGesture(tester.getCenter(cardFor(1)), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(Offset(listRect.center.dx, listRect.bottom - 10));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scrolled = pos.pixels;
      expect(scrolled, greaterThan(0));

      await g.up();
      await tester.pump(const Duration(milliseconds: 500));
      final afterUp = pos.pixels;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(pos.pixels, afterUp, reason: '松手后边缘滚动应停止');
    });
  });

  group('置顶 / 删除', () {
    testWidgets('置顶：调用 moveKeyToTop，目标移到第 1 位，并提示「已置顶」', (tester) async {
      final vm = await pumpGrid(tester);
      await enterManageMode(tester);
      final topBtn = find.descendant(of: cardFor(5), matching: find.byKey(const ValueKey('keyCard.moveToTop')));
      await tester.tap(topBtn);
      await tester.pump();
      await settle(tester, rounds: 2);
      expect(vm.moveToTopCalls, [5]);
      expect(visibleOrder(tester).first, 5);
      expect(find.text('已置顶'), findsOneWidget);
    });

    testWidgets('删除走确认对话框：取消时不删除，确认后删除', (tester) async {
      final vm = await pumpGrid(tester);
      await enterManageMode(tester);
      final delBtn = find.descendant(of: cardFor(4), matching: find.byKey(const ValueKey('keyCard.delete')));
      await tester.tap(delBtn);
      await settle(tester, rounds: 3);
      expect(find.text('取消'), findsWidgets);
      await tester.tap(find.text('取消').last);
      await settle(tester, rounds: 3);
      expect(vm.deleteCalls, isEmpty);
      expect(cardFor(4), findsOneWidget);

      await tester.tap(delBtn);
      await settle(tester, rounds: 3);
      await tester.tap(find.text('删除').last);
      await settle(tester, rounds: 3);
      expect(vm.deleteCalls, [4]);
      expect(cardFor(4), findsNothing);
    });
  });

  group('响应式列数（卡片高 140）', () {
    for (final entry in {700.0: 2, 1000.0: 3, 1280.0: 4, 1600.0: 5}.entries) {
      testWidgets('宽 ${entry.key.toInt()} → ${entry.value} 列', (tester) async {
        await pumpGrid(tester, size: Size(entry.key, 900));
        final tops = tester
            .widgetList<KeyCard>(find.byType(KeyCard))
            .map((c) => tester.getRect(find.byWidget(c)))
            .toList();
        final firstRowY = tops.map((r) => r.top).reduce((a, b) => a < b ? a : b);
        final firstRow = tops.where((r) => (r.top - firstRowY).abs() < 1).length;
        expect(firstRow, entry.value);
        for (final r in tops) {
          expect(r.height, closeTo(140, 0.5));
        }
      });
    }
  });
}
