// 侧栏导航：从第 0 页直接跳到最后一页（设置），不得经过 / 构建任何中间页，也不再有 PageView 横滑。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/views/screens/claude_config_screen.dart';
import 'package:key_core/views/screens/codex_config_screen.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/screens/mcp_config_screen.dart';
import 'package:key_core/views/screens/settings_screen.dart';
import 'package:key_core/views/screens/skills_config_screen.dart';
import 'package:key_core/views/widgets/app_switcher.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

void main() {
  setUpAll(installTestPlatformMocks);

  testWidgets('从 0 跳到最后一页：即时切换，中间页从不被构建', (tester) async {
    await setSurface(tester, const Size(1280, 820));
    await tester.pumpWidget(buildTestApp(viewModel: FakeKeyManagerViewModel(buildFakeKeys()), home: const MainScreen()));
    await settle(tester);

    expect(find.byType(PageView, skipOffstage: false), findsNothing);
    final sidebar = tester.widget<AppSidebar>(find.byType(AppSidebar));
    expect(sidebar.apps.length, greaterThanOrEqualTo(4));
    expect(sidebar.apps.last, AppType.settings);

    final intermediates = [ClaudeConfigScreen, CodexConfigScreen, McpConfigScreen, SkillsConfigScreen];
    void expectNoIntermediate() {
      for (final t in intermediates) {
        expect(find.byType(t, skipOffstage: false), findsNothing, reason: '$t 不应被构建');
      }
    }

    sidebar.onSwitch(AppType.settings);
    // 逐帧检查：任何一帧都不应出现中间页
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expectNoIntermediate();
    }
    // 第一帧之后就已经在设置页
    expect(find.byType(SettingsScreen), findsOneWidget);
    expectNoIntermediate();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
