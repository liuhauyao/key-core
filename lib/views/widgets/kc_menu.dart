// 统一菜单 / 弹出选择（v3 设计语言）：
//   实色面板（亮=主题背景，暗=#1C1C1E）· 圆角 10 · 细边框 + 柔和阴影 · 内边距 6
//   行高 32 · 可选前置 logo/图标 · 选中项尾部 ✓ · 分组标题 + 分隔线 · 危险样式
//   键盘：↑/↓ 移动、Enter/空格 选择、Esc 关闭；悬停高亮；锚定在触发器正下方（放不下时翻到上方）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';

const double kcMenuRadius = 10;
const double kcMenuPadding = 6;
const double kcMenuRowHeight = 32;

/// 菜单条目
sealed class KcMenuEntry<T> {
  const KcMenuEntry();
}

class KcMenuItem<T> extends KcMenuEntry<T> {
  const KcMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.leading,
    this.trailing,
    this.danger = false,
    this.enabled = true,
    this.key,
  });
  final T value;
  final String label;
  final IconData? icon;

  /// 自定义前置（工具 / 供应商 logo），优先于 [icon]
  final Widget? leading;

  /// 右侧附加文字（计数 / 快捷键）
  final String? trailing;
  final bool danger;
  final bool enabled;
  final Key? key;
}

class KcMenuHeader<T> extends KcMenuEntry<T> {
  const KcMenuHeader(this.label);
  final String label;
}

class KcMenuDivider<T> extends KcMenuEntry<T> {
  const KcMenuDivider();
}

/// 在 [anchor]（全局坐标）下方弹出菜单，返回选中的值；关闭返回 null。
Future<T?> showKcMenu<T>({
  required BuildContext context,
  required Rect anchor,
  required List<KcMenuEntry<T>> entries,
  T? selected,
  bool? hasSelection,
  double? minWidth,
  double maxWidth = 360,
  bool alignRight = false,
}) {
  return Navigator.of(context).push<T>(_KcMenuRoute<T>(
    anchor: anchor,
    entries: entries,
    selected: selected,
    hasSelection: hasSelection ?? selected != null,
    minWidth: minWidth ?? anchor.width.clamp(180.0, maxWidth),
    maxWidth: maxWidth,
    alignRight: alignRight,
    capturedThemes: InheritedTheme.capture(from: context, to: Navigator.of(context).context),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  ));
}

Rect _rectOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero);
  return topLeft & box.size;
}

class _KcMenuRoute<T> extends PopupRoute<T> {
  _KcMenuRoute({
    required this.anchor,
    required this.entries,
    required this.selected,
    required this.hasSelection,
    required this.minWidth,
    required this.maxWidth,
    required this.alignRight,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Rect anchor;
  final List<KcMenuEntry<T>> entries;
  final T? selected;
  final bool hasSelection;
  final double minWidth;
  final double maxWidth;
  final bool alignRight;
  final CapturedThemes capturedThemes;

  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 110);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return capturedThemes.wrap(MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: Builder(builder: (context) {
        final screen = MediaQuery.sizeOf(context);
        const margin = 8.0;
        const gap = 4.0;
        final below = screen.height - anchor.bottom - gap - margin;
        final above = anchor.top - gap - margin;
        final openUp = below < 200 && above > below;
        final maxH = (openUp ? above : below).clamp(80.0, 440.0);
        return CustomSingleChildLayout(
          delegate: _MenuLayout(anchor: anchor, openUp: openUp, alignRight: alignRight, margin: margin, gap: gap),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth, maxHeight: maxH),
              child: KcMenuPanel<T>(
                entries: entries,
                selected: selected,
                hasSelection: hasSelection,
                onSelected: (v) => Navigator.of(context).pop(v),
                onDismiss: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      }),
    ));
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor, required this.openUp, required this.alignRight, required this.margin, required this.gap});
  final Rect anchor;
  final bool openUp;
  final bool alignRight;
  final double margin;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(constraints.maxWidth - margin * 2, constraints.maxHeight - margin * 2));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = alignRight ? anchor.right - childSize.width : anchor.left;
    x = x.clamp(margin, size.width - childSize.width - margin);
    var y = openUp ? anchor.top - gap - childSize.height : anchor.bottom + gap;
    y = y.clamp(margin, size.height - childSize.height - margin);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.anchor != anchor || old.openUp != openUp || old.alignRight != alignRight;
}

/// 菜单面板本体（也可单独用于测试 / 嵌入）
class KcMenuPanel<T> extends StatefulWidget {
  const KcMenuPanel({super.key, required this.entries, this.selected, bool? hasSelection, required this.onSelected, this.onDismiss})
      : hasSelection = hasSelection ?? selected != null;
  final List<KcMenuEntry<T>> entries;
  final T? selected;
  final bool hasSelection;
  final ValueChanged<T> onSelected;
  final VoidCallback? onDismiss;

  /// 面板底色（测试用）
  static Color surfaceColor(BuildContext context) => ShadTheme.of(context).colorScheme.background;

  @override
  State<KcMenuPanel<T>> createState() => _KcMenuPanelState<T>();
}

class _KcMenuPanelState<T> extends State<KcMenuPanel<T>> {
  late int _active;
  final _focus = FocusNode(debugLabel: 'KcMenu');

  List<int> get _selectable => [
        for (final (i, e) in widget.entries.indexed)
          if (e is KcMenuItem<T> && e.enabled) i,
      ];

  @override
  void initState() {
    super.initState();
    final sel = widget.entries.indexWhere((e) => e is KcMenuItem<T> && e.enabled && e.value == widget.selected);
    _active = widget.hasSelection && sel >= 0 ? sel : -1;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _move(int dir) {
    final s = _selectable;
    if (s.isEmpty) return;
    final pos = s.indexOf(_active);
    final next = pos < 0 ? (dir > 0 ? 0 : s.length - 1) : (pos + dir) % s.length;
    setState(() => _active = s[next < 0 ? s.length - 1 : next]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.home) {
      if (_selectable.isNotEmpty) setState(() => _active = _selectable.first);
    } else if (k == LogicalKeyboardKey.end) {
      if (_selectable.isNotEmpty) setState(() => _active = _selectable.last);
    } else if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.space) {
      if (_active >= 0) widget.onSelected((widget.entries[_active] as KcMenuItem<T>).value);
    } else if (k == LogicalKeyboardKey.escape) {
      widget.onDismiss?.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          key: const ValueKey('kcMenu.panel'),
          decoration: BoxDecoration(
            color: KcMenuPanel.surfaceColor(context),
            borderRadius: BorderRadius.circular(kcMenuRadius),
            border: Border.all(color: cs.border),
            boxShadow: kc.shadowLg,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kcMenuRadius),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(kcMenuPadding),
              child: IntrinsicWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  for (final (i, e) in widget.entries.indexed) _entry(context, i, e),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, int i, KcMenuEntry<T> e) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    switch (e) {
      case KcMenuDivider<T>():
        return Padding(
          key: ValueKey('kcMenu.divider.$i'),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Divider(height: 1, thickness: 1, color: cs.border),
        );
      case KcMenuHeader<T>(:final label):
        return Padding(
          padding: EdgeInsets.fromLTRB(8, i == 0 ? 2 : 6, 8, 2),
          child: Text(label, style: KcType.caption.copyWith(color: cs.mutedForeground, fontWeight: FontWeight.w600)),
        );
      case KcMenuItem<T>():
        final active = i == _active;
        final isSel = widget.hasSelection && e.value == widget.selected;
        final fg = !e.enabled ? cs.mutedForeground.withValues(alpha: 0.6) : (e.danger ? kc.dangerText : cs.foreground);
        final hasLeadingCol = widget.entries.any((x) => x is KcMenuItem<T> && (x.icon != null || x.leading != null));
        return MouseRegion(
          cursor: e.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) {
            if (e.enabled) setState(() => _active = i);
          },
          child: GestureDetector(
            key: e.key,
            behavior: HitTestBehavior.opaque,
            onTap: e.enabled ? () => widget.onSelected(e.value) : null,
            child: Container(
              key: ValueKey('kcMenu.row.$i'),
              height: kcMenuRowHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: active ? (e.danger ? kc.dangerSoft : kc.subtle) : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                if (hasLeadingCol) ...[
                  SizedBox(
                    width: 18,
                    child: e.leading ?? (e.icon != null ? Icon(e.icon, size: 16, color: e.danger ? kc.dangerText : kc.text2) : null),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  fit: FlexFit.tight,
                  child: Text(e.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.body.copyWith(color: fg)),
                ),
                if (e.trailing != null) ...[
                  const SizedBox(width: 12),
                  Text(e.trailing!, style: KcType.caption.copyWith(color: cs.mutedForeground, fontFeatures: KcType.tabular)),
                ],
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  child: isSel ? Icon(Icons.check, size: 15, color: cs.primary, key: const ValueKey('kcMenu.check')) : null,
                ),
              ]),
            ),
          ),
        );
    }
  }
}

/// 点击 [child] 弹出菜单
class KcMenuButton<T> extends StatelessWidget {
  const KcMenuButton({
    super.key,
    required this.entries,
    required this.onSelected,
    required this.child,
    this.selected,
    this.hasSelection,
    this.tooltip,
    this.alignRight = false,
    this.minWidth,
    this.onOpen,
    this.onClose,
  });

  final List<KcMenuEntry<T>> Function() entries;
  final ValueChanged<T> onSelected;
  final Widget child;
  final T? selected;
  final bool? hasSelection;
  final String? tooltip;
  final bool alignRight;
  final double? minWidth;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  Future<void> open(BuildContext context) async {
    onOpen?.call();
    final v = await showKcMenu<T>(
      context: context,
      anchor: _rectOf(context),
      entries: entries(),
      selected: selected,
      hasSelection: hasSelection,
      alignRight: alignRight,
      minWidth: minWidth,
    );
    onClose?.call();
    if (v != null) onSelected(v);
  }

  @override
  Widget build(BuildContext context) {
    Widget w = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => open(context),
        child: IgnorePointer(child: child),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) w = Tooltip(message: tooltip!, child: w);
    return w;
  }
}

/// 值选择器（取代 DropdownButton / ShadSelect）：32 高描边触发器 + KcMenu
class KcSelect<T> extends StatelessWidget {
  const KcSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.width,
    this.leadingOf,
  });

  final T? value;

  /// (值, 文案)
  final List<(T, String)> options;
  final ValueChanged<T>? onChanged;
  final String? placeholder;
  final double? width;

  /// 可选：每个选项的前置 logo
  final Widget? Function(T value)? leadingOf;

  String? get _label {
    for (final (v, l) in options) {
      if (v == value) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final label = _label;
    final lead = value != null && leadingOf != null ? leadingOf!(value as T) : null;
    final trigger = Container(
      width: width,
      height: KcSize.control,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: cs.background,
        border: Border.all(color: cs.border),
        borderRadius: BorderRadius.circular(KcRadius.control),
      ),
      child: Row(mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max, children: [
        if (lead != null) ...[SizedBox(width: 16, height: 16, child: lead), const SizedBox(width: 6)],
        Flexible(
          fit: width == null ? FlexFit.loose : FlexFit.tight,
          child: Text(label ?? placeholder ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KcType.body.copyWith(color: label == null ? cs.mutedForeground : cs.foreground)),
        ),
        const SizedBox(width: 6),
        Icon(Icons.expand_more, size: 16, color: kc.text2),
      ]),
    );
    if (onChanged == null) return Opacity(opacity: 0.5, child: trigger);
    return KcMenuButton<T>(
      selected: value,
      hasSelection: true,
      onSelected: onChanged!,
      entries: () => [
        for (final (v, l) in options) KcMenuItem<T>(value: v, label: l, leading: leadingOf?.call(v)),
      ],
      child: trigger,
    );
  }
}
