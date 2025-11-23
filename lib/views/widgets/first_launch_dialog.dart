import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/first_launch_service.dart';
import '../../utils/app_localizations.dart';
import '../../models/mcp_server.dart';

/// 首次启动配置目录选择对话框
class FirstLaunchDialog extends StatefulWidget {
  final ConfigDirCheckResult configResult;
  final VoidCallback? onComplete;

  const FirstLaunchDialog({
    super.key,
    required this.configResult,
    this.onComplete,
  });

  @override
  State<FirstLaunchDialog> createState() => _FirstLaunchDialogState();
}

class _FirstLaunchDialogState extends State<FirstLaunchDialog> {
  bool _isSelecting = false;

  Future<void> _selectDirectory() async {
    setState(() {
      _isSelecting = true;
    });

    try {
      final localizations = AppLocalizations.of(context);
      final settingsViewModel = context.read<SettingsViewModel>();
      
      // 使用 file_picker 选择目录
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: localizations?.selectConfigDir(widget.configResult.toolName) ?? 
            '选择 ${widget.configResult.toolName} 配置目录',
      );

      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        // 根据工具类型设置配置目录
        if (widget.configResult.toolName == 'Claude') {
          await settingsViewModel.setClaudeConfigDir(selectedDirectory);
        } else if (widget.configResult.toolName == 'Codex') {
          await settingsViewModel.setCodexConfigDir(selectedDirectory);
        } else if (widget.configResult.toolName == 'Gemini') {
          // Gemini 使用 setToolConfigDir
          await settingsViewModel.setToolConfigDir(
            AiToolType.gemini,
            selectedDirectory,
          );
        } else if (widget.configResult.toolType != null) {
          await settingsViewModel.setToolConfigDir(
            widget.configResult.toolType!,
            selectedDirectory,
          );
        }

        // 标记已提示过
        final firstLaunchService = FirstLaunchService();
        await firstLaunchService.init();
        await firstLaunchService.markToolPrompted(widget.configResult.toolKey);

        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onComplete?.call();
        }
      } else {
        // 用户取消了选择，标记为已提示，避免重复提示
        final firstLaunchService = FirstLaunchService();
        await firstLaunchService.init();
        await firstLaunchService.markToolPrompted(widget.configResult.toolKey);
        
        if (mounted) {
          Navigator.of(context).pop(false);
          widget.onComplete?.call();
        }
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.browseDirectoryFailed(e.toString()) ?? 
                  '选择目录失败: $e',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSelecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 400),
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
                  Icon(
                    Icons.folder_outlined,
                    size: 24,
                    color: shadTheme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizations?.firstLaunchTitle ?? '首次启动设置',
                      style: shadTheme.textTheme.h4.copyWith(
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations?.firstLaunchMessage(widget.configResult.toolName) ?? 
                          '为了访问 ${widget.configResult.toolName} 的配置文件，请选择配置目录。',
                      style: shadTheme.textTheme.p.copyWith(
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: shadTheme.colorScheme.muted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: shadTheme.colorScheme.border,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: shadTheme.colorScheme.mutedForeground,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              localizations?.firstLaunchHint(widget.configResult.defaultPath) ?? 
                                  '默认路径：${widget.configResult.defaultPath}',
                              style: shadTheme.textTheme.small.copyWith(
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // 按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ShadButton.outline(
                          onPressed: _isSelecting ? null : () {
                            // 用户选择跳过，标记为已提示
                            FirstLaunchService().init().then((_) async {
                              final service = FirstLaunchService();
                              await service.init();
                              await service.markToolPrompted(widget.configResult.toolKey);
                            });
                            Navigator.of(context).pop(false);
                            widget.onComplete?.call();
                          },
                          child: Text(localizations?.skip ?? '跳过'),
                        ),
                        const SizedBox(width: 12),
                        ShadButton(
                          onPressed: _isSelecting ? null : _selectDirectory,
                          child: _isSelecting
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(localizations?.selectDirectory ?? '选择目录'),
                        ),
                      ],
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
}

