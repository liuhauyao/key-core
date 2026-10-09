// UI-7：MCP / Skills 卡片 token 化后的基本行为 + golden。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/skill.dart';
import 'package:key_core/views/widgets/mcp_card.dart';
import 'package:key_core/views/widgets/skill_card.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/test_app.dart';

final _t = DateTime(2026, 1, 1);

McpServer _mcp(String id, String name, {bool active = true, McpServerType type = McpServerType.stdio}) => McpServer(
      serverId: id,
      name: name,
      description: '$name MCP server',
      serverType: type,
      command: type == McpServerType.stdio ? 'npx' : null,
      url: type == McpServerType.stdio ? null : 'https://example.com/mcp',
      tags: const ['dev', 'tools'],
      isActive: active,
      createdAt: _t,
      updatedAt: _t,
    );

Skill _skill(String id, String name, {bool active = true}) => Skill(
      skillId: id,
      relativePath: id,
      name: name,
      description: '$name skill description',
      enabledTools: const [SkillTargetTool.claudecode, SkillTargetTool.codex],
      syncStatus: const {SkillTargetTool.claudecode: SkillSyncState.synced, SkillTargetTool.codex: SkillSyncState.outdated},
      isActive: active,
      createdAt: _t,
      updatedAt: _t,
    );

Widget _grid(List<Widget> cards, double h) => Padding(
      padding: const EdgeInsets.all(24),
      child: GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 300 / h,
        children: cards,
      ),
    );

Future<void> _pump(WidgetTester tester, Widget child, {Brightness b = Brightness.light}) async {
  await setSurface(tester, const Size(1000, 420));
  await tester.pumpWidget(buildTestApp(
      viewModel: FakeKeyManagerViewModel(const []), home: Scaffold(body: child), brightness: b));
  await settle(tester);
}

void main() {
  setUpAll(installTestPlatformMocks);
  final skipGolden = !Platform.isLinux;

  testWidgets('MCP 卡片：开关回调 + 编辑模式显示拖拽柄', (tester) async {
    bool? toggled;
    await _pump(
        tester,
        _grid([
          McpCard(server: _mcp('github', 'GitHub'), onToggleActive: (v) => toggled = v),
        ], 140));
    expect(find.text('GitHub'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpCard.toggle')));
    await tester.pump();
    expect(toggled, isFalse);
    // 开启态：只给轨道上主色，滑块保持默认白色（之前 activeColor=主色 → 滑块与轨道同色，看起来没有滑块）
    final sw = tester.widget<Switch>(find.byKey(const ValueKey('mcpCard.toggle')));
    expect(sw.activeTrackColor, isNotNull);
    expect(sw.activeThumbColor, isNull);

    await _pump(tester, _grid([McpCard(server: _mcp('github', 'GitHub'), isEditMode: true)], 140));
    expect(find.byKey(const ValueKey('mcpCard.dragHandle')), findsOneWidget);
    expect(find.byKey(const ValueKey('mcpCard.toggle')), findsNothing);
  });

  testWidgets('MCP 卡片 v3：工具图标行 + 定宽槽位，管理模式槽位不位移、缺失入口置灰', (tester) async {
    Rect r(String k) => tester.getRect(find.byKey(ValueKey(k)));
    await _pump(tester, _grid([McpCard(server: _mcp('github', 'GitHub'), enabledTools: const {AiToolType.claudecode, AiToolType.codex}, onEdit: () {}, onViewDetails: () {})], 140));
    expect(find.byKey(const ValueKey('mcpCard.tools')), findsOneWidget);
    expect(find.text('2 个工具'), findsOneWidget);
    final before = {for (final k in ['details', 'apps', 'homepage', 'docs', 'edit']) k: r('mcpCard.$k')};
    await _pump(tester, _grid([McpCard(server: _mcp('github', 'GitHub'), isEditMode: true, enabledTools: const {AiToolType.claudecode, AiToolType.codex}, onEdit: () {}, onDelete: () {})], 140));
    for (final e in before.entries) {
      expect(r('mcpCard.${e.key}'), e.value, reason: e.key);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skill 卡片：显示名称与描述，无溢出', (tester) async {
    await _pump(tester, _grid([SkillCard(skill: _skill('pdf', 'PDF Tools'))], 160));
    expect(find.text('PDF Tools'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final b in Brightness.values) {
    testWidgets('MCP + Skills 卡片 golden · ${b.name}', (tester) async {
      await setSurface(tester, const Size(1000, 420));
      await _pump(
          tester,
          Column(children: [
            Expanded(
                child: _grid([
              McpCard(server: _mcp('github', 'GitHub'), enabledTools: const {AiToolType.claudecode, AiToolType.codex, AiToolType.cursor}),
              McpCard(server: _mcp('context7', 'Context7', type: McpServerType.http)),
              McpCard(server: _mcp('fetch', 'Fetch', active: false)),
            ], 140)),
            Expanded(
                child: _grid([
              SkillCard(skill: _skill('pdf', 'PDF Tools')),
              SkillCard(skill: _skill('review', 'Code Review'), isSelected: true),
              SkillCard(skill: _skill('docx', 'Docx', active: false)),
            ], 160)),
          ]),
          b: b);
      await expectLater(find.byType(Scaffold), matchesGoldenFile('../goldens/mcp_skills_${b.name}.png'));
    }, skip: skipGolden);
  }
}
