// AppSidebar（ui_redesign_plan §5.1 / §9）：只显示已启用工具；工具行显示当前密钥；选中态；
// 进入设置后换成设置目录；窄窗口收为图标轨。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/theme/kc_tokens.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/screens/settings_screen.dart';
import 'package:key_core/views/widgets/app_switcher.dart';
import 'package:key_core/views/widgets/kc_logo.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

void main() {
  setUpAll(installTestPlatformMocks);

  test('AppType.visibleFor：只列出已启用的工具，Claude Code / Desktop 各自独立', () {
    final v = AppType.visibleFor([AiToolType.claudecode, AiToolType.codex]);
    expect(v, containsAll([AppType.keyManager, AppType.claudeCode, AppType.codex, AppType.mcp, AppType.skills, AppType.settings]));
    expect(v, isNot(contains(AppType.claudeDesktop)));
    expect(v, isNot(contains(AppType.gemini)));
    expect(v, isNot(contains(AppType.openClaw)));
    final d = AppType.visibleFor([AiToolType.claudeDesktop]);
    expect(d, contains(AppType.claudeDesktop));
    expect(d, isNot(contains(AppType.claudeCode)));
    // 顺序与 PageView 一致
    expect(AppType.visibleFor(AiToolType.values).first, AppType.keyManager);
    expect(AppType.visibleFor(AiToolType.values).last, AppType.settings);
  });

  Future<FakeKeyManagerViewModel> pumpSidebar(
    WidgetTester tester, {
    AppType active = AppType.keyManager,
    List<AppType>? apps,
    bool collapsed = false,
    ValueChanged<AppType>? onSwitch,
    ValueChanged<SettingsCategory>? onCategory,
    SettingsCategory category = SettingsCategory.general,
    Brightness brightness = Brightness.light,
  }) async {
    await setSurface(tester, const Size(400, 720));
    final vm = FakeKeyManagerViewModel(buildFakeKeys());
    vm.current[AiToolType.claudecode] = 1; // DeepSeek 主力
    vm.current[AiToolType.gemini] = 4; // Gemini 个人
    await tester.pumpWidget(buildTestApp(
      viewModel: vm,
      brightness: brightness,
      home: Scaffold(
        body: Row(children: [
          AppSidebar(
            activeApp: active,
            apps: apps ?? AppType.values,
            onSwitch: onSwitch ?? (_) {},
            collapsed: collapsed,
            settingsCategory: category,
            onSettingsCategory: onCategory,
          ),
          const Expanded(child: SizedBox()),
        ]),
      ),
    ));
    await settle(tester);
    return vm;
  }

  String rowText(WidgetTester tester, String key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)))
      .map((t) => t.data)
      .join('|');

  String tipOf(WidgetTester tester, String key) => tester
      .widget<Tooltip>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Tooltip)).first)
      .message!;

  // v3（form_v3.md §8）：当前密钥只显示图标，名称放在 tooltip；工具名不再被截断
  testWidgets('工具行右侧显示当前密钥图标 / 官方标志 / OpenClaw 叠放', (tester) async {
    await pumpSidebar(tester);
    Finder inRow(String row, String key) => find.descendant(of: find.byKey(ValueKey(row)), matching: find.byKey(ValueKey(key)));
    expect(inRow('sidebar.claudeCode', 'sidebar.current.claudecode'), findsOneWidget);
    expect(tipOf(tester, 'sidebar.claudeCode'), 'Claude Code 当前使用：DeepSeek 主力');
    expect(inRow('sidebar.claudeDesktop', 'sidebar.official.claudeDesktop'), findsOneWidget);
    expect(inRow('sidebar.codex', 'sidebar.official.codex'), findsOneWidget);
    expect(tipOf(tester, 'sidebar.codex'), 'Codex 当前使用：官方登录');
    expect(inRow('sidebar.gemini', 'sidebar.current.gemini'), findsOneWidget);
    expect(inRow('sidebar.openClaw', 'sidebar.current.openclaw'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('sidebar.openClaw')), matching: find.byType(KeyLogoStack)), findsOneWidget);
    // 工具名完整显示，没有密钥名文字
    expect(find.text('DeepSeek 主力'), findsNothing);
    expect(find.text('Claude Desktop'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar.brandGlyph')), findsOneWidget);
    expect(rowText(tester, 'sidebar.keyManager'), '钥匙包|12');
    expect(find.text('工具 · 按工具查看密钥'), findsOneWidget);
    expect(find.text('扩展'), findsOneWidget);
  });

  testWidgets('只渲染传入的可见工具', (tester) async {
    await pumpSidebar(tester, apps: AppType.visibleFor([AiToolType.codex]));
    expect(find.byKey(const ValueKey('sidebar.codex')), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar.claudeCode')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar.claudeDesktop')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar.openClaw')), findsNothing);
  });

  testWidgets('切换后侧栏立即更新当前密钥', (tester) async {
    final vm = await pumpSidebar(tester);
    await vm.switchCodexProvider(6);
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('sidebar.codex')), matching: find.byKey(const ValueKey('sidebar.current.codex'))),
        findsOneWidget);
    expect(tipOf(tester, 'sidebar.codex'), 'Codex 当前使用：OpenRouter 测试');
  });

  testWidgets('点击行回调 onSwitch；选中行使用 selected 底色', (tester) async {
    final tapped = <AppType>[];
    await pumpSidebar(tester, active: AppType.codex, onSwitch: tapped.add);
    await tester.tap(find.byKey(const ValueKey('sidebar.gemini')));
    await tester.tap(find.byKey(const ValueKey('sidebar.settings')));
    expect(tapped, [AppType.gemini, AppType.settings]);

    Color? bgOf(String key) {
      final c = tester.widget<Container>(find
          .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Container))
          .first);
      return (c.decoration as BoxDecoration?)?.color;
    }

    expect(bgOf('sidebar.codex'), KcTokens.light.selected);
    expect(bgOf('sidebar.gemini'), isNot(KcTokens.light.selected));
  });

  testWidgets('进入设置：侧栏换成设置目录 + 返回钥匙包', (tester) async {
    final cats = <SettingsCategory>[];
    final tapped = <AppType>[];
    await pumpSidebar(tester, active: AppType.settings, onCategory: cats.add, onSwitch: tapped.add);
    expect(find.byKey(const ValueKey('sidebar.codex')), findsNothing);
    for (final c in SettingsCategory.values) {
      expect(find.byKey(ValueKey('sidebar.settings.${c.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('sidebar.settings.tools')));
    await tester.tap(find.byKey(const ValueKey('sidebar.backToKeys')));
    expect(cats, [SettingsCategory.tools]);
    expect(tapped, [AppType.keyManager]);
  });

  testWidgets('收起为图标轨：宽 72，不显示文字，靠 Tooltip 提示', (tester) async {
    await pumpSidebar(tester, collapsed: true);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(tester.getSize(find.byKey(const ValueKey('appSidebar'))).width, KcSize.sidebarRail);
    expect(find.text('Claude Code'), findsNothing);
    final tip = tester.widget<Tooltip>(find
        .descendant(of: find.byKey(const ValueKey('sidebar.claudeCode')), matching: find.byType(Tooltip))
        .first);
    expect(tip.message, 'Claude Code 当前使用：DeepSeek 主力');
  });

  testWidgets('深色模式下侧栏用 KcTokens.dark.sidebar', (tester) async {
    await pumpSidebar(tester, brightness: Brightness.dark);
    final c = tester.widget<AnimatedContainer>(find.byKey(const ValueKey('appSidebar')));
    expect((c.decoration as BoxDecoration).color, KcTokens.dark.sidebar);
  });

  group('MainScreen 外壳', () {
    Future<void> pumpMain(WidgetTester tester, Size size) async {
      await setSurface(tester, size);
      await tester.pumpWidget(buildTestApp(viewModel: FakeKeyManagerViewModel(buildFakeKeys()), home: const MainScreen()));
      await settle(tester);
    }

    testWidgets('宽窗口：200px 侧栏 + 内容区', (tester) async {
      await pumpMain(tester, const Size(1280, 820));
      expect(find.byType(AppSidebar), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('appSidebar'))).width, KcSize.sidebar);
    });

    testWidgets('窄于 900：收为 72px 图标轨', (tester) async {
      await pumpMain(tester, const Size(860, 820));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(tester.getSize(find.byKey(const ValueKey('appSidebar'))).width, KcSize.sidebarRail);
    });
  });
}
