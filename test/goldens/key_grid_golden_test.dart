// 钥匙包网格 golden（1280×820，Linux，flutter_test 默认字体）。
//
// 用途：每个 UI PR 有意改变外观时用 `flutter test --update-goldens test/goldens` 重新生成，
// 在 PR diff 里直接看到前后对比；非预期的变化会让测试失败。
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/views/screens/main_screen.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Future<void> pumpMain(WidgetTester tester, {Brightness brightness = Brightness.light, bool empty = false}) async {
  await setSurface(tester, const Size(1280, 820));
  final vm = FakeKeyManagerViewModel(empty ? [] : buildFakeKeys());
  await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen(), brightness: brightness));
  await settle(tester, rounds: 6);
}

void main() {
  setUpAll(installTestPlatformMocks);
  // golden 只在 Linux 上比对（字体栅格化在各平台不同）
  final skip = !Platform.isLinux;

  testWidgets('钥匙包网格 · 浅色', (tester) async {
    await pumpMain(tester);
    await expectLater(find.byType(MainScreen), matchesGoldenFile('key_grid_light.png'));
  }, skip: skip);

  testWidgets('钥匙包网格 · 深色', (tester) async {
    await pumpMain(tester, brightness: Brightness.dark);
    await expectLater(find.byType(MainScreen), matchesGoldenFile('key_grid_dark.png'));
  }, skip: skip);

  testWidgets('钥匙包网格 · 管理模式', (tester) async {
    await pumpMain(tester);
    await tester.tap(find.byKey(const ValueKey('keyGrid.manageToggle')));
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester, rounds: 2);
    await expectLater(find.byType(MainScreen), matchesGoldenFile('key_grid_manage.png'));
  }, skip: skip);

  testWidgets('钥匙包 · 空状态', (tester) async {
    await pumpMain(tester, empty: true);
    await expectLater(find.byType(MainScreen), matchesGoldenFile('key_grid_empty.png'));
  }, skip: skip);
}
