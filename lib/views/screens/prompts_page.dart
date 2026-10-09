import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mcp_server.dart';
import '../../models/prompt.dart';
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
    showKcToast(context, ok ? success : '失败：${vm.errorMessage ?? '未知错误'}', kind: ok ? KcToastKind.success : KcToastKind.error);
  }

  Future<void> _edit(BuildContext context, PromptsViewModel vm, [Prompt? prompt]) async {
    final name = TextEditingController(text: prompt?.name ?? '');
    final content = TextEditingController(text: prompt?.content ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prompt == null ? '新建提示词' : '编辑提示词'),
        content: SizedBox(
          width: 640,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '名称')),
            const SizedBox(height: 12),
            TextField(
              controller: content,
              minLines: 12,
              maxLines: 20,
              decoration: const InputDecoration(labelText: '内容（Markdown）', alignLabelWithHint: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && context.mounted) {
      final saved = await vm.save(id: prompt?.id, name: name.text.trim(), content: content.text);
      if (context.mounted) _toast(context, vm, saved, '已保存');
    }
    name.dispose();
    content.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PromptsViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统提示词'),
        actions: [
          IconButton(
            tooltip: '从当前文件导入',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: vm.liveFileExists
                ? () async {
                    final ok = await vm.importFromFile();
                    if (context.mounted) _toast(context, vm, ok, '已导入');
                  }
                : null,
          ),
          IconButton(tooltip: '新建', icon: const Icon(Icons.add), onPressed: () => _edit(context, vm)),
        ],
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
                ? const Center(child: Text('暂无提示词。启用某条提示词后，它会写入上面的文件。'))
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
                                  if (context.mounted) _toast(context, vm, ok, v ? '已启用并写入文件' : '已停用');
                                },
                              ),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  tooltip: '编辑',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _edit(context, vm, p),
                                ),
                                IconButton(
                                  tooltip: p.enabled ? '启用中的提示词不能删除' : '删除',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: p.enabled
                                      ? null
                                      : () async {
                                          final ok = await vm.delete(p);
                                          if (context.mounted) _toast(context, vm, ok, '已删除');
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
