import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/mcp_server.dart';
import '../../utils/app_localizations.dart';
import '../../theme/kc_tokens.dart';
import 'kc_logo.dart';

/// MCP 服务器卡片组件
class McpCard extends StatefulWidget {
  final McpServer server;
  final bool isEditMode;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleActive;
  final VoidCallback? onOpenHomepage;
  final VoidCallback? onOpenDocs;
  final VoidCallback? onViewDetails;

  /// 按工具启用（打开工具开关列表）
  final VoidCallback? onManageApps;

  /// 已在哪些工具启用（v3 工具图标行）；null 表示不显示该行
  final Set<AiToolType>? enabledTools;

  const McpCard({
    super.key,
    required this.server,
    this.isEditMode = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onToggleActive,
    this.onOpenHomepage,
    this.onOpenDocs,
    this.onViewDetails,
    this.onManageApps,
    this.enabledTools,
  });

  @override
  State<McpCard> createState() => _McpCardState();
}

class _McpCardState extends State<McpCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final cs = shadTheme.colorScheme;
    final kc = context.kc;
    final localizations = AppLocalizations.of(context);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.x3, KcSpace.x2 + 2, KcSpace.x3, 0),
      child: _buildCardContent(context, shadTheme, localizations),
    );

    return Semantics(
      container: true,
      label: widget.server.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: KcMotion.of(context),
          curve: KcMotion.curve,
          decoration: BoxDecoration(
            color: widget.server.isActive ? cs.card : Color.alphaBlend(kc.subtle.withValues(alpha: 0.5), cs.card),
            borderRadius: BorderRadius.circular(KcRadius.panel),
            border: Border.all(color: _isHovering && !widget.isEditMode ? cs.input : cs.border),
            boxShadow: _isHovering && !widget.isEditMode ? kc.shadowMd : kc.shadowSm,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KcRadius.panel),
            child: Material(
              type: MaterialType.transparency,
              // 编辑（排序）模式不包 InkWell，避免抢走拖动手势
              child: widget.isEditMode
                  ? SizedBox.expand(child: content)
                  : InkWell(
                      onTap: widget.onTap,
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

  Widget _buildCardContent(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final cs = shadTheme.colorScheme;
    final kc = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部 36：logo + 名称 / serverId + 右上角（开关或拖拽手柄）
        SizedBox(
          height: 36,
          child: Row(
            children: [
              KcLogoBox(
                child: SvgPicture.asset(
                  'assets/icons/platforms/${widget.server.icon ?? 'mcp.svg'}',
                  width: 22,
                  height: 22,
                  allowDrawingOutsideViewBox: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.server.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.strong.copyWith(color: cs.foreground)),
                    Text(widget.server.serverId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KcType.mono.copyWith(fontSize: 11, color: cs.mutedForeground, height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: KcSpace.x1_5),
              if (widget.isEditMode)
                Container(
                  key: const ValueKey('mcpCard.dragHandle'),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(KcRadius.control)),
                  child: Icon(Icons.drag_indicator, size: 16, color: kc.text2),
                )
              else
                SizedBox(
                  height: 24,
                  child: FittedBox(
                    child: Switch(
                      key: const ValueKey('mcpCard.toggle'),
                      value: widget.server.isActive,
                      onChanged: (value) => widget.onToggleActive?.call(value),
                      activeTrackColor: cs.primary,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: cs.border,
                      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: KcSpace.x2),
        // 标签行 20：服务器类型 + 用户标签（单行裁切）
        SizedBox(
          height: 20,
          width: double.infinity,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTag(context, widget.server.serverType.value.toUpperCase(), fg: kc.actionText, bg: kc.actionSoft),
                  for (final tag in widget.server.tags ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(left: KcSpace.x1_5),
                      child: _buildTag(context, tag, fg: kc.text2, bg: kc.subtle),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.enabledTools != null) ...[
          const SizedBox(height: KcSpace.x2),
          SizedBox(
            key: const ValueKey('mcpCard.tools'),
            height: 20,
            child: Row(children: [
              for (final t in widget.enabledTools!.take(6))
                Padding(padding: const EdgeInsets.only(right: 4), child: Tooltip(message: kcToolName(t), child: KcToolLogo(tool: t, size: 20))),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  widget.enabledTools!.isEmpty
                      ? (localizations?.tr('mcp_no_tools', '未在任何工具启用') ?? '未在任何工具启用')
                      : (localizations?.tr('n_tools', '{n} 个工具') ?? '{n} 个工具').replaceAll('{n}', '${widget.enabledTools!.length}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KcType.caption.copyWith(color: kc.text2),
                ),
              ),
            ]),
          ),
        ],
        const Spacer(),
        // 底栏 34：查看 / 主页 / 文档 … 编辑（排序模式下加删除）
        Container(
          height: 34,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.border))),
          child: Row(
            children: [
              // v3 定宽槽位（form_v3.md §7）：缺失的入口只置灰、不隐藏，管理模式不位移
              _buildActionButton(
                context,
                key: const ValueKey('mcpCard.details'),
                icon: Icons.visibility_outlined,
                tooltip: localizations?.mcpViewDetails ?? '查看详情',
                onPressed: widget.onViewDetails,
              ),
              _buildActionButton(
                context,
                key: const ValueKey('mcpCard.apps'),
                icon: Icons.apps_outlined,
                tooltip: localizations?.tr('mcp_enable_per_tool', '按工具启用') ?? '按工具启用',
                onPressed: widget.isEditMode ? null : widget.onManageApps,
              ),
              _buildActionButton(
                context,
                key: const ValueKey('mcpCard.homepage'),
                icon: Icons.language,
                tooltip: localizations?.openManagementUrl ?? '管理地址',
                onPressed: (widget.server.homepage?.isNotEmpty ?? false) ? widget.onOpenHomepage : null,
              ),
              _buildActionButton(
                context,
                key: const ValueKey('mcpCard.docs'),
                icon: Icons.description_outlined,
                tooltip: localizations?.mcpOpenDocs ?? '文档地址',
                onPressed: (widget.server.docs?.isNotEmpty ?? false) ? widget.onOpenDocs : null,
              ),
              const Spacer(),
              _buildActionButton(
                context,
                key: const ValueKey('mcpCard.edit'),
                icon: Icons.edit_outlined,
                tooltip: localizations?.edit ?? '编辑',
                onPressed: widget.onEdit,
              ),
              Visibility(
                visible: widget.isEditMode,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _buildActionButton(
                  context,
                  key: const ValueKey('mcpCard.delete'),
                  icon: Icons.delete_outline,
                  tooltip: localizations?.deleteTooltip ?? '删除',
                  onPressed: widget.isEditMode ? widget.onDelete : null,
                  color: kc.dangerText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTag(BuildContext context, String text, {required Color fg, required Color bg}) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KcRadius.control)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: KcType.badge.copyWith(color: fg))]),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final c = color ?? context.kc.text2;
    return Tooltip(
      key: key,
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(KcRadius.control),
          // 阻止事件冒泡，避免触发拖动
          onTapDown: (_) {},
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(icon, size: 15, color: onPressed == null ? c.withValues(alpha: 0.35) : c),
          ),
        ),
      ),
    );
  }
}
