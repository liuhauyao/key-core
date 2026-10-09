// UI-5 详情抽屉（ui_redesign_plan §5.3 / mockup 03）：右侧抽屉、工具表（开关 / 设为当前 / 生效中）、
// 缺模型时转编辑页、删除、复制为环境变量、掩码显示切换。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/views/screens/key_form_page.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/widgets/key_card.dart';
import 'package:key_core/views/widgets/key_details_dialog.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Finder byKey(String k) => find.byKey(ValueKey(k));
Finder cardFor(int id) => find.byWidgetPredicate((w) => w is KeyCard && w.aiKey.id == id);
Finder inSheet(Finder f) => find.descendant(of: byKey('keyDetails.sheet'), matching: f);

Future<FakeKeyManagerViewModel> openDetails(WidgetTester tester, int id,
    {void Function(FakeKeyManagerViewModel vm)? setup}) async {
  await setSurface(tester, const Size(1280, 820));
  final vm = FakeKeyManagerViewModel(buildFakeKeys());
  setup?.call(vm);
  await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen()));
  await settle(tester);
  await tester.tap(find.descendant(of: cardFor(id), matching: find.text(vm.allKeys.firstWhere((k) => k.id == id).name)));
  await settle(tester, rounds: 3);
  await tester.pump(const Duration(milliseconds: 300));
  return vm;
}

void main() {
  final clipboard = <String>[];

  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  setUp(() {
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
      return null;
    });
  });

  test('哪些工具开启前需要先补全配置', () {
    final bare = fakeKey(7, 'b', PlatformType.siliconFlow);
    expect(toolNeedsSetup(bare, AiToolType.gemini), isFalse);
    expect(toolNeedsSetup(bare, AiToolType.claudecode), isTrue);
    expect(toolNeedsSetup(bare, AiToolType.codex), isTrue);
    final ready = fakeKey(1, 'a', PlatformType.deepSeek, claudeCode: true, codex: true, model: 'm');
    expect(toolNeedsSetup(ready, AiToolType.claudecode), isFalse);
    expect(toolNeedsSetup(ready, AiToolType.codex), isFalse);
  });

  test('复制为环境变量：按启用的工具给变量，单引号转义', () {
    final k = fakeKey(1, 'a', PlatformType.deepSeek, claudeCode: true, codex: true, model: 'm')
        .copyWith(keyValue: "sk-it's", claudeCodeBaseUrl: 'https://x/anthropic', codexBaseUrl: 'https://x/v1');
    final s = buildEnvExport(k);
    expect(s, contains("export ANTHROPIC_BASE_URL='https://x/anthropic'"));
    expect(s, contains("export ANTHROPIC_AUTH_TOKEN='sk-it'\\''s'"));
    expect(s, contains("export OPENAI_BASE_URL='https://x/v1'"));
    expect(s, contains('export OPENAI_API_KEY='));
    expect(s, isNot(contains('GEMINI')));
    final plain = buildEnvExport(fakeKey(7, 'b', PlatformType.siliconFlow));
    expect(plain, contains('export API_KEY='));
  });

  testWidgets('点卡片打开右侧抽屉：工具表三态（生效中 / 设为当前 / 未启用），OpenClaw 无「设为当前」', (tester) async {
    await openDetails(tester, 1, setup: (vm) => vm.current[AiToolType.claudecode] = 1);
    expect(byKey('keyDetails.sheet'), findsOneWidget);
    // 贴右侧
    final r = tester.getRect(byKey('keyDetails.sheet'));
    expect(r.right, 1280);
    expect(r.width, 560);

    expect(inSheet(find.text('用在哪些工具')), findsOneWidget);
    expect(inSheet(find.text('3 个已启用 · 1 个生效中')), findsOneWidget);
    expect(inSheet(find.text('● 生效中')), findsOneWidget);
    expect(byKey('keyDetails.setCurrent.codex'), findsOneWidget);
    expect(byKey('keyDetails.setCurrent.claudecode'), findsNothing);
    expect(byKey('keyDetails.setCurrent.openclaw'), findsNothing);
    expect(inSheet(find.text('未启用')), findsNWidgets(2)); // Desktop + Gemini
    // 配置路径提示
    expect(inSheet(find.text('~/.codex/auth.json')), findsOneWidget);
  });

  testWidgets('「设为当前」直接切换并即时变成生效中', (tester) async {
    final vm = await openDetails(tester, 1);
    await tester.tap(byKey('keyDetails.setCurrent.codex'));
    await settle(tester, rounds: 3);
    expect(vm.switchCalls['codex'], [1]);
    expect(byKey('keyDetails.setCurrent.codex'), findsNothing);
    expect(inSheet(find.text('● 生效中')), findsOneWidget);
    expect(find.textContaining('Codex 已切换到 DeepSeek 主力'), findsOneWidget);
  });

  testWidgets('工具开关：关闭即保存 enable 标志；开启缺配置的工具转去编辑页', (tester) async {
    final vm = await openDetails(tester, 1);
    await tester.tap(byKey('keyDetails.toggle.codex'));
    await settle(tester, rounds: 3);
    expect(vm.updateCalls.single.enableCodex, isFalse);
    expect(vm.allKeys.firstWhere((k) => k.id == 1).enableCodex, isFalse);
    expect(byKey('keyDetails.setCurrent.codex'), findsNothing);
    expect(inSheet(find.text('2 个已启用 · 0 个生效中')), findsOneWidget);
    expect(find.textContaining('已从 Codex 的候选列表移除'), findsOneWidget);

    // Claude Desktop 还没有请求地址 → 不保存，关闭抽屉并打开编辑页
    await tester.tap(byKey('keyDetails.toggle.claude_desktop'));
    await settle(tester, rounds: 4);
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester, rounds: 2);
    expect(vm.updateCalls.length, 1);
    expect(byKey('keyDetails.sheet'), findsNothing);
    expect(find.byType(KeyFormPage), findsOneWidget);
  });

  testWidgets('API 密钥默认掩码，可切换显示；复制为环境变量写剪贴板', (tester) async {
    await openDetails(tester, 1);
    final text = tester.widget<Text>(byKey('keyDetails.keyValue')).data!;
    expect(text, contains('•'));
    await tester.tap(byKey('keyDetails.reveal'));
    await tester.pump();
    expect(tester.widget<Text>(byKey('keyDetails.keyValue')).data, isNot(contains('•')));

    await tester.tap(byKey('keyDetails.copyEnv'));
    await settle(tester, rounds: 2);
    expect(clipboard.single, contains('export ANTHROPIC_AUTH_TOKEN='));
    expect(clipboard.single, contains('export OPENAI_API_KEY='));
  });

  testWidgets('删除密钥：关闭抽屉 → 二次确认 → 删除', (tester) async {
    final vm = await openDetails(tester, 7);
    await tester.tap(byKey('keyDetails.delete'));
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 300));
    expect(byKey('keyDetails.sheet'), findsNothing);
    expect(find.text('确认删除'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await settle(tester, rounds: 3);
    expect(vm.deleteCalls, [7]);
  });

  testWidgets('卡片「＋」菜单：无需配置的工具（Gemini）直接启用；缺配置（Codex）转编辑页', (tester) async {
    await setSurface(tester, const Size(1280, 820));
    final keys = buildFakeKeys();
    final vm = FakeKeyManagerViewModel(keys);
    await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen()));
    await settle(tester);
    await tester.tap(find.descendant(of: cardFor(7), matching: byKey('toolChip.plus')));
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.textContaining('启用到 Gemini'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 3);
    expect(vm.updateCalls.single.enableGemini, isTrue);
    expect(find.descendant(of: cardFor(7), matching: byKey('toolChip.enabled.gemini')), findsOneWidget);

    await tester.pump(const Duration(seconds: 6)); // 等 toast 消失，免得挡住菜单
    await settle(tester, rounds: 2);
    // 已有工具时 ＋ 只在 hover 时出现
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(cardFor(7)));
    await tester.pump();
    await tester.tap(find.descendant(of: cardFor(7), matching: byKey('toolChip.plus')));
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('启用到 Codex'));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(vm.updateCalls.length, 1);
    expect(find.byType(KeyFormPage), findsOneWidget);
  });
}
