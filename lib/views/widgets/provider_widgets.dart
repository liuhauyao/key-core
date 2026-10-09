import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/provider.dart';
import '../../utils/app_localizations.dart';

/// 可一键切换的 AI 工具的展示信息
class ToolMeta {
  final String id;
  final String displayName;
  final String logoPath;

  const ToolMeta(this.id, this.displayName, this.logoPath);

  static const List<ToolMeta> all = [
    ToolMeta('claude_code', 'Claude Code', 'assets/icons/platforms/claude-color.svg'),
    ToolMeta('gemini_cli', 'Gemini CLI', 'assets/icons/platforms/gemini-color.svg'),
    ToolMeta('openclaw', 'OpenClaw', 'assets/icons/platforms/openclaw-color.svg'),
    ToolMeta('grok_build', 'Grok Build', 'assets/icons/platforms/grok.svg'),
  ];

  static ToolMeta? of(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static String nameOf(String id) => of(id)?.displayName ?? id;
}

/// 获取本地化对象；没有注册 delegate 时（例如部分测试）回退到中文内置文案
AppLocalizations l10nOf(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizations(const Locale('zh'));

/// 当前为中文界面时返回供应商中文名（与名称不同时），用于副标题
String? providerLocalizedAlias(BuildContext context, Provider provider) {
  final l = l10nOf(context);
  final zh = provider.nameZh;
  if (l.locale.languageCode != 'zh' || zh == null || zh.isEmpty) return null;
  return provider.name.contains(zh) ? null : zh;
}

/// 掩码显示 API Key（只保留末 4 位）
String maskApiKey(String? key) {
  if (key == null || key.isEmpty) return '';
  if (key.length <= 8) return '••••';
  return '••••${key.substring(key.length - 4)}';
}

class ToolLogo extends StatelessWidget {
  final String toolId;
  final double size;

  const ToolLogo(this.toolId, {super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final meta = ToolMeta.of(toolId);
    if (meta == null) return Icon(Icons.extension, size: size);
    return SvgPicture.asset(meta.logoPath, width: size, height: size);
  }
}

/// 供应商首字母头像
class ProviderAvatar extends StatelessWidget {
  final Provider provider;
  final double size;

  const ProviderAvatar(this.provider, {super.key, this.size = 40});

  static const _palette = [
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF5AC8FA),
    Color(0xFF5856D6),
  ];

  @override
  Widget build(BuildContext context) {
    final name = provider.name.trim();
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final color = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// 小号标签
class SmallTag extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;

  const SmallTag(this.text, {super.key, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final c = color ?? theme.colorScheme.mutedForeground;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.textTheme.small.copyWith(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 与顶部 AppSwitcher 一致的分段选择器
class SegmentedPills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final ValueChanged<T> onSelected;
  final Key Function(T)? keyOf;

  const SegmentedPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.leadingOf,
    this.keyOf,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: values.map((v) {
          final active = v == selected;
          return GestureDetector(
            key: keyOf?.call(v),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: active ? theme.colorScheme.background : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadingOf != null) ...[
                    leadingOf!(v),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    labelOf(v),
                    style: theme.textTheme.small.copyWith(
                      color: active
                          ? theme.colorScheme.foreground
                          : theme.colorScheme.mutedForeground,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 统一的卡片容器（圆角 12 + 边框，与密钥卡片一致）
class PanelCard extends StatelessWidget {
  final Widget child;
  final bool highlighted;
  final EdgeInsetsGeometry padding;

  const PanelCard({
    super.key,
    required this.child,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.05)
            : theme.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? theme.colorScheme.primary : theme.colorScheme.border,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
