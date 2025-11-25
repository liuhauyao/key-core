import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/ai_key.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_helper.dart';

/// 密钥详情弹窗（通用组件）
class KeyDetailsDialog extends StatefulWidget {
  final AIKey aiKey;
  final KeyManagerViewModel viewModel;
  final VoidCallback onEdit;
  final VoidCallback onCopyKey;
  final VoidCallback onOpenManagementUrl;
  final Function(String) onCopyText; // 更灵活的复制文本回调

  const KeyDetailsDialog({
    super.key,
    required this.aiKey,
    required this.viewModel,
    required this.onEdit,
    required this.onCopyKey,
    required this.onOpenManagementUrl,
    required this.onCopyText,
  });

  @override
  State<KeyDetailsDialog> createState() => KeyDetailsDialogState();
}

class KeyDetailsDialogState extends State<KeyDetailsDialog> {
  bool _showKeyValue = false;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  PlatformIconHelper.buildIcon(
                    platform: widget.aiKey.platformType,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.aiKey.name,
                      style: shadTheme.textTheme.h4.copyWith(
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: localizations?.edit ?? '编辑',
                    child: ShadButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      onPressed: widget.onEdit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(localizations?.platformLabel ?? '平台', widget.aiKey.platform),
                    const SizedBox(height: 12),
                    // 管理地址
                    if (widget.aiKey.managementUrl != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.managementUrl ?? '管理地址',
                        widget.aiKey.managementUrl!,
                        Icons.language,
                        localizations?.open ?? '打开',
                        widget.onOpenManagementUrl,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 基本API地址
                    if (widget.aiKey.apiEndpoint != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.apiEndpoint ?? 'API地址',
                        widget.aiKey.apiEndpoint!,
                        Icons.api,
                        localizations?.copy ?? '复制',
                        () => _copyTextAndShowToast(context, widget.aiKey.apiEndpoint!),
                        isMonospace: true,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 密钥值
                    _buildKeyValueRow(context),
                    const SizedBox(height: 10),
                    // ClaudeCode 配置区域
                    if (widget.aiKey.enableClaudeCode) ...[
                      _buildConfigSection(
                        context,
                        'ClaudeCode 配置',
                        [
                          if (widget.aiKey.claudeCodeBaseUrl != null)
                            _buildActionRow(
                              context,
                              '请求地址',
                              widget.aiKey.claudeCodeBaseUrl!,
                              Icons.link,
                              localizations?.copy ?? '复制',
                              () => _copyTextAndShowToast(context, widget.aiKey.claudeCodeBaseUrl!),
                              isMonospace: true,
                            ),
                          if (widget.aiKey.claudeCodeModel != null)
                            _buildDetailRow('主模型', widget.aiKey.claudeCodeModel!),
                          if (widget.aiKey.claudeCodeHaikuModel != null)
                            _buildDetailRow('Haiku模型', widget.aiKey.claudeCodeHaikuModel!),
                          if (widget.aiKey.claudeCodeSonnetModel != null)
                            _buildDetailRow('Sonnet模型', widget.aiKey.claudeCodeSonnetModel!),
                          if (widget.aiKey.claudeCodeOpusModel != null)
                            _buildDetailRow('Opus模型', widget.aiKey.claudeCodeOpusModel!),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    // Codex 配置区域
                    if (widget.aiKey.enableCodex) ...[
                      _buildConfigSection(
                        context,
                        'Codex 配置',
                        [
                          if (widget.aiKey.codexBaseUrl != null)
                            _buildActionRow(
                              context,
                              '请求地址',
                              widget.aiKey.codexBaseUrl!,
                              Icons.link,
                              localizations?.copy ?? '复制',
                              () => _copyTextAndShowToast(context, widget.aiKey.codexBaseUrl!),
                              isMonospace: true,
                            ),
                          if (widget.aiKey.codexModel != null)
                            _buildDetailRow('模型', widget.aiKey.codexModel!),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (widget.aiKey.expiryDate != null) ...[
                      _buildDetailRow(localizations?.expiryDate ?? '过期日期', widget.aiKey.formattedExpiryDate),
                      const SizedBox(height: 10),
                    ],
                    if (widget.aiKey.tags.isNotEmpty) ...[
                      _buildDetailRow(localizations?.tags ?? '标签', widget.aiKey.tags.join(', ')),
                      const SizedBox(height: 10),
                    ],
                    if (widget.aiKey.notes != null && widget.aiKey.notes!.isNotEmpty) ...[
                      _buildDetailRow(localizations?.notes ?? '备注', widget.aiKey.notes!),
                      const SizedBox(height: 10),
                    ],
                    // 创建时间和更新时间在同一行
                    _buildTimeRow(
                      context,
                      localizations?.createdTime ?? '创建时间',
                      _formatDateTime(widget.aiKey.createdAt),
                      localizations?.updatedTime ?? '更新时间',
                      _formatDateTime(widget.aiKey.updatedAt),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isMonospace = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.primary,
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontSize: isMonospace ? 13 : null,
                ),
              ),
            ),
            Tooltip(
              message: tooltip,
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                child: Icon(icon, size: 18, color: shadTheme.colorScheme.mutedForeground),
                onPressed: onPressed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildKeyValueRow(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${localizations?.keyValueLabel ?? '密钥值'}:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _showKeyValue
                      ? widget.aiKey.keyValue
                      : '•' * widget.aiKey.keyValue.length,
                  style: shadTheme.textTheme.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _showKeyValue ? (localizations?.hide ?? '隐藏') : (localizations?.show ?? '显示'),
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _showKeyValue ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  setState(() {
                    _showKeyValue = !_showKeyValue;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: localizations?.copy ?? '复制',
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  widget.onCopyKey();
                  setState(() {
                    _showKeyValue = true;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTimeRow(
    BuildContext context,
    String label1,
    String value1,
    String label2,
    String value2,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label1:',
                style: shadTheme.textTheme.small.copyWith(
                  fontWeight: FontWeight.w500,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value1,
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.foreground,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label2:',
                style: shadTheme.textTheme.small.copyWith(
                  fontWeight: FontWeight.w500,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value2,
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.foreground,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建配置区域
  Widget _buildConfigSection(BuildContext context, String title, List<Widget> children) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: shadTheme.textTheme.small.copyWith(
              fontWeight: FontWeight.w600,
              color: shadTheme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// 复制文本并显示提示
  void _copyTextAndShowToast(BuildContext context, String text) {
    widget.onCopyText(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制: ${text.length > 30 ? '${text.substring(0, 30)}...' : text}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}