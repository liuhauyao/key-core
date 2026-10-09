// MCP 同步（v3 全页）：左侧目标工具列表（logo + 状态徽标），右侧逐服务差异行
// （状态 chip / 内联 JSON 差异 / 推送·拉入·删除·忽略 / 勾选），底部固定操作栏 + 确认面板。
// 只负责展示与交互；读取 / 比对 / 写入仍由 McpSyncService + McpViewModel 完成（见 mcp_sync_page.dart）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/mcp_server.dart';
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../utils/mcp_comparison.dart';
import 'kc_logo.dart';
import 'kc_segmented.dart';

/// 对单个服务的待执行动作
enum McpSyncAction { push, pull, delete }

/// 左侧工具列表的一项
class McpToolSummary {
  const McpToolSummary({
    required this.tool,
    this.pending = 0,
    this.conflicts = 0,
    this.total = 0,
    this.loading = false,
    this.error = false,
    this.notInstalled = false,
  });
  final AiToolType tool;
  final int pending;
  final int conflicts;
  final int total;
  final bool loading;
  final bool error;
  final bool notInstalled;
}

/// 默认动作：只在本应用 → 推送；只在工具 → 拉入；不一致 → 推送（以本应用为准）；一致 → 无
McpSyncAction? defaultMcpAction(McpComparisonStatus s) => switch (s) {
      McpComparisonStatus.onlyInLocal => McpSyncAction.push,
      McpComparisonStatus.onlyInTool => McpSyncAction.pull,
      McpComparisonStatus.different => McpSyncAction.push,
      McpComparisonStatus.identical => null,
    };

String _t(BuildContext c, String k, String f) => AppLocalizations.of(c)?.tr(k, f) ?? f;

String mcpJsonOf(McpServer? s, {bool mask = false}) {
  if (s == null) return '';
  var cfg = s.toToolConfigFormat();
  if (mask) {
    // env / headers 里的值可能是令牌：显示时打码（比对仍基于原值）
    cfg = {
      for (final e in cfg.entries)
        e.key: (e.key == 'env' || e.key == 'headers') && e.value is Map
            ? {for (final kv in (e.value as Map).entries) kv.key: _maskSecret('${kv.value}')}
            : e.value,
    };
  }
  return const JsonEncoder.withIndent('  ').convert({s.serverId: cfg});
}

String _maskSecret(String v) => v.length <= 4 ? '••••' : '${v.substring(0, 2)}••••${v.substring(v.length - 2)}';

enum _Filter { all, pending, onlyLocal, onlyTool, different, identical }

class McpSyncBoard extends StatefulWidget {
  const McpSyncBoard({
    super.key,
    required this.tools,
    required this.selectedTool,
    required this.onSelectTool,
    required this.results,
    required this.pending,
    required this.onSetAction,
    required this.onApply,
    required this.onDiscard,
    this.configPath,
    this.scopeSelector,
    this.loading = false,
    this.error,
    this.onRefresh,
  });

  final List<McpToolSummary> tools;
  final AiToolType? selectedTool;
  final ValueChanged<AiToolType> onSelectTool;
  final List<McpComparisonResult> results;
  final Map<String, McpSyncAction> pending;
  final void Function(String serverId, McpSyncAction? action) onSetAction;

  /// 打开确认面板并执行（由页面实现）
  final VoidCallback onApply;
  final VoidCallback onDiscard;
  final String? configPath;
  final Widget? scopeSelector;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;

  @override
  State<McpSyncBoard> createState() => _McpSyncBoardState();
}

class _McpSyncBoardState extends State<McpSyncBoard> {
  _Filter _filter = _Filter.all;
  final Set<String> _selected = {};
  final Set<String> _expanded = {};

  @override
  void didUpdateWidget(covariant McpSyncBoard old) {
    super.didUpdateWidget(old);
    if (old.selectedTool != widget.selectedTool) {
      _selected.clear();
      _expanded.clear();
      _filter = _Filter.all;
    }
    final ids = widget.results.map((r) => r.server.serverId).toSet();
    _selected.retainAll(ids);
  }

  bool _match(McpComparisonResult r) => switch (_filter) {
        _Filter.all => true,
        _Filter.pending => r.status != McpComparisonStatus.identical,
        _Filter.onlyLocal => r.status == McpComparisonStatus.onlyInLocal,
        _Filter.onlyTool => r.status == McpComparisonStatus.onlyInTool,
        _Filter.different => r.status == McpComparisonStatus.different,
        _Filter.identical => r.status == McpComparisonStatus.identical,
      };

  void _queue(Iterable<McpComparisonResult> rows) {
    for (final r in rows) {
      final a = defaultMcpAction(r.status);
      if (a != null) widget.onSetAction(r.server.serverId, a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 232, child: _toolList(context)),
      VerticalDivider(width: 1, thickness: 1, color: cs.border),
      Expanded(child: _main(context)),
    ]);
  }

  // ───────── 左：目标工具 ─────────
  Widget _toolList(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    return ColoredBox(
      color: kc.subtle.withValues(alpha: 0.45),
      child: ListView(padding: const EdgeInsets.all(KcSpace.x2), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Text(_t(context, 'mcp_sync_targets', '目标工具'), style: KcType.caption.copyWith(color: cs.mutedForeground, fontWeight: FontWeight.w600)),
        ),
        for (final s in widget.tools)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: s.tool == widget.selectedTool ? cs.background : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                key: ValueKey('mcpSync.tool.${s.tool.value}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => widget.onSelectTool(s.tool),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: s.tool == widget.selectedTool
                      ? BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.border), boxShadow: kc.shadowSm)
                      : null,
                  child: Row(children: [
                    KcToolLogo(tool: s.tool, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.tool.displayName,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.body.copyWith(color: cs.foreground, fontWeight: FontWeight.w500)),
                    ),
                    _toolBadge(context, s),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _toolBadge(BuildContext context, McpToolSummary s) {
    final kc = context.kc;
    if (s.loading) return const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5));
    if (s.notInstalled) return _pill(context, _t(context, 'mcp_sync_not_installed', '未安装'), kc.text2, kc.subtle);
    if (s.error) return _pill(context, _t(context, 'mcp_sync_read_failed', '读取失败'), kc.dangerText, kc.dangerSoft);
    if (s.conflicts > 0) return _pill(context, _t(context, 'mcp_sync_n_conflicts', '{n} 冲突').replaceAll('{n}', '${s.conflicts}'), kc.dangerText, kc.dangerSoft);
    if (s.pending > 0) return _pill(context, _t(context, 'mcp_sync_n_pending', '{n} 待处理').replaceAll('{n}', '${s.pending}'), kc.warnText, kc.warnSoft);
    return _pill(context, _t(context, 'mcp_sync_in_sync', '已同步'), kc.okText, kc.okSoft);
  }

  Widget _pill(BuildContext context, String text, Color fg, Color bg) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: KcType.badge.copyWith(color: fg)),
      );

  // ───────── 右：差异列表 ─────────
  Widget _main(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final rows = widget.results.where(_match).toList();
    int n(_Filter f) {
      final keep = _filter;
      _filter = f;
      final c = widget.results.where(_match).length;
      _filter = keep;
      return c;
    }

    final pendingCount = widget.results.where((r) => r.status != McpComparisonStatus.identical).length;
    final allInSync = widget.results.isNotEmpty && pendingCount == 0 && widget.pending.isEmpty;
    final tool = widget.selectedTool;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // 工具信息行
      Padding(
        padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x4, KcSpace.page, 0),
        child: Row(children: [
          if (tool != null) ...[KcToolLogo(tool: tool, size: 26), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tool?.displayName ?? '', style: KcType.title.copyWith(color: cs.foreground)),
              if (widget.configPath != null)
                Text(widget.configPath!, key: const ValueKey('mcpSync.path'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: KcType.mono.copyWith(fontSize: 11.5, color: cs.mutedForeground)),
            ]),
          ),
          if (widget.scopeSelector != null) ...[widget.scopeSelector!, const SizedBox(width: 8)],
          if (widget.onRefresh != null)
            Tooltip(
              message: _t(context, 'mcp_sync_reread', '重新读取'),
              child: ShadButton.outline(
                key: const ValueKey('mcpSync.refresh'),
                width: KcSize.control,
                height: KcSize.control,
                padding: EdgeInsets.zero,
                onPressed: widget.onRefresh,
                child: Icon(Icons.refresh, size: 16, color: kc.text2),
              ),
            ),
        ]),
      ),
      if (widget.results.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, KcSpace.x2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: KcSegmented<_Filter>(
                key: const ValueKey('mcpSync.filter'),
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
                items: [
                  (_Filter.all, _t(context, 'segment_all', '全部'), n(_Filter.all)),
                  (_Filter.pending, _t(context, 'mcp_sync_f_pending', '待处理'), n(_Filter.pending)),
                  (_Filter.onlyLocal, _t(context, 'mcp_sync_only_local', '仅 key-core'), n(_Filter.onlyLocal)),
                  (_Filter.onlyTool, _t(context, 'mcp_sync_only_tool', '仅工具'), n(_Filter.onlyTool)),
                  (_Filter.different, _t(context, 'mcp_sync_different', '不一致'), n(_Filter.different)),
                  (_Filter.identical, _t(context, 'mcp_sync_same', '一致'), n(_Filter.identical)),
                ],
              ),
            ),
          ),
        ),
      Expanded(child: _body(context, rows, allInSync)),
      _bottomBar(context, rows),
    ]);
  }

  Widget _body(BuildContext context, List<McpComparisonResult> rows, bool allInSync) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    if (widget.loading) return const Center(child: CircularProgressIndicator());
    if (widget.error != null) {
      return Center(child: Text(widget.error!, style: KcType.body.copyWith(color: kc.dangerText)));
    }
    if (widget.results.isEmpty || allInSync) {
      return Center(
        key: const ValueKey('mcpSync.allInSync'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: kc.okSoft, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 30, color: kc.okText),
          ),
          const SizedBox(height: KcSpace.x4),
          Text(
            widget.results.isEmpty ? _t(context, 'mcp_sync_empty', '两边都没有 MCP 服务') : _t(context, 'mcp_sync_all_same', '已全部同步'),
            style: KcType.title.copyWith(color: cs.foreground),
          ),
          const SizedBox(height: 6),
          Text(
            (_t(context, 'mcp_sync_all_same_desc', 'key-core 与 {tool} 中的 {n} 个服务配置完全一致'))
                .replaceAll('{tool}', widget.selectedTool?.displayName ?? '')
                .replaceAll('{n}', '${widget.results.length}'),
            style: KcType.body.copyWith(color: kc.text2),
          ),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x1, KcSpace.page, KcSpace.x4),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _row(context, rows[i]),
    );
  }

  (String, Color, Color) _statusChip(BuildContext context, McpComparisonStatus s) {
    final kc = context.kc;
    return switch (s) {
      McpComparisonStatus.onlyInLocal => (_t(context, 'mcp_sync_only_local', '仅 key-core'), kc.actionText, kc.actionSoft),
      McpComparisonStatus.onlyInTool => (_t(context, 'mcp_sync_only_tool', '仅工具'), kc.warnText, kc.warnSoft),
      McpComparisonStatus.different => (_t(context, 'mcp_sync_different', '不一致'), kc.dangerText, kc.dangerSoft),
      McpComparisonStatus.identical => (_t(context, 'mcp_sync_same', '一致'), kc.okText, kc.okSoft),
    };
  }

  String _actionLabel(BuildContext context, McpSyncAction a) => switch (a) {
        McpSyncAction.push => _t(context, 'mcp_sync_will_push', '将推送到工具'),
        McpSyncAction.pull => _t(context, 'mcp_sync_will_pull', '将拉入 key-core'),
        McpSyncAction.delete => _t(context, 'mcp_sync_will_delete', '将从工具删除'),
      };

  Widget _row(BuildContext context, McpComparisonResult r) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final id = r.server.serverId;
    final chip = _statusChip(context, r.status);
    final action = widget.pending[id];
    final expanded = _expanded.contains(id);
    final canSelect = r.status != McpComparisonStatus.identical;
    Widget act(String key, IconData icon, String tip, McpSyncAction a, {bool danger = false}) => Tooltip(
          message: tip,
          child: ShadButton.ghost(
            key: ValueKey('mcpSync.$key.$id'),
            width: 28,
            height: 28,
            padding: EdgeInsets.zero,
            backgroundColor: action == a ? (danger ? kc.dangerSoft : kc.actionSoft) : null,
            onPressed: () => widget.onSetAction(id, action == a ? null : a),
            child: Icon(icon, size: 16, color: danger ? kc.dangerText : (action == a ? cs.primary : kc.text2)),
          ),
        );

    return Container(
      key: ValueKey('mcpSync.row.$id'),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(KcRadius.panel),
        border: Border.all(color: action != null ? cs.primary.withValues(alpha: 0.6) : cs.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 52,
          child: Row(children: [
            const SizedBox(width: 6),
            SizedBox(
              width: 32,
              child: canSelect
                  ? Checkbox(
                      key: ValueKey('mcpSync.check.$id'),
                      value: _selected.contains(id),
                      onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                    )
                  : null,
            ),
            const SizedBox(width: 4),
            KcLogoBox(
              size: 30,
              child: SvgPicture.asset('assets/icons/platforms/${r.server.icon ?? 'mcp.svg'}', width: 19, height: 19, allowDrawingOutsideViewBox: true),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(r.server.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.strong.copyWith(color: cs.foreground)),
                Text(
                  action != null ? '$id · ${_actionLabel(context, action)}' : '$id · ${r.server.serverType.value.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KcType.caption.copyWith(color: action != null ? cs.primary : cs.mutedForeground),
                ),
              ]),
            ),
            _pill(context, chip.$1, chip.$2, chip.$3),
            const SizedBox(width: 10),
            // 行内动作（固定槽位，不随状态位移）
            SizedBox(
              width: 28 * 3 + 8,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (r.status != McpComparisonStatus.onlyInTool && r.status != McpComparisonStatus.identical)
                  act('push', Icons.upload_outlined, _t(context, 'mcp_sync_push', '推送到工具'), McpSyncAction.push),
                if (r.status == McpComparisonStatus.onlyInTool || r.status == McpComparisonStatus.different)
                  act('pull', Icons.download_outlined, _t(context, 'mcp_sync_pull', '拉入 key-core'), McpSyncAction.pull),
                if (r.status == McpComparisonStatus.onlyInTool)
                  act('delete', Icons.delete_outline, _t(context, 'mcp_sync_delete', '从工具删除'), McpSyncAction.delete, danger: true),
              ]),
            ),
            Tooltip(
              message: _t(context, 'mcp_sync_ignore', '忽略（清除待执行动作）'),
              child: ShadButton.ghost(
                key: ValueKey('mcpSync.ignore.$id'),
                width: 28,
                height: 28,
                padding: EdgeInsets.zero,
                onPressed: action == null ? null : () => widget.onSetAction(id, null),
                child: Icon(Icons.block, size: 15, color: action == null ? kc.text2.withValues(alpha: 0.35) : kc.text2),
              ),
            ),
            ShadButton.ghost(
              key: ValueKey('mcpSync.expand.$id'),
              width: 28,
              height: 28,
              padding: EdgeInsets.zero,
              onPressed: () => setState(() => expanded ? _expanded.remove(id) : _expanded.add(id)),
              child: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: kc.text2),
            ),
            const SizedBox(width: 8),
          ]),
        ),
        if (expanded) _diff(context, r),
      ]),
    );
  }

  Widget _diff(BuildContext context, McpComparisonResult r) {
    final cs = ShadTheme.of(context).colorScheme;
    final local = r.status == McpComparisonStatus.onlyInTool ? null : r.server;
    final tool = switch (r.status) {
      McpComparisonStatus.onlyInTool => r.server,
      McpComparisonStatus.onlyInLocal => null,
      _ => r.toolServer,
    };
    final a = mcpJsonOf(local).split('\n');
    final b = mcpJsonOf(tool).split('\n');
    final am = mcpJsonOf(local, mask: true).split('\n');
    final bm = mcpJsonOf(tool, mask: true).split('\n');
    final bSet = b.toSet();
    final aSet = a.toSet();
    Widget pane(String title, List<String> raw, List<String> shown, Set<String> other, Color hl) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: KcType.caption.copyWith(color: cs.mutedForeground, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: cs.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: cs.border),
              ),
              child: raw.length == 1 && raw.first.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(_t(context, 'mcp_sync_absent', '（不存在）'), style: KcType.caption.copyWith(color: cs.mutedForeground)),
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final (i, l) in raw.indexed)
                        Container(
                          color: other.isNotEmpty && !other.contains(l) ? hl : null,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(i < shown.length ? shown[i] : l, style: KcType.mono.copyWith(fontSize: 11.5, height: 1.5, color: cs.foreground)),
                        ),
                    ]),
            ),
          ]),
        );
    return Container(
      key: ValueKey('mcpSync.diff.${r.server.serverId}'),
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        pane('key-core', a, am, bSet, context.kc.okSoft),
        const SizedBox(width: 10),
        pane(widget.selectedTool?.displayName ?? '', b, bm, aSet, context.kc.dangerSoft),
      ]),
    );
  }

  // ───────── 底部固定操作栏 ─────────
  Widget _bottomBar(BuildContext context, List<McpComparisonResult> visible) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final p = widget.pending.values;
    final push = p.where((a) => a == McpSyncAction.push).length;
    final pull = p.where((a) => a == McpSyncAction.pull).length;
    final del = p.where((a) => a == McpSyncAction.delete).length;
    final pendingRows = widget.results.where((r) => r.status != McpComparisonStatus.identical).toList();
    final selRows = widget.results.where((r) => _selected.contains(r.server.serverId)).toList();
    return Container(
      key: const ValueKey('mcpSync.bar'),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: cs.background, border: Border(top: BorderSide(color: cs.border))),
      child: Row(children: [
        Expanded(
          child: Text(
            widget.pending.isEmpty
                ? _t(context, 'mcp_sync_bar_idle', '已选 {s} · 尚无待执行的变更').replaceAll('{s}', '${_selected.length}')
                : _t(context, 'mcp_sync_bar_counts', '待推送 {a} · 待拉入 {b} · 待删除 {c}')
                    .replaceAll('{a}', '$push')
                    .replaceAll('{b}', '$pull')
                    .replaceAll('{c}', '$del'),
            key: const ValueKey('mcpSync.counts'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KcType.caption.copyWith(color: kc.text2),
          ),
        ),
        if (widget.pending.isNotEmpty) ...[
          ShadButton.ghost(height: 32, onPressed: widget.onDiscard, child: Text(_t(context, 'mcp_sync_discard', '放弃变更'))),
          const SizedBox(width: 6),
        ],
        ShadButton.outline(
          key: const ValueKey('mcpSync.syncSelected'),
          height: 32,
          onPressed: selRows.isEmpty
              ? null
              : () {
                  _queue(selRows);
                  widget.onApply();
                },
          child: Text(_t(context, 'mcp_sync_selected', '同步所选') + (selRows.isEmpty ? '' : ' (${selRows.length})')),
        ),
        const SizedBox(width: 8),
        ShadButton(
          key: const ValueKey('mcpSync.syncAll'),
          height: 32,
          leading: const Icon(Icons.sync, size: 16),
          onPressed: pendingRows.isEmpty && widget.pending.isEmpty
              ? null
              : () {
                  if (widget.pending.isEmpty) _queue(pendingRows);
                  widget.onApply();
                },
          child: Text(widget.pending.isEmpty
              ? _t(context, 'mcp_sync_all', '全部同步')
              : _t(context, 'mcp_sync_apply_n', '应用变更 ({n})').replaceAll('{n}', '${widget.pending.length}')),
        ),
      ]),
    );
  }
}

/// 确认面板：列出将写入的文件与条目。返回 true = 确认执行。
Future<bool> showMcpSyncConfirm({
  required BuildContext context,
  required AiToolType tool,
  required String configPath,
  required Map<String, McpSyncAction> pending,
}) async {
  final res = await showDialog<bool>(
    context: context,
    barrierColor: context.kc.overlay,
    builder: (ctx) => McpSyncConfirmSheet(tool: tool, configPath: configPath, pending: pending),
  );
  return res == true;
}

class McpSyncConfirmSheet extends StatelessWidget {
  const McpSyncConfirmSheet({super.key, required this.tool, required this.configPath, required this.pending});
  final AiToolType tool;
  final String configPath;
  final Map<String, McpSyncAction> pending;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    List<String> of(McpSyncAction a) => [for (final e in pending.entries) if (e.value == a) e.key];
    final push = of(McpSyncAction.push), pull = of(McpSyncAction.pull), del = of(McpSyncAction.delete);
    Widget group(IconData icon, String title, String target, List<String> ids, {bool danger = false}) => Padding(
          padding: const EdgeInsets.only(bottom: KcSpace.x3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 16, color: danger ? kc.dangerText : cs.primary),
              const SizedBox(width: 6),
              Text('$title (${ids.length})', style: KcType.strong.copyWith(color: cs.foreground)),
            ]),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(target, style: KcType.mono.copyWith(fontSize: 11.5, color: cs.mutedForeground)),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final id in ids)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(999)),
                    child: Text(id, style: KcType.badge.copyWith(color: cs.foreground)),
                  ),
              ]),
            ),
          ]),
        );
    return Dialog(
      key: const ValueKey('mcpSync.confirm'),
      backgroundColor: cs.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KcRadius.dialog), side: BorderSide(color: cs.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(KcSpace.page),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              KcToolLogo(tool: tool, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_t(context, 'mcp_sync_confirm_title', '确认同步到 {tool}').replaceAll('{tool}', tool.displayName),
                    style: KcType.title.copyWith(color: cs.foreground)),
              ),
            ]),
            const SizedBox(height: KcSpace.x4),
            if (push.isNotEmpty) group(Icons.upload_outlined, _t(context, 'mcp_sync_push', '推送到工具'), configPath, push),
            if (del.isNotEmpty) group(Icons.delete_outline, _t(context, 'mcp_sync_delete', '从工具删除'), configPath, del, danger: true),
            if (pull.isNotEmpty) group(Icons.download_outlined, _t(context, 'mcp_sync_pull', '拉入 key-core'), _t(context, 'mcp_sync_kc_db', 'key-core 本地数据库'), pull),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kc.warnSoft, borderRadius: BorderRadius.circular(8)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 15, color: kc.warnText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _t(context, 'mcp_sync_backup_note', '只会改写上述文件中的 MCP 服务条目；key-core 不会自动备份该文件，如有手工改动建议先自行备份。'),
                    style: KcType.caption.copyWith(color: kc.warnText, height: 1.45),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: KcSpace.x5),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              ShadButton.outline(onPressed: () => Navigator.of(context).pop(false), child: Text(_t(context, 'cancel_btn', '取消'))),
              const SizedBox(width: 8),
              ShadButton(
                key: const ValueKey('mcpSync.confirm.ok'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(_t(context, 'mcp_sync_confirm_ok', '同步 {n} 项').replaceAll('{n}', '${pending.length}')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
