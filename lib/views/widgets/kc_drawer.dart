// 统一右侧抽屉（密钥 / MCP / Skills 详情共用）：
//   · 实色面板：亮色 = colorScheme.background(白)，暗色 = background(#1C1C1E)；不再有半透明灰
//     （旧实现给无填充色的 Container 加 boxShadow，阴影从面板下透出来，整块发灰）
//   · 统一遮罩 kc.overlay、宽 560（窄窗全宽）、左边线、阴影只在面板外侧
//   · 统一页头（KcDrawerHeader）与固定底栏（KcDrawerFooter）
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';

const double kcDrawerWidth = 560;

/// 以右侧抽屉方式打开（统一遮罩 + 滑入动画）
Future<T?> showKcDrawer<T>({required BuildContext context, required WidgetBuilder builder}) {
  final kc = context.kc;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: kc.overlay,
    transitionDuration: KcMotion.of(context, KcMotion.slide),
    pageBuilder: (ctx, _, __) => Align(alignment: Alignment.centerRight, child: builder(ctx)),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: KcMotion.curve)),
      child: child,
    ),
  );
}

/// 抽屉面板：header / (tabs) / 可滚动 body / 固定 footer
class KcDrawerSurface extends StatelessWidget {
  const KcDrawerSurface({
    super.key,
    required this.header,
    required this.body,
    this.tabs,
    this.footer,
  });

  final Widget header;
  final Widget? tabs;
  final Widget body;
  final Widget? footer;

  /// 抽屉面板底色（测试与截图校验用）
  static Color surfaceColor(BuildContext context) => ShadTheme.of(context).colorScheme.background;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final bg = surfaceColor(context);
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width < 640 ? width : kcDrawerWidth,
        height: double.infinity,
        decoration: BoxDecoration(
          color: bg, // 实色填充：阴影不会再透进面板
          border: Border(left: BorderSide(color: cs.border)),
          boxShadow: context.kc.shadowLg,
        ),
        child: SafeArea(
          left: false,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            if (tabs != null) tabs!,
            Divider(height: 1, thickness: 1, color: cs.border),
            Expanded(child: body),
            if (footer != null) ...[
              Divider(height: 1, thickness: 1, color: cs.border),
              footer!,
            ],
          ]),
        ),
      ),
    );
  }
}

/// 统一页头：logo + 标题/副标题 + 操作 + 关闭
class KcDrawerHeader extends StatelessWidget {
  const KcDrawerHeader({super.key, this.leading, required this.title, this.subtitle, this.actions = const [], this.onClose});

  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> actions;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x4, KcSpace.x3, KcSpace.x3),
      child: Row(children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            DefaultTextStyle.merge(style: KcType.title.copyWith(color: cs.foreground), maxLines: 1, overflow: TextOverflow.ellipsis, child: title),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              DefaultTextStyle.merge(style: KcType.caption.copyWith(color: cs.mutedForeground), maxLines: 1, overflow: TextOverflow.ellipsis, child: subtitle!),
            ],
          ]),
        ),
        ...actions,
        IconButton(
          key: const ValueKey('kcDrawer.close'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClose ?? () => Navigator.of(context).maybePop(),
          icon: Icon(Icons.close, size: 18, color: context.kc.text2),
        ),
      ]),
    );
  }
}

/// 固定底栏：左侧（危险/次要）+ 右侧（主要）
class KcDrawerFooter extends StatelessWidget {
  const KcDrawerFooter({super.key, this.leading = const [], this.trailing = const []});
  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('kcDrawer.footer'),
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: KcSpace.page),
          child: Row(children: [
            ...leading,
            const Spacer(),
            for (final (i, w) in trailing.indexed) ...[if (i > 0) const SizedBox(width: 8), w],
          ]),
        ),
      );
}
