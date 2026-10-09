import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reorderables/reorderables.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../models/mcp_server.dart';
import '../widgets/kc_manage_scaffold.dart';
import '../widgets/kc_logo.dart';
import '../widgets/kc_drawer.dart';
import '../widgets/kc_segmented.dart';
import '../../theme/kc_tokens.dart';
import '../widgets/mcp_card.dart';
import '../widgets/confirm_dialog.dart';
import 'mcp_sync_page.dart';
import 'mcp_form_page.dart';
import '../../utils/app_localizations.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import '../widgets/kc_toast.dart';
import '../../services/mcp_sync_service.dart';
import '../../viewmodels/settings_viewmodel.dart';
import 'dart:convert';

/// MCP 配置管理页面
class McpConfigScreen extends StatefulWidget {
  const McpConfigScreen({super.key});

  @override
  State<McpConfigScreen> createState() => _McpConfigScreenState();
}

class _McpConfigScreenState extends State<McpConfigScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isEditMode = false;
  final Set<int> _selectedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<McpViewModel>().init();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: Consumer<McpViewModel>(
        builder: (context, viewModel, child) {
          return Column(
            children: [
              _buildHeader(context, viewModel),
              // MCP 服务器列表
              Expanded(
                child: viewModel.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: shadTheme.colorScheme.primary,
                        ),
                      )
                    : _visible(viewModel).isEmpty && _filter == null
                        ? _buildEmptyState(context, viewModel)
                        : Stack(children: [
                            Positioned.fill(child: _buildServerList(context, viewModel, _isEditMode)),
                            if (_isEditMode)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 16,
                                child: Center(child: _buildSelectionBar(context, viewModel)),
                              ),
                          ]),
              ),
            ],
          );
        },
      ),
    );
  }

  /// null = 全部；true = 已启用；false = 已停用。管理（排序）模式下始终显示全部，避免按过滤结果重排
  bool? _filter;
  List<McpServer> _visible(McpViewModel vm) =>
      (_filter == null || _isEditMode) ? vm.servers : vm.servers.where((s) => s.isActive == _filter).toList();

  Widget _buildHeader(BuildContext context, McpViewModel viewModel) {
    final l = AppLocalizations.of(context);
    String t(String k, String f) => l?.tr(k, f) ?? f;
    final icon = KcPageHeader.iconButton;
    final all = viewModel.servers;
    final on = all.where((s) => s.isActive).length;
    final header = KcPageHeader(
      title: 'MCP',
      subtitle: t('mcp_subtitle', '{n} 个服务 · {m} 个已启用').replaceAll('{n}', '${all.length}').replaceAll('{m}', '$on'),
      manageSubtitle: t('manage_subtitle_mcp', '管理模式 · 拖动排序，勾选后批量操作'),
      manage: _isEditMode,
      searchKey: const ValueKey('mcp.search'),
      searchController: _searchController,
      searchHint: l?.mcpSearchPlaceholder ?? '搜索 MCP 服务器...',
      onSearch: (q) => viewModel.setSearchQuery(q),
      actions: [
        icon(context,
            key: const ValueKey('mcp.manageToggle'),
            icon: _isEditMode ? Icons.check : Icons.drag_indicator,
            tip: _isEditMode ? (l?.mcpFinishEdit ?? '完成编辑') : t('manage_tip', '管理：排序 / 批量操作'),
            active: _isEditMode,
            onPressed: () => _isEditMode ? _exitManage() : setState(() => _isEditMode = true)),
        icon(context, key: const ValueKey('mcp.diff'), icon: Icons.compare_arrows, tip: l?.mcpSync ?? '对比与同步', onPressed: () => _showSyncDialog(context)),
        Padding(
          padding: const EdgeInsets.only(left: KcSpace.x2),
          child: PopupMenuButton<String>(
            key: const ValueKey('mcp.moreMenu'),
            tooltip: t('more', '更多'),
            position: PopupMenuPosition.under,
            onSelected: (v) {
              switch (v) {
                case 'import':
                  _importFromEnabledTools(context, viewModel);
                case 'sync':
                  _syncAllEnabled(context, viewModel);
                case 'diff':
                  _showSyncDialog(context);
                case 'refresh':
                  viewModel.refresh();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, height: 28, child: Text(t('menu_group_sync', '同步'), style: KcType.caption)),
              PopupMenuItem(value: 'diff', child: Text(t('mcp_menu_diff', '对比与同步…'))),
              PopupMenuItem(value: 'sync', child: Text(t('mcp_menu_rewrite', '重新写入全部已启用的服务'))),
              const PopupMenuDivider(),
              PopupMenuItem(enabled: false, height: 28, child: Text(t('menu_group_import', '导入'), style: KcType.caption)),
              PopupMenuItem(value: 'import', child: Text(t('mcp_menu_import', '从已启用的工具导入'))),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'refresh', child: Text(l?.refreshKeyList ?? '刷新')),
            ],
            child: IgnorePointer(child: icon(context, icon: Icons.more_horiz, tip: '', onPressed: () {})),
          ),
        ),
      ],
      primary: _isEditMode
          ? ShadButton(
              key: const ValueKey('mcp.done'),
              height: KcSize.control,
              width: 112,
              leading: const Icon(Icons.check, size: 16),
              onPressed: _exitManage,
              child: Text(t('done', '完成')),
            )
          : ShadButton(
              key: const ValueKey('mcp.add'),
              height: KcSize.control,
              width: 112,
              leading: const Icon(Icons.add, size: 16),
              onPressed: () => _showAddMcpPage(context),
              child: Text(t('mcp_add_short', '添加服务'), maxLines: 1, overflow: TextOverflow.clip),
            ),
    );
    if (all.isEmpty) return header;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      header,
      Padding(
        padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, 0),
        child: Row(children: [
          KcSegmented<bool?>(
            key: const ValueKey('mcp.statusFilter'),
            value: _isEditMode ? null : _filter,
            onChanged: (v) => setState(() => _filter = v),
            items: [
              (null, t('segment_all', '全部'), all.length),
              (true, t('mcp_seg_on', '已启用'), on),
              (false, t('mcp_seg_off', '已停用'), all.length - on),
            ],
          ),
        ]),
      ),
    ]);
  }

  Widget _buildEmptyState(BuildContext context, McpViewModel viewModel) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    if (viewModel.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 16),
            Text(
              localizations?.mcpNoSearchResults ?? '未找到匹配的 MCP 服务器',
              style: shadTheme.textTheme.h4.copyWith(
                color: shadTheme.colorScheme.foreground,
              ),
            ),
          ],
        ),
      );
    }

    // 空状态（form_v3.md §7）：说明 MCP 是什么 + 两个直接动作（添加 / 从已启用的工具导入）
    final kc = context.kc;
    String t(String k, String f) => localizations?.tr(k, f) ?? f;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          KcLogoBox(size: 56, child: Icon(Icons.dns_outlined, size: 28, color: kc.actionText)),
          const SizedBox(height: KcSpace.x4),
          Text(localizations?.mcpNoServers ?? '暂无 MCP 服务器', style: KcType.title.copyWith(color: shadTheme.colorScheme.foreground)),
          const SizedBox(height: KcSpace.x2),
          Text(
            t('mcp_empty_desc', 'MCP 服务器为 Claude Code、Codex、Cursor 等工具提供额外能力（文件系统、浏览器、数据库…）。在这里统一添加一次，再按工具启用即可。'),
            textAlign: TextAlign.center,
            style: KcType.body.copyWith(color: kc.text2, height: 1.5),
          ),
          const SizedBox(height: KcSpace.x5),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ShadButton(
              key: const ValueKey('mcp.empty.add'),
              leading: const Icon(Icons.add, size: 16),
              onPressed: () => _showAddMcpPage(context),
              child: Text(t('mcp_add_short', '添加服务')),
            ),
            const SizedBox(width: KcSpace.x2),
            ShadButton.outline(
              key: const ValueKey('mcp.empty.import'),
              leading: const Icon(Icons.download_outlined, size: 16),
              onPressed: () => _importFromEnabledTools(context, viewModel),
              child: Text(t('mcp_menu_import', '从已启用的工具导入')),
            ),
          ]),
        ]),
      ),
    );
  }

  void _exitManage() => setState(() {
        _isEditMode = false;
        _selectedIds.clear();
      });

  /// 底部悬浮批量栏：启用 / 停用 · 删除（form_v3.md §13.4）
  Widget _buildSelectionBar(BuildContext context, McpViewModel viewModel) {
    final l10n = AppLocalizations.of(context);
    final all = viewModel.servers.map((s) => s.id).whereType<int>().toSet();
    final sel = _selectedIds.intersection(all);
    final picked = viewModel.servers.where((s) => sel.contains(s.id)).toList();
    final allSelected = all.isNotEmpty && sel.length == all.length;
    Future<void> setActive(bool v) async {
      for (final s in picked) {
        if (s.isActive != v) await viewModel.toggleActive(s.id!, v);
      }
    }

    return KcFloatingSelectionBar(
      selectedCount: sel.length,
      allSelected: allSelected,
      onSelectAll: () => setState(() => allSelected ? _selectedIds.removeAll(all) : _selectedIds.addAll(all)),
      onDone: _exitManage,
      actions: [
        KcBatchAction(icon: Icons.toggle_on_outlined, label: l10n?.tr('enable', '启用') ?? '启用', onPressed: () => setActive(true)),
        KcBatchAction(icon: Icons.toggle_off_outlined, label: l10n?.tr('disable', '停用') ?? '停用', onPressed: () => setActive(false)),
        KcBatchAction(
          key: const ValueKey('mcp.batch.delete'),
          icon: Icons.delete_outline,
          label: l10n?.delete ?? '删除',
          danger: true,
          onPressed: () async {
            final ok = await ConfirmDialog.show(
              context: context,
              title: l10n?.confirmDelete ?? '确认删除',
              message: (l10n?.tr('batch_delete_mcp_confirm', '确定要删除选中的 {n} 个 MCP 服务器吗？') ?? '确定要删除选中的 {n} 个 MCP 服务器吗？')
                  .replaceAll('{n}', '${picked.length}'),
              confirmText: l10n?.delete ?? '删除',
              isDangerous: true,
            );
            if (ok != true) return;
            for (final s in picked) {
              await viewModel.deleteServer(s.id!);
            }
            setState(() => _selectedIds.removeAll(picked.map((s) => s.id)));
          },
        ),
      ],
    );
  }

  Widget _buildServerList(
    BuildContext context,
    McpViewModel viewModel,
    bool isEditMode,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minCardWidth = 240; // 减小最小宽度，让一列显示更多卡片
        const double cardSpacing = 10;
        const double padding = 16;
        const double cardHeight = 140; // 固定卡片高度

        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, 5);

        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }

        final servers = List<McpServer>.from(_visible(viewModel));

        // 构建卡片列表
        final cardWidgets = servers.map((server) {
          return KcSelectableCard(
            key: ValueKey('sel-${server.id}'),
            manage: isEditMode,
            selected: _selectedIds.contains(server.id),
            checkKey: ValueKey('mcpCard.select.${server.id}'),
            onSelect: (v) => setState(() => v ? _selectedIds.add(server.id!) : _selectedIds.remove(server.id)),
            child: McpCard(
            key: ValueKey(server.id), // 使用稳定的key，不包含isActive状态
            server: server,
            isEditMode: isEditMode,
            onTap: () => _showMcpDetails(context, server),
            onEdit: () => _showEditMcpPage(context, server, viewModel),
            onDelete: () => _deleteServer(context, server, viewModel),
            onToggleActive: (isActive) => _toggleActive(context, server, isActive, viewModel),
            onViewDetails: () => _showMcpDetails(context, server),
            onManageApps: () => _showServerAppsDialog(context, server, viewModel),
            enabledTools: viewModel.serverApps[server.serverId] ?? const <AiToolType>{},
            onOpenHomepage: server.homepage != null && server.homepage!.isNotEmpty
                ? () => UrlLauncherService().openUrl(server.homepage!)
                : null,
            onOpenDocs: server.docs != null && server.docs!.isNotEmpty
                ? () => UrlLauncherService().openUrl(server.docs!)
                : null,
          ));
        }).toList();

        // 编辑模式下使用 ReorderableWrap
        if (isEditMode) {
          // 与网格同样的 padding；底部为悬浮批量栏预留（form_v3.md §13.4）
          return SingleChildScrollView(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(padding, padding, padding, padding + kcFloatingBarReserve),
            child: ReorderableWrap(
              spacing: cardSpacing,
              runSpacing: cardSpacing,
              needsLongPressDraggable: false, // 禁用长按拖动，允许直接拖动
              onReorder: (oldIndex, newIndex) {
                // ReorderableWrap 的索引计算
                // 根据官方示例，ReorderableWrap 的 newIndex 已经是正确的插入位置
                // 不需要再调整
                final reorderedServers = List<McpServer>.from(viewModel.servers);
                
                // 先移除拖动项
                final draggedServer = reorderedServers.removeAt(oldIndex);
                
                // 直接使用 newIndex 作为插入位置
                // ReorderableWrap 已经处理了索引调整
                final insertIndex = newIndex.clamp(0, reorderedServers.length);
                
                reorderedServers.insert(insertIndex, draggedServer);
                viewModel.reorderServers(reorderedServers);
              },
              onNoReorder: (index) {
                // 拖动取消时的回调
              },
              children: cardWidgets.asMap().entries.map((entry) {
                final index = entry.key;
                final card = entry.value;
                return SizedBox(
                  key: ValueKey(servers[index].id),
                  width: cardWidth,
                  height: cardHeight,
                  child: card,
                );
              }).toList(),
            ),
          ));
        }

        // 非编辑模式使用普通 GridView
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
            childAspectRatio: (cardWidth / cardHeight), // 固定高度，动态宽度
          ),
          itemCount: cardWidgets.length,
          itemBuilder: (context, index) => cardWidgets[index],
        );
      },
    );
  }

  Future<void> _showAddMcpPage(BuildContext context) async {
    final viewModel = context.read<McpViewModel>();
    final localizations = AppLocalizations.of(context);

    final result = await Navigator.of(context).push<McpServer>(
      MaterialPageRoute(
        builder: (context) => const McpFormPage(),
      ),
    );

    if (result != null) {
      final success = await viewModel.addServer(result);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      if (success) {
        _showSnackBar(context, localizations?.mcpServerAdded ?? 'MCP 服务器添加成功');
      } else {
        _showSnackBar(
          context,
          viewModel.errorMessage ?? (localizations?.mcpAddFailed ?? '添加失败'),
          isError: true,
        );
      }
    }
  }

  Future<void> _showEditMcpPage(
    BuildContext context,
    McpServer server,
    McpViewModel viewModel,
  ) async {
    final localizations = AppLocalizations.of(context);

    final result = await Navigator.of(context).push<McpServer>(
      MaterialPageRoute(
        builder: (context) => McpFormPage(editingServer: server),
      ),
    );

    if (result != null) {
      final success = await viewModel.updateServer(result);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      if (success) {
        showKcToast(this.context, localizations?.mcpServerUpdated ?? 'MCP 服务器更新成功', kind: KcToastKind.success);
      } else {
        showKcToast(this.context, viewModel.errorMessage ?? (localizations?.mcpUpdateFailed ?? '更新失败'), kind: KcToastKind.error);
      }
    }
  }

  Future<void> _deleteServer(
    BuildContext context,
    McpServer server,
    McpViewModel viewModel,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: localizations?.confirmDelete ?? '确认删除',
      message: localizations?.mcpDeleteConfirmMessage(server.name) ?? 
          '确定要删除 MCP 服务器"${server.name}"吗？此操作不可撤销。',
      confirmText: localizations?.delete ?? '删除',
    );

    if (confirmed == true) {
      final success = await viewModel.deleteServer(server.id!);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      
      // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在下一帧显示 SnackBar
      // 这样可以避免在 widget 重建过程中访问失效的 context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return; // 再次检查
        if (success) {
          _showSnackBarSafe(context, localizations?.mcpServerDeleted ?? 'MCP 服务器已删除');
        } else {
          _showSnackBarSafe(
            context,
            viewModel.errorMessage ?? (localizations?.mcpDeleteFailed ?? '删除失败'),
            isError: true,
          );
        }
      });
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    McpServer server,
    bool isActive,
    McpViewModel viewModel,
  ) async {
    final success = await viewModel.toggleActive(server.id!, isActive);
    if (!mounted) return; // 检查 widget 是否仍然挂载
    final localizations = AppLocalizations.of(context);
    if (success) {
      _showSnackBar(
        context,
        isActive 
            ? (localizations?.mcpServerActivated ?? 'MCP 服务器已激活')
            : (localizations?.mcpServerDeactivated ?? 'MCP 服务器已停用'),
      );
    } else {
      _showSnackBar(
        context,
        viewModel.errorMessage ?? (localizations?.mcpOperationFailed ?? '操作失败'),
        isError: true,
      );
    }
  }

  /// 已启用、可作为 MCP 同步目标的工具
  List<AiToolType> _mcpTools(BuildContext context) {
    final enabled = context.read<SettingsViewModel>().getEnabledTools().toSet();
    return McpSyncService.mcpTargetTools.where(enabled.contains).toList();
  }

  /// 按工具启用：每个工具一个开关，切换后立即写入该工具的配置
  Future<void> _showServerAppsDialog(BuildContext context, McpServer server, McpViewModel viewModel) async {
    // 按工具启用 sheet（form_v3.md §7）：列出**全部** MCP 目标工具；设置里未启用的置灰并提示去哪开启。
    final enabledInSettings = context.read<SettingsViewModel>().getEnabledTools().toSet();
    final all = McpSyncService.mcpTargetTools;
    final l = AppLocalizations.of(context);
    final busy = <AiToolType>{};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final cs = ShadTheme.of(dialogContext).colorScheme;
          final kc = dialogContext.kc;
          final enabled = viewModel.serverApps[server.serverId] ?? const <AiToolType>{};
          final onCount = all.where(enabled.contains).length;
          return Dialog(
            key: const ValueKey('mcpApps.sheet'),
            backgroundColor: cs.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KcRadius.dialog)),
            child: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${server.name} · ${l?.tr('mcp_enable_per_tool', '按工具启用') ?? '按工具启用'}',
                            style: KcType.title.copyWith(color: cs.foreground)),
                        const SizedBox(height: 2),
                        Text((l?.tr('mcp_enable_summary', '已在 {n} / {total} 个工具启用 · 切换后立即写入该工具配置') ?? '已在 {n} / {total} 个工具启用 · 切换后立即写入该工具配置')
                                .replaceAll('{n}', '$onCount').replaceAll('{total}', '${all.length}'),
                            style: KcType.caption.copyWith(color: kc.text2)),
                      ]),
                    ),
                    IconButton(
                      key: const ValueKey('mcpApps.close'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: Icon(Icons.close, size: 18, color: kc.text2),
                    ),
                  ]),
                ),
                Divider(height: 1, color: cs.border),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.62),
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 6), children: [
                    for (final tool in all)
                      Builder(builder: (_) {
                        final avail = enabledInSettings.contains(tool);
                        final on = enabled.contains(tool);
                        return Opacity(
                          opacity: avail ? 1 : 0.5,
                          child: SizedBox(
                            key: ValueKey('mcpApps.tool.${tool.value}'),
                            height: 44,
                            child: Row(children: [
                              const SizedBox(width: 20),
                              KcToolLogo(tool: tool, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(kcToolName(tool), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: KcType.strong.copyWith(color: cs.foreground)),
                              ),
                              if (!avail)
                                Text(l?.tr('enable_in_settings_hint', '在 设置 › 工具配置 中开启') ?? '在 设置 › 工具配置 中开启',
                                    style: KcType.caption.copyWith(color: kc.text2))
                              else if (busy.contains(tool))
                                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                Switch.adaptive(
                                  value: on,
                                  onChanged: (v) async {
                                    setDialogState(() => busy.add(tool));
                                    final ok = await viewModel.setServerEnabledForTool(server, tool, v);
                                    busy.remove(tool);
                                    if (!ok && context.mounted) {
                                      _showSnackBarSafe(context, viewModel.errorMessage ?? (l?.tr('write_failed', '写入失败') ?? '写入失败'), isError: true);
                                    }
                                    if (dialogContext.mounted) setDialogState(() {});
                                  },
                                ),
                              const SizedBox(width: 16),
                            ]),
                          ),
                        );
                      }),
                  ]),
                ),
                Divider(height: 1, color: cs.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: Text(l?.tr('mcp_enable_footer', '停用会从该工具的配置中移除此服务') ?? '停用会从该工具的配置中移除此服务',
                          style: KcType.caption.copyWith(color: kc.text2)),
                    ),
                    ShadButton(
                      height: KcSize.control,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(l?.tr('done', '完成') ?? '完成'),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _importFromEnabledTools(BuildContext context, McpViewModel viewModel) async {
    final r = await viewModel.importFromTools(_mcpTools(context));
    if (!context.mounted || r == null) return;
    final linked = r.linked.values.fold<int>(0, (a, b) => a + b.length);
    final l = AppLocalizations.of(context);
    var msg = (l?.tr('mcp_import_result', '新增 {a} 个服务，记录 {b} 条启用关系') ?? '新增 {a} 个服务，记录 {b} 条启用关系')
        .replaceAll('{a}', '${r.added.length}').replaceAll('{b}', '$linked');
    if (r.failed.isNotEmpty) {
      msg += (l?.tr('mcp_import_failed_suffix', '，失败 {n} 个') ?? '，失败 {n} 个').replaceAll('{n}', '${r.failed.length}');
    }
    _showSnackBarSafe(context, msg);
  }

  Future<void> _syncAllEnabled(BuildContext context, McpViewModel viewModel) async {
    final r = await viewModel.syncAllEnabled();
    if (!context.mounted) return;
    final failed = r.entries.where((e) => !e.value).map((e) => e.key.displayName).toList();
    final l = AppLocalizations.of(context);
    _showSnackBarSafe(
        context,
        failed.isEmpty
            ? (l?.tr('mcp_written_n', '已写入 {n} 个工具') ?? '已写入 {n} 个工具').replaceAll('{n}', '${r.length}')
            : '${l?.tr('write_failed', '写入失败') ?? '写入失败'}：${failed.join('、')}',
        isError: failed.isNotEmpty);
  }

  void _showSyncDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const McpSyncPage(),
      ),
    );
  }

  void _showMcpDetails(BuildContext context, McpServer server) {
    showKcDrawer(
      context: context,
      builder: (context) => _McpDetailsDialog(
        server: server,
        onEdit: () {
          Navigator.pop(context);
          _showEditMcpPage(context, server, context.read<McpViewModel>());
        },
        onCopyJson: () {
          final jsonConfig = _generateJsonConfig(server);
          ClipboardService().copyToClipboard(jsonConfig);
          final loc = AppLocalizations.of(context);
          _showSnackBar(context, loc?.mcpJsonCopied ?? 'JSON配置已复制');
        },
        onOpenHomepage: server.homepage != null && server.homepage!.isNotEmpty
            ? () => UrlLauncherService().openUrl(server.homepage!)
            : null,
        onOpenDocs: server.docs != null && server.docs!.isNotEmpty
            ? () => UrlLauncherService().openUrl(server.docs!)
            : null,
      ),
    );
  }

  String _generateJsonConfig(McpServer server) {
    final config = <String, dynamic>{};
    
    if (server.serverType == McpServerType.stdio) {
      if (server.command != null && server.command!.isNotEmpty) {
        config['command'] = server.command;
      }
      if (server.args != null && server.args!.isNotEmpty) {
        config['args'] = server.args;
      }
      if (server.env != null && server.env!.isNotEmpty) {
        config['env'] = server.env;
      }
      if (server.cwd != null && server.cwd!.isNotEmpty) {
        config['cwd'] = server.cwd;
      }
    } else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) {
      if (server.url != null && server.url!.isNotEmpty) {
        config['url'] = server.url;
      }
      if (server.headers != null && server.headers!.isNotEmpty) {
        config['headers'] = server.headers;
      }
    }
    
    final jsonWithId = <String, dynamic>{
      server.serverId: config,
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    if (!mounted) return; // 检查 widget 是否仍然挂载
    showKcToast(context, message, kind: isError ? KcToastKind.error : KcToastKind.success);
  }

  /// 安全地显示 SnackBar，避免在 widget 销毁时访问失效的 context
  void _showSnackBarSafe(BuildContext context, String message, {bool isError = false}) {
    if (!mounted) return; // 检查 widget 是否仍然挂载
    showKcToast(this.context, message, kind: isError ? KcToastKind.error : KcToastKind.success);
  }

}

/// MCP 服务器详情弹窗
class _McpDetailsDialog extends StatelessWidget {
  final McpServer server;
  final VoidCallback onEdit;
  final VoidCallback onCopyJson;
  final VoidCallback? onOpenHomepage;
  final VoidCallback? onOpenDocs;

  const _McpDetailsDialog({
    required this.server,
    required this.onEdit,
    required this.onCopyJson,
    this.onOpenHomepage,
    this.onOpenDocs,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    
    // 统一抽屉（kc_drawer.dart）：实色面板 + 统一页头 + 固定底栏
    return KcDrawerSurface(
      key: const ValueKey('mcpDetails.sheet'),
      header: KcDrawerHeader(
        leading: KcLogoBox(
          child: SvgPicture.asset('assets/icons/platforms/${server.icon ?? 'mcp.svg'}', width: 22, height: 22, allowDrawingOutsideViewBox: true),
        ),
        title: Text(server.name),
        subtitle: Text('${server.serverId} · ${server.serverType.value.toUpperCase()}'),
      ),
      body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      context,
                      localizations?.mcpServerIdLabel ?? '服务器ID',
                      server.serverId,
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      context,
                      localizations?.mcpServerType ?? '服务器类型',
                      server.serverType.value.toUpperCase(),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      context,
                      localizations?.mcpStatus ?? '状态',
                      server.isActive
                          ? (localizations?.mcpActive ?? '已激活')
                          : (localizations?.mcpInactive ?? '未激活'),
                    ),
                    const SizedBox(height: 10),
                    // 根据服务器类型显示不同字段
                    if (server.serverType == McpServerType.stdio) ...[
                      if (server.command != null && server.command!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpCommandLabel ?? '命令',
                          server.command!,
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.args != null && server.args!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpArgsLabel ?? '参数',
                          server.args!.join(' '),
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.env != null && server.env!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpEnv ?? '环境变量',
                          server.env!.entries.map((e) => '${e.key}=${e.value}').join('\n'),
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.cwd != null && server.cwd!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpCwd ?? '工作目录',
                          server.cwd!,
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ] else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) ...[
                      if (server.url != null && server.url!.isNotEmpty) ...[
                        _buildActionRow(
                          context,
                          localizations?.mcpUrlLabel ?? 'URL',
                          server.url!,
                          Icons.language,
                          localizations?.open ?? '打开',
                          () {
                            if (server.url != null) {
                              UrlLauncherService().openUrl(server.url!);
                            }
                          },
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.headers != null && server.headers!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpHeaders ?? '请求头',
                          server.headers!.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    // 管理地址
                    if (onOpenHomepage != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.mcpHomepage ?? '管理地址',
                        server.homepage!,
                        Icons.language,
                        localizations?.open ?? '打开',
                        onOpenHomepage!,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 文档地址
                    if (onOpenDocs != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.mcpDocs ?? '文档地址',
                        server.docs!,
                        Icons.description_outlined,
                        localizations?.open ?? '打开',
                        onOpenDocs!,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 描述
                    if (server.description != null && server.description!.isNotEmpty) ...[
                      _buildDetailRow(
                        context,
                        localizations?.mcpDescription ?? '描述',
                        server.description!,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 标签
                    if (server.tags != null && server.tags!.isNotEmpty) ...[
                      _buildDetailRow(
                        context,
                        localizations?.mcpTags ?? '标签',
                        server.tags!.join(', '),
                      ),
                      const SizedBox(height: 10),
                    ],
                    // JSON配置
                    _buildJsonConfigRow(context),
                    const SizedBox(height: 10),
                    // 创建时间和更新时间在同一行
                    _buildTimeRow(
                      context,
                      localizations?.createdTime ?? '创建时间',
                      _formatDateTime(server.createdAt),
                      localizations?.updatedTime ?? '更新时间',
                      _formatDateTime(server.updatedAt),
                    ),
                  ],
                ),
              ),
      footer: KcDrawerFooter(
        leading: [
          if (onOpenHomepage != null)
            ShadButton.ghost(leading: const Icon(Icons.language, size: 16), onPressed: onOpenHomepage, child: Text(localizations?.openManagementUrl ?? '管理地址')),
          if (onOpenDocs != null)
            ShadButton.ghost(leading: const Icon(Icons.description_outlined, size: 16), onPressed: onOpenDocs, child: Text(localizations?.mcpOpenDocs ?? '文档地址')),
        ],
        trailing: [
          ShadButton.outline(
            key: const ValueKey('mcpDetails.copyJson'),
            leading: const Icon(Icons.copy, size: 15),
            onPressed: onCopyJson,
            child: Text(localizations?.tr('copy_json', '复制 JSON') ?? '复制 JSON'),
          ),
          ShadButton(
            key: const ValueKey('mcpDetails.edit'),
            leading: const Icon(Icons.edit_outlined, size: 15),
            onPressed: onEdit,
            child: Text(localizations?.edit ?? '编辑'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {bool isMonospace = false}) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
            fontFamily: isMonospace ? 'monospace' : null,
            fontSize: isMonospace ? 13 : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isMonospace = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.primary,
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontSize: isMonospace ? 13 : null,
                ),
              ),
            ),
            Tooltip(
              message: tooltip,
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                onPressed: onPressed,
                child: Icon(icon, size: 18, color: shadTheme.colorScheme.mutedForeground),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJsonConfigRow(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    final jsonConfig = _generateJsonConfig();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${localizations?.mcpJsonConfigLabel ?? 'JSON配置'}:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  jsonConfig,
                  style: shadTheme.textTheme.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: localizations?.mcpCopyJson ?? '复制JSON配置',
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                onPressed: onCopyJson,
                child: Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRow(
    BuildContext context,
    String createdLabel,
    String createdValue,
    String updatedLabel,
    String updatedValue,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$createdLabel / $updatedLabel:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$createdValue / $updatedValue',
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
          ),
        ),
      ],
    );
  }

  String _generateJsonConfig() {
    final config = <String, dynamic>{};
    
    if (server.serverType == McpServerType.stdio) {
      if (server.command != null && server.command!.isNotEmpty) {
        config['command'] = server.command;
      }
      if (server.args != null && server.args!.isNotEmpty) {
        config['args'] = server.args;
      }
      if (server.env != null && server.env!.isNotEmpty) {
        config['env'] = server.env;
      }
      if (server.cwd != null && server.cwd!.isNotEmpty) {
        config['cwd'] = server.cwd;
      }
    } else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) {
      if (server.url != null && server.url!.isNotEmpty) {
        config['url'] = server.url;
      }
      if (server.headers != null && server.headers!.isNotEmpty) {
        config['headers'] = server.headers;
      }
    }
    
    final jsonWithId = <String, dynamic>{
      server.serverId: config,
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

