import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/mcp_server.dart';
import '../../utils/app_localizations.dart';
import '../../utils/mcp_server_presets.dart';

/// MCP 服务器卡片组件
class McpCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: server.isActive
              ? shadTheme.colorScheme.primary
              : shadTheme.colorScheme.border,
          width: server.isActive ? 2 : 1,
        ),
      ),
      color: server.isActive
          ? shadTheme.colorScheme.primary.withOpacity(0.05)
          : shadTheme.colorScheme.background,
      child: Stack(
        children: [
          // 编辑模式下不使用 InkWell，避免拦截拖动事件
          isEditMode
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildCardContent(context, shadTheme, localizations),
                )
              : InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildCardContent(context, shadTheme, localizations),
                  ),
                ),
          // 右上角激活开关（仅在非编辑模式显示）
          if (!isEditMode)
            Positioned(
              top: 8,
              right: 8,
              child: Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: server.isActive,
                  onChanged: (value) => onToggleActive?.call(value),
                  activeColor: shadTheme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    return SizedBox(
      height: 160, // 固定卡片高度
      child: Column(
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
                  child: server.icon != null
                      ? SvgPicture.asset(
                          'assets/icons/platforms/${server.icon}',
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
                      server.name,
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.bold,
                        color: shadTheme.colorScheme.foreground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      server.serverId,
                      style: shadTheme.textTheme.small.copyWith(
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 拖动手柄（仅在编辑模式显示，作为视觉提示）
              if (isEditMode)
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
          const SizedBox(height: 10),
          // 中间：服务器类型和标签（单行显示，超出部分隐藏）
          SizedBox(
            height: 24, // 固定高度，避免换行
            width: double.infinity, // 确保使用全部可用宽度
            child: ClipRect(
              clipBehavior: Clip.hardEdge,
              child: Row(
                children: [
                  // 服务器类型标签
                  _buildTag(
                    context,
                    server.serverType.value.toUpperCase(),
                    color: shadTheme.colorScheme.primary,
                  ),
                  // 用户自定义标签（显示为紫色）
                  if (server.tags != null && server.tags!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ...server.tags!.map((tag) => Padding(
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
                    onPressed: onViewDetails,
                  ),
                  const SizedBox(width: 8),
                  if (server.homepage != null && server.homepage!.isNotEmpty)
                    _buildActionButton(
                      context,
                      icon: Icons.language,
                      tooltip: localizations?.openManagementUrl ?? '管理地址',
                      onPressed: onOpenHomepage,
                    ),
                  if (server.homepage != null && server.homepage!.isNotEmpty)
                    const SizedBox(width: 8),
                  if (server.docs != null && server.docs!.isNotEmpty)
                    _buildActionButton(
                      context,
                      icon: Icons.description_outlined,
                      tooltip: localizations?.mcpOpenDocs ?? '文档地址',
                      onPressed: onOpenDocs,
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
                    onPressed: onEdit,
                  ),
                  if (isEditMode) ...[
                    const SizedBox(width: 8),
                    _buildActionButton(
                      context,
                      icon: Icons.delete_outline,
                      tooltip: localizations?.deleteTooltip ?? '删除',
                      onPressed: onDelete,
                      color: Colors.red,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTag(BuildContext context, String text, {Color? color, bool isUserTag = false}) {
    final shadTheme = ShadTheme.of(context);
    final isCategory = color != null;
    // 用户标签使用紫色
    final isPurple = isUserTag;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCategory
            ? shadTheme.colorScheme.primary.withOpacity(0.1)
            : isPurple
                ? Colors.purple.withOpacity(0.1)
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
                  : shadTheme.colorScheme.mutedForeground,
          fontWeight: FontWeight.w500,
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

