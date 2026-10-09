import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../theme/kc_tokens.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/skill.dart';
import '../../services/skills/skills_backup_service.dart';
import '../../services/skills/skills_fs.dart';
import '../../services/skills/skills_market_service.dart';
import '../../services/skills_path_service.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../widgets/kc_manage_scaffold.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/skill_card.dart';
import '../widgets/skill_details_dialog.dart';
import 'skill_form_page.dart';
import '../widgets/kc_toast.dart';
import 'prompts_page.dart';
import 'skills_sync_page.dart';

class SkillsConfigScreen extends StatefulWidget {
  const SkillsConfigScreen({super.key});

  @override
  State<SkillsConfigScreen> createState() => _SkillsConfigScreenState();
}

class _SkillsConfigScreenState extends State<SkillsConfigScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isEditMode = false;

  // 多选模式
  final Set<int> _selectedSkillIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SkillsViewModel>().init();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSelectMode => _selectedSkillIds.isNotEmpty;

  void _clearSelection() => setState(() => _selectedSkillIds.clear());

  void _toggleSelection(Skill skill) {
    setState(() {
      if (_selectedSkillIds.contains(skill.id)) {
        _selectedSkillIds.remove(skill.id);
      } else {
        if (skill.id != null) _selectedSkillIds.add(skill.id!);
      }
    });
  }

  List<Skill> _getSelectedSkills(SkillsViewModel viewModel) {
    return viewModel.allSkills.where((s) => s.id != null && _selectedSkillIds.contains(s.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: Consumer<SkillsViewModel>(
        builder: (context, viewModel, child) {
          // Sync status bar
          final syncSummary = viewModel.getSyncSummary();

          return Column(
            children: [
              // Toolbar
              _buildToolbar(context, viewModel, shadTheme, localizations, syncSummary),

              // Selection mode bar
              if (_isSelectMode)
                _buildSelectionToolbar(context, viewModel, shadTheme, localizations),

              // Content area
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category sidebar
                    _buildCategorySidebar(context, viewModel, shadTheme, localizations),

                    // Separator
                    Container(width: 1, color: shadTheme.colorScheme.border),

                    // Skill list
                    Expanded(
                      child: viewModel.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : viewModel.skills.isEmpty
                              ? _buildEmptyState(context, viewModel, shadTheme, localizations)
                              : _buildSkillList(context, viewModel, shadTheme),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    SkillsViewModel viewModel,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
    SkillsSyncStatusSummary syncSummary,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.background,
        border: Border(
          bottom: BorderSide(color: shadTheme.colorScheme.border, width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 38,
                  child: ShadInput(
                    controller: _searchController,
                    onChanged: (v) {
                      viewModel.setSearchQuery(v);
                      _clearSelection();
                    },
                    placeholder: Text(localizations?.skillsSearchPlaceholder ?? 'Search skills...'),
                    leading: Icon(Icons.search, size: 18, color: shadTheme.colorScheme.mutedForeground),
                    trailing: _searchController.text.isNotEmpty
                        ? ShadButton.ghost(
                            width: 20,
                            height: 20,
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.transparent,
                            onPressed: () {
                              _searchController.clear();
                              viewModel.setSearchQuery('');
                            },
                            child: Icon(Icons.clear, size: 14, color: shadTheme.colorScheme.mutedForeground),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                height: 38,
                decoration: BoxDecoration(
                  border: Border.all(color: shadTheme.colorScheme.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _toolbarButton(
                      icon: _isEditMode ? Icons.check : Icons.drag_handle,
                      tooltip: _isEditMode
                          ? (localizations?.skillsFinishEdit ?? 'Done')
                          : (localizations?.edit ?? 'Edit'),
                      onPressed: () {
                        setState(() {
                          _isEditMode = !_isEditMode;
                          _clearSelection();
                        });
                      },
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    _toolbarButton(
                      icon: Icons.sync,
                      tooltip: localizations?.skillsSyncAll ?? 'Sync All',
                      onPressed: () => _syncAllSkills(context, viewModel),
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    _toolbarButton(
                      icon: Icons.swap_horiz,
                      tooltip: localizations?.skillsSync ?? 'Sync',
                      onPressed: () => _openSyncPage(context),
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    _toolbarButton(
                      icon: Icons.notes_outlined,
                      tooltip: localizations?.tr('skills_prompts_tooltip', '系统提示词（CLAUDE.md / AGENTS.md 等）') ?? '系统提示词（CLAUDE.md / AGENTS.md 等）',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PromptsPage()),
                      ),
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    // ⋯ 维护菜单（form_v3.md §8）：更新 / 备份 / 设置
                    PopupMenuButton<String>(
                      key: const ValueKey('skills.moreMenu'),
                      tooltip: localizations?.tr('more', '更多') ?? '更多',
                      icon: Icon(Icons.more_horiz, size: 18, color: shadTheme.colorScheme.primary),
                      onSelected: (v) => _onMarketAction(context, viewModel, v),
                      itemBuilder: (_) => [
                        _menuHeader(localizations?.tr('menu_group_maintain', '维护') ?? '维护'),
                        _menuItem('updates', Icons.system_update_alt, localizations?.tr('skills_menu_updates', '检查更新') ?? '检查更新'),
                        _menuItem('backups', Icons.restore, localizations?.tr('skills_menu_backups', '卸载备份与恢复') ?? '卸载备份与恢复'),
                        const PopupMenuDivider(),
                        _menuHeader(localizations?.tr('menu_group_settings', '设置') ?? '设置'),
                        _menuItem('method', Icons.link, localizations?.tr('skills_menu_method', '同步方式') ?? '同步方式'),
                        _menuItem('storage', Icons.folder_outlined, localizations?.tr('skills_menu_storage', '存储位置') ?? '存储位置'),
                      ],
                    ),
                    _divider(shadTheme),
                    _toolbarButton(
                      icon: Icons.refresh,
                      tooltip: localizations?.refreshKeyList ?? 'Refresh',
                      onPressed: () => viewModel.refresh(),
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    // + 分组添加菜单（form_v3.md §8）：新建 / 安装 / 导入
                    PopupMenuButton<String>(
                      key: const ValueKey('skills.addMenu'),
                      tooltip: localizations?.tr('add', '添加') ?? '添加',
                      icon: Icon(Icons.add, size: 18, color: shadTheme.colorScheme.primary),
                      onSelected: (v) => _onMarketAction(context, viewModel, v),
                      itemBuilder: (_) => _addMenuItems(localizations),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Sync status summary
          if (syncSummary.total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _statusChip(AppLocalizations.of(context)?.skillsStatTotal(syncSummary.total) ?? '共 ${syncSummary.total} 个', shadTheme.colorScheme.mutedForeground, shadTheme),
                  const SizedBox(width: 8),
                  _statusChip(AppLocalizations.of(context)?.skillsStatSynced(syncSummary.synced) ?? '${syncSummary.synced} 个已同步', Colors.green, shadTheme),
                  const SizedBox(width: 8),
                  _statusChip(AppLocalizations.of(context)?.skillsStatPending(syncSummary.pending) ?? '${syncSummary.pending} 个待同步', Colors.orange, shadTheme),
                  if (syncSummary.conflicts > 0) ...[
                    const SizedBox(width: 8),
                    _statusChip(AppLocalizations.of(context)?.skillsStatConflicts(syncSummary.conflicts) ?? '${syncSummary.conflicts} 个冲突', shadTheme.colorScheme.destructive, shadTheme),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String text, Color color, ShadThemeData shadTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: shadTheme.textTheme.small.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSelectionToolbar(
    BuildContext context,
    SkillsViewModel viewModel,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final selected = _getSelectedSkills(viewModel);
    final visibleIds = viewModel.skills.map((s) => s.id).whereType<int>().toSet();
    final allSelected = visibleIds.isNotEmpty && _selectedSkillIds.containsAll(visibleIds);
    return KcFloatingSelectionBar(
      selectedCount: selected.length,
      allSelected: allSelected,
      onSelectAll: () => setState(() => allSelected ? _selectedSkillIds.removeAll(visibleIds) : _selectedSkillIds.addAll(visibleIds)),
      onDone: () => setState(() {
        _isEditMode = false;
        _selectedSkillIds.clear();
      }),
      actions: [
        KcBatchAction(icon: Icons.sync, label: localizations?.skillsSync ?? '同步', onPressed: () => _batchSyncToTool(context, viewModel, selected)),
        KcBatchAction(icon: Icons.toggle_on_outlined, label: localizations?.skillsActive ?? '启用', onPressed: () => _batchToggleActive(context, viewModel, selected, true)),
        KcBatchAction(icon: Icons.toggle_off_outlined, label: localizations?.skillsInactive ?? '停用', onPressed: () => _batchToggleActive(context, viewModel, selected, false)),
        KcBatchAction(
          key: const ValueKey('skills.batch.delete'),
          icon: Icons.delete_outline,
          label: localizations?.tr('uninstall', '卸载') ?? '卸载',
          danger: true,
          onPressed: () => _batchDelete(context, viewModel, selected),
        ),
      ],
    );
  }

  Widget _buildCategorySidebar(
    BuildContext context,
    SkillsViewModel viewModel,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final categories = viewModel.categories;
    if (categories.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        children: [
          _categoryItem(
            label: localizations?.skillsAll ?? 'All',
            icon: Icons.psychology_outlined,
            isSelected: viewModel.activeCategory == null,
            count: viewModel.allSkills.length,
            onTap: () => viewModel.setActiveCategory(null),
            shadTheme: shadTheme,
          ),
          for (final cat in categories)
            _categoryItem(
              label: cat.isEmpty ? (localizations?.skillsUncategorized ?? 'Uncategorized') : cat,
              icon: cat.isEmpty ? Icons.folder_off_outlined : Icons.folder_outlined,
              isSelected: viewModel.activeCategory == cat,
              count: viewModel.getSkillsByCategory(cat).length,
              onTap: () => viewModel.setActiveCategory(cat),
              shadTheme: shadTheme,
            ),
        ],
      ),
    );
  }

  Widget _categoryItem({
    required String label,
    required IconData icon,
    required bool isSelected,
    required int count,
    required VoidCallback onTap,
    required ShadThemeData shadTheme,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? shadTheme.colorScheme.primary.withOpacity(0.1) : Colors.transparent,
          border: Border(
            right: BorderSide(
              color: isSelected ? shadTheme.colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? shadTheme.colorScheme.primary : shadTheme.colorScheme.mutedForeground),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: shadTheme.textTheme.small.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? shadTheme.colorScheme.primary : shadTheme.colorScheme.foreground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: shadTheme.colorScheme.muted,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: shadTheme.textTheme.small.copyWith(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    required ShadThemeData shadTheme,
  }) {
    return Tooltip(
      message: tooltip,
      child: ShadButton.ghost(
        width: 38,
        height: 38,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Icon(icon, size: 18, color: shadTheme.colorScheme.primary),
      ),
    );
  }

  Widget _divider(ShadThemeData shadTheme) {
    return Container(width: 1, height: 20, color: shadTheme.colorScheme.border);
  }

  Widget _buildEmptyState(
    BuildContext context,
    SkillsViewModel viewModel,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    if (viewModel.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: shadTheme.colorScheme.mutedForeground),
            const SizedBox(height: 16),
            Text(
              localizations?.skillsNoSearchResults ?? 'No matching skills',
              style: shadTheme.textTheme.h4,
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.muted,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.psychology_outlined, size: 64, color: shadTheme.colorScheme.mutedForeground),
          ),
          const SizedBox(height: 24),
          Text(localizations?.skillsNoSkills ?? 'No skills yet', style: shadTheme.textTheme.h4),
          const SizedBox(height: 8),
          Text(
            localizations?.skillsAddFirst ?? 'Create or import your first skill',
            style: shadTheme.textTheme.p.copyWith(color: shadTheme.colorScheme.mutedForeground),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadButton(
                onPressed: () => _openCreatePage(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 16),
                    const SizedBox(width: 6),
                    Text(localizations?.skillsCreate ?? 'Create'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ShadButton.outline(
                key: const ValueKey('skills.empty.repos'),
                onPressed: () => _onMarketAction(context, viewModel, 'repos'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storefront_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(localizations?.tr('skills_menu_repos', '从仓库发现并安装') ?? '从仓库发现并安装'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ShadButton.outline(
                key: const ValueKey('skills.empty.importAll'),
                onPressed: () => _onMarketAction(context, viewModel, 'importAll'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.file_upload_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(localizations?.skillsImport ?? 'Import'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkillList(BuildContext context, SkillsViewModel viewModel, ShadThemeData shadTheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minCardWidth = 260.0;
        const cardSpacing = 10.0;
        const padding = 16.0;
        const cardHeight = 160.0;

        final availableWidth = constraints.maxWidth - padding * 2;
        var crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor().clamp(1, 5);
        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) crossAxisCount -= 1;

        final skills = List<Skill>.from(viewModel.skills);
        final cards = skills.map((skill) {
          return SizedBox(
            key: ValueKey('skillSlot-${skill.id}'),
            width: cardWidth,
            height: cardHeight,
            child: KcSelectableCard(
              manage: _isEditMode,
              selected: skill.id != null && _selectedSkillIds.contains(skill.id),
              checkKey: ValueKey('skillCard.select.${skill.id}'),
              onSelect: (_) => _toggleSelection(skill),
              child: SkillCard(
              key: ValueKey(skill.id),
              skill: skill,
              isEditMode: _isEditMode,
              isSelected: skill.id != null && _selectedSkillIds.contains(skill.id),
              onTap: () {
                if (_isSelectMode) {
                  _toggleSelection(skill);
                } else if (!_isEditMode) {
                  // Single tap in normal mode → open details
                  SkillDetailsDialog.show(context, skill);
                } else {
                  _openEditPage(context, skill);
                }
              },
              onDoubleTap: () {
                if (!_isEditMode && !_isSelectMode) {
                  SkillDetailsDialog.show(context, skill);
                }
              },
              onLongPress: () {
                if (!_isEditMode) {
                  _toggleSelection(skill);
                }
              },
              onEdit: () => _openEditPage(context, skill),
              onDelete: () => _deleteSkill(context, skill, viewModel),
              onToggleActive: (active) => viewModel.toggleActive(skill),
            )),
          );
        }).toList();

        if (_isEditMode) {
          // 与普通模式同样的 padding；底部为悬浮批量栏预留
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(padding, padding, padding, padding + kcFloatingBarReserve),
            child: ReorderableWrap(
              spacing: cardSpacing,
              runSpacing: cardSpacing,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = skills.removeAt(oldIndex);
                skills.insert(newIndex, item);
                viewModel.updateSortOrder(skills);
              },
              children: cards,
            ),
          );
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, padding, padding, padding + (_isSelectMode ? kcFloatingBarReserve : 0)),
          child: Wrap(
            spacing: cardSpacing,
            runSpacing: cardSpacing,
            children: cards,
          ),
        );
      },
    );
  }

  Future<void> _openSyncPage(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SkillsSyncPage()),
    );
    if (mounted) context.read<SkillsViewModel>().refresh();
  }

  Future<void> _openCreatePage(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SkillFormPage()),
    );
    if (result == true && mounted) context.read<SkillsViewModel>().refresh();
  }

  Future<void> _openEditPage(BuildContext context, Skill skill) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SkillFormPage(skill: skill)),
    );
    if (result == true && mounted) context.read<SkillsViewModel>().refresh();
  }

  Future<void> _importFromFolder(BuildContext context, SkillsViewModel viewModel) async {
    final localizations = AppLocalizations.of(context);
    final selectedDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: localizations?.skillsImport ?? 'Import Skill',
    );
    if (selectedDir == null) return;

    final success = await viewModel.importFromFolder(selectedDir);
    if (!mounted) return;

    showKcToast(context, success
              ? (localizations?.skillsImportSuccess ?? 'Skill imported')
              : (viewModel.errorMessage ?? localizations?.skillsImportFailed ?? 'Import failed'), kind: KcToastKind.success);
  }

  Future<void> _deleteSkill(BuildContext context, Skill skill, SkillsViewModel viewModel) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: localizations?.delete ?? 'Delete',
      message: localizations?.skillsDeleteConfirm(skill.name) ??
          'Delete skill "${skill.name}"? This removes source files and symlinks.',
      confirmText: localizations?.delete ?? 'Delete',
    );
    if (confirmed != true) return;

    final success = await viewModel.deleteSkill(skill);
    if (!mounted) return;

    showKcToast(context, success
              ? (localizations?.skillsDeleteSuccess ?? 'Skill deleted')
              : (viewModel.errorMessage ?? localizations?.skillsDeleteFailed ?? 'Delete failed'), kind: KcToastKind.success);
  }

  // ── Batch operations ──

  Future<void> _batchToggleActive(
    BuildContext context,
    SkillsViewModel viewModel,
    List<Skill> selected,
    bool active,
  ) async {
    final count = await viewModel.batchToggleActive(selected, active);
    _clearSelection();
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    showKcToast(context, active
          ? '${loc?.skillsActive ?? 'Active'}: $count'
          : '${loc?.skillsInactive ?? 'Inactive'}: $count', kind: KcToastKind.success);
  }

  Future<void> _batchDelete(
    BuildContext context,
    SkillsViewModel viewModel,
    List<Skill> selected,
  ) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: loc?.skillsBatchDeleteTitle(selected.length) ?? 'Delete ${selected.length} skills?',
      message: loc?.skillsBatchDeleteMessage() ?? 'This will permanently remove the skill source files and symlinks.',
      confirmText: loc?.delete ?? 'Delete',
    );
    if (confirmed != true) return;

    final count = await viewModel.batchDelete(selected);
    _clearSelection();
    if (!mounted) return;
    showKcToast(context, '$count ${(loc?.delete ?? 'deleted').toLowerCase()}', kind: KcToastKind.success);
  }

  Future<void> _batchSyncToTool(
    BuildContext context,
    SkillsViewModel viewModel,
    List<Skill> selected,
  ) async {
    final count = await viewModel.batchSyncToFirstTool(selected);
    _clearSelection();
    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    showKcToast(context, '$count ${(loc?.skillsSync ?? 'synced').toLowerCase()}', kind: KcToastKind.success);
  }

  Future<void> _syncAllSkills(BuildContext context, SkillsViewModel viewModel) async {
    final summaries = await viewModel.syncAll(replaceExisting: true);
    if (!mounted) return;
    if (summaries == null) return;

    var totalSynced = 0;
    var totalConflicts = 0;
    for (final summary in summaries.values) {
      totalSynced += summary.synced;
      totalConflicts += summary.conflicts;
    }

    final loc = AppLocalizations.of(context);
    showKcToast(context, loc?.skillsFullSyncComplete(totalSynced, totalConflicts) ??
              'Full sync completed: $totalSynced synced, $totalConflicts conflicts', kind: KcToastKind.success);
  }

  // ========== CC Switch 对齐的 Skills 功能（最小 UI 入口） ==========

  void _toast(BuildContext context, String message, {bool error = false}) {
    if (!mounted) return;
    // 「…失败：…」类消息按错误样式显示
    final isError = error || message.contains('失败');
    showKcToast(context, message, kind: isError ? KcToastKind.error : KcToastKind.success);
  }

  void _toastResult(BuildContext context, SkillsViewModel vm, String success, Object? result) {
    _toast(context, result == null ? '失败：${vm.errorMessage ?? '未知错误'}' : success, error: result == null);
  }

  Future<List<SkillTargetTool>> _installTargets() => SkillsPathService().detectInstalledTools();

  PopupMenuItem<String> _menuHeader(String text) => PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text(text, style: KcType.caption.copyWith(fontWeight: FontWeight.w600)),
      );

  PopupMenuItem<String> _menuItem(String value, IconData icon, String text) => PopupMenuItem<String>(
        value: value,
        height: 36,
        child: Row(children: [Icon(icon, size: 16), const SizedBox(width: 10), Text(text)]),
      );

  List<PopupMenuEntry<String>> _addMenuItems(AppLocalizations? l) => [
        _menuItem('create', Icons.edit_note, l?.tr('skills_menu_create', '新建 Skill') ?? '新建 Skill'),
        const PopupMenuDivider(),
        _menuHeader(l?.tr('menu_group_install', '安装') ?? '安装'),
        _menuItem('repos', Icons.storefront_outlined, l?.tr('skills_menu_repos', '从仓库发现并安装') ?? '从仓库发现并安装'),
        _menuItem('skillssh', Icons.travel_explore, l?.tr('skills_menu_skillssh', '搜索 skills.sh') ?? '搜索 skills.sh'),
        _menuItem('zip', Icons.folder_zip_outlined, l?.tr('skills_menu_zip', '从 ZIP 安装') ?? '从 ZIP 安装'),
        const PopupMenuDivider(),
        _menuHeader(l?.tr('menu_group_import', '导入') ?? '导入'),
        _menuItem('folder', Icons.file_upload_outlined, l?.tr('skills_menu_folder', '从文件夹导入') ?? '从文件夹导入'),
        _menuItem('importAll', Icons.download_for_offline_outlined, l?.tr('skills_menu_import_all', '从所有工具导入未管理的 Skill') ?? '从所有工具导入未管理的 Skill'),
      ];

  Future<void> _onMarketAction(BuildContext context, SkillsViewModel vm, String action) async {
    switch (action) {
      case 'create':
        _openCreatePage(context);
      case 'folder':
        await _importFromFolder(context, vm);
      case 'repos':
        await _showRepoDialog(context, vm);
      case 'skillssh':
        await _showSkillsShDialog(context, vm);
      case 'zip':
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['zip', 'skill'],
        );
        final file = picked?.files.single.path;
        if (file == null || !context.mounted) return;
        final result = await vm.installFromZip(file, enabledTools: await _installTargets());
        if (!context.mounted) return;
        _toastResult(context, vm, '已安装 ${result?.length ?? 0} 个 Skill', result);
      case 'importAll':
        final result = await vm.importFromAllTools();
        if (!context.mounted) return;
        final imported = result?.values.fold<int>(0, (a, b) => a + b.imported) ?? 0;
        final skipped = result?.values.fold<int>(0, (a, b) => a + b.skipped) ?? 0;
        _toastResult(context, vm, '已导入 $imported 个，跳过 $skipped 个', result);
      case 'updates':
        await _showUpdatesDialog(context, vm);
      case 'backups':
        await _showBackupsDialog(context, vm);
      case 'method':
        await _showSyncMethodDialog(context, vm);
      case 'storage':
        await _showStorageDialog(context, vm);
    }
  }

  Future<void> _showRepoDialog(BuildContext context, SkillsViewModel vm) async {
    final repoController = TextEditingController();
    var repos = await vm.getRepos();
    List<RemoteSkill>? remote;
    Map<String, String> errors = const {};
    var loading = false;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Skills 仓库'),
          content: SizedBox(
            width: 560,
            height: 480,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: repoController,
                      decoration: const InputDecoration(hintText: 'owner/name 或 GitHub 地址（可加 @分支）'),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      try {
                        repos = await vm.addRepo(repoController.text);
                        repoController.clear();
                        setDialogState(() {});
                      } catch (e) {
                        if (ctx.mounted) _toast(ctx, '$e', error: true);
                      }
                    },
                    child: const Text('添加'),
                  ),
                ]),
                Wrap(
                  spacing: 6,
                  children: repos
                      .map((r) => InputChip(
                            label: Text(r.branch == null ? r.fullName : '${r.fullName}@${r.branch}'),
                            onDeleted: () async {
                              repos = await vm.removeRepo(r);
                              setDialogState(() {});
                            },
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                if (loading) const LinearProgressIndicator(),
                if (errors.isNotEmpty)
                  Text(errors.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                      style: const TextStyle(color: Colors.red, fontSize: 12)),
                Expanded(
                  child: remote == null
                      ? const Center(child: Text('点击“发现”从启用的仓库下载并列出 Skill'))
                      : ListView(
                          children: remote!
                              .map((r) => ListTile(
                                    dense: true,
                                    title: Text(r.name),
                                    subtitle: Text(
                                      '${r.repo.fullName}/${r.subdir}\n${r.description ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: r.installed
                                        ? const Text('已安装')
                                        : TextButton(
                                            onPressed: () async {
                                              final s = await vm.installRemote(r,
                                                  enabledTools: await _installTargets());
                                              if (!ctx.mounted) return;
                                              _toastResult(ctx, vm, '已安装 ${r.name}', s);
                                            },
                                            child: const Text('安装'),
                                          ),
                                  ))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      setDialogState(() => loading = true);
                      final result = await vm.discoverRepoSkills();
                      setDialogState(() {
                        loading = false;
                        remote = result?.skills ?? const [];
                        errors = result?.errors ?? {'': vm.errorMessage ?? ''};
                      });
                    },
              child: const Text('发现'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      ),
    );
    repoController.dispose();
  }

  Future<void> _showSkillsShDialog(BuildContext context, SkillsViewModel vm) async {
    final queryController = TextEditingController();
    List<SkillsShResult> results = const [];
    var loading = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> search() async {
            if (queryController.text.trim().isEmpty) return;
            setDialogState(() => loading = true);
            final r = await vm.searchSkillsSh(queryController.text.trim());
            setDialogState(() {
              loading = false;
              results = r ?? const [];
            });
            if (r == null && ctx.mounted) _toast(ctx, '搜索失败：${vm.errorMessage}');
          }

          return AlertDialog(
            title: const Text('搜索 skills.sh'),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(children: [
                TextField(
                  controller: queryController,
                  decoration: const InputDecoration(hintText: '关键词，回车搜索'),
                  onSubmitted: (_) => search(),
                ),
                if (loading) const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    children: results
                        .map((r) => ListTile(
                              dense: true,
                              title: Text(r.name),
                              subtitle: Text('${r.source} · ${r.installs} 次安装'),
                              trailing: TextButton(
                                onPressed: () async {
                                  final s = await vm.installFromSkillsSh(r,
                                      enabledTools: await _installTargets());
                                  if (!ctx.mounted) return;
                                  _toastResult(ctx, vm, '已安装 ${r.name}', s);
                                },
                                child: const Text('安装'),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
          );
        },
      ),
    );
    queryController.dispose();
  }

  Future<void> _showUpdatesDialog(BuildContext context, SkillsViewModel vm) async {
    final infos = await vm.checkUpdates();
    if (!context.mounted) return;
    if (infos == null) {
      _toast(context, '检查更新失败：${vm.errorMessage}');
      return;
    }
    if (infos.isEmpty) {
      _toast(context, '没有从仓库安装的 Skill');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skill 更新'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: infos
                .map((i) => ListTile(
                      dense: true,
                      title: Text(i.skill.name),
                      subtitle: Text(i.error ??
                          (i.hasUpdate
                              ? (i.locallyModified ? '有更新（本地已修改，更新前会自动备份）' : '有更新')
                              : '已是最新')),
                      trailing: i.hasUpdate
                          ? TextButton(
                              onPressed: () async {
                                final s = await vm.updateFromRemote(i.skill);
                                if (!ctx.mounted) return;
                                _toastResult(ctx, vm, '已更新 ${i.skill.name}', s);
                              },
                              child: const Text('更新'),
                            )
                          : null,
                    ))
                .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  Future<void> _showBackupsDialog(BuildContext context, SkillsViewModel vm) async {
    var backups = await vm.listBackups();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('卸载备份'),
          content: SizedBox(
            width: 480,
            child: backups.isEmpty
                ? const Text('暂无备份')
                : ListView(
                    shrinkWrap: true,
                    children: backups
                        .map((SkillBackupEntry b) => ListTile(
                              dense: true,
                              title: Text(b.skillName),
                              subtitle: Text('${b.reason == 'update' ? '更新前' : '卸载'} · ${b.createdAt.toLocal()}'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                TextButton(
                                  onPressed: () async {
                                    final s = await vm.restoreBackup(b);
                                    backups = await vm.listBackups();
                                    setDialogState(() {});
                                    if (!ctx.mounted) return;
                                    _toastResult(ctx, vm, '已恢复 ${b.skillName}', s);
                                  },
                                  child: const Text('恢复'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await vm.deleteBackup(b);
                                    backups = await vm.listBackups();
                                    setDialogState(() {});
                                  },
                                  child: const Text('删除'),
                                ),
                              ]),
                            ))
                        .toList(),
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      ),
    );
  }

  Future<void> _showSyncMethodDialog(BuildContext context, SkillsViewModel vm) async {
    final current = await vm.getSyncMethod();
    if (!context.mounted) return;
    const labels = {
      SkillSyncMethod.auto: '自动（优先符号链接，失败时复制）',
      SkillSyncMethod.symlink: '仅符号链接',
      SkillSyncMethod.copy: '复制',
    };
    final picked = await showDialog<SkillSyncMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Skills 同步方式'),
        children: SkillSyncMethod.values
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, m),
                  child: Text('${m == current ? '● ' : '○ '}${labels[m]}'),
                ))
            .toList(),
      ),
    );
    if (picked == null || picked == current) return;
    await vm.setSyncMethod(picked);
    if (!context.mounted) return;
    await _syncAllSkills(context, vm);
  }

  Future<void> _showStorageDialog(BuildContext context, SkillsViewModel vm) async {
    final current = await vm.getStorageLocation();
    if (!context.mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Skills 存储位置'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'keycore'),
            child: Text('${current == 'keycore' ? '● ' : '○ '}~/.keycore/skills（默认）'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'agents'),
            child: Text('${current == 'agents' ? '● ' : '○ '}~/.agents/skills（与 CC Switch 共用）'),
          ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    final result = await vm.migrateStorage(picked);
    if (!context.mounted) return;
    _toastResult(context, vm, '已迁移 ${result?.moved ?? 0} 个 Skill', result);
  }
}
