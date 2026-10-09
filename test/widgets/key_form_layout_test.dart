// UI-5 表单双栏（ui_redesign_plan §5.4 / mockup 04）：左栏预设 + 基本信息、右栏工具页签（✓）、
// 后果说明、就地错误 +「n 处需要修改」、窄屏单栏。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/viewmodels/settings_viewmodel.dart';
import 'package:key_core/views/screens/key_form_page.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

class _Settings extends SettingsViewModel {
  @override
  List<AiToolType> getEnabledTools() =>
      [AiToolType.claudecode, AiToolType.claudeDesktop, AiToolType.codex, AiToolType.gemini, AiToolType.openclaw];
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<FakeKeyManagerViewModel> pumpForm(WidgetTester tester, {int? editId, Size size = const Size(1280, 820)}) async {
  await setSurface(tester, size);
  final keys = buildFakeKeys();
  final vm = FakeKeyManagerViewModel(keys);
  vm.current[AiToolType.claudecode] = 1;
  final editing = editId == null ? null : keys.firstWhere((k) => k.id == editId);
  await tester.pumpWidget(buildTestApp(viewModel: vm, settings: _Settings(), home: KeyFormPage(editingKey: editing)));
  await settle(tester, rounds: 6);
  return vm;
}

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  testWidgets('宽屏双栏：编辑模式标题、工具页签带 ✓、生效中的工具给出写入后果', (tester) async {
    await pumpForm(tester, editId: 1);
    expect(byKey('keyForm.left'), findsOneWidget);
    expect(byKey('keyForm.right'), findsOneWidget);
    expect(find.text('编辑密钥'), findsOneWidget);
    // 左栏 380
    expect(tester.getSize(byKey('keyForm.left')).width, 380);
    for (final t in ['claudecode', 'claude_desktop', 'codex', 'gemini', 'openclaw']) {
      expect(byKey('keyForm.toolTab.$t'), findsOneWidget);
    }
    Finder check(String t) => find.descendant(of: byKey('keyForm.toolTab.$t'), matching: find.byIcon(Icons.check));
    expect(check('claudecode'), findsOneWidget);
    expect(check('codex'), findsOneWidget);
    expect(check('gemini'), findsNothing);
    // 默认第一个页签 Claude Code：这把密钥正在生效
    expect(find.textContaining('正在 Claude Code 生效'), findsOneWidget);

    await tester.tap(byKey('keyForm.toolTab.codex'));
    await settle(tester);
    expect(find.textContaining('开启后出现在 Codex 的候选列表'), findsOneWidget);
  });

  testWidgets('新建：左栏显示带 logo 的平台预设 chip（选中项高亮）', (tester) async {
    await pumpForm(tester);
    expect(find.text('添加密钥'), findsOneWidget);
    expect(find.text('平台预设'), findsOneWidget);
    expect(byKey('keyForm.preset.custom'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存时缺必填项：就地报错 +「2 处需要修改」，不关闭页面', (tester) async {
    await pumpForm(tester);
    await tester.tap(byKey('keyForm.submit'));
    await settle(tester);
    expect(byKey('keyForm.errorCount'), findsOneWidget);
    expect(find.text('2 处需要修改'), findsOneWidget);
    // 提示文案与 hint 相同，所以至少出现两次（hint + 错误）
    expect(find.text('请输入密钥名称'), findsNWidgets(2));
    expect(find.text('请输入密钥值'), findsNWidgets(2));
    expect(find.byType(KeyFormPage), findsOneWidget);
  });

  testWidgets('窄屏单栏（无左右分栏）', (tester) async {
    await pumpForm(tester, editId: 1, size: const Size(760, 820));
    expect(byKey('keyForm.left'), findsNothing);
    expect(byKey('keyForm.toolTab.codex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
