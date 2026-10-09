// 表单 v3（form_v3.md §1）：左栏 供应商/基本信息/更多选项，右栏列出全部工具；
// 可搜索供应商选择器（不越界）、密钥默认掩码、固定底栏状态与「n 处需要修改」、窄屏单栏。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/platform_registry.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/viewmodels/settings_viewmodel.dart';
import 'package:key_core/views/screens/key_form_page.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

class _OnlyClaude extends SettingsViewModel {
  @override
  List<AiToolType> getEnabledTools() => [AiToolType.claudecode];
}

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
  setUpAll(PlatformRegistry.initBuiltinPlatforms);
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  testWidgets('宽屏双栏（v3）：左栏 clamp(340, 35%, 420)；右栏列出全部工具，生效中的工具给出写入后果', (tester) async {
    await pumpForm(tester, editId: 1);
    expect(byKey('keyForm.left'), findsOneWidget);
    expect(byKey('keyForm.right'), findsOneWidget);
    expect(find.text('编辑密钥'), findsOneWidget);
    expect(tester.getSize(byKey('keyForm.left')).width, 420); // 1280 × 35% = 448 → 夹到 420
    for (final t in ['claudecode', 'claude_desktop', 'codex', 'gemini', 'openclaw']) {
      expect(byKey('keyForm.tool.$t'), findsOneWidget);
    }
    expect(find.textContaining('正在 Claude Code 生效'), findsOneWidget);
    expect(find.textContaining('开启后出现在 Codex 的候选列表'), findsOneWidget);
    expect(find.text('生效中'), findsOneWidget);
  });

  testWidgets('1024 宽：左栏下限 340 → 358（35%）', (tester) async {
    await pumpForm(tester, editId: 1, size: const Size(1024, 700));
    expect(tester.getSize(byKey('keyForm.left')).width, closeTo(358.4, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑态密钥默认掩码；可切换显示', (tester) async {
    await pumpForm(tester, editId: 1);
    EditableText key() => tester.widgetList<EditableText>(find.byType(EditableText)).firstWhere((e) => e.obscureText);
    expect(key().obscureText, isTrue);
    await tester.tap(byKey('keyForm.toggleObscure'));
    await tester.pump();
    expect(tester.widgetList<EditableText>(find.byType(EditableText)).where((e) => e.obscureText), isEmpty);
  });

  testWidgets('供应商选择器：可搜索，选中后回填；弹层不超出窗口', (tester) async {
    await pumpForm(tester, size: const Size(1024, 614));
    await tester.tap(byKey('keyForm.presetAll'));
    await settle(tester, rounds: 3);
    expect(byKey('providerPicker'), findsOneWidget);
    final r = tester.getRect(byKey('providerPicker'));
    expect(r.right, lessThanOrEqualTo(1024));
    expect(r.bottom, lessThanOrEqualTo(614));
    final items = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('providerPicker.item.'));
    expect(items, findsWidgets);
    final id = '${(tester.widget(items.first).key as ValueKey).value}'.substring('providerPicker.item.'.length);
    final p = PlatformRegistry.get(id)!;
    await tester.enterText(byKey('providerPicker.search'), p.value.toLowerCase());
    await tester.pump();
    expect(byKey('providerPicker.item.$id'), findsOneWidget);
    await tester.enterText(byKey('providerPicker.search'), 'zzzz-none');
    await tester.pump();
    expect(find.text('没有匹配的供应商'), findsOneWidget);
    await tester.enterText(byKey('providerPicker.search'), p.value.toLowerCase());
    await tester.pump();
    await tester.tap(byKey('providerPicker.item.$id'), warnIfMissed: true);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(byKey('providerPicker'), findsNothing);
    expect(find.text(p.value), findsWidgets);
  });

  testWidgets('设置中未启用的工具置灰并说明去哪开启', (tester) async {
    await setSurface(tester, const Size(1280, 820));
    final vm = FakeKeyManagerViewModel(buildFakeKeys());
    await tester.pumpWidget(buildTestApp(viewModel: vm, settings: _OnlyClaude(), home: const KeyFormPage()));
    await settle(tester, rounds: 6);
    expect(byKey('keyForm.tool.codex'), findsOneWidget);
    expect(find.text('设置中未启用'), findsNWidgets(4));
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
    expect(byKey('keyForm.tool.codex'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
