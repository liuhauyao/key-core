import 'package:flutter/services.dart';
import '../widgets/kc_manage_scaffold.dart';
import '../../theme/kc_tokens.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mcp_server.dart';
import '../../models/prompt.dart';
import '../widgets/kc_window_header.dart';
import '../../utils/app_localizations.dart';
import '../widgets/kc_toast.dart';
import '../../viewmodels/prompts_viewmodel.dart';

/// 系统提示词管理（CLAUDE.md / AGENTS.md / GEMINI.md / SOUL.md）。
/// 最小 UI：工具切换 + 列表 + 启用开关 + 编辑/删除/导入，全部使用现有 Material 组件。
class PromptsPage extends StatelessWidget {
  const PromptsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PromptsViewModel()..init(),
      child: const _PromptsView(),
    );
  }
}

class _PromptsView extends StatelessWidget {
  const _PromptsView();

  void _toast(BuildContext context, PromptsViewModel vm, bool ok, String success) {
    showKcToast(context, ok ? success : '${_l(context, 'op_failed', '失败')}：${vm.errorMessage ?? _l(context, 'unknown_error', '未知错误')}', kind: ok ? KcToastKind.success : KcToastKind.error);
  }

  Future<void> _edit(BuildContext context, PromptsViewModel vm, [Prompt? prompt]) async {
    final name = TextEditingController(text: prompt?.name ?? '');
    final content = TextEditingController(text: prompt?.content ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prompt == null ? _l(context, 'prompt_new', '新建提示词') : _l(context, 'prompt_edit', '编辑提示词')),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: _l(context, 'name_label', '名称'))),
            const SizedBox(height: 12),
            TextField(
              controller: content,
              minLines: 12,
              maxLines: 20,
              decoration: InputDecoration(labelText: _l(context, 'content_md', '内容（Markdown）'), alignLabelWithHint: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_l(context, 'cancel_btn', '取消'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_l(context, 'save_btn', '保存'))),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && context.mounted) {
      final saved = await vm.save(id: prompt?.id, name: name.text.trim(), content: content.text);
      if (context.mounted) _toast(context, vm, saved, _l(context, 'saved', '已保存'));
    }
    name.dispose();
    content.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PromptsViewModel>();
    // Esc 关闭（与其它全页一致）
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: KcWindowHeader(
        title: AppLocalizations.of(context)?.tr('prompts_title', '系统提示词') ?? '系统提示词',
        actions: [
          IconButton(
            tooltip: _l(context, 'prompt_import_current', '从当前文件导入'),
            icon: const Icon(Icons.file_download_outlined),
            onPressed: vm.liveFileExists
                ? () async {
                    final ok = await vm.importFromFile();
                    if (context.mounted) _toast(context, vm, ok, _l(context, 'imported', '已导入'));
                  }
                : null,
          ),
          IconButton(tooltip: _l(context, 'new_btn', '新建'), icon: const Icon(Icons.add), onPressed: () => _edit(context, vm)),
        ],
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Builder(builder: (context) {
        final cs = ShadTheme.of(context).colorScheme;
        final kc = context.kc;
        // 与钥匙包 / MCP / Skills 同一语言：筛选行（工具弹出菜单 + 目标文件路径）+ 分组卡片列表
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, KcSpace.x3),
            child: Row(children: [
              KcFilterMenuButton<AiToolType>(
                key: const ValueKey('prompts.tool'),
                label: vm.tool.displayName,
                selected: vm.tool,
                onSelected: vm.selectTool,
                items: [for (final t in vm.tools) (t, t.displayName, null)],
              ),
              const SizedBox(width: KcSpace.x3),
              Icon(Icons.description_outlined, size: 15, color: kc.text2),
              const SizedBox(width: 4),
              Expanded(
                child: Text(vm.filePath ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.mono.copyWith(fontSize: 12, color: kc.text2)),
              ),
            ]),
          ),
          if (vm.isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: vm.prompts.isEmpty
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.notes_outlined, size: 40, color: kc.text2.withValues(alpha: 0.5)),
                      const SizedBox(height: KcSpace.x3),
                      Text(_l(context, 'prompts_empty', '暂无提示词。启用某条提示词后，它会写入上面的文件。'), style: KcType.body.copyWith(color: kc.text2)),
                      const SizedBox(height: KcSpace.x4),
                      ShadButton(leading: const Icon(Icons.add, size: 16), onPressed: () => _edit(context, vm), child: Text(_l(context, 'new_btn', '新建'))),
                    ]),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(KcSpace.page, 0, KcSpace.page, KcSpace.x6),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: cs.card,
                          borderRadius: BorderRadius.circular(KcRadius.panel),
                          border: Border.all(color: cs.border),
                        ),
                        child: Column(children: [
                          for (final (i, p) in vm.prompts.indexed) ...[
                            if (i > 0) Divider(height: 1, thickness: 1, indent: KcSpace.x4, color: cs.border),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: KcSpace.x4, vertical: KcSpace.x3),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(p.name, style: KcType.strong.copyWith(color: cs.foreground)),
                                    const SizedBox(height: 2),
                                    Text(p.content.replaceAll('\n', ' '), maxLines: 2, overflow: TextOverflow.ellipsis, style: KcType.caption.copyWith(color: kc.text2)),
                                  ]),
                                ),
                                const SizedBox(width: KcSpace.x3),
                                IconButton(
                                  tooltip: _l(context, 'edit_btn', '编辑'),
                                  icon: Icon(Icons.edit_outlined, size: 17, color: kc.text2),
                                  onPressed: () => _edit(context, vm, p),
                                ),
                                IconButton(
                                  tooltip: p.enabled ? _l(context, 'prompt_cant_delete_enabled', '启用中的提示词不能删除') : _l(context, 'delete_btn', '删除'),
                                  icon: Icon(Icons.delete_outline, size: 17, color: p.enabled ? kc.text2.withValues(alpha: 0.5) : kc.dangerText),
                                  onPressed: p.enabled
                                      ? null
                                      : () async {
                                          final ok = await vm.delete(p);
                                          if (context.mounted) _toast(context, vm, ok, _l(context, 'deleted', '已删除'));
                                        },
                                ),
                                const SizedBox(width: KcSpace.x2),
                                Switch(
                                  value: p.enabled,
                                  activeTrackColor: cs.primary,
                                  onChanged: (v) async {
                                    final ok = await vm.setEnabled(p, v);
                                    if (context.mounted) _toast(context, vm, ok, v ? _l(context, 'prompt_enabled_written', '已启用并写入文件') : _l(context, 'disabled', '已停用'));
                                  },
                                ),
                              ]),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ),
          ),
        ]);
      }),
    ),
      ),
    );
  }
}

String _l(BuildContext c, String k, String zh) => AppLocalizations.of(c)?.tr(k, zh) ?? zh;
