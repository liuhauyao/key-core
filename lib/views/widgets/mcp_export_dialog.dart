import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/mcp_server.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/mcp_sync_service.dart';
import '../../utils/app_localizations.dart';

/// MCP 下发对话框
/// 从集中管理列表选择 MCP 服务下发到工具配置文件
class McpExportDialog extends StatefulWidget {
  const McpExportDialog({super.key});

  @override
  State<McpExportDialog> createState() => _McpExportDialogState();
}

class _McpExportDialogState extends State<McpExportDialog> {
  AiToolType? _selectedTool;
  Set<String> _selectedServerIds = {};
  bool _isLoading = false;
  String? _errorMessage;

  final McpSyncService _syncService = McpSyncService();

  @override
  void initState() {
    super.initState();
    // 默认选择第一个已启用的工具
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settingsViewModel = context.read<SettingsViewModel>();
      final enabledTools = settingsViewModel.getEnabledTools();
      if (enabledTools.isNotEmpty) {
        setState(() {
          _selectedTool = enabledTools.first;
        });
      }
    });
  }

  /// 获取已启用的工具列表
  List<AiToolType> _getEnabledTools(BuildContext context) {
    try {
      final settingsViewModel = context.read<SettingsViewModel>();
      return settingsViewModel.getEnabledTools();
    } catch (e) {
      return [];
    }
  }

  Future<void> _exportToTool() async {
    final localizations = AppLocalizations.of(context);
    if (_selectedTool == null) {
      setState(() {
        _errorMessage = localizations?.mcpPleaseSelectTool ?? '请先选择工具';
      });
      return;
    }

    if (_selectedServerIds.isEmpty) {
      setState(() {
        _errorMessage = localizations?.mcpPleaseSelectAtLeastOne ?? '请至少选择一个 MCP 服务';
      });
      return;
    }

    // 检查工具配置文件中是否有同名的 MCP 服务
    final toolServers = await _syncService.getToolMcpServers(_selectedTool!);
    final existingServerIds = <String>[];
    
    if (toolServers != null) {
      for (final serverId in _selectedServerIds) {
        if (toolServers.containsKey(serverId)) {
          existingServerIds.add(serverId);
        }
      }
    }

    // 如果有覆盖，显示确认对话框
    if (existingServerIds.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          final dialogLocalizations = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(dialogLocalizations?.mcpConfirmOverride ?? '确认覆盖'),
            content: Text(
              dialogLocalizations?.mcpOverrideMessageTool(_selectedTool!.displayName, existingServerIds.join('\n')) ?? '工具 ${_selectedTool!.displayName} 中以下 MCP 服务将被覆盖：\n\n${existingServerIds.join('\n')}\n\n确定要继续吗？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(dialogLocalizations?.cancel ?? '取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(dialogLocalizations?.mcpConfirm ?? '确定'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final viewModel = context.read<McpViewModel>();
      final success = await viewModel.exportToTool(_selectedTool!, _selectedServerIds);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? (localizations?.mcpExportSuccess(_selectedServerIds.length, _selectedTool!.displayName) ?? '已成功下发 ${_selectedServerIds.length} 个 MCP 服务到 ${_selectedTool!.displayName}')
                  : (localizations?.mcpExportFailedShort ?? '下发失败'),
            ),
            backgroundColor: success ? null : Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = localizations?.mcpExportFailed(e.toString()) ?? '下发失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Consumer<McpViewModel>(
      builder: (context, viewModel, child) {
        final servers = viewModel.allServers;

        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 700,
            height: 600,
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: shadTheme.colorScheme.border,
                width: 1,
              ),
            ),
            child: Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                      Text(
                        localizations?.mcpExportDialogTitle ?? '下发 MCP 服务到工具',
                        style: shadTheme.textTheme.h4.copyWith(
                          color: shadTheme.colorScheme.foreground,
                        ),
                      ),
                      const Spacer(),
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
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 工具选择
                        Text(
                          localizations?.mcpSelectTool ?? '选择工具',
                          style: shadTheme.textTheme.small.copyWith(
                            fontWeight: FontWeight.w600,
                            color: shadTheme.colorScheme.foreground,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Consumer<SettingsViewModel>(
                          builder: (context, settingsViewModel, child) {
                            final enabledTools = _getEnabledTools(context);
                            if (enabledTools.isEmpty) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: shadTheme.colorScheme.muted,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  localizations?.mcpNoEnabledTools ?? '没有已启用的工具，请在设置中启用工具',
                                  style: shadTheme.textTheme.small.copyWith(
                                    color: shadTheme.colorScheme.mutedForeground,
                                  ),
                                ),
                              );
                            }
                            return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                              children: enabledTools.map((tool) {
                            final isSelected = _selectedTool == tool;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedTool = tool;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? shadTheme.colorScheme.primary
                                      : shadTheme.colorScheme.muted,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? shadTheme.colorScheme.primary
                                        : shadTheme.colorScheme.border,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Text(
                                  tool.displayName,
                                  style: shadTheme.textTheme.small.copyWith(
                                    color: isSelected
                                        ? Colors.white
                                        : shadTheme.colorScheme.foreground,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // MCP 服务列表
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                localizations?.mcpServerList(servers.length) ?? 'MCP 服务列表 (${servers.length} 个)',
                                style: shadTheme.textTheme.small.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: shadTheme.colorScheme.foreground,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedServerIds = servers.map((s) => s.serverId).toSet();
                                });
                              },
                              child: Text(localizations?.mcpSelectAll ?? '全选'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedServerIds.clear();
                                });
                              },
                              child: Text(localizations?.mcpDeselectAll ?? '取消全选'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: servers.isEmpty
                              ? Center(
                                  child: Text(
                                    localizations?.mcpNoServers ?? '暂无 MCP 服务',
                                    style: shadTheme.textTheme.p.copyWith(
                                      color: shadTheme.colorScheme.mutedForeground,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: servers.length,
                                  itemBuilder: (context, index) {
                                    final server = servers[index];
                                    final isSelected = _selectedServerIds.contains(server.serverId);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: shadTheme.colorScheme.muted,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected
                                              ? shadTheme.colorScheme.primary
                                              : shadTheme.colorScheme.border,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: CheckboxListTile(
                                        value: isSelected,
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedServerIds.add(server.serverId);
                                            } else {
                                              _selectedServerIds.remove(server.serverId);
                                            }
                                          });
                                        },
                                        title: Text(
                                          server.name,
                                          style: shadTheme.textTheme.p.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: shadTheme.colorScheme.foreground,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(localizations?.mcpServerId(server.serverId) ?? 'ID: ${server.serverId}'),
                                            if (server.description != null && server.description!.isNotEmpty)
                                              Text(server.description!),
                                          ],
                                        ),
                                        secondary: server.isActive
                                            ? Icon(
                                                Icons.check_circle,
                                                size: 20,
                                                color: Colors.green,
                                              )
                                            : Icon(
                                                Icons.circle_outlined,
                                                size: 20,
                                                color: shadTheme.colorScheme.mutedForeground,
                                              ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        // 错误信息
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, size: 20, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: shadTheme.textTheme.small.copyWith(
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // 底部按钮
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: shadTheme.colorScheme.border,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ShadButton.outline(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations?.cancel ?? '取消'),
                      ),
                      const SizedBox(width: 12),
                      ShadButton(
                        onPressed: _isLoading || _selectedServerIds.isEmpty
                            ? null
                            : _exportToTool,
                        leading: _isLoading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.upload, size: 18),
                        child: Text(localizations?.mcpExportToToolButton ?? '下发到工具'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

