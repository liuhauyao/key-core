// 密枢设计 token（ui_redesign_plan.md §4）。
//
// 只放数据：两份 ShadColorScheme（浅 / 深）+ 一个 ThemeExtension<KcTokens>，
// 后者存放 shadcn 方案里没有的槽位（侧栏、选中、ok / warn / danger 语义色、工具 glyph 色、
// 圆角 / 间距 / 尺寸常量）。不新增 Provider，不建并行主题系统：
// main.dart 仍是一个 ShadTheme + 一个 MaterialApp.theme，KcTokens 挂在 ThemeData.extensions 上。
//
// 取值：`ShadTheme.of(context).colorScheme.*` 或 `context.kc.*`。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 圆角（§4.2）。
abstract final class KcRadius {
  /// 按钮、输入框、侧栏行
  static const double control = 6;

  /// 卡片、通知条、toast
  static const double panel = 10;

  /// 对话框、抽屉
  static const double dialog = 14;

  /// logo 容器（36px）
  static const double logo = 8;
}

/// 间距（4px 网格，§4.2）。
abstract final class KcSpace {
  static const double x1 = 4;
  static const double x1_5 = 6;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;

  /// 页面左右 padding
  static const double page = 24;
}

/// 控件尺寸（§4.2）。
abstract final class KcSize {
  static const double controlSm = 28;
  static const double control = 32;
  static const double tab = 36;
  static const double chip = 24;
  static const double badge = 20;
  static const double sidebar = 200;
  static const double sidebarRail = 72;
  static const double pageHeader = 52;

  /// v3 顶栏高度：红绿灯在其中垂直居中（form_v3.md §10）
  static const double toolbar = 52;

  /// macOS 非全屏时，红绿灯右侧内容的起始 x（灯组右缘约 81.5 + 14.5）
  static const double macTrafficInset = 96;
}

/// 动效（§4.4）。
abstract final class KcMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration slide = Duration(milliseconds: 200);
  static const Curve curve = Cubic(0.4, 0, 0.2, 1);

  /// 尊重系统「减少动态效果」
  static Duration of(BuildContext context, [Duration d = fast]) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// 工具 glyph 色：只用于 18px 图标块，不作大面积背景（§4.1）。
abstract final class KcToolColors {
  static const Color claude = Color(0xFFD97757);
  static const Color claudeDesktop = Color(0xFFC2410C);
  static const Color codex = Color(0xFF18181B);
  static const Color gemini = Color(0xFF4285F4);
  static const Color openclaw = Color(0xFFE11D48);
}

/// 平台 / 工具 logo 容器（§4.6）：明暗模式都保持白底 + 1px 描边，
/// 保证 fill="currentColor" 的单色品牌 SVG 在深色下可见。
abstract final class KcLogo {
  static const Color containerBg = Color(0xFFFFFFFF);
  static const Color containerBorder = Color(0xFFE4E4E9);
}

/// 字体规格（§4.3）。系统字体，不打包字体；数字等宽。
abstract final class KcType {
  static const List<String> monoFamilyFallback = [
    'SF Mono', 'JetBrains Mono', 'Menlo', 'Consolas', 'DejaVu Sans Mono', 'monospace',
  ];
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle page = TextStyle(fontSize: 18, height: 26 / 18, fontWeight: FontWeight.w600);
  static const TextStyle title = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600);
  static const TextStyle section = TextStyle(fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w600);
  static const TextStyle strong = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);
  static const TextStyle body = TextStyle(fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w400);
  static const TextStyle caption = TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w400);
  static const TextStyle badge = TextStyle(fontSize: 11, height: 16 / 11, fontWeight: FontWeight.w500);
  static const TextStyle mono = TextStyle(
    fontSize: 12,
    fontFamily: 'monospace',
    fontFamilyFallback: monoFamilyFallback,
    fontFeatures: tabular,
  );
}

/// 浅 / 深两份 shadcn 配色（§4.1 表格「映射到」一列）。
abstract final class KcColorSchemes {
  static const ShadColorScheme light = ShadColorScheme(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF18181B),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF18181B),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF18181B),
    primary: Color(0xFF007AFF),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFFEFEFF2),
    secondaryForeground: Color(0xFF18181B),
    muted: Color(0xFFEFEFF2),
    mutedForeground: Color(0xFF65656E),
    accent: Color(0xFFEFEFF2),
    accentForeground: Color(0xFF18181B),
    destructive: Color(0xFFDC2626),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFE4E4E9),
    input: Color(0xFFCFCFD6),
    ring: Color(0xFF007AFF),
    selection: Color(0x40007AFF),
  );

  static const ShadColorScheme dark = ShadColorScheme(
    background: Color(0xFF1C1C1E),
    foreground: Color(0xFFF4F4F5),
    card: Color(0xFF2E2E33),
    cardForeground: Color(0xFFF4F4F5),
    popover: Color(0xFF2E2E33),
    popoverForeground: Color(0xFFF4F4F5),
    primary: Color(0xFF0A84FF),
    primaryForeground: Color(0xFFFFFFFF),
    secondary: Color(0xFF26262A),
    secondaryForeground: Color(0xFFF4F4F5),
    muted: Color(0xFF26262A),
    mutedForeground: Color(0xFFA9A9B2),
    accent: Color(0xFF26262A),
    accentForeground: Color(0xFFF4F4F5),
    destructive: Color(0xFFF87171),
    destructiveForeground: Color(0xFF1C1C1E),
    border: Color(0xFF3A3A40),
    input: Color(0xFF4A4A52),
    ring: Color(0xFF0A84FF),
    selection: Color(0x550A84FF),
  );
}

/// shadcn 方案之外的 token。
@immutable
class KcTokens extends ThemeExtension<KcTokens> {
  const KcTokens({
    required this.sidebar,
    required this.selected,
    required this.subtle,
    required this.text2,
    required this.actionHover,
    required this.actionText,
    required this.actionSoft,
    required this.ok,
    required this.okText,
    required this.okSoft,
    required this.warn,
    required this.warnText,
    required this.warnSoft,
    required this.danger,
    required this.dangerText,
    required this.dangerSoft,
    required this.overlay,
    required this.shadowColor,
  });

  final Color sidebar;
  final Color selected;
  final Color subtle;
  final Color text2;
  final Color actionHover;
  final Color actionText;
  final Color actionSoft;
  final Color ok;
  final Color okText;
  final Color okSoft;
  final Color warn;
  final Color warnText;
  final Color warnSoft;
  final Color danger;
  final Color dangerText;
  final Color dangerSoft;
  final Color overlay;
  final Color shadowColor;

  static const KcTokens light = KcTokens(
    sidebar: Color(0xFFF5F5F7),
    selected: Color(0xFFE4E4EA),
    subtle: Color(0xFFEFEFF2),
    text2: Color(0xFF52525B),
    actionHover: Color(0xFF0066D6),
    actionText: Color(0xFF0060C7),
    actionSoft: Color(0xFFEAF3FF),
    ok: Color(0xFF16A34A),
    okText: Color(0xFF007634),
    okSoft: Color(0xFFE8F7EE),
    warn: Color(0xFFD97706),
    warnText: Color(0xFFA64A00),
    warnSoft: Color(0xFFFEF3C7),
    danger: Color(0xFFDC2626),
    dangerText: Color(0xFFB91C1C),
    dangerSoft: Color(0xFFFEE2E2),
    overlay: Color(0x5C09090B),
    shadowColor: Color(0x1A000000),
  );

  static const KcTokens dark = KcTokens(
    sidebar: Color(0xFF161618),
    selected: Color(0xFF313136),
    subtle: Color(0xFF26262A),
    text2: Color(0xFFD0D0D8),
    actionHover: Color(0xFF2B95FF),
    actionText: Color(0xFF5AA9FF),
    actionSoft: Color(0x240A84FF),
    ok: Color(0xFF30D158),
    okText: Color(0xFF4ADE80),
    okSoft: Color(0x2130D158),
    warn: Color(0xFFF59E0B),
    warnText: Color(0xFFFBBF24),
    warnSoft: Color(0x24F59E0B),
    danger: Color(0xFFF87171),
    dangerText: Color(0xFFFCA5A5),
    dangerSoft: Color(0x24F87171),
    overlay: Color(0x8C000000),
    shadowColor: Color(0x66000000),
  );

  static KcTokens of(Brightness b) => b == Brightness.dark ? dark : light;

  /// 卡片默认 / hover 阴影（CC Switch：极淡阴影 + hover 加深）
  List<BoxShadow> get shadowSm => [BoxShadow(color: shadowColor.withValues(alpha: shadowColor.a * 0.6), blurRadius: 2, offset: const Offset(0, 1))];
  List<BoxShadow> get shadowMd => [BoxShadow(color: shadowColor, blurRadius: 12, offset: const Offset(0, 4))];
  List<BoxShadow> get shadowLg => [BoxShadow(color: shadowColor.withValues(alpha: (shadowColor.a * 1.6).clamp(0, 1)), blurRadius: 28, offset: const Offset(0, 12))];

  @override
  KcTokens copyWith({
    Color? sidebar,
    Color? selected,
    Color? subtle,
    Color? text2,
    Color? actionHover,
    Color? actionText,
    Color? actionSoft,
    Color? ok,
    Color? okText,
    Color? okSoft,
    Color? warn,
    Color? warnText,
    Color? warnSoft,
    Color? danger,
    Color? dangerText,
    Color? dangerSoft,
    Color? overlay,
    Color? shadowColor,
  }) {
    return KcTokens(
      sidebar: sidebar ?? this.sidebar,
      selected: selected ?? this.selected,
      subtle: subtle ?? this.subtle,
      text2: text2 ?? this.text2,
      actionHover: actionHover ?? this.actionHover,
      actionText: actionText ?? this.actionText,
      actionSoft: actionSoft ?? this.actionSoft,
      ok: ok ?? this.ok,
      okText: okText ?? this.okText,
      okSoft: okSoft ?? this.okSoft,
      warn: warn ?? this.warn,
      warnText: warnText ?? this.warnText,
      warnSoft: warnSoft ?? this.warnSoft,
      danger: danger ?? this.danger,
      dangerText: dangerText ?? this.dangerText,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      overlay: overlay ?? this.overlay,
      shadowColor: shadowColor ?? this.shadowColor,
    );
  }

  @override
  KcTokens lerp(ThemeExtension<KcTokens>? other, double t) {
    if (other is! KcTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KcTokens(
      sidebar: l(sidebar, other.sidebar),
      selected: l(selected, other.selected),
      subtle: l(subtle, other.subtle),
      text2: l(text2, other.text2),
      actionHover: l(actionHover, other.actionHover),
      actionText: l(actionText, other.actionText),
      actionSoft: l(actionSoft, other.actionSoft),
      ok: l(ok, other.ok),
      okText: l(okText, other.okText),
      okSoft: l(okSoft, other.okSoft),
      warn: l(warn, other.warn),
      warnText: l(warnText, other.warnText),
      warnSoft: l(warnSoft, other.warnSoft),
      danger: l(danger, other.danger),
      dangerText: l(dangerText, other.dangerText),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      overlay: l(overlay, other.overlay),
      shadowColor: l(shadowColor, other.shadowColor),
    );
  }
}

/// `context.kc`：读当前主题的 KcTokens。
///
/// 优先用 ThemeData.extensions；没挂扩展时（例如单测里裸用 ShadTheme）按 ShadTheme 的亮度回退。
extension KcTokensContext on BuildContext {
  KcTokens get kc {
    final ext = Theme.of(this).extension<KcTokens>();
    if (ext != null) {
      final shad = ShadTheme.maybeOf(this);
      // ShadTheme 与 Material 主题亮度不一致时，以 ShadTheme 为准（shadcn 组件看到的是它）
      if (shad != null && shad.brightness != Theme.of(this).brightness) {
        return KcTokens.of(shad.brightness);
      }
      return ext;
    }
    return KcTokens.of(ShadTheme.maybeOf(this)?.brightness ?? Theme.of(this).brightness);
  }
}

/// 应用主题构建（main.dart 与测试共用，保证 golden 与真机一致）。
abstract final class KcTheme {
  static ShadThemeData shad(Brightness brightness) {
    final scheme = brightness == Brightness.dark ? KcColorSchemes.dark : KcColorSchemes.light;
    return ShadThemeData(
      brightness: brightness,
      colorScheme: scheme,
      radius: BorderRadius.circular(KcRadius.control),
    );
  }

  static ThemeData material(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final s = isDark ? KcColorSchemes.dark : KcColorSchemes.light;
    final kc = KcTokens.of(brightness);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: s.primary,
        brightness: brightness,
        primary: s.primary,
        onPrimary: s.primaryForeground,
        surface: s.background,
        onSurface: s.foreground,
        error: s.destructive,
        outline: s.border,
      ),
      primaryColor: s.primary,
      scaffoldBackgroundColor: s.background,
      canvasColor: s.background,
      dividerColor: s.border,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: s.background,
        foregroundColor: s.foreground,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: KcType.page.copyWith(color: s.foreground),
      ),
      cardTheme: CardThemeData(
        color: s.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KcRadius.panel),
          side: BorderSide(color: s.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.card,
        surfaceTintColor: Colors.transparent,
        barrierColor: kc.overlay,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KcRadius.dialog)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF3A3A40) : const Color(0xFF27272A),
        contentTextStyle: KcType.body.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KcRadius.panel)),
        width: 420,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 400),
        textStyle: KcType.caption.copyWith(color: isDark ? s.background : Colors.white),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFFE4E4E9) : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(KcRadius.control),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? s.primary : (isDark ? const Color(0xFF4A4A52) : const Color(0xFFD4D4D8))),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: KcSpace.x4, vertical: KcSpace.x2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KcRadius.control)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(KcRadius.control)),
        filled: true,
        fillColor: s.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: KcSpace.x3, vertical: KcSpace.x2),
      ),
      extensions: [kc],
    );
  }
}
