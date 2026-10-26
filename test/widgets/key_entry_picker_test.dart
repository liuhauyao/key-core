// 多密钥卡片「当前密钥」下拉（KcKeyEntryPicker）：单密钥不渲染；多密钥列出别名 + 掩码；
// 主界面卡片选择后写回 ViewModel 的 setActiveKeyEntry。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/views/screens/main_screen.dart';
import 'package:key_core/views/widgets/kc_key_entry_picker.dart';
import 'package:key_core/views/widgets/key_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Finder trigger() => find.byKey(const ValueKey('keyEntryPicker.trigger'));
Finder item(int i) => find.byKey(ValueKey('keyEntryPicker.item.$i'));
Finder cardFor(int id) => find.byWidgetPredicate((w) => w is KeyCard && w.aiKey.id == id);

AIKey multiKeyCard(int id) {
  final base = fakeKey(id, 'DeepSeek 主力', PlatformType.deepSeek, claudeCode: true, model: 'deepseek-chat');
  return base.copyWith(
    keyEntries: [
      const KeyEntry(value: 'sk-first-1111', label: '主号', validated: true),
      const KeyEntry(value: 'sk-second-2222', label: '备用', endpoint: 'https://api.backup.com'),
    ],
    activeKeyIndex: 0,
  );
}

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  Future<void> pumpPicker(WidgetTester tester, AIKey key, List<int> picked) async {
    await setSurface(tester, const Size(900, 600));
    await tester.pumpWidget(buildTestApp(
      viewModel: FakeKeyManagerViewModel(const []),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: KcKeyEntryPicker(aiKey: key, activeIndex: key.normalizedActiveIndex, onSelected: picked.add),
        ),
      ),
    ));
    await settle(tester, rounds: 2);
  }

  testWidgets('单密钥卡片不渲染选择器；多密钥显示当前那把的别名', (tester) async {
    await pumpPicker(tester, fakeKey(1, 'a', PlatformType.deepSeek), []);
    expect(trigger(), findsNothing);

    await pumpPicker(tester, multiKeyCard(1), []);
    expect(trigger(), findsOneWidget);
    expect(find.descendant(of: trigger(), matching: find.textContaining('主号')), findsOneWidget);
    expect(find.descendant(of: trigger(), matching: find.textContaining('默认地址')), findsOneWidget,
        reason: '该把未配置独立地址时显示「默认地址」');
  });

  testWidgets('弹出菜单列出全部别名与掩码；选中另一把回传下标', (tester) async {
    final picked = <int>[];
    await pumpPicker(tester, multiKeyCard(1), picked);
    await tester.tap(trigger());
    await settle(tester, rounds: 3);

    expect(item(0), findsOneWidget);
    expect(item(1), findsOneWidget);
    expect(find.text('主号'), findsWidgets);
    expect(find.text('备用'), findsWidgets);
    expect(find.text('sk-••••1111'), findsOneWidget, reason: '菜单里给出每把的掩码');
    expect(find.text('sk-••••2222'), findsOneWidget);
    expect(find.text('api.backup.com'), findsOneWidget, reason: '配置了独立地址的那把在第二行显示主机名');
    expect(find.text('默认地址'), findsOneWidget);

    await tester.tap(item(1));
    await settle(tester, rounds: 3);
    await tester.pump(const Duration(milliseconds: 400));
    expect(picked, [1]);
  });

  testWidgets('主界面卡片下拉切换当前密钥：写回 ViewModel，卡片显示新别名', (tester) async {
    await setSurface(tester, const Size(1280, 820));
    final keys = [multiKeyCard(1), ...buildFakeKeys().skip(1)];
    final vm = FakeKeyManagerViewModel(keys);
    await tester.pumpWidget(buildTestApp(viewModel: vm, home: const MainScreen()));
    await settle(tester, rounds: 4);

    final cardTrigger = find.descendant(of: cardFor(1), matching: trigger());
    expect(cardTrigger, findsOneWidget);
    expect(find.descendant(of: cardFor(1), matching: find.textContaining('主号')), findsOneWidget);

    await tester.tap(cardTrigger);
    await settle(tester, rounds: 3);
    await tester.tap(item(1));
    await settle(tester, rounds: 4);

    expect(vm.setActiveEntryCalls, [(1, 1)]);
    expect(find.descendant(of: cardFor(1), matching: find.textContaining('备用')), findsWidgets, reason: '卡片改为显示新别名');
    expect(find.descendant(of: cardFor(1), matching: find.textContaining('api.backup.com')), findsWidgets,
        reason: '切换后卡片同时显示该把的地址主机名');

    // MainScreen 启动时会起一个 1s 的首次权限检查定时器，测试结束前必须让它落地
    await tester.pump(const Duration(seconds: 7));
  });
}
