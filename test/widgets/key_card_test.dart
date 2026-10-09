// UI-4 新卡片（ui_redesign_plan §5.2 / §9）：工具状态 chip 三态、点 chip 直接切换 + 撤销、
// 管理模式不渲染可点 chip、收藏 / 掩码 / 过期 badge / 首字回退、hover 操作、过滤分段、拖拽 feedback、Esc。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/widgets/key_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Finder cardFor(int id) => find.byWidgetPredicate((w) => w is KeyCard && w.aiKey.id == id);
Finder inCard(int id, Finder f) => find.descendant(of: cardFor(id), matching: f);
Finder byKey(String k) => find.byKey(ValueKey(k));

Future<FakeKeyManagerViewModel> pumpGrid(
  WidgetTester tester, {
  List<dynamic>? keys,
  void Function(FakeKeyManagerViewModel vm)? setup,
  Size size = const Size(1280, 820),
}) async {
  await setSurface(tester, size);
  final vm = FakeKeyManagerViewModel(keys?.cast() ?? buildFakeKeys());
  setup?.call(vm);
  await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen()));
  await settle(tester);
  return vm;
}

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  test('掩码密钥：只露前缀和后 4 位；加密存储时不露任何字符', () {
    expect(maskKeyForCard(fakeKey(1, 'a', PlatformType.deepSeek)), 'sk-••••0001');
    final enc = fakeKey(2, 'b', PlatformType.deepSeek).copyWith(keyNonce: 'nonce');
    expect(maskKeyForCard(enc), '••••••••');
    expect(maskKeyForCard(fakeKey(3, 'c', PlatformType.deepSeek).copyWith(keyValue: 'abc')), '••••••••');
  });

  testWidgets('工具 chip 三态：生效中 / 已启用 / 未用到工具（＋）', (tester) async {
    await pumpGrid(tester, setup: (vm) => vm.current[AiToolType.claudecode] = 1);
    // 1: Claude Code 生效中；Codex / OpenClaw 已启用
    expect(inCard(1, byKey('toolChip.active.claudecode')), findsOneWidget);
    expect(inCard(1, byKey('toolChip.enabled.codex')), findsOneWidget);
    expect(inCard(1, byKey('toolChip.enabled.openclaw')), findsOneWidget);
    expect(inCard(1, byKey('toolChip.enabled.gemini')), findsNothing);
    // 3: 同样启用了 Claude Code，但不是当前 → 描边 chip
    expect(inCard(3, byKey('toolChip.enabled.claudecode')), findsOneWidget);
    expect(inCard(3, byKey('toolChip.active.claudecode')), findsNothing);
    // 7: 一个工具都没有 → 「＋ 未用到工具」
    expect(inCard(7, byKey('toolChip.plus')), findsOneWidget);
    expect(inCard(7, find.text('未用到工具')), findsOneWidget);
    // 有工具的卡片不 hover 时不显示 ＋
    expect(inCard(1, byKey('toolChip.plus')), findsNothing);
  });

  testWidgets('点击「已启用」chip 直接切换；toast 带撤销，撤销恢复为官方配置', (tester) async {
    final vm = await pumpGrid(tester);
    await tester.tap(inCard(1, byKey('toolChip.enabled.codex')));
    await settle(tester, rounds: 2);
    expect(vm.switchCalls['codex'], [1]);
    expect(vm.current[AiToolType.codex], 1);
    expect(find.textContaining('Codex 已切换到 DeepSeek 主力'), findsOneWidget);
    // 切换后立即变成「生效中」
    expect(inCard(1, byKey('toolChip.active.codex')), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('撤销'));
    await settle(tester, rounds: 2);
    expect(vm.officialCalls, ['codex']);
    expect(vm.current[AiToolType.codex], isNull);
    expect(find.textContaining('已恢复：Codex 使用 官方'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('撤销恢复到切换前的那把密钥', (tester) async {
    final vm = await pumpGrid(tester, setup: (vm) => vm.current[AiToolType.codex] = 6);
    await tester.tap(inCard(1, byKey('toolChip.enabled.codex')));
    await settle(tester, rounds: 2);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('撤销'));
    await settle(tester, rounds: 2);
    expect(vm.switchCalls['codex'], [1, 6]);
    expect(vm.current[AiToolType.codex], 6);
    expect(find.textContaining('已恢复：Codex 使用 OpenRouter 测试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('切换失败：错误 toast 带「重试」，不出现撤销', (tester) async {
    final vm = await pumpGrid(tester, setup: (vm) => vm.failSwitches = true);
    await tester.tap(inCard(3, byKey('toolChip.enabled.claudecode')));
    await settle(tester, rounds: 2);
    expect(vm.switchCalls['claudeCode'], [3]);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('撤销'), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('OpenClaw chip 不触发切换（多把可同时启用，在 OpenClaw 页管理）', (tester) async {
    final vm = await pumpGrid(tester);
    await tester.tap(inCard(1, byKey('toolChip.enabled.openclaw')));
    await settle(tester, rounds: 2);
    expect(vm.switchCalls, isEmpty);
    expect(vm.decryptCalls, isEmpty, reason: '点 chip 不应冒泡成「打开详情」');
  });

  testWidgets('管理模式：不渲染可点 chip，底部显示「n 个工具」+ 置顶/编辑/删除', (tester) async {
    await pumpGrid(tester, setup: (vm) => vm.current[AiToolType.claudecode] = 1);
    await tester.tap(byKey('keyGrid.manageToggle'));
    await settle(tester, rounds: 2);
    expect(find.byKey(const ValueKey('toolChip.active.claudecode')), findsNothing);
    expect(find.byKey(const ValueKey('toolChip.enabled.codex')), findsNothing);
    expect(inCard(1, find.text('3 个工具')), findsOneWidget);
    expect(inCard(7, find.text('未用到工具')), findsOneWidget);
    expect(find.text('管理密钥'), findsOneWidget);
    expect(byKey('keyGrid.done'), findsOneWidget);
    expect(byKey('keyGrid.manageNotice'), findsOneWidget);

    // Esc 退出管理模式
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, rounds: 2);
    expect(byKey('keyGrid.manageNotice'), findsNothing);
    expect(find.text('管理密钥'), findsNothing);
  });

  testWidgets('收藏 ★、掩码密钥、首字回退只给自定义平台', (tester) async {
    await pumpGrid(tester);
    expect(inCard(1, byKey('keyCard.favorite')), findsOneWidget);
    expect(inCard(2, byKey('keyCard.favorite')), findsOneWidget);
    expect(inCard(3, byKey('keyCard.favorite')), findsNothing);
    expect(inCard(1, find.textContaining('sk-••••0001', findRichText: true)), findsOneWidget);
    expect(find.byKey(const ValueKey('platformLogo.initial')), findsOneWidget);
    expect(inCard(12, byKey('platformLogo.initial')), findsOneWidget);
  });

  testWidgets('过期 / 即将过期 badge', (tester) async {
    final keys = [
      fakeKey(1, 'A', PlatformType.deepSeek, expiry: DateTime.now().add(const Duration(days: 5, hours: 2))),
      fakeKey(2, 'B', PlatformType.kimi, expiry: DateTime.now().subtract(const Duration(days: 1))),
      fakeKey(3, 'C', PlatformType.zhipu),
    ];
    await pumpGrid(tester, keys: keys);
    expect(inCard(1, find.text('5 天后过期')), findsOneWidget);
    expect(inCard(2, find.text('已过期')), findsOneWidget);
    expect(inCard(3, find.textContaining('过期')), findsNothing);
  });

  testWidgets('hover 才出现右上角操作（复制 / 编辑 / ⋯）', (tester) async {
    await pumpGrid(tester);
    double opacityOfActions() => tester
        .widget<AnimatedOpacity>(find
            .ancestor(of: inCard(5, byKey('keyCard.copy')), matching: find.byType(AnimatedOpacity))
            .first)
        .opacity;
    expect(opacityOfActions(), 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(cardFor(5)));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(opacityOfActions(), 1);
    // hover 时有工具的卡片也出现 ＋
    expect(inCard(5, byKey('toolChip.plus')), findsOneWidget);
  });

  testWidgets('过滤分段：正在使用 / 未用到工具 / 需处理', (tester) async {
    await pumpGrid(tester, setup: (vm) {
      vm.current[AiToolType.claudecode] = 1;
      vm.current[AiToolType.gemini] = 4;
    });
    expect(find.text('2 个正被工具使用', findRichText: true), findsNothing); // 副标题是一整句
    expect(find.textContaining('12 个密钥 · 2 个正被工具使用'), findsOneWidget);

    await tester.tap(byKey('segment._KeySegment.inUse'));
    await settle(tester, rounds: 2);
    expect(tester.widgetList<KeyCard>(find.byType(KeyCard)).map((c) => c.aiKey.id).toSet(), {1, 4});

    await tester.tap(byKey('segment._KeySegment.unused'));
    await settle(tester, rounds: 2);
    expect(tester.widgetList<KeyCard>(find.byType(KeyCard)).map((c) => c.aiKey.id).toSet(), {7, 8, 11, 12});

    await tester.tap(byKey('segment._KeySegment.attention'));
    await settle(tester, rounds: 2);
    expect(find.byType(KeyCard), findsNothing);
    expect(find.text('没有符合条件的密钥'), findsOneWidget);
  });

  testWidgets('分段过滤下拖拽：只重排可见子集', (tester) async {
    final vm = await pumpGrid(tester);
    await tester.tap(byKey('segment._KeySegment.unused'));
    await settle(tester, rounds: 2);
    await tester.tap(byKey('keyGrid.manageToggle'));
    await settle(tester, rounds: 2);
    final from = tester.getCenter(cardFor(12));
    final r = tester.getRect(cardFor(7));
    final g = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(from, Offset(r.left + r.width / 5, r.center.dy), i / 12)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.byType(KeyCardDragFeedback), findsOneWidget);
    await g.up();
    await settle(tester, rounds: 3);
    expect(vm.reorderCalls, isNotEmpty);
    final call = vm.reorderCalls.last;
    expect(call.toSet(), {7, 8, 11, 12}, reason: '只传可见子集给 reorderKeys');
    expect(call.first, 12);
  });

  testWidgets('空状态：标题 + 添加 / 导入备份按钮', (tester) async {
    await pumpGrid(tester, keys: const []);
    expect(find.text('钥匙包还是空的'), findsOneWidget);
    expect(byKey('keyGrid.emptyAdd'), findsOneWidget);
    expect(byKey('keyGrid.emptyImport'), findsOneWidget);
  });
}
