// UI-6 工具页 lens（ui_redesign_plan §5.5 / mockup 05、06）：页头「当前：X · 写入 路径」、lens 卡片底栏
// （模型 + 也用于）、官方卡片新样式、配置缺失时的常驻提示条、「未启用到 X 的密钥」区一键启用。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/views/screens/codex_config_screen.dart';
import 'package:key_core/views/screens/key_form_page.dart';
import 'package:key_core/views/widgets/key_card.dart';
import 'package:key_core/views/widgets/official_key_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Finder byKey(String k) => find.byKey(ValueKey(k));
Finder cardFor(int id) => find.byWidgetPredicate((w) => w is KeyCard && w.aiKey.id == id);
Finder inCard(int id, Finder f) => find.descendant(of: cardFor(id), matching: f);

Future<FakeKeyManagerViewModel> pumpCodex(WidgetTester tester,
    {void Function(FakeKeyManagerViewModel vm)? setup, List<dynamic>? keys}) async {
  await setSurface(tester, const Size(1280, 820));
  final vm = FakeKeyManagerViewModel(keys?.cast() ?? buildFakeKeys());
  setup?.call(vm);
  final key = GlobalKey<CodexConfigScreenState>();
  await tester.pumpWidget(buildTestApp(viewModel: vm, home: CodexConfigScreen(key: key)));
  await settle(tester);
  key.currentState!.refresh(force: true);
  await settle(tester, rounds: 6);
  return vm;
}

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  testWidgets('页头：工具名 +「当前：X · 写入 路径」', (tester) async {
    await pumpCodex(tester, setup: (vm) => vm.current[AiToolType.codex] = 1);
    expect(find.text('Codex'), findsWidgets);
    expect(find.text('当前：DeepSeek 主力  ·  写入 ~/.codex/auth.json'), findsOneWidget);
    expect(byKey('toolPage.notice'), findsNothing);
  });

  testWidgets('lens 卡片：底栏是该工具的模型 + 也用于其他工具；生效卡有「生效中」', (tester) async {
    await pumpCodex(tester, setup: (vm) => vm.current[AiToolType.codex] = 1);
    // 1 号：codex + claudecode + openclaw，模型 deepseek-chat
    expect(inCard(1, byKey('lens.model')), findsOneWidget);
    expect(inCard(1, find.text('deepseek-chat')), findsOneWidget);
    expect(inCard(1, byKey('lens.alsoUsed')), findsOneWidget);
    expect(inCard(1, find.text('生效中')), findsOneWidget);
    // lens 卡片不出现钥匙包的工具 chip
    expect(inCard(1, byKey('toolChip.enabled.claudecode')), findsNothing);
    // 6 号只用于 Codex → 没有「也用于」
    expect(inCard(6, byKey('lens.alsoUsed')), findsNothing);
    // 官方卡片：新样式，不是当前 → 没有生效 badge
    expect(find.byType(OfficialKeyCard), findsOneWidget);
    expect(byKey('officialCard.active'), findsNothing);
  });

  testWidgets('官方配置生效时官方卡片显示「生效中」', (tester) async {
    await pumpCodex(tester);
    expect(byKey('officialCard.active'), findsOneWidget);
    expect(find.text('当前：官方配置  ·  写入 ~/.codex/auth.json'), findsOneWidget);
  });

  testWidgets('配置文件缺失：页内常驻提示条（不再弹橙色 SnackBar）', (tester) async {
    await pumpCodex(tester, setup: (vm) => vm.toolConfigExists = false);
    expect(byKey('toolPage.notice'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('「未启用到 Codex 的密钥」：展开后一键启用；缺配置时转编辑页', (tester) async {
    final vm = await pumpCodex(tester);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(byKey('unenabled.toggle'), 200, scrollable: scrollable);
    expect(find.text('未启用到 Codex 的密钥'), findsOneWidget);
    await tester.tap(byKey('unenabled.toggle'));
    await settle(tester);
    // 4 号（Gemini 个人）没有 Codex 请求地址 → 转编辑页，不保存
    await tester.scrollUntilVisible(byKey('unenabled.enable.4'), 200, scrollable: scrollable);
    await tester.tap(byKey('unenabled.enable.4'));
    await settle(tester, rounds: 4);
    await tester.pump(const Duration(milliseconds: 400));
    expect(vm.updateCalls, isEmpty);
    expect(find.byType(KeyFormPage), findsOneWidget);
  });

  testWidgets('「未启用」区：配置齐全的密钥一键启用，随即进入上方列表', (tester) async {
    final keys = buildFakeKeys();
    final i7 = keys.indexWhere((k) => k.id == 7);
    keys[i7] = keys[i7].copyWith(codexBaseUrl: 'https://api.example.com/v1', codexModel: 'qwen-coder');
    final vm = await pumpCodex(tester, keys: keys);
    expect(cardFor(7), findsNothing);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(byKey('unenabled.toggle'), 200, scrollable: scrollable);
    await tester.tap(byKey('unenabled.toggle'));
    await settle(tester);
    await tester.scrollUntilVisible(byKey('unenabled.enable.7'), 200, scrollable: scrollable);
    await tester.tap(byKey('unenabled.enable.7'));
    await settle(tester, rounds: 6);
    expect(vm.updateCalls.single.enableCodex, isTrue);
    expect(find.textContaining('已启用到 Codex'), findsOneWidget);
    await tester.scrollUntilVisible(cardFor(7), -200, scrollable: scrollable);
    expect(cardFor(7), findsOneWidget);
  });

  testWidgets('工具页 State 被重建后无需外部 refresh 也会自行首次加载（不再一直显示「暂无密钥」）', (tester) async {
    await setSurface(tester, const Size(1280, 820));
    final vm = FakeKeyManagerViewModel(buildFakeKeys());
    vm.current[AiToolType.codex] = 1;
    await tester.pumpWidget(buildTestApp(viewModel: vm, home: const CodexConfigScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(cardFor(1), findsNothing); // 翻页动画期间（路过）不加载
    await tester.pump(const Duration(milliseconds: 200));
    await settle(tester, rounds: 6);
    expect(cardFor(1), findsOneWidget);
  });
}
