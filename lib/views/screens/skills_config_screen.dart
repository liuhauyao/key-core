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

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: Consumer<SkillsViewModel>(
        builder: (context, viewModel, child) {
          return Column(
            children: [
              _buildToolbar(context, viewModel, shadTheme, localizations),
              Expanded(
                child: viewModel.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: shadTheme.colorScheme.primary,
                        ),
                      )
                    : viewModel.skills.isEmpty
                        ? _buildEmptyState(context, viewModel, shadTheme, localizations)
                        : _buildSkillList(context, viewModel, shadTheme),
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
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.background,
        border: Border(
          bottom: BorderSide(color: shadTheme.colorScheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 38,
              child: ShadInput(
                controller: _searchController,
                onChanged: viewModel.setSearchQuery,
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
                  icon: Icons.swap_horiz,
                  tooltip: localizations?.skillsSync ?? 'Sync',
                  onPressed: () => _openSyncPage(context),
                  shadTheme: shadTheme,
                ),
                _divider(shadTheme),
                _toolbarButton(
                  icon: _isEditMode ? Icons.check : Icons.drag_handle,
                  tooltip: _isEditMode
                      ? (localizations?.skillsFinishEdit ?? 'Done')
                      : (localizations?.edit ?? 'Edit'),
                  onPressed: () => setState(() => _isEditMode = !_isEditMode),
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
              onTap: () => _openEditPage(context, skill),
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
}
