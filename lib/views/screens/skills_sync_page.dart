import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/skill.dart';
import '../../services/skills_path_service.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../widgets/kc_window_header.dart';
import '../widgets/kc_toast.dart';
import '../widgets/confirm_dialog.dart';

class SkillsSyncPage extends StatefulWidget {
  const SkillsSyncPage({super.key});

  @override
  State<SkillsSyncPage> createState() => _SkillsSyncPageState();
}

class _SkillsSyncPageState extends State<SkillsSyncPage> {
  SkillTargetTool? _selectedTool;
  List<ToolSkillEntry> _toolEntries = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final enabled = _getEnabledSkillTools();
      if (enabled.isNotEmpty) {
        setState(() => _selectedTool = enabled.first);
        _scanTool();
      }
    });
  }

  List<SkillTargetTool> _getEnabledSkillTools() {
    return SkillsPathService.supportedTools;
  }

  Future<void> _scanTool() async {
    if (_selectedTool == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries = await context.read<SkillsViewModel>().scanToolSkills(_selectedTool!);
      if (mounted) {
        setState(() {
          _toolEntries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    final viewModel = context.watch<SkillsViewModel>();

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      appBar: KcWindowHeader(
        title: localizations?.skillsSyncPageTitle ?? 'Skills Sync',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildToolSelector(shadTheme, localizations),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton(
                  onPressed: _selectedTool == null || _isLoading ? null : _scanTool,
                  child: Text(localizations?.skillsReadFromTool ?? 'Read from tool'),
                ),
                ShadButton.outline(
                  onPressed: _selectedTool == null || _isLoading ? null : () => _importFromTool(context),
                  child: Text(localizations?.skillsImportToKeyCore ?? 'Import to Key Core'),
                ),
                ShadButton.outline(
                  onPressed: _selectedTool == null || _isLoading ? null : () => _syncToTool(context, false),
                  child: Text(localizations?.skillsSyncToTool ?? 'Sync to tool'),
                ),
                ShadButton(
                  onPressed: _selectedTool == null || _isLoading ? null : () => _migrateTool(context),
                  child: Text(localizations?.skillsMigrateOneClick ?? 'One-click migrate'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildKeyCorePanel(viewModel, shadTheme, localizations)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildToolPanel(shadTheme, localizations)),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: TextStyle(color: shadTheme.colorScheme.destructive)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildToolSelector(ShadThemeData shadTheme, AppLocalizations? localizations) {
    final tools = _getEnabledSkillTools();
    return Row(
      children: [
        Text(localizations?.skillsSelectTool ?? 'Select tool', style: shadTheme.textTheme.p),
        const SizedBox(width: 12),
        DropdownButton<SkillTargetTool>(
          value: _selectedTool,
          items: tools
              .map((tool) => DropdownMenuItem(value: tool, child: Text(tool.displayName)))
              .toList(),
          onChanged: (tool) {
            setState(() => _selectedTool = tool);
            _scanTool();
          },
        ),
      ],
    );
  }

  Widget _buildKeyCorePanel(
    SkillsViewModel viewModel,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    return _panel(
      title: localizations?.skillsKeyCoreList ?? 'Key Core Skills',
      shadTheme: shadTheme,
      child: viewModel.allSkills.isEmpty
          ? Center(child: Text(localizations?.skillsNoSkills ?? 'No skills yet'))
          : ListView.separated(
              itemCount: viewModel.allSkills.length,
              separatorBuilder: (_, __) => Divider(color: shadTheme.colorScheme.border),
              itemBuilder: (context, index) {
                final skill = viewModel.allSkills[index];
                return ListTile(
                  dense: true,
                  title: Text(skill.name),
                  subtitle: Text(skill.relativePath),
                  trailing: _syncStatusIcon(skill, shadTheme),
                );
              },
            ),
    );
  }

  Widget _buildToolPanel(ShadThemeData shadTheme, AppLocalizations? localizations) {
    return _panel(
      title: localizations?.skillsToolList ?? 'Tool Directory',
      shadTheme: shadTheme,
      child: _isLoading
          ? Center(child: CircularProgressIndicator(color: shadTheme.colorScheme.primary))
          : _toolEntries.isEmpty
              ? Center(child: Text(localizations?.skillsNoToolSkills ?? 'No skills found in tool directory'))
              : ListView.separated(
                  itemCount: _toolEntries.length,
                  separatorBuilder: (_, __) => Divider(color: shadTheme.colorScheme.border),
                  itemBuilder: (context, index) {
                    final entry = _toolEntries[index];
                    return ListTile(
                      dense: true,
                      title: Text(entry.name),
                      subtitle: Text(entry.relativePath),
                      trailing: entry.isKeyCoreManaged
                          ? Icon(Icons.link, size: 18, color: shadTheme.colorScheme.primary)
                          : entry.isSymlink
                              ? Icon(Icons.link_off, size: 18, color: shadTheme.colorScheme.destructive)
                              : Icon(Icons.folder_outlined, size: 18, color: shadTheme.colorScheme.mutedForeground),
                    );
                  },
                ),
    );
  }

  Widget _panel({
    required String title,
    required ShadThemeData shadTheme,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: shadTheme.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: shadTheme.textTheme.p.copyWith(fontWeight: FontWeight.w600)),
          ),
          Divider(height: 1, color: shadTheme.colorScheme.border),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget? _syncStatusIcon(Skill skill, ShadThemeData shadTheme) {
    if (skill.hasConflict) {
      return Icon(Icons.warning_amber_rounded, color: shadTheme.colorScheme.destructive, size: 18);
    }
    if (skill.needsSync) {
      return Icon(Icons.sync_problem, color: Colors.orange, size: 18);
    }
    if (skill.syncStatus.values.any((s) => s == SkillSyncState.synced)) {
      return Icon(Icons.check_circle_outline, color: Colors.green, size: 18);
    }
    return null;
  }

  Future<void> _importFromTool(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final viewModel = context.read<SkillsViewModel>();
    final summary = await viewModel.importFromTool(_selectedTool!);
    if (!mounted || summary == null) return;

    await _scanTool();
    showKcToast(context, localizations?.skillsImportComplete(summary.imported, summary.skipped, summary.failed) ??
              'Imported ${summary.imported}, skipped ${summary.skipped}, failed ${summary.failed}', kind: KcToastKind.success);
  }

  Future<void> _syncToTool(BuildContext context, bool replaceExisting) async {
    final localizations = AppLocalizations.of(context);
    final viewModel = context.read<SkillsViewModel>();

    if (replaceExisting) {
      final confirmed = await ConfirmDialog.show(
        context: context,
        title: localizations?.skillsConfirmReplaceTitle ?? 'Replace existing directories?',
        message: localizations?.skillsConfirmReplaceMessage ??
            'Existing skill directories in the tool folder will be replaced with symlinks.',
        confirmText: localizations?.confirm ?? 'Confirm',
      );
      if (confirmed != true) return;
    }

    final summary = await viewModel.syncToTool(_selectedTool!, replaceExisting: replaceExisting);
    if (!mounted || summary == null) return;

    await _scanTool();
    showKcToast(context, localizations?.skillsSyncComplete(summary.synced, summary.skipped, summary.conflicts, summary.failed) ??
              'Synced ${summary.synced}, conflicts ${summary.conflicts}, failed ${summary.failed}', kind: KcToastKind.success);
  }

  Future<void> _migrateTool(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final viewModel = context.read<SkillsViewModel>();

    final confirmed = await ConfirmDialog.show(
      context: context,
      title: localizations?.skillsMigrateOneClick ?? 'One-click migrate',
      message: localizations?.skillsMigrateConfirm ??
          'Import skills from the tool directory into Key Core and replace tool copies with symlinks.',
      confirmText: localizations?.confirm ?? 'Confirm',
    );
    if (confirmed != true) return;

    final result = await viewModel.migrateFromTool(_selectedTool!, replaceWithSymlink: true);
    if (!mounted || result == null) return;

    await _scanTool();
    showKcToast(context, localizations?.skillsMigrateComplete(result.importSummary.imported) ??
              'Migrated ${result.importSummary.imported} skills', kind: KcToastKind.success);
  }
}
