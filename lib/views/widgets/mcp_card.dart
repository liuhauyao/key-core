import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../../models/mcp_server.dart';
import '../../utils/app_localizations.dart';
import '../../utils/mcp_server_presets.dart';
import 'mcp_tool_list_dialog.dart';

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
  });

  @override
  State<McpCard> createState() => _McpCardState();
}

class _McpCardState extends State<McpCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    final isActive = widget.server.isActive;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // 基础背景色
          color: isActive
              ? Color.alphaBlend(
                  shadTheme.colorScheme.primary.withOpacity(0.04),
                  shadTheme.colorScheme.card,
                )
              : shadTheme.colorScheme.card,
          border: Border.all(
            color: isActive
                ? shadTheme.colorScheme.primary
                : shadTheme.colorScheme.border.withOpacity(0.8),
            width: isActive ? 2 : 1.5,
          ),
          boxShadow: [
            if (_isHovering)
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
                spreadRadius: 0,
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // 1. 柔和的流光渐变（模拟环境光）
              // 左上角的高光
              Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        isActive 
                            ? shadTheme.colorScheme.primary.withOpacity(0.1)
                            : shadTheme.colorScheme.primary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              // 右下角的反光
              Positioned(
                bottom: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        isActive
                            ? shadTheme.colorScheme.secondary.withOpacity(0.1)
                            : shadTheme.colorScheme.secondary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),

              // 2. 噪点纹理
              Positioned.fill(
                child: Opacity(
                  opacity: 0.04,
                  child: CustomPaint(
                    painter: _McpNoisePainter(
                      color: shadTheme.colorScheme.foreground,
                    ),
                  ),
                ),
              ),

              // 3. 内容层
              widget.isEditMode
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildCardContent(context, shadTheme, localizations),
                    )
                  : InkWell(
                      onTap: widget.onTap,
                      borderRadius: BorderRadius.circular(12),
                      hoverColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildCardContent(context, shadTheme, localizations),
                      ),
                    ),
              
              // 4. 右上角激活开关（仅在非编辑模式显示）
              if (!widget.isEditMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: widget.server.isActive,
                      onChanged: (value) => widget.onToggleActive?.call(value),
                      activeColor: shadTheme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部：图标 + 标题区域
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: shadTheme.colorScheme.muted,
              ),
              child: Center(
                child: widget.server.icon != null
                    ? SvgPicture.asset(
                        'assets/icons/platforms/${widget.server.icon}',
                        width: 28,
                        height: 28,
                      )
                    : SvgPicture.asset(
                        'assets/icons/platforms/mcp.svg',
                        width: 28,
                        height: 28,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            // 标题和描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.server.name,
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.bold,
                      color: shadTheme.colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.server.serverId,
                    style: shadTheme.textTheme.small.copyWith(
                      fontSize: 11,
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 拖动手柄（仅在编辑模式显示，作为视觉提示）
            if (widget.isEditMode)
              Container(
                margin: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.drag_handle,
                  size: 20,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 中间：服务器类型和标签（单行显示，超出部分隐藏）
        SizedBox(
          height: 24, // 固定高度
          width: double.infinity,
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: Row(
              children: [
                // 服务器类型标签
                _buildTag(
                  context,
                  widget.server.serverType.value.toUpperCase(),
                  color: shadTheme.colorScheme.primary,
                ),
                const SizedBox(width: 6),

                // 用户自定义标签（显示为紫色）
                if (widget.server.tags != null && widget.server.tags!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  ...widget.server.tags!.map((tag) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _buildTag(context, tag, isUserTag: true),
                  )),
                ],
              ],
            ),
          ),
        ),
        const Spacer(),
        // 底部：操作按钮组
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 左侧：查看详情、管理地址和文档地址按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.visibility_outlined,
                  tooltip: localizations?.mcpViewDetails ?? '查看详情',
                  onPressed: widget.onViewDetails,
                ),
                const SizedBox(width: 8),
                if (widget.server.homepage != null && widget.server.homepage!.isNotEmpty)
                  _buildActionButton(
                    context,
                    icon: Icons.language,
                    tooltip: localizations?.openManagementUrl ?? '管理地址',
                    onPressed: widget.onOpenHomepage,
                  ),
                if (widget.server.homepage != null && widget.server.homepage!.isNotEmpty)
                  const SizedBox(width: 8),
                if (widget.server.docs != null && widget.server.docs!.isNotEmpty)
                  _buildActionButton(
                    context,
                    icon: Icons.description_outlined,
                    tooltip: localizations?.mcpOpenDocs ?? '文档地址',
                    onPressed: widget.onOpenDocs,
                  ),
              ],
            ),
            // 右侧：编辑和删除按钮
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(
                  context,
                  icon: Icons.edit_outlined,
                  tooltip: localizations?.edit ?? '编辑',
                  onPressed: widget.onEdit,
                ),
                if (widget.isEditMode) ...[
                  const SizedBox(width: 8),
                  _buildActionButton(
                    context,
                    icon: Icons.delete_outline,
                    tooltip: localizations?.deleteTooltip ?? '删除',
                    onPressed: widget.onDelete,
                    color: Colors.red,
                  ),
                ],
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTag(BuildContext context, String text, {Color? color, bool isUserTag = false, bool isToolTag = false}) {
    final shadTheme = ShadTheme.of(context);
    final isCategory = color != null;
    // 用户标签使用紫色，工具标签使用橙色
    final isPurple = isUserTag;
    final isOrange = isToolTag;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCategory
            ? shadTheme.colorScheme.primary.withOpacity(0.1)
            : isPurple
                ? Colors.purple.withOpacity(0.1)
                : isOrange
                    ? Colors.orange.withOpacity(0.1)
                    : shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: shadTheme.textTheme.small.copyWith(
          fontSize: 11,
          color: isCategory
              ? shadTheme.colorScheme.primary
              : isPurple
                  ? Colors.purple
                  : isOrange
                      ? Colors.orange
                      : shadTheme.colorScheme.mutedForeground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStatusTag(BuildContext context, String text, Color color, {VoidCallback? onTap}) {
    final shadTheme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: shadTheme.textTheme.small.copyWith(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          // 阻止事件冒泡，避免触发拖动
          onTapDown: (_) {},
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.muted,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 15,
              color: color ?? shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class _McpNoisePainter extends CustomPainter {
  final Color color;
  final double density;

  _McpNoisePainter({
    required this.color,
    this.density = 0.8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    final random = math.Random(42);

    for (int i = 0; i < size.width * size.height * 0.05 * density; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;

      paint.color = color.withOpacity(random.nextDouble() * 0.5);
      canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _McpNoisePainter oldDelegate) {
    return false;
  }
}
