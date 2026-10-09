// macOS 系统设置风格的设置页组件（form_v3.md §6 / settings_*.png 稿件）
//
// - KcSettingsPage：页头 52（17/600 标题 + 灰色说明），bg-subtle 底，内容列居中宽 640；
// - KcSettingsSection：11.5 灰色小标题 + 白底卡片（1px 边框、圆角 10）；
// - KcSettingsRow：单行 40 / 带说明 50，可选 28 彩色图标块或 logo，分隔线从文字左缘开始；
// - KcIconTile / KcStatusChip：图标块与状态徽标。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';

class KcSettingsPage extends StatelessWidget {
  const KcSettingsPage({super.key, required this.title, this.subtitle, required this.children});
  final String title;
  final String? subtitle;
  final List<Widget> children;

  static const double contentWidth = 640;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    return ColoredBox(
      color: kc.subtle.withValues(alpha: ShadTheme.of(context).brightness == Brightness.dark ? 0.35 : 0.55),
      child: LayoutBuilder(builder: (context, c) {
        final side = ((c.maxWidth - contentWidth) / 2).clamp(20.0, double.infinity);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            key: const ValueKey('settings.pageHeader'),
            height: KcSize.pageHeader,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600).copyWith(color: cs.foreground)),
                if (subtitle != null) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.caption.copyWith(color: cs.mutedForeground)),
                  ),
                ],
              ]),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(side, 6, side, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, w) in children.indexed) ...[if (i > 0) const SizedBox(height: 18), w],
              ]),
            ),
          ),
        ]);
      }),
    );
  }
}

class KcSettingsSection extends StatelessWidget {
  const KcSettingsSection({super.key, this.title, required this.rows, this.footer, this.dividerIndent});
  final String? title;
  final List<Widget> rows;
  final String? footer;

  /// 分隔线起点；默认：首行有图标块时 50，否则 12
  final double? dividerIndent;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final indent = dividerIndent ??
        (rows.isNotEmpty && rows.first is KcSettingsRow && (rows.first as KcSettingsRow).leading != null ? 50.0 : 12.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
          child: Text(title!, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: cs.mutedForeground)),
        ),
      Container(
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: BorderRadius.circular(KcRadius.panel),
          border: Border.all(color: cs.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: indent, color: cs.border),
            r,
          ],
        ]),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 0),
          child: Text(footer!, style: TextStyle(fontSize: 11.5, height: 1.45, color: cs.mutedForeground)),
        ),
    ]);
  }
}

class KcSettingsRow extends StatelessWidget {
  const KcSettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.danger = false,
    this.mono = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;

  /// 28px 图标块 / logo（[KcIconTile]）
  final Widget? leading;
  final Widget? trailing;
  final bool danger;

  /// 说明用等宽字体（路径）
  final bool mono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: hasSub ? 50 : 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          if (leading != null) ...[SizedBox(width: 28, height: 28, child: Center(child: leading)), const SizedBox(width: 10)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.3, color: danger ? kc.dangerText : cs.foreground)),
              if (hasSub)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono
                        ? KcType.mono.copyWith(fontSize: 11, height: 1.4, color: cs.mutedForeground)
                        : TextStyle(fontSize: 11.5, height: 1.4, color: cs.mutedForeground)),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// 28px 彩色圆角图标块（白色图标）
class KcIconTile extends StatelessWidget {
  const KcIconTile(this.icon, {super.key, required this.color, this.size = 28});
  final IconData icon;
  final Color color;
  final double size;

  static const gray = Color(0xFF8E8E93);
  static const blue = Color(0xFF007AFF);
  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9500);
  static const purple = Color(0xFF5856D6);
  static const red = Color(0xFFFF3B30);
  static const graphite = Color(0xFF1D1D1F);

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.25)),
        child: Icon(icon, size: size * 0.55, color: Colors.white),
      );
}

enum KcChipKind { ok, warn, danger, info, neutral }

class KcStatusChip extends StatelessWidget {
  const KcStatusChip(this.text, {super.key, this.kind = KcChipKind.neutral, this.icon});
  final String text;
  final KcChipKind kind;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final kc = context.kc;
    final (fg, bg) = switch (kind) {
      KcChipKind.ok => (kc.okText, kc.okSoft),
      KcChipKind.warn => (kc.warnText, kc.warnSoft),
      KcChipKind.danger => (kc.dangerText, kc.dangerSoft),
      KcChipKind.info => (kc.actionText, kc.actionSoft),
      KcChipKind.neutral => (kc.text2, kc.subtle),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 3)],
        Text(text, style: KcType.badge.copyWith(color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
