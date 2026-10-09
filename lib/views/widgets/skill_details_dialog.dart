import 'package:flutter/material.dart';
import '../../theme/kc_tokens.dart';
import 'key_details_dialog.dart' show showKeyDetailsSheet;
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/skill.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../screens/skill_form_page.dart';

/// 同步状态信息展示组件
class _SyncStatusSection extends StatelessWidget {
  final Skill skill;

  const _SyncStatusSection({required this.skill});

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final loc = AppLocalizations.of(context);

    if (skill.enabledTools.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: shadTheme.colorScheme.mutedForeground),
            const SizedBox(width: 6),
            Text(
              loc?.skillsNoToolsEnabled ?? 'No tools enabled',
              style: shadTheme.textTheme.small.copyWith(
                color: shadTheme.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: skill.enabledTools.map((tool) {
          final state = skill.syncStatus[tool];
          final String statusLabel;
          final Color statusColor;
          final IconData statusIcon;

          switch (state) {
            case SkillSyncState.synced:
              statusLabel = loc?.skillsSyncedStatus ?? 'Synced';
              statusColor = Colors.green;
              statusIcon = Icons.check_circle;
            case SkillSyncState.conflict:
              statusLabel = loc?.skillsConflictStatus ?? 'Conflict';
              statusColor = shadTheme.colorScheme.destructive;
              statusIcon = Icons.warning_amber_rounded;
            case SkillSyncState.outdated:
              statusLabel = loc?.skillsOutdatedStatus ?? 'Outdated';
              statusColor = Colors.orange;
              statusIcon = Icons.sync_problem;
            default:
              statusLabel = loc?.skillsNotSyncedStatus ?? 'Not synced';
              statusColor = shadTheme.colorScheme.mutedForeground;
              statusIcon = Icons.remove_circle_outline;
          }

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  '${tool.displayName}: $statusLabel',
                  style: shadTheme.textTheme.small.copyWith(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// SKILL.md 内容预览对话框
class SkillDetailsDialog extends StatelessWidget {
  final Skill skill;

  const SkillDetailsDialog({super.key, required this.skill});

  /// 展示对话框
  static Future<void> show(BuildContext context, Skill skill) async {
    final viewModel = context.read<SkillsViewModel>();
    await viewModel.readSkillContent(skill);

    if (!context.mounted) return;

    // 右侧抽屉（与密钥 / MCP 详情一致，form_v3.md §8）
    await showKeyDetailsSheet<void>(
      context: context,
      builder: (_) => SkillDetailsDialog(skill: skill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final loc = AppLocalizations.of(context);
    final viewModel = context.watch<SkillsViewModel>();

    final width = MediaQuery.sizeOf(context).width;
    return Material(
      key: const ValueKey('skillDetails.sheet'),
      color: shadTheme.colorScheme.background,
      child: Container(
        width: width < 640 ? width : 560,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: shadTheme.colorScheme.border)),
          boxShadow: context.kc.shadowLg,
        ),
        child: FutureBuilder<String>(
          future: viewModel.readSkillContent(skill),
          builder: (context, snapshot) {
            return Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: shadTheme.colorScheme.border, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(skill.name, style: shadTheme.textTheme.h4),
                            const SizedBox(height: 4),
                            Text(
                              skill.skillId,
                              style: shadTheme.textTheme.small.copyWith(
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: Text(
                          skill.relativePath,
                          style: shadTheme.textTheme.small.copyWith(
                            color: shadTheme.colorScheme.mutedForeground,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // Description + sync status + tags
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (skill.description != null && skill.description!.isNotEmpty)
                        Text(
                          skill.description!,
                          style: shadTheme.textTheme.p.copyWith(
                            color: shadTheme.colorScheme.mutedForeground,
                          ),
                        ),
                      _SyncStatusSection(skill: skill),
                      if (skill.tags != null && skill.tags!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: skill.tags!.map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: shadTheme.colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '#$tag',
                                style: shadTheme.textTheme.small.copyWith(
                                  color: shadTheme.colorScheme.primary,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: shadTheme.colorScheme.muted,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: shadTheme.colorScheme.border),
                    ),
                    child: snapshot.connectionState == ConnectionState.waiting
                        ? const Center(child: CircularProgressIndicator())
                        : snapshot.hasError
                            ? Center(
                                child: Text(
                                  loc?.skillsFailedLoadContent ?? 'Failed to load content',
                                  style: TextStyle(color: shadTheme.colorScheme.destructive),
                                ),
                              )
                            : SingleChildScrollView(
                                child: SelectableText(
                                  snapshot.data ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                  ),
                ),

                // Footer actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Row(
                    children: [
                      ShadButton.ghost(
                        onPressed: () => viewModel.toggleActive(skill),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              skill.isActive ? Icons.toggle_on : Icons.toggle_off_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(skill.isActive
                                ? (loc?.skillsActive ?? 'Active')
                                : (loc?.skillsInactive ?? 'Inactive')),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (skill.enabledTools.isNotEmpty)
                        ShadButton.outline(
                          onPressed: () {
                            viewModel
                                .syncToTool(skill.enabledTools.first, replaceExisting: false)
                                .then((_) {
                              if (context.mounted) Navigator.of(context).pop();
                            });
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sync, size: 16),
                              const SizedBox(width: 6),
                              Text(loc?.skillsSync ?? 'Sync'),
                            ],
                          ),
                        ),
                      const SizedBox(width: 8),
                      ShadButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          Future.microtask(() async {
                            if (!context.mounted) return;
                            context.read<SkillsViewModel>().refresh();
                            await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => SkillFormPage(skill: skill),
                              ),
                            );
                          });
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.edit_outlined, size: 16),
                            const SizedBox(width: 6),
                            Text(loc?.edit ?? 'Edit'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
