import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/first_launch_service.dart';
import '../../services/settings_service.dart';
import '../../utils/app_localizations.dart';
import '../../models/mcp_server.dart';

/// 首次启动配置目录选择对话框
/// 现在统一选择用户主目录，授权后自动检测所有工具配置
class FirstLaunchDialog extends StatefulWidget {
  final String? defaultHomeDir;
  final VoidCallback? onComplete;

  const FirstLaunchDialog({
    super.key,
    this.defaultHomeDir,
    this.onComplete,
  });

  @override
  State<FirstLaunchDialog> createState() => _FirstLaunchDialogState();
}

class _FirstLaunchDialogState extends State<FirstLaunchDialog> {
  bool _isSelecting = false;
  bool _isDetecting = false;
  List<ToolConfigDetected> _detectedTools = [];
  Set<String> _autoEnabledTools = {}; // 记录自动开启的工具名称

  Future<void> _requestHomeDirectoryAccess() async {
    setState(() {
      _isSelecting = true;
    });

    try {
      final localizations = AppLocalizations.of(context);
      final settingsViewModel = context.read<SettingsViewModel>();
      final firstLaunchService = FirstLaunchService();
      await firstLaunchService.init();
      
      // 直接尝试访问用户主目录
      // 在 macOS 沙盒环境中，直接访问可能会触发系统权限请求
      // 如果无法访问，需要使用 NSOpenPanel（通过 FilePicker）让用户选择目录来授予权限
      final homeDir = widget.defaultHomeDir ?? await SettingsService.getUserHomeDir();
      
      setState(() {
        _isDetecting = true;
      });

      // 先尝试直接访问用户主目录
      // 注意：在 macOS 沙盒环境中，直接访问通常不会自动弹出权限请求
      // 但如果应用有适当的权限声明，系统可能会提示
      final canAccess = await firstLaunchService.canAccessConfigDir(homeDir);
      
      if (canAccess) {
        // 可以访问，检测该目录下的所有工具配置
        final detected = await firstLaunchService.detectToolConfigsInHomeDir(homeDir);
        
        setState(() {
          _detectedTools = detected;
        });

        // 自动设置检测到的工具配置目录并开启工具
        final autoEnabled = <String>[];
        for (final tool in detected) {
          AiToolType? toolType;
          
          // 先设置配置目录
          if (tool.toolName == 'Claude') {
            await settingsViewModel.setClaudeConfigDir(tool.configDir);
            toolType = AiToolType.claudecode;
          } else if (tool.toolName == 'Codex') {
            await settingsViewModel.setCodexConfigDir(tool.configDir);
            toolType = AiToolType.codex;
          } else if (tool.toolType != null) {
            await settingsViewModel.setToolConfigDir(
              tool.toolType!,
              tool.configDir,
            );
            toolType = tool.toolType;
          }
          
          // 自动开启检测到的工具（如果配置有效）
          if (toolType != null) {
            // 等待一小段时间，确保配置目录设置已生效
            await Future.delayed(const Duration(milliseconds: 100));
            
            // 刷新配置验证状态（验证配置文件是否存在且有效）
            await settingsViewModel.refreshToolConfigValidation(toolType);
            
            // 如果配置有效，自动开启工具
            if (settingsViewModel.isToolConfigValid(toolType)) {
              final success = await settingsViewModel.setToolEnabled(toolType, true);
              if (success) {
                autoEnabled.add(tool.toolName);
              }
            }
          }
        }
        
        setState(() {
          _autoEnabledTools = autoEnabled.toSet();
        });

        // 标记已提示过用户主目录授权
        await firstLaunchService.markHomeDirPrompted();

        if (mounted) {
          Navigator.of(context).pop(true);
          widget.onComplete?.call();
        }
      } else {
        // 无法直接访问，需要通过 NSOpenPanel 让用户选择目录来授予权限
        // 这是 macOS 沙盒应用的标准做法：通过文件选择对话框授予权限
        // NSOpenPanel 是 macOS 原生的文件选择窗口
        if (mounted) {
          final selectedHomeDir = await FilePicker.platform.getDirectoryPath(
            dialogTitle: localizations?.selectHomeDirectory ?? '请选择用户主目录以授予访问权限',
            initialDirectory: homeDir,
          );

          if (selectedHomeDir != null && selectedHomeDir.isNotEmpty) {
            // 用户通过 NSOpenPanel 选择了目录，系统已自动授予该目录的访问权限
            // 检测工具配置
            final detected = await firstLaunchService.detectToolConfigsInHomeDir(selectedHomeDir);
            
            setState(() {
              _detectedTools = detected;
            });

            // 自动设置检测到的工具配置目录并开启工具
            final autoEnabled = <String>[];
            for (final tool in detected) {
              AiToolType? toolType;
              
              // 先设置配置目录
              if (tool.toolName == 'Claude') {
                await settingsViewModel.setClaudeConfigDir(tool.configDir);
                toolType = AiToolType.claudecode;
              } else if (tool.toolName == 'Codex') {
                await settingsViewModel.setCodexConfigDir(tool.configDir);
                toolType = AiToolType.codex;
              } else if (tool.toolType != null) {
                await settingsViewModel.setToolConfigDir(
                  tool.toolType!,
                  tool.configDir,
                );
                toolType = tool.toolType;
              }
              
              // 自动开启检测到的工具（如果配置有效）
              if (toolType != null) {
                // 等待一小段时间，确保配置目录设置已生效
                await Future.delayed(const Duration(milliseconds: 100));
                
                // 刷新配置验证状态（验证配置文件是否存在且有效）
                await settingsViewModel.refreshToolConfigValidation(toolType);
                
                // 如果配置有效，自动开启工具
                if (settingsViewModel.isToolConfigValid(toolType)) {
                  final success = await settingsViewModel.setToolEnabled(toolType, true);
                  if (success) {
                    autoEnabled.add(tool.toolName);
                  }
                }
              }
            }
            
            setState(() {
              _autoEnabledTools = autoEnabled.toSet();
            });

            await firstLaunchService.markHomeDirPrompted();

            if (mounted) {
              Navigator.of(context).pop(true);
              widget.onComplete?.call();
            }
          } else {
            // 用户取消了选择，标记为已提示，避免重复提示
            await firstLaunchService.markHomeDirPrompted();
            
            if (mounted) {
              Navigator.of(context).pop(false);
              widget.onComplete?.call();
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.browseDirectoryFailed(e.toString()) ?? 
                  '访问目录失败: $e',
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
          _isDetecting = false;
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
        width: 520,
        constraints: const BoxConstraints(maxHeight: 500),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: shadTheme.colorScheme.border.withOpacity(0.5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: shadTheme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: shadTheme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations?.firstLaunchTitle ?? '首次启动设置',
                          style: shadTheme.textTheme.h4.copyWith(
                            color: shadTheme.colorScheme.foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '需要授权访问用户主目录',
                          style: shadTheme.textTheme.small.copyWith(
                            color: shadTheme.colorScheme.mutedForeground,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 主描述文字 - 使用更小的字体和更好的排版
                    Text(
                      localizations?.firstLaunchHomeDirMessage ?? 
                          '应用需要访问您的用户主目录以读取工具配置文件。',
                      style: shadTheme.textTheme.small.copyWith(
                        color: shadTheme.colorScheme.foreground,
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 操作说明 - 分段显示，更易读
                    Text(
                      localizations?.firstLaunchInstruction ?? 
                          '点击"授权"按钮后，macOS 将弹出系统权限请求对话框，请选择"允许"以授予访问权限。',
                      style: shadTheme.textTheme.small.copyWith(
                        color: shadTheme.colorScheme.mutedForeground,
                        height: 1.5,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 功能说明 - 使用列表样式
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '• ',
                            style: shadTheme.textTheme.small.copyWith(
                              color: shadTheme.colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            localizations?.firstLaunchFeature ?? 
                                '应用将自动检测并加载该目录下的所有工具配置',
                            style: shadTheme.textTheme.small.copyWith(
                              color: shadTheme.colorScheme.mutedForeground,
                              height: 1.5,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _buildToolTag('.claude', shadTheme),
                          _buildToolTag('.codex', shadTheme),
                          _buildToolTag('.gemini', shadTheme),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 路径信息卡片 - 优化样式
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: shadTheme.colorScheme.muted.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: shadTheme.colorScheme.border.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.info_outline,
                              size: 16,
                              color: shadTheme.colorScheme.mutedForeground,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localizations?.firstLaunchHomeDirLabel ?? '用户主目录',
                                  style: shadTheme.textTheme.small.copyWith(
                                    color: shadTheme.colorScheme.foreground,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.defaultHomeDir ?? '/Users/您的用户名',
                                  style: shadTheme.textTheme.small.copyWith(
                                    color: shadTheme.colorScheme.mutedForeground,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isDetecting) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: shadTheme.colorScheme.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  shadTheme.colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '正在检测工具配置...',
                              style: shadTheme.textTheme.small.copyWith(
                                color: shadTheme.colorScheme.foreground,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_detectedTools.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: shadTheme.colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: shadTheme.colorScheme.primary.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: shadTheme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '已检测到 ${_detectedTools.length} 个工具配置${_autoEnabledTools.isNotEmpty ? '，已自动开启 ${_autoEnabledTools.length} 个' : ''}',
                                    style: shadTheme.textTheme.small.copyWith(
                                      color: shadTheme.colorScheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _detectedTools.map((tool) {
                                final isEnabled = _autoEnabledTools.contains(tool.toolName);
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isEnabled
                                        ? shadTheme.colorScheme.primary.withOpacity(0.15)
                                        : shadTheme.colorScheme.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: isEnabled
                                        ? Border.all(
                                            color: shadTheme.colorScheme.primary.withOpacity(0.3),
                                            width: 1,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        tool.toolName,
                                        style: shadTheme.textTheme.small.copyWith(
                                          color: shadTheme.colorScheme.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (isEnabled) ...[
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.check,
                                          size: 12,
                                          color: shadTheme.colorScheme.primary,
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // 按钮区域
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: shadTheme.colorScheme.border.withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ShadButton.outline(
                            onPressed: (_isSelecting || _isDetecting) ? null : () async {
                              // 用户选择跳过，标记为已提示
                              final firstLaunchService = FirstLaunchService();
                              await firstLaunchService.init();
                              await firstLaunchService.markHomeDirPrompted();
                              if (mounted) {
                                Navigator.of(context).pop(false);
                                widget.onComplete?.call();
                              }
                            },
                            child: Text(
                              localizations?.skip ?? '跳过',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ShadButton(
                            onPressed: (_isSelecting || _isDetecting) ? null : _requestHomeDirectoryAccess,
                            child: (_isSelecting || _isDetecting)
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    localizations?.authorize ?? '授权',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                          ),
                        ],
                      ),
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

  /// 构建工具标签
  Widget _buildToolTag(String toolName, ShadThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        toolName,
        style: theme.textTheme.small.copyWith(
          color: theme.colorScheme.mutedForeground,
          fontSize: 10,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

