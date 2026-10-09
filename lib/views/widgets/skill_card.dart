import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/skill.dart';
import '../../utils/app_localizations.dart';
import '../../theme/kc_tokens.dart';
import 'kc_logo.dart';

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
            borderRadius: BorderRadius.circular(KcRadius.panel),
            color: widget.isSelected
                ? Color.alphaBlend(context.kc.actionSoft, shadTheme.colorScheme.card)
                : isActive
                    ? shadTheme.colorScheme.card
                    : Color.alphaBlend(context.kc.subtle.withValues(alpha: 0.5), shadTheme.colorScheme.card),
            border: Border.all(
              color: widget.isSelected
                  ? shadTheme.colorScheme.primary
                  : (_isHovering && !widget.isEditMode ? shadTheme.colorScheme.input : shadTheme.colorScheme.border),
              width: widget.isSelected ? 1.5 : 1,
            ),
            boxShadow: _isHovering && !widget.isEditMode ? context.kc.shadowMd : context.kc.shadowSm,
          ),
          child: Padding(
            padding: const EdgeInsets.all(KcSpace.x3),
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
                    KcLogoBox(
                      background: context.kc.actionSoft,
                      bordered: false,
                      child: Icon(Icons.psychology_outlined, size: 20, color: context.kc.actionText),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.skill.name,
                            style: KcType.strong.copyWith(color: shadTheme.colorScheme.foreground),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.skill.relativePath,
                            style: KcType.mono.copyWith(fontSize: 11, color: shadTheme.colorScheme.mutedForeground),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (!widget.isEditMode && !widget.isSelected && widget.onToggleActive != null)
                      SizedBox(
                        height: 24,
                        child: FittedBox(
                          child: Switch(
                            value: isActive,
                            onChanged: widget.onToggleActive,
                            activeTrackColor: shadTheme.colorScheme.primary,
                            inactiveThumbColor: Colors.white,
                            inactiveTrackColor: shadTheme.colorScheme.border,
                            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    widget.skill.description ??
                        (localizations?.skillsNoDescription ?? 'No description'),
                    style: KcType.caption.copyWith(color: context.kc.text2, height: 1.4),
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
    // 真实彩色 logo（白底小圆），与钥匙包工具 chip 一致
    return KcLogoBox(
      size: 18,
      circle: true,
      child: SvgPicture.asset(iconPath, width: 12, height: 12, allowDrawingOutsideViewBox: true),
    );
  }

  Widget _buildSyncBadge(ShadThemeData shadTheme, AppLocalizations? localizations) {
    if (widget.skill.hasConflict) {
      return _badge(
        localizations?.skillsSyncConflict ?? 'Conflict',
        context.kc.dangerText,
        shadTheme,
        bg: context.kc.dangerSoft,
      );
    }
    if (widget.skill.needsSync) {
      return _badge(
        localizations?.skillsSyncPending ?? 'Pending',
        context.kc.warnText,
        shadTheme,
        bg: context.kc.warnSoft,
      );
    }
    if (widget.skill.syncStatus.values.any((s) => s == SkillSyncState.synced)) {
      return _badge(
        localizations?.skillsSyncSynced ?? 'Synced',
        context.kc.okText,
        shadTheme,
        bg: context.kc.okSoft,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _badge(String text, Color color, ShadThemeData shadTheme, {required Color bg}) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: KcType.badge.copyWith(color: color))]),
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
        color: isDestructive ? context.kc.dangerText : context.kc.text2,
      ),
    );
  }
}
