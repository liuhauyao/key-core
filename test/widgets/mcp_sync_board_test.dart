import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/utils/mcp_comparison.dart';
import 'package:key_core/views/widgets/mcp_sync_board.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/test_app.dart';

McpServer _s(String id, List<String> args) => McpServer(
      serverId: id,
      name: id,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: args,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

class _Host extends StatefulWidget {
  const _Host(this.results, this.applied);
  final List<McpComparisonResult> results;
  final List<Map<String, McpSyncAction>> applied;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final pending = <String, McpSyncAction>{};
  @override
  Widget build(BuildContext context) => Scaffold(
        body: McpSyncBoard(
          tools: const [
            McpToolSummary(tool: AiToolType.claudecode, pending: 3, conflicts: 1),
            McpToolSummary(tool: AiToolType.cursor),
            McpToolSummary(tool: AiToolType.windsurf, notInstalled: true),
          ],
          selectedTool: AiToolType.claudecode,
          onSelectTool: (_) {},
          results: widget.results,
          pending: pending,
          configPath: '~/.claude.json',
          onSetAction: (id, a) => setState(() => a == null ? pending.remove(id) : pending[id] = a),
          onApply: () => widget.applied.add(Map.of(pending)),
          onDiscard: () => setState(pending.clear),
        ),
      );
}

void main() {
  setUpAll(installTestPlatformMocks);

  final results = [
    McpComparisonResult(server: _s('fetch', ['a']), status: McpComparisonStatus.identical, toolServer: _s('fetch', ['a'])),
    McpComparisonResult(server: _s('github', ['x']), status: McpComparisonStatus.different, toolServer: _s('github', ['y'])),
    McpComparisonResult(server: _s('ctx7', ['c']), status: McpComparisonStatus.onlyInLocal),
    McpComparisonResult(server: _s('sqlite', ['s']), status: McpComparisonStatus.onlyInTool),
  ];

  Future<List<Map<String, McpSyncAction>>> pump(WidgetTester tester, List<McpComparisonResult> r) async {
    final applied = <Map<String, McpSyncAction>>[];
    await setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(buildTestApp(viewModel: FakeKeyManagerViewModel(const []), home: _Host(r, applied)));
    await settle(tester, rounds: 2);
    return applied;
  }

  testWidgets('左侧工具徽标 + 状态 chip + 行内 JSON 差异', (tester) async {
    await pump(tester, results);
    expect(find.text('1 冲突'), findsOneWidget);
    expect(find.text('已同步'), findsOneWidget);
    expect(find.text('未安装'), findsOneWidget);
    for (final id in ['fetch', 'github', 'ctx7', 'sqlite']) {
      expect(find.byKey(ValueKey('mcpSync.row.$id')), findsOneWidget);
    }
    // 一致的行不可勾选
    expect(find.byKey(const ValueKey('mcpSync.check.fetch')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mcpSync.expand.github')));
    await tester.pump();
    final diff = find.byKey(const ValueKey('mcpSync.diff.github'));
    expect(diff, findsOneWidget);
    expect(find.descendant(of: diff, matching: find.textContaining('"x"')), findsOneWidget);
    expect(find.descendant(of: diff, matching: find.textContaining('"y"')), findsOneWidget);
  });

  testWidgets('勾选 → 同步所选按默认动作排队（推送 / 拉入）', (tester) async {
    final applied = await pump(tester, results);
    await tester.tap(find.byKey(const ValueKey('mcpSync.check.github')));
    await tester.tap(find.byKey(const ValueKey('mcpSync.check.sqlite')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mcpSync.syncSelected')));
    await tester.pump();
    expect(applied.single, {'github': McpSyncAction.push, 'sqlite': McpSyncAction.pull});
  });

  testWidgets('行内删除 + 忽略；全部同步覆盖全部差异', (tester) async {
    final applied = await pump(tester, results);
    await tester.tap(find.byKey(const ValueKey('mcpSync.delete.sqlite')));
    await tester.pump();
    expect(find.textContaining('待删除 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mcpSync.ignore.sqlite')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mcpSync.syncAll')));
    await tester.pump();
    expect(applied.single.keys.toSet(), {'github', 'ctx7', 'sqlite'});
  });

  testWidgets('差异视图对 env 中的令牌打码', (tester) async {
    final t = McpServer(
      serverId: 'gh', name: 'gh', serverType: McpServerType.stdio, command: 'npx', args: const ['x'],
      env: const {'TOKEN': 'ghp_supersecret123'}, createdAt: DateTime(2026), updatedAt: DateTime(2026));
    await pump(tester, [McpComparisonResult(server: _s('gh', ['x']), status: McpComparisonStatus.different, toolServer: t)]);
    await tester.tap(find.byKey(const ValueKey('mcpSync.expand.gh')));
    await tester.pump();
    expect(find.textContaining('ghp_supersecret123'), findsNothing);
    expect(find.textContaining('gh••••23'), findsOneWidget);
  });

  testWidgets('全部一致 → 已全部同步空状态', (tester) async {
    await pump(tester, [results.first]);
    expect(find.byKey(const ValueKey('mcpSync.allInSync')), findsOneWidget);
    expect(find.text('已全部同步'), findsOneWidget);
  });

  testWidgets('确认面板列出写入文件与备份提示', (tester) async {
    await setSurface(tester, const Size(1200, 800));
    await tester.pumpWidget(buildTestApp(
      viewModel: FakeKeyManagerViewModel(const []),
      home: const Scaffold(
        body: McpSyncConfirmSheet(
          tool: AiToolType.cursor,
          configPath: '~/.cursor/mcp.json',
          pending: {'github': McpSyncAction.push, 'sqlite': McpSyncAction.pull},
        ),
      ),
    ));
    await settle(tester, rounds: 2);
    expect(find.text('~/.cursor/mcp.json'), findsOneWidget);
    expect(find.text('key-core 本地数据库'), findsOneWidget);
    expect(find.textContaining('备份'), findsOneWidget);
    expect(find.text('同步 2 项'), findsOneWidget);
  });
}
