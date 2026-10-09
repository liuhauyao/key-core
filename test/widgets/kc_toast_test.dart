import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/viewmodels/key_manager_viewmodel.dart';
import 'package:key_core/views/widgets/kc_toast.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/test_app.dart';

Future<BuildContext> _pumpHost(WidgetTester tester) async {
  late BuildContext ctx;
  await setSurface(tester, const Size(1000, 700));
  await tester.pumpWidget(buildTestApp(
    viewModel: FakeKeyManagerViewModel(const []),
    home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })),
  ));
  await settle(tester, rounds: 2);
  return ctx;
}

void main() {
  setUpAll(installTestPlatformMocks);

  test('humanizeError 去掉 Exception 前缀', () {
    expect(humanizeError(Exception('无法解析配置文件 a.json')), '无法解析配置文件 a.json');
    expect(humanizeError(null), '');
    expect(humanizeError('plain'), 'plain');
  });

  test('ToolSwitchException 只保留原因文本', () {
    expect(ToolSwitchException(Exception('x 坏了')).toString(), 'x 坏了');
    expect(ToolSwitchException(null).toString(), '');
  });

  testWidgets('切换成功：写结果，不再只是「已切换」', (tester) async {
    final ctx = await _pumpHost(tester);
    showSwitchResult(ctx, success: true, targetName: 'DeepSeek 主力');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已切换到 DeepSeek 主力。新开的会话会读取新配置。'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('切换失败：带原因和「重试」，点击重试会重新调用', (tester) async {
    final ctx = await _pumpHost(tester);
    var retried = 0;
    showSwitchResult(
      ctx,
      success: false,
      targetName: 'Codex 测试',
      error: '无法解析配置文件 ~/.codex/auth.json（已中止写入，文件未被修改）：Unexpected character (at line 3)',
      onRetry: () => retried++,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('没能切换到 Codex 测试：无法解析配置文件 ~/.codex/auth.json'), findsOneWidget);
    expect(find.textContaining('line 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('重试'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(retried, 1);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('失败但没有原因时给出兜底说明，而不是空白', (tester) async {
    final ctx = await _pumpHost(tester);
    showSwitchResult(ctx, success: false, targetName: 'X', error: '');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('没能切换到 X：写入配置文件失败，详见日志'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('成功可带「撤销」', (tester) async {
    final ctx = await _pumpHost(tester);
    var undone = false;
    showSwitchResult(ctx, success: true, targetName: 'Kimi K2', onUndo: () => undone = true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('撤销'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(undone, isTrue);
    await tester.pump(const Duration(seconds: 6));
  });
}
