import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/ai_key.dart';
import '../../models/platform_category.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_helper.dart';

/// 密钥卡片组件（卡片式布局）
class KeyCard extends StatelessWidget {
  final AIKey aiKey;
  final bool isEditMode;
  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback? onView; // 预览/查看回调，如果提供则优先使用，否则使用 onTap
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenManagementUrl;
  final VoidCallback? onCopyApiEndpoint;
  final VoidCallback? onCopyApiKey;
  final VoidCallback? onCopyEnvVarCommand; // 复制环境变量命令

  const KeyCard({
    super.key,
    required this.aiKey,
    this.isEditMode = false,
    this.isCurrent = false,
    this.onTap,
    this.onView,
    this.onEdit,
    this.onDelete,
    this.onOpenManagementUrl,
    this.onCopyApiEndpoint,
    this.onCopyApiKey,
    this.onCopyEnvVarCommand,
  });

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Card(
      elevation: isCurrent ? 4 : 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrent
              ? shadTheme.colorScheme.primary
              : shadTheme.colorScheme.border,
          width: isCurrent ? 2 : 1,
        ),
      ),
      color: isCurrent
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
          // 悬浮在右上角的"当前"标签
          if (isCurrent)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '当前',
                  style: shadTheme.textTheme.small.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部：Logo + 标题区域 + 拖动手柄
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: shadTheme.colorScheme.muted,
              ),
              child: Center(
                child: PlatformIconHelper.buildIcon(
                  platform: aiKey.platformType,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aiKey.name,
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.bold,
                      color: shadTheme.colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    aiKey.platform,
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
        // 中间：标签区域（单行显示，超出部分隐藏）
        SizedBox(
          height: 24, // 固定高度，避免换行
          width: double.infinity, // 确保使用全部可用宽度
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: Row(
              children: [
                // 平台分类标签
                ...PlatformCategoryManager.getCategoriesForPlatform(aiKey.platformType)
                    .take(2)
                    .map((category) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildTag(
                        context,
                        category.getValue(context),
                        isCategory: true,
                      ),
                    )),
                // 用户自定义标签（显示为紫色）
                ...aiKey.tags.map((tag) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildTag(context, tag, isCategory: false, isUserTag: true),
                )),
              ],
            ),
          ),
        ),
        const Spacer(),
        // 底部：操作按钮组
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    context,
                    icon: Icons.visibility_outlined,
                    tooltip: localizations?.details ?? '查看',
                    onPressed: onView ?? onTap,
                  ),
                  const SizedBox(width: 8),
                  if (aiKey.managementUrl != null)
                    _buildActionButton(
                      context,
                      icon: Icons.language,
                      tooltip: localizations?.openManagementUrl ?? '管理地址',
                      onPressed: onOpenManagementUrl,
                    ),
                  if (aiKey.managementUrl != null) const SizedBox(width: 8),
                  if (aiKey.apiEndpoint != null)
                    _buildActionButton(
                      context,
                      icon: Icons.code,
                      tooltip: localizations?.copyApiEndpoint ?? 'API地址',
                      onPressed: onCopyApiEndpoint,
                    ),
                  if (aiKey.apiEndpoint != null) const SizedBox(width: 8),
                  _buildActionButton(
                    context,
                    icon: Icons.copy_outlined,
                    tooltip: localizations?.copyKey ?? '复制',
                    onPressed: onCopyApiKey,
                  ),
                  // 如果启用 Codex 且提供了复制环境变量命令回调，显示按钮
                  // 注意：实际是否需要环境变量由调用者判断，这里只负责显示按钮
                  if (aiKey.enableCodex && onCopyEnvVarCommand != null) ...[
                    const SizedBox(width: 8),
                    _buildActionButton(
                      context,
                      icon: Icons.terminal_outlined,
                      tooltip: '复制环境变量命令',
                      onPressed: onCopyEnvVarCommand,
                    ),
                  ],
                ],
              ),
            ),
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
    );
  }

  Widget _buildTag(BuildContext context, String text, {required bool isCategory, bool isUserTag = false}) {
    final shadTheme = ShadTheme.of(context);
    // 用户标签使用紫色
    final isPurple = isUserTag && !isCategory;
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
