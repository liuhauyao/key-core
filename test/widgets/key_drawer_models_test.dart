// 详情抽屉「模型」页签（form_v3.md §5，取代独立的模型列表弹窗）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/model_info.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/views/widgets/key_details_dialog.dart';
import 'package:key_core/views/widgets/model_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

Finder byKey(String k) => find.byKey(ValueKey(k));

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  Future<List<String>> pump(WidgetTester tester, {List<ModelInfo>? cached, List<ModelInfo>? fresh, int tab = 1, bool withModels = true}) async {
    await setSurface(tester, const Size(1280, 820));
    final keys = buildFakeKeys();
    final vm = FakeKeyManagerViewModel(keys);
    final copied = <String>[];
    await tester.pumpWidget(buildTestApp(
      viewModel: vm,
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: KeyDetailsDialog(
            aiKey: keys.first,
            viewModel: vm,
            onEdit: () {},
            onCopyKey: () {},
            onOpenManagementUrl: () {},
            onCopyText: copied.add,
            initialTab: tab,
            loadModels: withModels ? () async => cached : null,
            refreshModels: withModels ? () async => fresh : null,
          ),
        ),
      ),
    ));
    await settle(tester, rounds: 4);
    return copied;
  }

  final models = [
    ModelInfo(id: 'deepseek-chat', name: 'DeepSeek Chat'),
    ModelInfo(id: 'deepseek-reasoner', name: 'DeepSeek Reasoner'),
    ModelInfo(id: 'other-x', name: 'Other'),
  ];

  testWidgets('打开即在「模型」页签：显示计数、可搜索、点击复制 ID', (tester) async {
    final copied = await pump(tester, cached: models);
    expect(byKey('keyDetails.tabs'), findsOneWidget);
    expect(byKey('keyDetails.models.list'), findsOneWidget);
    expect(find.text('共 3 个模型 · 点击复制 ID'), findsOneWidget);
    await tester.enterText(byKey('keyDetails.models.search'), 'reason');
    await tester.pump();
    expect(find.text('匹配 1 / 3'), findsOneWidget);
    await tester.tap(find.byType(ModelCard).first);
    await tester.pump();
    expect(copied, ['deepseek-reasoner']);
  });

  testWidgets('无缓存：空状态 → 刷新后显示新列表', (tester) async {
    await pump(tester, cached: null, fresh: models);
    expect(byKey('keyDetails.models.empty'), findsOneWidget);
    await tester.tap(byKey('keyDetails.models.refresh'));
    await settle(tester, rounds: 3);
    expect(byKey('keyDetails.models.list'), findsOneWidget);
  });

  testWidgets('切回「概览」；不传 loadModels 时不显示页签（工具页沿用单页）', (tester) async {
    await pump(tester, cached: models);
    await tester.tap(find.text('概览'));
    await settle(tester);
    expect(byKey('keyDetails.models.list'), findsNothing);
    await pump(tester, withModels: false, tab: 0);
    expect(byKey('keyDetails.tabs'), findsNothing);
  });
}
