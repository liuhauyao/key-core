import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../services/platform/window_chrome.dart';
import '../../theme/kc_tokens.dart';

/// 空白处可拖动窗口的区域（macOS）。双击按系统偏好缩放。
class KcDragArea extends StatelessWidget {
  const KcDragArea({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => WindowChrome.startDrag(),
      onDoubleTap: WindowChrome.doubleClick,
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// 整窗路由的统一顶栏（form_v3.md §0 / §10）。
///
/// 高 52；macOS 非全屏时内容从 x = 96 开始（给红绿灯让位），否则 20。
/// 依次为：[leading]（logo 等）、标题 / 副标题、可拖动 spacer、[actions]、关闭按钮。
class KcWindowHeader extends StatelessWidget implements PreferredSizeWidget {
  const KcWindowHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.center,
    this.actions = const [],
    this.onClose,
    this.closeKey,
    this.titleKey,
    this.inset = true,
    this.showDivider = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// 标题之后、spacer 之前的附加内容（如分段控件）。
  final Widget? center;
  final List<Widget> actions;

  /// 为 null 时不显示关闭按钮。
  final VoidCallback? onClose;
  final Key? closeKey;
  final Key? titleKey;

  /// false：用于侧栏右侧的内容区页头（红绿灯在侧栏内，不需要内缩）。
  final bool inset;
  final bool showDivider;

  @override
  Size get preferredSize => const Size.fromHeight(KcSize.toolbar);

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.isFullScreen,
      builder: (context, _, __) {
        final left = inset ? WindowChrome.leadingInset : 20.0;
        return Container(
          key: const ValueKey('kcWindowHeader'),
          height: KcSize.toolbar,
          decoration: BoxDecoration(
            color: cs.background,
            border: showDivider ? Border(bottom: BorderSide(color: cs.border)) : null,
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: KcDragArea()),
              Padding(
                padding: EdgeInsets.only(left: left, right: 12),
                child: Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 10)],
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              key: titleKey ?? const ValueKey('kcWindowHeader.title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KcType.title.copyWith(color: cs.foreground, height: 1.2)),
                          if (subtitle != null && subtitle!.isNotEmpty)
                            Text(subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KcType.caption.copyWith(color: cs.mutedForeground, height: 1.25)),
                        ],
                      ),
                    ),
                    if (center != null) ...[const SizedBox(width: 16), center!],
                    const Spacer(),
                    ...actions.expand((w) => [w, const SizedBox(width: 6)]),
                    if (onClose != null)
                      ShadButton.ghost(
                        key: closeKey ?? const ValueKey('kcWindowHeader.close'),
                        width: 32,
                        height: 32,
                        padding: EdgeInsets.zero,
                        onPressed: onClose,
                        child: Icon(Icons.close, size: 18, color: cs.mutedForeground),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
