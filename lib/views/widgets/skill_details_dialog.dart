import 'package:flutter/material.dart';
import '../../theme/kc_tokens.dart';
import 'kc_drawer.dart';
import 'kc_logo.dart';
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
    await showKcDrawer<void>(
      context: context,
      builder: (_) => SkillDetailsDialog(skill: skill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final cs = shadTheme.colorScheme;
    final kc = context.kc;
    final loc = AppLocalizations.of(context);
    final viewModel = context.watch<SkillsViewModel>();

    // 统一抽屉（kc_drawer.dart）：实色面板 + 统一页头 + 可滚动正文 + 固定底栏
    return KcDrawerSurface(
      key: const ValueKey('skillDetails.sheet'),
      header: KcDrawerHeader(
        leading: KcLogoBox(child: Icon(Icons.psychology_outlined, size: 22, color: kc.actionText)),
        title: Text(skill.name),
        subtitle: Text(skill.relativePath == skill.skillId ? skill.skillId : '${skill.skillId} · ${skill.relativePath}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x5, KcSpace.page, KcSpace.x6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (skill.description != null && skill.description!.isNotEmpty)
            Text(skill.description!, style: KcType.body.copyWith(color: kc.text2)),
          _SyncStatusSection(skill: skill),
          if (skill.tags != null && skill.tags!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final tag in skill.tags!)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(999)),
                  child: Text('#$tag', style: KcType.badge.copyWith(color: kc.text2)),
                ),
            ]),
          ],
          const SizedBox(height: KcSpace.x5),
          Text('SKILL.md', style: KcType.section.copyWith(color: cs.foreground)),
          const SizedBox(height: KcSpace.x2),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.card,
              borderRadius: BorderRadius.circular(KcRadius.panel),
              border: Border.all(color: cs.border),
            ),
            child: FutureBuilder<String>(
              future: viewModel.readSkillContent(skill),
              builder: (context, snapshot) => snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  : snapshot.hasError
                      ? Text(loc?.skillsFailedLoadContent ?? 'Failed to load content', style: TextStyle(color: cs.destructive))
                      : SelectableText(snapshot.data ?? '', style: KcType.mono.copyWith(fontSize: 12.5, height: 1.5, color: cs.foreground)),
            ),
          ),
        ]),
      ),
      footer: KcDrawerFooter(
        leading: [
          ShadButton.ghost(
            key: const ValueKey('skillDetails.toggle'),
            leading: Icon(skill.isActive ? Icons.toggle_on : Icons.toggle_off_outlined, size: 18),
            onPressed: () => viewModel.toggleActive(skill),
            child: Text(skill.isActive ? (loc?.skillsActive ?? 'Active') : (loc?.skillsInactive ?? 'Inactive')),
          ),
        ],
        trailing: [
          if (skill.enabledTools.isNotEmpty)
            ShadButton.outline(
              key: const ValueKey('skillDetails.sync'),
              leading: const Icon(Icons.sync, size: 16),
              onPressed: () {
                viewModel.syncToTool(skill.enabledTools.first, replaceExisting: false).then((_) {
                  if (context.mounted) Navigator.of(context).pop();
                });
              },
              child: Text(loc?.skillsSync ?? 'Sync'),
            ),
          ShadButton(
            key: const ValueKey('skillDetails.edit'),
            leading: const Icon(Icons.edit_outlined, size: 16),
            onPressed: () {
              Navigator.of(context).pop();
              Future.microtask(() async {
                if (!context.mounted) return;
                context.read<SkillsViewModel>().refresh();
                await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SkillFormPage(skill: skill)));
              });
            },
            child: Text(loc?.edit ?? 'Edit'),
          ),
        ],
      ),
    );
  }
}
