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
import '../widgets/kc_segmented.dart';
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
  _SkillStatus? _status;

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

          // 批量栏悬浮在底部（Stack 叠放），不插入到 Column 中 → 不推动内容（零位移，form_v3.md §13）
          return Stack(children: [
            Column(
            children: [
              // Toolbar
              _buildToolbar(context, viewModel, shadTheme, localizations, syncSummary),

              // 内容区：单列网格（不再有页面内的第二条分类侧栏）
              Expanded(
                child: viewModel.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _visibleSkills(viewModel).isEmpty
                        ? _buildEmptyState(context, viewModel, shadTheme, localizations)
                        : _buildSkillList(context, viewModel, shadTheme),
              ),
            ],
            ),
            if (_isEditMode || _isSelectMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(child: _buildSelectionToolbar(context, viewModel, shadTheme, localizations)),
              ),
          ]);
        },
      ),
    );
  }

  /// 单个技能的同步状态（与 getSyncSummary 同一规则：冲突 > 待同步 > 已同步）
  _SkillStatus? _statusOf(Skill skill) {
    final states = skill.enabledTools.isNotEmpty
        ? skill.enabledTools.map((t) => skill.syncStatus[t] ?? SkillSyncState.notSynced).toList()
        : skill.syncStatus.values.toList();
    if (!skill.isActive || states.isEmpty) return null;
    if (states.contains(SkillSyncState.conflict)) return _SkillStatus.conflict;
    if (states.any((s) => s == SkillSyncState.notSynced || s == SkillSyncState.outdated)) return _SkillStatus.pending;
    return _SkillStatus.synced;
  }

  List<Skill> _visibleSkills(SkillsViewModel vm) =>
      _status == null ? vm.skills : vm.skills.where((s) => _statusOf(s) == _status).toList();

  Widget _buildToolbar(
    BuildContext context,
    SkillsViewModel viewModel,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
    SkillsSyncStatusSummary syncSummary,
  ) {
    String t(String k, String f) => localizations?.tr(k, f) ?? f;
    final icon = KcPageHeader.iconButton;
    // 统一页头（与钥匙包 / MCP 相同几何）：标题 · 副标题 · 搜索 240 · 图标组 · 定宽主按钮槽
    final header = KcPageHeader(
      title: 'Skills',
      subtitle: t('skills_subtitle', '{n} 个技能 · {m} 个待同步')
          .replaceAll('{n}', '${syncSummary.total}')
          .replaceAll('{m}', '${syncSummary.pending + syncSummary.conflicts}'),
      manageSubtitle: t('manage_subtitle_skills', '管理模式 · 拖动排序，勾选后批量操作'),
      manage: _isEditMode,
      searchKey: const ValueKey('skills.search'),
      searchController: _searchController,
      searchHint: localizations?.skillsSearchPlaceholder ?? '搜索 Skills…',
      onSearch: (v) {
        viewModel.setSearchQuery(v);
        _clearSelection();
      },
      actions: [
        icon(context,
            key: const ValueKey('skills.manageToggle'),
            icon: _isEditMode ? Icons.check : Icons.drag_indicator,
            tip: _isEditMode ? (localizations?.skillsFinishEdit ?? '完成') : t('manage_tip', '管理：排序 / 批量操作'),
            active: _isEditMode,
            onPressed: () => setState(() {
                  _isEditMode = !_isEditMode;
                  _clearSelection();
                })),
        icon(context, icon: Icons.sync, tip: localizations?.skillsSyncAll ?? '全部同步', onPressed: () => _syncAllSkills(context, viewModel)),
        icon(context, icon: Icons.compare_arrows, tip: localizations?.skillsSync ?? '对比与同步', onPressed: () => _openSyncPage(context)),
        icon(context,
            key: const ValueKey('skills.prompts'),
            icon: Icons.notes_outlined,
            tip: t('skills_prompts_tooltip', '系统提示词（CLAUDE.md / AGENTS.md 等）'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PromptsPage()))),
        Padding(
          padding: const EdgeInsets.only(left: KcSpace.x2),
          child: PopupMenuButton<String>(
            key: const ValueKey('skills.moreMenu'),
            tooltip: t('more', '更多'),
            position: PopupMenuPosition.under,
            onSelected: (v) => _onMarketAction(context, viewModel, v),
            itemBuilder: (_) => [
              _menuHeader(t('menu_group_maintain', '维护')),
              _menuItem('updates', Icons.system_update_alt, t('skills_menu_updates', '检查更新')),
              _menuItem('backups', Icons.restore, t('skills_menu_backups', '卸载备份与恢复')),
              _menuItem('refresh', Icons.refresh, localizations?.refreshKeyList ?? '刷新'),
              const PopupMenuDivider(),
              _menuHeader(t('menu_group_settings', '设置')),
              _menuItem('method', Icons.link, t('skills_menu_method', '同步方式')),
              _menuItem('storage', Icons.folder_outlined, t('skills_menu_storage', '存储位置')),
            ],
            child: IgnorePointer(child: icon(context, icon: Icons.more_horiz, tip: t('more', '更多'), onPressed: () {})),
          ),
        ),
      ],
      primary: _isEditMode
          ? ShadButton(
              key: const ValueKey('skills.done'),
              height: KcSize.control,
              width: 112,
              leading: const Icon(Icons.check, size: 16),
              onPressed: () => setState(() {
                _isEditMode = false;
                _clearSelection();
              }),
              child: Text(t('done', '完成')),
            )
          : PopupMenuButton<String>(
              key: const ValueKey('skills.addMenu'),
              tooltip: '',
              position: PopupMenuPosition.under,
              onSelected: (v) => _onMarketAction(context, viewModel, v),
              itemBuilder: (_) => _addMenuItems(localizations),
              child: IgnorePointer(
                child: ShadButton(
                  height: KcSize.control,
                  width: 112,
                  leading: const Icon(Icons.add, size: 16),
                  trailing: const Icon(Icons.expand_more, size: 14),
                  onPressed: () {},
                  child: Text(t('add', '添加')),
                ),
              ),
            ),
    );

    final cats = viewModel.categories;
    String catName(String c) => c.isEmpty ? (localizations?.skillsUncategorized ?? '未分类') : c;
    final all = viewModel.skills;
    int n(_SkillStatus? st) => st == null ? all.length : all.where((s) => _statusOf(s) == st).length;
    final filterRow = Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, 0),
      child: Row(children: [
        KcSegmented<_SkillStatus?>(
          key: const ValueKey('skills.statusFilter'),
          value: _status,
          onChanged: (v) => setState(() => _status = v),
          items: [
            (null, t('segment_all', '全部'), n(null)),
            (_SkillStatus.synced, t('status_synced', '已同步'), n(_SkillStatus.synced)),
            (_SkillStatus.pending, t('status_pending', '待同步'), n(_SkillStatus.pending)),
            (_SkillStatus.conflict, t('status_conflict', '冲突'), n(_SkillStatus.conflict)),
          ],
        ),
        const Spacer(),
        // 分类筛选改为弹出菜单（取代原来页面内的第二条侧栏）
        if (cats.isNotEmpty)
          KcFilterMenuButton<String?>(
            key: const ValueKey('skills.categoryFilter'),
            label: viewModel.activeCategory == null ? t('all_categories', '全部分类') : catName(viewModel.activeCategory!),
            selected: viewModel.activeCategory,
            onSelected: (c) {
              viewModel.setActiveCategory(c);
              _clearSelection();
            },
            items: [
              (null, t('all_categories', '全部分类'), viewModel.allSkills.length),
              for (final c in cats) (c, catName(c), viewModel.getSkillsByCategory(c).length),
            ],
          ),
      ]),
    );
    return Column(mainAxisSize: MainAxisSize.min, children: [header, filterRow]);
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

        final skills = List<Skill>.from(_visibleSkills(viewModel));
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
              onTap: () {
                if (_isSelectMode) {
                  _toggleSelection(skill);
                } else if (!_isEditMode) {
                  // Single tap in normal mode → open details
                  SkillDetailsDialog.show(context, skill);
                } else {
                  // 管理模式：点卡片 = 勾选（与钥匙包 / MCP 一致）
                  _toggleSelection(skill);
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
    final isError = error;
    showKcToast(context, message, kind: isError ? KcToastKind.error : KcToastKind.success);
  }

  void _toastResult(BuildContext context, SkillsViewModel vm, String success, Object? result) {
    _toast(context, result == null ? '${_l(context, 'op_failed', '失败')}：${vm.errorMessage ?? _l(context, 'unknown_error', '未知错误')}' : success, error: result == null);
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
      case 'refresh':
        await vm.refresh();
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
        _toastResult(context, vm, _l(context, 'skills_installed_n', '已安装 {n} 个 Skill').replaceAll('{n}', '${result?.length ?? 0}'), result);
      case 'importAll':
        final result = await vm.importFromAllTools();
        if (!context.mounted) return;
        final imported = result?.values.fold<int>(0, (a, b) => a + b.imported) ?? 0;
        final skipped = result?.values.fold<int>(0, (a, b) => a + b.skipped) ?? 0;
        _toastResult(context, vm, _l(context, 'skills_imported_n', '已导入 {a} 个，跳过 {b} 个').replaceAll('{a}', '${imported}').replaceAll('{b}', '${skipped}'), result);
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
          title: Text(_l(context, 'skills_repos', 'Skills 仓库')),
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
                      decoration: InputDecoration(hintText: _l(context, 'skills_repo_hint', 'owner/name 或 GitHub 地址（可加 @分支）')),
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
                    child: Text(_l(context, 'add', '添加')),
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
                      ? Center(child: Text(_l(context, 'skills_discover_hint', '点击“发现”从启用的仓库下载并列出 Skill')))
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
                                        ? Text(_l(context, 'installed', '已安装'))
                                        : TextButton(
                                            onPressed: () async {
                                              final s = await vm.installRemote(r,
                                                  enabledTools: await _installTargets());
                                              if (!ctx.mounted) return;
                                              _toastResult(ctx, vm, _l(context, 'installed_x', '已安装 {x}').replaceAll('{x}', '${r.name}'), s);
                                            },
                                            child: Text(_l(context, 'install', '安装')),
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
              child: Text(_l(context, 'discover', '发现')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_l(context, 'close_btn', '关闭'))),
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
            if (r == null && ctx.mounted) _toast(ctx, '${_l(context, 'search_failed', '搜索失败')}：${vm.errorMessage}');
          }

          return AlertDialog(
            title: Text(_l(context, 'skills_menu_skillssh', '搜索 skills.sh')),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(children: [
                TextField(
                  controller: queryController,
                  decoration: InputDecoration(hintText: _l(context, 'keyword_enter_search', '关键词，回车搜索')),
                  onSubmitted: (_) => search(),
                ),
                if (loading) const LinearProgressIndicator(),
                Expanded(
                  child: ListView(
                    children: results
                        .map((r) => ListTile(
                              dense: true,
                              title: Text(r.name),
                              subtitle: Text('${r.source} · ${_l(context, 'n_installs', '{n} 次安装').replaceAll('{n}', '${r.installs}')}'),
                              trailing: TextButton(
                                onPressed: () async {
                                  final s = await vm.installFromSkillsSh(r,
                                      enabledTools: await _installTargets());
                                  if (!ctx.mounted) return;
                                  _toastResult(ctx, vm, _l(context, 'installed_x', '已安装 {x}').replaceAll('{x}', '${r.name}'), s);
                                },
                                child: Text(_l(context, 'install', '安装')),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_l(context, 'close_btn', '关闭')))],
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
      _toast(context, '${_l(context, 'update_failed_check', '检查更新失败')}：${vm.errorMessage}');
      return;
    }
    if (infos.isEmpty) {
      _toast(context, _l(context, 'skills_none_from_repo', '没有从仓库安装的 Skill'));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l(context, 'skills_updates_title', 'Skill 更新')),
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
                              ? (i.locallyModified ? _l(context, 'skills_update_modified', '有更新（本地已修改，更新前会自动备份）') : _l(context, 'update_available_short', '有更新'))
                              : _l(context, 'up_to_date', '已是最新'))),
                      trailing: i.hasUpdate
                          ? TextButton(
                              onPressed: () async {
                                final s = await vm.updateFromRemote(i.skill);
                                if (!ctx.mounted) return;
                                _toastResult(ctx, vm, _l(context, 'updated_x', '已更新 {x}').replaceAll('{x}', '${i.skill.name}'), s);
                              },
                              child: Text(_l(context, 'update_btn', '更新')),
                            )
                          : null,
                    ))
                .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_l(context, 'close_btn', '关闭')))],
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
          title: Text(_l(context, 'skills_backups_title', '卸载备份')),
          content: SizedBox(
            width: 480,
            child: backups.isEmpty
                ? Text(_l(context, 'no_backups', '暂无备份'))
                : ListView(
                    shrinkWrap: true,
                    children: backups
                        .map((SkillBackupEntry b) => ListTile(
                              dense: true,
                              title: Text(b.skillName),
                              subtitle: Text('${b.reason == 'update' ? _l(context, 'backup_before_update', '更新前') : _l(context, 'backup_uninstall', '卸载')} · ${b.createdAt.toLocal()}'),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                TextButton(
                                  onPressed: () async {
                                    final s = await vm.restoreBackup(b);
                                    backups = await vm.listBackups();
                                    setDialogState(() {});
                                    if (!ctx.mounted) return;
                                    _toastResult(ctx, vm, _l(context, 'restored_x', '已恢复 {x}').replaceAll('{x}', '${b.skillName}'), s);
                                  },
                                  child: Text(_l(context, 'restore', '恢复')),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    await vm.deleteBackup(b);
                                    backups = await vm.listBackups();
                                    setDialogState(() {});
                                  },
                                  child: Text(_l(context, 'delete_btn', '删除')),
                                ),
                              ]),
                            ))
                        .toList(),
                  ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_l(context, 'close_btn', '关闭')))],
        ),
      ),
    );
  }

  Future<void> _showSyncMethodDialog(BuildContext context, SkillsViewModel vm) async {
    final current = await vm.getSyncMethod();
    if (!context.mounted) return;
    final labels = {
      SkillSyncMethod.auto: _l(context, 'sync_method_auto', '自动（优先符号链接，失败时复制）'),
      SkillSyncMethod.symlink: _l(context, 'sync_method_symlink', '仅符号链接'),
      SkillSyncMethod.copy: _l(context, 'sync_method_copy', '复制'),
    };
    final picked = await showDialog<SkillSyncMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_l(context, 'skills_sync_method_title', 'Skills 同步方式')),
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
        title: Text(_l(context, 'skills_storage_title', 'Skills 存储位置')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'keycore'),
            child: Text('${current == 'keycore' ? '● ' : '○ '}~/.keycore/skills（${_l(context, 'default_label', '默认')}）'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'agents'),
            child: Text('${current == 'agents' ? '● ' : '○ '}~/.agents/skills（${_l(context, 'shared_with_ccswitch', '与 CC Switch 共用')}）'),
          ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    final result = await vm.migrateStorage(picked);
    if (!context.mounted) return;
    _toastResult(context, vm, _l(context, 'skills_migrated_n', '已迁移 {n} 个 Skill').replaceAll('{n}', '${result?.moved ?? 0}'), result);
  }
}

String _l(BuildContext c, String k, String zh) => AppLocalizations.of(c)?.tr(k, zh) ?? zh;

enum _SkillStatus { synced, pending, conflict }
