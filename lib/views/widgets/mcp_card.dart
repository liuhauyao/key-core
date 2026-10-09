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
        const Spacer(),
        // 底栏 34：查看 / 主页 / 文档 … 编辑（排序模式下加删除）
        Container(
          height: 34,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.border))),
          child: Row(
            children: [
              _buildActionButton(
                context,
                icon: Icons.visibility_outlined,
                tooltip: localizations?.mcpViewDetails ?? '查看详情',
                onPressed: widget.onViewDetails,
              ),
              if (widget.server.homepage != null && widget.server.homepage!.isNotEmpty)
                _buildActionButton(
                  context,
                  icon: Icons.language,
                  tooltip: localizations?.openManagementUrl ?? '管理地址',
                  onPressed: widget.onOpenHomepage,
                ),
              // 数据栈新增：按工具启用（移入新版底栏）
              if (widget.onManageApps != null)
                _buildActionButton(
                  context,
                  icon: Icons.apps_outlined,
                  tooltip: '按工具启用',
                  onPressed: widget.onManageApps,
                ),
              if (widget.server.docs != null && widget.server.docs!.isNotEmpty)
                _buildActionButton(
                  context,
                  icon: Icons.description_outlined,
                  tooltip: localizations?.mcpOpenDocs ?? '文档地址',
                  onPressed: widget.onOpenDocs,
                ),
              const Spacer(),
              _buildActionButton(
                context,
                icon: Icons.edit_outlined,
                tooltip: localizations?.edit ?? '编辑',
                onPressed: widget.onEdit,
              ),
              if (widget.isEditMode)
                _buildActionButton(
                  context,
                  icon: Icons.delete_outline,
                  tooltip: localizations?.deleteTooltip ?? '删除',
                  onPressed: widget.onDelete,
                  color: kc.dangerText,
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
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return Tooltip(
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
            child: Icon(icon, size: 15, color: color ?? context.kc.text2),
          ),
        ),
      ),
    );
  }
}
