// v4 修复回归测试：工具无法关闭、单卡网格居中、窗口顶栏垂直居中、紧凑开关规格、侧栏徽标尺寸。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/services/platform/window_chrome.dart';
import 'package:key_core/theme/kc_tokens.dart';
import 'package:key_core/viewmodels/settings_viewmodel.dart';
import 'package:key_core/views/widgets/kc_card_wrap.dart';
import 'package:key_core/views/widgets/kc_controls.dart';
import 'package:key_core/views/widgets/kc_logo.dart';
import 'package:key_core/views/widgets/kc_window_header.dart';
import 'package:key_core/views/widgets/tool_settings_row.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../fixtures/test_app.dart';

/// 已启用但配置「缺失」（或尚未校验）的工具：旧实现开关 onChanged=null，无法关闭。
class _Vm extends SettingsViewModel {
  final enabled = <AiToolType, bool>{AiToolType.openclaw: true, AiToolType.codex: true};
  final valid = <AiToolType, bool>{AiToolType.openclaw: false, AiToolType.codex: true};
  final calls = <String>[];
  @override
  bool isToolEnabled(AiToolType tool) => enabled[tool] ?? false;
  @override
  bool isToolConfigValid(AiToolType tool) => valid[tool] ?? false;
  @override
  Future<void> refreshToolConfigValidation(AiToolType tool) async {}
  @override
  String getDefaultToolConfigDir(AiToolType tool) => '/home/u/.${tool.value}';
  @override
  String? getToolConfigDir(AiToolType tool) => null;
  @override
  Future<bool> setToolEnabled(AiToolType tool, bool e) async {
    calls.add('${tool.value}=$e');
    enabled[tool] = e;
    notifyListeners();
    return true;
  }
}

Widget _host(Widget child, {Brightness b = Brightness.light}) => ShadTheme(
      data: KcTheme.shad(b),
      child: MaterialApp(theme: KcTheme.material(b), home: Scaffold(body: child)),
    );

void main() {
  setUpAll(installTestPlatformMocks);
  tearDown(() => WindowChrome.debugIsMacOS = null);

  group('工具配置开关（v4 #6）', () {
    test('关闭总是允许，不依赖配置是否有效', () async {
      final vm = _Vm();
      expect(await applyToolToggle(vm, AiToolType.openclaw, false), isTrue);
      expect(vm.calls, ['openclaw=false']);
      expect(vm.isToolEnabled(AiToolType.openclaw), isFalse);
    });

    test('开启时配置无效 → 拒绝，不写入', () async {
      final vm = _Vm()..enabled[AiToolType.openclaw] = false;
      expect(await applyToolToggle(vm, AiToolType.openclaw, true), isFalse);
      expect(vm.calls, isEmpty);
    });

    testWidgets('配置缺失的已启用工具：点开关即可关闭（旧实现开关被禁用）', (tester) async {
      final vm = _Vm();
      await tester.pumpWidget(_host(ListenableBuilder(
        listenable: vm,
        builder: (_, __) => Column(children: [
          ToolSettingsRow(tool: AiToolType.openclaw, viewModel: vm),
          ToolSettingsRow(tool: AiToolType.codex, viewModel: vm),
        ]),
      )));
      await tester.pump();
      final sw = tester.widget<KcSwitch>(find.byKey(const ValueKey('toolRow.switch.openclaw')));
      expect(sw.onChanged, isNotNull);
      expect(find.text('配置缺失'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolRow.switch.openclaw')));
      await tester.pumpAndSettle();
      expect(vm.calls, ['openclaw=false']);
      expect(tester.widget<KcSwitch>(find.byKey(const ValueKey('toolRow.switch.openclaw'))).value, isFalse);
      // 正常工具同样可以关闭
      await tester.tap(find.byKey(const ValueKey('toolRow.switch.codex')));
      await tester.pumpAndSettle();
      expect(vm.calls.last, 'codex=false');
    });
  });

  testWidgets('单卡网格左对齐（v4 #2）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        KcCardWrap(key: const ValueKey('grid'), children: [Container(key: const ValueKey('card'), width: 260, height: 160, color: Colors.red)]),
      ]),
    )));
    expect(tester.getTopLeft(find.byKey(const ValueKey('card'))).dx, 16);
    expect(tester.getSize(find.byKey(const ValueKey('grid'))).width, 1000 - 32);
  });

  testWidgets('窗口顶栏：标题块在 52 高内垂直居中（与红绿灯中心 y=26 对齐，v4 #1）', (tester) async {
    WindowChrome.debugIsMacOS = true;
    // 放在 Column 里（表单页的真实用法），不是 AppBar 槽
    await tester.pumpWidget(_host(Column(children: [
      KcWindowHeader(title: '添加密钥', subtitle: '自定义', onClose: () {}),
      const Expanded(child: SizedBox()),
    ])));
    final top = tester.getTopLeft(find.text('添加密钥')).dy;
    final bottom = tester.getBottomLeft(find.text('自定义')).dy;
    expect(((top + bottom) / 2 - KcSize.toolbar / 2).abs(), lessThan(1.5));
    final close = tester.getCenter(find.byKey(const ValueKey('kcWindowHeader.close'))).dy;
    expect((close - 26).abs(), lessThanOrEqualTo(0.5)); // 底部 1px 分隔线
  });

  testWidgets('紧凑开关 32×18，即使父级给紧约束（v4 #5）', (tester) async {
    await tester.pumpWidget(_host(Center(
      child: SizedBox(width: 60, height: 30, child: KcSwitch(key: const ValueKey('sw'), value: true, onChanged: (_) {})),
    )));
    expect(tester.getSize(find.descendant(of: find.byKey(const ValueKey('sw')), matching: find.byType(AnimatedContainer))), const Size(32, 18));
  });

  testWidgets('按钮规格：默认 md 32、sm 28，字号 13（v4 #5）', (tester) async {
    await tester.pumpWidget(_host(Column(children: [
      ShadButton.outline(key: const ValueKey('md'), onPressed: () {}, child: const Text('写入')),
      ShadButton.outline(key: const ValueKey('sm'), size: ShadButtonSize.sm, onPressed: () {}, child: const Text('写入')),
    ])));
    // ShadButton 外层含焦点环的 1px 内边距（上下各 1），可见按钮高 = 外框 - 2
    expect(tester.getSize(find.byKey(const ValueKey('md'))).height - 2, 32);
    expect(tester.getSize(find.byKey(const ValueKey('sm'))).height - 2, 28);
    final txt = tester.widget<RichText>(find.descendant(of: find.byKey(const ValueKey('md')), matching: find.byType(RichText)).first);
    expect(txt.text.style?.fontSize, 13);
  });

  testWidgets('侧栏徽标统一 20×20（自有 / 官方 / 未选择，v4 #4）', (tester) async {
    await tester.pumpWidget(_host(const Column(children: [
      KeyLogoChip.official(key: ValueKey('o'), tool: AiToolType.claudeDesktop),
      KeyLogoChip.none(key: ValueKey('n')),
    ])));
    expect(tester.getSize(find.byKey(const ValueKey('o'))), const Size(20, 20));
    expect(tester.getSize(find.byKey(const ValueKey('n'))), const Size(20, 20));
  });
}
