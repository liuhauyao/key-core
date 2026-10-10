// 统一控件规格（v4）：按钮 sm 28 / md 32、圆角 6、字号 13；紧凑开关 32×18。
// 全局 ShadButton 尺寸/字号已在 KcTheme.shad 里按同一规格设置；这里提供显式用法与开关。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';

/// 控件规格常量（form_v3 §0：控件 26–32；v4 统一为 sm 28 / md 32）
abstract final class KcControl {
  static const double sm = 28;
  static const double md = 32;
  static const double radius = 6;
  static const double fontSize = 13;
  static const EdgeInsets padSm = EdgeInsets.symmetric(horizontal: 10);
  static const EdgeInsets padMd = EdgeInsets.symmetric(horizontal: 12);
  static const double switchW = 32;
  static const double switchH = 18;
}

enum KcButtonVariant { primary, secondary, outline, ghost, danger }

enum KcButtonSize { sm, md }

/// 统一按钮：高度固定（sm 28 / md 32），宽度随内容（文字不截断），图标 14。
class KcButton extends StatelessWidget {
  const KcButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = KcButtonVariant.outline,
    this.size = KcButtonSize.md,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final KcButtonVariant variant;
  final KcButtonSize size;

  @override
  Widget build(BuildContext context) {
    final h = size == KcButtonSize.sm ? KcControl.sm : KcControl.md;
    final pad = size == KcButtonSize.sm ? KcControl.padSm : KcControl.padMd;
    final lead = icon == null ? null : Icon(icon, size: 14);
    final child = Text(label, maxLines: 1, softWrap: false);
    return switch (variant) {
      KcButtonVariant.primary => ShadButton(height: h, padding: pad, leading: lead, onPressed: onPressed, child: child),
      KcButtonVariant.secondary => ShadButton.secondary(height: h, padding: pad, leading: lead, onPressed: onPressed, child: child),
      KcButtonVariant.outline => ShadButton.outline(height: h, padding: pad, leading: lead, onPressed: onPressed, child: child),
      KcButtonVariant.ghost => ShadButton.ghost(height: h, padding: pad, leading: lead, onPressed: onPressed, child: child),
      KcButtonVariant.danger => ShadButton.outline(
          height: h,
          padding: pad,
          leading: lead,
          foregroundColor: context.kc.dangerText,
          hoverForegroundColor: context.kc.dangerText,
          onPressed: onPressed,
          child: child,
        ),
    };
  }
}

/// 紧凑开关 32×18（macOS 风格），所有开关统一用它。
///
/// 兼容旧 Material Switch 的几个颜色参数（忽略），便于原位替换。
class KcSwitch extends StatelessWidget {
  const KcSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    // ↓ 旧 Switch 参数：统一规格后忽略
    Color? activeTrackColor,
    Color? activeColor,
    Color? inactiveThumbColor,
    Color? inactiveTrackColor,
    MaterialTapTargetSize? materialTapTargetSize,
    WidgetStateProperty<Color?>? trackOutlineColor,
    WidgetStateProperty<Color?>? thumbColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    final enabled = onChanged != null;
    final track = value ? cs.primary : (dark ? const Color(0xFF4A4A52) : const Color(0xFFD4D4D8));
    void toggle() => onChanged?.call(!value);
    // Align：外层若给紧约束（如 SizedBox(height: 24)），开关仍保持 32×18 并居中
    return Align(widthFactor: 1, heightFactor: 1, child: Semantics(
      toggled: value,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        shortcuts: const {SingleActivator(LogicalKeyboardKey.space): ActivateIntent()},
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => toggle())},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? toggle : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: KcControl.switchW,
              height: KcControl.switchH,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(KcControl.switchH / 2)),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}
