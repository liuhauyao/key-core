import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/skill.dart';
import '../../utils/app_localizations.dart';

class SkillCard extends StatefulWidget {
  final Skill skill;
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleActive;

  const SkillCard({
    super.key,
    required this.skill,
    this.isEditMode = false,
    this.isSelected = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onEdit,
    this.onDelete,
    this.onToggleActive,
  });

  @override
  State<SkillCard> createState() => _SkillCardState();
}

class _SkillCardState extends State<SkillCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    final isActive = widget.skill.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: widget.isSelected
                ? shadTheme.colorScheme.primary.withOpacity(0.12)
                : isActive
                    ? Color.alphaBlend(
                        shadTheme.colorScheme.primary.withOpacity(0.04),
                        shadTheme.colorScheme.background,
                      )
                    : shadTheme.colorScheme.muted.withOpacity(0.5),
            border: Border.all(
              color: widget.isSelected
                  ? shadTheme.colorScheme.primary
                  : isActive
                      ? shadTheme.colorScheme.primary.withOpacity(0.3)
                      : shadTheme.colorScheme.border,
              width: widget.isSelected ? 2 : 1,
            ),
            boxShadow: (_isHovering || widget.isSelected) && !widget.isEditMode
                ? [
                    BoxShadow(
                      color: (widget.isSelected
                              ? shadTheme.colorScheme.primary
                              : shadTheme.colorScheme.primary)
                          .withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Show checkbox when selected
                    if (widget.isSelected)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.check_circle,
                          color: shadTheme.colorScheme.primary,
                          size: 22,
                        ),
                      ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: shadTheme.colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.psychology_outlined,
                        size: 20,
                        color: shadTheme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.skill.name,
                            style: shadTheme.textTheme.p.copyWith(
                              fontWeight: FontWeight.w600,
                              color: shadTheme.colorScheme.foreground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.skill.relativePath,
                            style: shadTheme.textTheme.small.copyWith(
                              color: shadTheme.colorScheme.mutedForeground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isEditMode && !widget.isSelected && widget.onToggleActive != null)
                      Switch(
                        value: isActive,
                        onChanged: widget.onToggleActive,
                        activeColor: shadTheme.colorScheme.primary,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    widget.skill.description ??
                        (localizations?.skillsNoDescription ?? 'No description'),
                    style: shadTheme.textTheme.small.copyWith(
                      color: shadTheme.colorScheme.mutedForeground,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ...widget.skill.enabledTools.map((tool) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildToolIcon(tool, shadTheme),
                      );
                    }),
                    const Spacer(),
                    _buildSyncBadge(shadTheme, localizations),
                    if (_isHovering && !widget.isEditMode && !widget.isSelected) ...[
                      const SizedBox(width: 4),
                      if (widget.onEdit != null)
                        _iconButton(Icons.edit_outlined, widget.onEdit!, shadTheme),
                      if (widget.onDelete != null)
                        _iconButton(Icons.delete_outline, widget.onDelete!, shadTheme,
                            isDestructive: true),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolIcon(SkillTargetTool tool, ShadThemeData shadTheme) {
    final iconPath = tool.iconPath;
    if (iconPath == null) {
      return Icon(Icons.extension, size: 16, color: shadTheme.colorScheme.mutedForeground);
    }
    return SvgPicture.asset(
      iconPath,
      width: 16,
      height: 16,
      colorFilter: ColorFilter.mode(
        shadTheme.colorScheme.mutedForeground,
        BlendMode.srcIn,
      ),
    );
  }

  Widget _buildSyncBadge(ShadThemeData shadTheme, AppLocalizations? localizations) {
    if (widget.skill.hasConflict) {
      return _badge(
        localizations?.skillsSyncConflict ?? 'Conflict',
        shadTheme.colorScheme.destructive,
        shadTheme,
      );
    }
    if (widget.skill.needsSync) {
      return _badge(
        localizations?.skillsSyncPending ?? 'Pending',
        Colors.orange,
        shadTheme,
      );
    }
    if (widget.skill.syncStatus.values.any((s) => s == SkillSyncState.synced)) {
      return _badge(
        localizations?.skillsSyncSynced ?? 'Synced',
        Colors.green,
        shadTheme,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _badge(String text, Color color, ShadThemeData shadTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
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

  Widget _iconButton(IconData icon, VoidCallback onPressed, ShadThemeData shadTheme,
      {bool isDestructive = false}) {
    return ShadButton.ghost(
      width: 28,
      height: 28,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Icon(
        icon,
        size: 16,
        color: isDestructive
            ? shadTheme.colorScheme.destructive
            : shadTheme.colorScheme.mutedForeground,
      ),
    );
  }
}
