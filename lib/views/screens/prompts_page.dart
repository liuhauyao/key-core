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
    return Scaffold(
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              DropdownButton<AiToolType>(
                value: vm.tool,
                onChanged: (t) => t == null ? null : vm.selectTool(t),
                items: vm.tools
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.displayName)))
                    .toList(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(vm.filePath ?? '', overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
          if (vm.isLoading) const LinearProgressIndicator(),
          Expanded(
            child: vm.prompts.isEmpty
                ? Center(child: Text(_l(context, 'prompts_empty', '暂无提示词。启用某条提示词后，它会写入上面的文件。')))
                : ListView(
                    children: vm.prompts
                        .map((p) => ListTile(
                              title: Text(p.name),
                              subtitle: Text(
                                p.content.replaceAll('\n', ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              leading: Switch(
                                value: p.enabled,
                                onChanged: (v) async {
                                  final ok = await vm.setEnabled(p, v);
                                  if (context.mounted) _toast(context, vm, ok, v ? _l(context, 'prompt_enabled_written', '已启用并写入文件') : _l(context, 'disabled', '已停用'));
                                },
                              ),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: _l(context, 'edit_btn', '编辑'),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(context, vm, p),
                                ),
                                IconButton(
                                  tooltip: p.enabled ? _l(context, 'prompt_cant_delete_enabled', '启用中的提示词不能删除') : _l(context, 'delete_btn', '删除'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: p.enabled
                                      ? null
                                      : () async {
                                          final ok = await vm.delete(p);
                                          if (context.mounted) _toast(context, vm, ok, _l(context, 'deleted', '已删除'));
                                        },
                                ),
                              ]),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

String _l(BuildContext c, String k, String zh) => AppLocalizations.of(c)?.tr(k, zh) ?? zh;
