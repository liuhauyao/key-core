import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reorderables/reorderables.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/skill.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/skill_card.dart';
import '../widgets/skill_details_dialog.dart';
import 'skill_form_page.dart';
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
                      icon: Icons.file_upload_outlined,
                      tooltip: localizations?.skillsImport ?? 'Import',
                      onPressed: () => _importFromFolder(context, viewModel),
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    _toolbarButton(
                      icon: Icons.refresh,
                      tooltip: localizations?.refreshKeyList ?? 'Refresh',
                      onPressed: () => viewModel.refresh(),
                      shadTheme: shadTheme,
                    ),
                    _divider(shadTheme),
                    _toolbarButton(
                      icon: Icons.add,
                      tooltip: localizations?.skillsCreate ?? 'Create',
                      onPressed: () => _openCreatePage(context),
                      shadTheme: shadTheme,
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
                  _statusChip('${syncSummary.total} total', shadTheme.colorScheme.mutedForeground, shadTheme),
                  const SizedBox(width: 8),
                  _statusChip('${syncSummary.synced} synced', Colors.green, shadTheme),
                  const SizedBox(width: 8),
                  _statusChip('${syncSummary.pending} pending', Colors.orange, shadTheme),
                  if (syncSummary.conflicts > 0) ...[
                    const SizedBox(width: 8),
                    _statusChip('${syncSummary.conflicts} conflicts', shadTheme.colorScheme.destructive, shadTheme),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.primary.withOpacity(0.06),
        border: Border(
          bottom: BorderSide(color: shadTheme.colorScheme.primary.withOpacity(0.15)),
        ),
      ),
      child: Row(
        children: [
          Text(
            localizations?.skillsSelectedCount(selected.length) ?? '${selected.length} selected',
            style: shadTheme.textTheme.p.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          ShadButton.ghost(
            onPressed: () => _batchToggleActive(context, viewModel, selected, true),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toggle_on, size: 16),
                const SizedBox(width: 4),
                Text(localizations?.skillsActive ?? 'Enable'),
              ],
            ),
          ),
          const SizedBox(width: 4),
          ShadButton.ghost(
            onPressed: () => _batchToggleActive(context, viewModel, selected, false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.toggle_off_outlined, size: 16),
                const SizedBox(width: 4),
                Text(localizations?.skillsInactive ?? 'Disable'),
              ],
            ),
          ),
          const Spacer(),
          ShadButton.outline(
            onPressed: () => _batchSyncToTool(context, viewModel, selected),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync, size: 16),
                const SizedBox(width: 4),
                Text(localizations?.skillsSync ?? 'Sync'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadButton(
            backgroundColor: shadTheme.colorScheme.destructive,
            foregroundColor: Colors.white,
            onPressed: () => _batchDelete(context, viewModel, selected),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.delete_outline, size: 16),
                const SizedBox(width: 4),
                Text(localizations?.delete ?? 'Delete'),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ShadButton.ghost(
            onPressed: _clearSelection,
            child: Text(localizations?.cancel ?? 'Cancel'),
          ),
        ],
      ),
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
                onPressed: () => _importFromFolder(context, viewModel),
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
            width: cardWidth,
            height: cardHeight,
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
            ),
          );
        }).toList();

        if (_isEditMode) {
          return Padding(
            padding: const EdgeInsets.all(padding),
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
          padding: const EdgeInsets.all(padding),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (localizations?.skillsImportSuccess ?? 'Skill imported')
              : (viewModel.errorMessage ?? localizations?.skillsImportFailed ?? 'Import failed'),
        ),
      ),
    );
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (localizations?.skillsDeleteSuccess ?? 'Skill deleted')
              : (viewModel.errorMessage ?? localizations?.skillsDeleteFailed ?? 'Delete failed'),
        ),
      ),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(active
          ? '${loc?.skillsActive ?? 'Active'}: $count'
          : '${loc?.skillsInactive ?? 'Inactive'}: $count')),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count ${(loc?.delete ?? 'deleted').toLowerCase()}')),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count ${(loc?.skillsSync ?? 'synced').toLowerCase()}')),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          loc?.skillsFullSyncComplete(totalSynced, totalConflicts) ??
              'Full sync completed: $totalSynced synced, $totalConflicts conflicts',
        ),
      ),
    );
  }
}
