// 应用外壳导航（ui_redesign_plan §2.2 / §5.1）：左侧 200px 侧栏，窄窗口（<900）收为 72px 图标轨。
// `AppType` 仍是唯一的导航数据源；Claude Code / Claude Desktop 拆为两行，共用 ClaudeConfigScreen。
import 'package:flutter/material.dart';
import '../../services/platform/window_chrome.dart';
import 'kc_window_header.dart' show KcDragArea;
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/ai_key.dart';
import '../../models/mcp_server.dart';
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../screens/settings_screen.dart' show SettingsCategory, SettingsScreen;
import 'kc_logo.dart';

/// 应用类型枚举（导航数据源）
enum AppType {
  keyManager(Icons.vpn_key_outlined, null, null),
  claudeCode(Icons.code, 'assets/icons/platforms/claude-color.svg', AiToolType.claudecode),
  claudeDesktop(Icons.desktop_windows_outlined, 'assets/icons/platforms/claude-color.svg', AiToolType.claudeDesktop),
  codex(Icons.terminal, 'assets/icons/platforms/openai.svg', AiToolType.codex),
  gemini(Icons.auto_awesome, 'assets/icons/platforms/gemini-color.svg', AiToolType.gemini),
  openClaw(Icons.cruelty_free, 'assets/icons/platforms/openclaw-color.svg', AiToolType.openclaw),
  mcp(Icons.dns_outlined, 'assets/icons/platforms/mcp.svg', null),
  skills(Icons.auto_awesome_outlined, null, null),
  settings(Icons.settings_outlined, null, null);

  const AppType(this.icon, this.logoPath, this.tool);
  final IconData icon;
  final String? logoPath;

  /// 对应的 AI 工具（工具行才有）
  final AiToolType? tool;

  bool get isTool => tool != null;

  String getLabel(BuildContext? context) {
    final localizations = context != null ? AppLocalizations.of(context) : null;
    switch (this) {
      case AppType.keyManager:
        return localizations?.keys ?? '钥匙包';
      case AppType.claudeCode:
        return 'Claude Code';
      case AppType.claudeDesktop:
        return 'Claude Desktop';
      case AppType.codex:
        return 'Codex';
      case AppType.gemini:
        return 'Gemini';
      case AppType.openClaw:
        return 'OpenClaw';
      case AppType.mcp:
        return localizations?.mcpServersNav ?? 'MCP';
      case AppType.skills:
        return localizations?.skills ?? 'Skills';
      case AppType.settings:
        return localizations?.settings ?? '设置';
    }
  }

  /// 根据已启用的工具计算可见页面（钥匙包 / MCP / Skills / 设置始终可见）
  static List<AppType> visibleFor(List<AiToolType> enabledTools) {
    return AppType.values.where((app) {
      final tool = app.tool;
      if (tool == null) return true;
      return enabledTools.contains(tool);
    }).toList();
  }
}

/// 侧栏宽度断点：窗口宽度小于该值时收为图标轨
const double kSidebarCollapseBreakpoint = 900;

IconData _settingsIcon(SettingsCategory c) {
  switch (c) {
    case SettingsCategory.general:
      return Icons.tune;
    case SettingsCategory.tools:
      return Icons.build_outlined;
    case SettingsCategory.data:
      return Icons.storage_outlined;
    case SettingsCategory.security:
      return Icons.shield_outlined;
    case SettingsCategory.about:
      return Icons.info_outline;
  }
}

/// 全局侧栏
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.activeApp,
    required this.apps,
    required this.onSwitch,
    this.collapsed = false,
    this.settingsCategory = SettingsCategory.general,
    this.onSettingsCategory,
  });

  final AppType activeApp;

  /// 可见页面（顺序即 PageView 顺序）
  final List<AppType> apps;
  final ValueChanged<AppType> onSwitch;
  final bool collapsed;
  final SettingsCategory settingsCategory;
  final ValueChanged<SettingsCategory>? onSettingsCategory;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l10n = AppLocalizations.of(context);

    final inSettings = activeApp == AppType.settings;
    final children = <Widget>[
      _Brand(collapsed: collapsed),
      const SizedBox(height: KcSpace.x2),
      if (inSettings) ..._settingsItems(context, l10n) else ..._appItems(context, l10n),
    ];

    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.isFullScreen,
      builder: (context, _, __) => _buildShell(context, cs, kc, children, inSettings),
    );
  }

  Widget _buildShell(BuildContext context, ShadColorScheme cs, KcTokens kc, List<Widget> children, bool inSettings) {
    // macOS：顶部 52px 是拖动条，红绿灯在其中垂直居中；全屏 12；Windows / Linux 10（form_v3.md §10）
    final topInset = WindowChrome.sidebarTopInset;
    final shell = Semantics(
      container: true,
      label: 'sidebar',
      child: AnimatedContainer(
        key: const ValueKey('appSidebar'),
        duration: KcMotion.of(context, KcMotion.fast),
        curve: KcMotion.curve,
        width: collapsed ? KcSize.sidebarRail : KcSize.sidebar,
        padding: EdgeInsets.fromLTRB(KcSpace.x2, topInset, KcSpace.x2, KcSpace.x2),
        decoration: BoxDecoration(
          color: kc.sidebar,
          border: Border(right: BorderSide(color: cs.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              // primary:false —— 否则在移动端默认平台（含 widget 测试）会抢占 PrimaryScrollController，
              // 与钥匙包 ReorderableWrap 的内部滚动冲突（"ScrollController attached to multiple scroll views"）
              child: SingleChildScrollView(
                primary: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
            if (!inSettings) ...[
              Divider(height: KcSpace.x4, thickness: 1, color: cs.border),
              _SidebarRow(
                key: const ValueKey('sidebar.settings'),
                app: AppType.settings,
                leading: Icon(AppType.settings.icon, size: 16, color: kc.text2),
                label: AppType.settings.getLabel(context),
                selected: false,
                collapsed: collapsed,
                onTap: () => onSwitch(AppType.settings),
              ),
            ],
          ],
        ),
      ),
    );
    if (!WindowChrome.isMacOS) return shell;
    return Stack(children: [
      shell,
      Positioned(top: 0, left: 0, right: 0, height: topInset, child: const KcDragArea()),
    ]);
  }

  List<Widget> _settingsItems(BuildContext context, AppLocalizations? l10n) {
    final kc = context.kc;
    final cats = l10n != null
        ? SettingsScreen.categoryLabels(l10n)
        : SettingsCategory.values.map((c) => (c.name, c)).toList();
    return [
      _SidebarRow(
        key: const ValueKey('sidebar.backToKeys'),
        leading: Icon(Icons.arrow_back, size: 16, color: kc.text2),
        label: l10n?.backToKeys ?? '返回钥匙包',
        selected: false,
        collapsed: collapsed,
        onTap: () => onSwitch(AppType.keyManager),
      ),
      _SectionLabel(text: AppType.settings.getLabel(context), collapsed: collapsed),
      for (final (label, cat) in cats)
        _SidebarRow(
          key: ValueKey('sidebar.settings.${cat.name}'),
          leading: Icon(_settingsIcon(cat), size: 16, color: cat == settingsCategory ? ShadTheme.of(context).colorScheme.foreground : kc.text2),
          label: label,
          selected: cat == settingsCategory,
          collapsed: collapsed,
          onTap: () => onSettingsCategory?.call(cat),
        ),
    ];
  }

  List<Widget> _appItems(BuildContext context, AppLocalizations? l10n) {
    final vm = context.watch<KeyManagerViewModel>();
    final kc = context.kc;
    final cs = ShadTheme.of(context).colorScheme;
    final tools = apps.where((a) => a.isTool).toList();
    final mcpCount = _maybeCount<McpViewModel>(context, (v) => v.allServers.length);
    final skillsCount = _maybeCount<SkillsViewModel>(context, (v) => v.allSkills.length);

    Widget leadingFor(AppType app) {
      if (app.tool != null) return KcToolLogo(tool: app.tool!, size: 18);
      final selected = app == activeApp;
      return Icon(app.icon, size: 16, color: selected ? cs.foreground : kc.text2);
    }

    return [
      _SidebarRow(
        key: const ValueKey('sidebar.keyManager'),
        app: AppType.keyManager,
        leading: leadingFor(AppType.keyManager),
        label: AppType.keyManager.getLabel(context),
        trailing: '${vm.allKeys.length}',
        selected: activeApp == AppType.keyManager,
        collapsed: collapsed,
        primary: true,
        onTap: () => onSwitch(AppType.keyManager),
      ),
      if (tools.isNotEmpty) _SectionLabel(text: l10n?.sidebarToolsSection ?? '工具 · 按工具查看密钥', collapsed: collapsed),
      for (final app in tools)
        _toolRow(context, app, vm, l10n, leadingFor(app)),
      _SectionLabel(text: l10n?.sidebarExtensionsSection ?? '扩展', collapsed: collapsed),
      for (final app in const [AppType.mcp, AppType.skills])
        if (apps.contains(app))
          _SidebarRow(
            key: ValueKey('sidebar.${app.name}'),
            app: app,
            leading: leadingFor(app),
            label: app.getLabel(context),
            trailing: switch (app) {
              AppType.mcp => (mcpCount ?? 0) > 0 ? '$mcpCount' : null,
              AppType.skills => (skillsCount ?? 0) > 0 ? '$skillsCount' : null,
              _ => null,
            },
            selected: activeApp == app,
            collapsed: collapsed,
            onTap: () => onSwitch(app),
          ),
    ];
  }

  Widget _toolRow(BuildContext context, AppType app, KeyManagerViewModel vm, AppLocalizations? l10n, Widget leading) {
    final kc = context.kc;
    final cs = ShadTheme.of(context).colorScheme;
    String? trailing;
    Color? trailingColor;
    final tool = app.tool!;
    if (tool == AiToolType.openclaw) {
      final n = vm.allKeys.where((k) => k.enableOpenclaw).length;
      if (n > 0) {
        trailing = l10n?.nEnabled(n) ?? '$n 个已启用';
        trailingColor = kc.okText;
      }
    } else {
      final id = vm.currentKeyIds[tool];
      if (id != null) {
        AIKey? key;
        for (final k in vm.allKeys) {
          if (k.id == id) {
            key = k;
            break;
          }
        }
        if (key != null) {
          trailing = key.name;
          trailingColor = kc.okText;
        }
      } else if (vm.currentToolKeysLoaded) {
        trailing = l10n?.officialShort ?? '官方';
        trailingColor = cs.mutedForeground;
      }
    }
    final label = app.getLabel(context);
    return _SidebarRow(
      key: ValueKey('sidebar.${app.name}'),
      app: app,
      leading: leading,
      label: label,
      trailing: trailing,
      trailingColor: trailingColor,
      trailingStyle: KcType.badge,
      tooltip: trailing != null ? (l10n?.sidebarCurrentKeyTip(label, trailing) ?? '$label 当前使用：$trailing') : null,
      selected: activeApp == app,
      collapsed: collapsed,
      onTap: () => onSwitch(app),
    );
  }

  static int? _maybeCount<T extends ChangeNotifier>(BuildContext context, int Function(T) f) {
    try {
      return f(Provider.of<T>(context));
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed});
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final icon = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(6)),
      child: Icon(Icons.vpn_key_outlined, size: 13, color: cs.primaryForeground),
    );
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          if (!collapsed) const SizedBox(width: KcSpace.x1_5),
          icon,
          if (!collapsed) ...[
            const SizedBox(width: KcSpace.x2),
            Text('密枢', style: KcType.strong.copyWith(color: cs.foreground)),
            const SizedBox(width: KcSpace.x1_5),
            Text('Key Core', style: KcType.caption.copyWith(color: cs.mutedForeground)),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.collapsed});
  final String text;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: KcSpace.x2, horizontal: KcSpace.x3),
        child: Divider(height: 1, thickness: 1, color: cs.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.x1_5, KcSpace.x4, KcSpace.x1_5, KcSpace.x1),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: KcType.caption.copyWith(fontSize: 11, color: cs.mutedForeground),
      ),
    );
  }
}

class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    super.key,
    this.app,
    required this.leading,
    required this.label,
    required this.selected,
    required this.collapsed,
    required this.onTap,
    this.trailing,
    this.trailingColor,
    this.trailingStyle,
    this.tooltip,
    this.primary = false,
  });

  final AppType? app;
  final Widget leading;
  final String label;
  final String? trailing;
  final Color? trailingColor;
  final TextStyle? trailingStyle;
  final String? tooltip;
  final bool selected;
  final bool collapsed;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final bg = widget.selected ? kc.selected : (_hover ? kc.subtle : Colors.transparent);
    final height = widget.primary ? 32.0 : 28.0;
    final labelStyle = (widget.primary || widget.selected ? KcType.body.copyWith(fontWeight: FontWeight.w600) : KcType.body)
        .copyWith(color: widget.selected ? cs.foreground : kc.text2);

    Widget content;
    if (widget.collapsed) {
      content = Center(child: widget.leading);
    } else {
      content = Row(
        children: [
          SizedBox(width: 20, child: Center(child: widget.leading)),
          const SizedBox(width: KcSpace.x2),
          Expanded(
            child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: KcSpace.x1_5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 76),
              child: Text(
                widget.trailing!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (widget.trailingStyle ?? KcType.badge).copyWith(
                  color: widget.trailingColor ?? cs.mutedForeground,
                  fontWeight: FontWeight.w500,
                  fontFeatures: KcType.tabular,
                ),
              ),
            ),
          ],
        ],
      );
    }

    final tip = widget.collapsed
        ? (widget.trailing != null ? '${widget.label} · ${widget.trailing}' : widget.label)
        : widget.tooltip;

    Widget row = Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: height,
            margin: const EdgeInsets.only(bottom: 2),
            padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : KcSpace.x1_5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KcRadius.control)),
            child: content,
          ),
        ),
      ),
    );
    if (tip != null) {
      row = Tooltip(message: tip, waitDuration: const Duration(milliseconds: 400), child: row);
    }
    return row;
  }
}
