import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/mcp_server.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../utils/app_localizations.dart';

/// 工具配置卡片组件
class ToolConfigCard extends StatefulWidget {
  final AiToolType tool;
  final SettingsViewModel viewModel;

  const ToolConfigCard({
    super.key,
    required this.tool,
    required this.viewModel,
  });

  @override
  State<ToolConfigCard> createState() => _ToolConfigCardState();
}

class _ToolConfigCardState extends State<ToolConfigCard> {
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    // 进入页面时，只检测已启用工具的配置文件
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.viewModel.isToolEnabled(widget.tool)) {
        await widget.viewModel.refreshToolConfigValidation(widget.tool);
      }
    });
  }

  Future<void> _handleToggle(bool enabled) async {
    if (enabled) {
      // 启用前先验证配置文件
      setState(() {
        _isValidating = true;
      });

      // 刷新验证状态
      await widget.viewModel.refreshToolConfigValidation(widget.tool);
      final isValid = widget.viewModel.isToolConfigValid(widget.tool);

      setState(() {
        _isValidating = false;
      });

      if (!isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无法启用：未找到 ${widget.tool.displayName} 配置文件'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    final success = await widget.viewModel.setToolEnabled(widget.tool, enabled);
    if (!success && enabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('启用失败：配置文件不存在'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _browseDirectory() async {
    final localizations = AppLocalizations.of(context);
    try {
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择 ${widget.tool.displayName} 配置目录',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        await widget.viewModel.setToolConfigDir(widget.tool, selectedDirectory);
        
        // 如果工具已启用，重新验证配置
        if (widget.viewModel.isToolEnabled(widget.tool)) {
          await widget.viewModel.refreshToolConfigValidation(widget.tool);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已设置配置目录: $selectedDirectory'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('选择目录失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _resetDirectory() async {
    await widget.viewModel.resetToolConfigDir(widget.tool);
    
    // 如果工具已启用，重新验证配置
    if (widget.viewModel.isToolEnabled(widget.tool)) {
      await widget.viewModel.refreshToolConfigValidation(widget.tool);
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已重置为默认目录'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final isEnabled = widget.viewModel.isToolEnabled(widget.tool);
    final isValid = widget.viewModel.isToolConfigValid(widget.tool);
    final currentDir = widget.viewModel.getToolConfigDir(widget.tool) ?? 
                      widget.viewModel.getDefaultToolConfigDir(widget.tool);
    final defaultDir = widget.viewModel.getDefaultToolConfigDir(widget.tool);
    final isCustom = currentDir != defaultDir;

    return Card(
      elevation: isEnabled ? 2 : 1,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isEnabled
              ? shadTheme.colorScheme.primary
              : shadTheme.colorScheme.border,
          width: isEnabled ? 2 : 1,
        ),
      ),
      color: isEnabled
          ? shadTheme.colorScheme.primary.withOpacity(0.05)
          : shadTheme.colorScheme.background,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 120, // 固定卡片高度
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部：图标、名称、开关
                Row(
                  children: [
                    // 工具图标
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: shadTheme.colorScheme.muted,
                      ),
                      child: Center(
                        child: widget.tool.iconPath != null
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: SvgPicture.asset(
                                  widget.tool.iconPath!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Icon(
                                Icons.code,
                                size: 24,
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 工具名称和状态
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.tool.displayName,
                            style: shadTheme.textTheme.p.copyWith(
                              fontWeight: FontWeight.bold,
                              color: shadTheme.colorScheme.foreground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              // 只在工具启用时显示配置状态标签
                              if (isEnabled)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isValid
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isValid 
                                      ? (AppLocalizations.of(context)?.configValid ?? '配置正常')
                                      : (AppLocalizations.of(context)?.configMissing ?? '配置缺失'),
                                  style: shadTheme.textTheme.small.copyWith(
                                    color: isValid ? Colors.green : Colors.orange,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              if (isCustom) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: shadTheme.colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '自定义',
                                    style: shadTheme.textTheme.small.copyWith(
                                      color: shadTheme.colorScheme.primary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // 启用开关（与常规设置页面的最小化选项样式一致）
                    if (_isValidating)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: shadTheme.colorScheme.primary,
                        ),
                      )
                    else
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          value: isEnabled,
                          onChanged: isValid || !isEnabled ? _handleToggle : null,
                          activeColor: shadTheme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                const Spacer(), // 推动底部内容到底部
                // 配置目录和浏览按钮（同一行，底部对齐）
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentDir,
                        style: shadTheme.textTheme.small.copyWith(
                          color: shadTheme.colorScheme.mutedForeground,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _browseDirectory,
                      icon: Icon(
                        Icons.folder_open,
                        size: 16,
                        color: shadTheme.colorScheme.primary,
                      ),
                      label: Text(
                        AppLocalizations.of(context)?.browse ?? '浏览',
                        style: shadTheme.textTheme.small.copyWith(
                          color: shadTheme.colorScheme.primary,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    if (isCustom) ...[
                      TextButton.icon(
                        onPressed: _resetDirectory,
                        icon: Icon(
                          Icons.undo,
                          size: 16,
                          color: shadTheme.colorScheme.mutedForeground,
                        ),
                        label: Text(
                          '重置',
                          style: shadTheme.textTheme.small.copyWith(
                            color: shadTheme.colorScheme.mutedForeground,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

