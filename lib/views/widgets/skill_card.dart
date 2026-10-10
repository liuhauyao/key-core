import 'kc_controls.dart';
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
    final cs = shadTheme.colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final skill = widget.skill;
    final isActive = skill.isActive;
    final manage = widget.isEditMode;

    // v3 卡片（与密钥 / MCP 卡片同一语言）：
    // 顶部 36（logo + 名称/ID + 右上角开关；管理模式让位给选择框）· 描述 2 行
    // · 工具图标行 20（+「n 个工具」+ 状态徽标）· 定宽底栏 34（详情 / 编辑 … 删除槽常驻占位）
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.x3, KcSpace.x2 + 2, KcSpace.x3, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 36,
          child: Row(children: [
            KcLogoBox(child: Icon(Icons.psychology_outlined, size: 20, color: kc.actionText)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(skill.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.strong.copyWith(color: cs.foreground)),
                Text(skill.skillId,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.mono.copyWith(fontSize: 11, color: cs.mutedForeground, height: 1.25)),
              ]),
            ),
            const SizedBox(width: KcSpace.x1_5),
            if (manage)
              const SizedBox(key: ValueKey('skillCard.slot'), width: 26, height: 26)
            else
              SizedBox(
                height: 24,
                child: SizedBox(child: KcSwitch(
                    key: const ValueKey('skillCard.toggle'),
                    value: isActive,
                    onChanged: widget.onToggleActive,
                    activeTrackColor: cs.primary,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: cs.border,
                    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: KcSpace.x2),
        SizedBox(
          height: 34,
          child: Text(
            (skill.description?.isNotEmpty ?? false) ? skill.description! : (l?.tr('skill_no_desc', '暂无描述') ?? '暂无描述'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: KcType.caption.copyWith(color: kc.text2, height: 1.4),
          ),
        ),
        const Spacer(),
        SizedBox(
          key: const ValueKey('skillCard.tools'),
          height: 20,
          child: Row(children: [
            for (final t in skill.enabledTools.take(5))
              Padding(padding: const EdgeInsets.only(right: 4), child: Tooltip(message: t.displayName, child: _buildToolIcon(t, shadTheme))),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                skill.enabledTools.isEmpty
                    ? (l?.tr('skill_no_tools', '未分配工具') ?? '未分配工具')
                    : (l?.tr('n_tools', '{n} 个工具') ?? '{n} 个工具').replaceAll('{n}', '${skill.enabledTools.length}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KcType.caption.copyWith(color: kc.text2),
              ),
            ),
            _buildSyncBadge(shadTheme, l),
          ]),
        ),
        const SizedBox(height: KcSpace.x2),
        Container(
          height: 34,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.border))),
          child: Row(children: [
            _slot(const ValueKey('skillCard.details'), Icons.visibility_outlined, l?.tr('view_details', '查看详情') ?? '查看详情', manage ? null : widget.onTap),
            const Spacer(),
            Visibility(
              visible: manage,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _slot(const ValueKey('skillCard.delete'), Icons.delete_outline, l?.tr('delete_btn', '删除') ?? '删除',
                  manage ? widget.onDelete : null, color: kc.dangerText),
            ),
            _slot(const ValueKey('skillCard.edit'), Icons.edit_outlined, l?.edit ?? '编辑', widget.onEdit),
          ]),
        ),
      ]),
    );

    return Semantics(
      container: true,
      label: skill.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: KcMotion.of(context),
          curve: KcMotion.curve,
          decoration: BoxDecoration(
            color: isActive ? cs.card : Color.alphaBlend(kc.subtle.withValues(alpha: 0.5), cs.card),
            borderRadius: BorderRadius.circular(KcRadius.panel),
            border: Border.all(color: _isHovering && !manage ? cs.input : cs.border),
            boxShadow: _isHovering && !manage ? kc.shadowMd : kc.shadowSm,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KcRadius.panel),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onDoubleTap: widget.onDoubleTap,
                onLongPress: widget.onLongPress,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: SizedBox.expand(child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slot(Key key, IconData icon, String tip, VoidCallback? onPressed, {Color? color}) {
    final c = color ?? context.kc.text2;
    return Tooltip(
      key: key,
      message: tip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(KcRadius.control),
        child: SizedBox(width: 26, height: 26, child: Icon(icon, size: 15, color: onPressed == null ? c.withValues(alpha: 0.35) : c)),
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
}
