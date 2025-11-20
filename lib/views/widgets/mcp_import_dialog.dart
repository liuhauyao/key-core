import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/mcp_server.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/mcp_sync_service.dart';
import '../../utils/app_localizations.dart';

/// MCP 导入对话框
/// 从工具配置文件读取 MCP 配置并同步到集中管理列表
class McpImportDialog extends StatefulWidget {
  const McpImportDialog({super.key});

  @override
  State<McpImportDialog> createState() => _McpImportDialogState();
}

class _McpImportDialogState extends State<McpImportDialog> {
  AiToolType? _selectedTool;
  Map<String, McpServer> _toolServers = {};
  Set<String> _selectedServerIds = {};
  bool _isLoading = false;
  bool _hasRead = false;
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

  Future<void> _readFromTool() async {
    final localizations = AppLocalizations.of(context);
    if (_selectedTool == null) {
      setState(() {
        _errorMessage = localizations?.mcpPleaseSelectTool ?? '请先选择工具';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasRead = false;
      _toolServers = {};
      _selectedServerIds = {};
    });

    try {
      final servers = await _syncService.readMcpServersFromTool(_selectedTool!);
      
      setState(() {
        _toolServers = servers;
        _selectedServerIds = servers.keys.toSet(); // 默认全选
        _hasRead = true;
        _isLoading = false;
        
        if (servers.isEmpty) {
          _errorMessage = localizations?.mcpNoConfigInTool(_selectedTool!.displayName) ?? '工具 ${_selectedTool!.displayName} 中没有找到 MCP 配置';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = localizations?.mcpReadFailed(e.toString()) ?? '读取失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _syncToLocal() async {
    final localizations = AppLocalizations.of(context);
    if (_selectedServerIds.isEmpty) {
      setState(() {
        _errorMessage = localizations?.mcpPleaseSelectAtLeastOne ?? '请至少选择一个 MCP 服务';
      });
      return;
    }

    final viewModel = context.read<McpViewModel>();
    
    // 检查是否有覆盖的服务
    final existingServerIds = <String>[];
    for (final serverId in _selectedServerIds) {
      final exists = await viewModel.serverIdExists(serverId);
      if (exists) {
        existingServerIds.add(serverId);
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
              dialogLocalizations?.mcpOverrideMessage(existingServerIds.join('\n')) ?? '以下 MCP 服务已存在，将被覆盖：\n\n${existingServerIds.join('\n')}\n\n确定要继续吗？',
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
      final result = await viewModel.importFromTool(_selectedTool!, _selectedServerIds);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.mcpImportComplete(result.addedCount, result.overriddenCount, result.failedCount) ?? '导入完成：新增 ${result.addedCount} 个，覆盖 ${result.overriddenCount} 个${result.failedCount > 0 ? '，失败 ${result.failedCount} 个' : ''}',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = localizations?.mcpSyncFailed(e.toString()) ?? '同步失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

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
                    localizations?.mcpImportDialogTitle ?? '从工具读取 MCP 配置',
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
                              _hasRead = false;
                              _toolServers = {};
                              _selectedServerIds = {};
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
                    // 读取按钮
                    ShadButton(
                      onPressed: _isLoading ? null : _readFromTool,
                      leading: _isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download, size: 18),
                      child: Text(localizations?.mcpRead ?? '读取'),
                    ),
                    const SizedBox(height: 16),
                    // MCP 服务列表
                    if (_hasRead) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              localizations?.mcpServerList(_toolServers.length) ?? 'MCP 服务列表 (${_toolServers.length} 个)',
                              style: shadTheme.textTheme.small.copyWith(
                                fontWeight: FontWeight.w600,
                                color: shadTheme.colorScheme.foreground,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedServerIds = _toolServers.keys.toSet();
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
                        child: _toolServers.isEmpty
                            ? Center(
                                child: Text(
                                  localizations?.mcpNoConfigFound ?? '未找到 MCP 配置',
                                  style: shadTheme.textTheme.p.copyWith(
                                    color: shadTheme.colorScheme.mutedForeground,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _toolServers.length,
                                itemBuilder: (context, index) {
                                  final entry = _toolServers.entries.elementAt(index);
                                  final serverId = entry.key;
                                  final server = entry.value;
                                  final isSelected = _selectedServerIds.contains(serverId);

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
                                            _selectedServerIds.add(serverId);
                                          } else {
                                            _selectedServerIds.remove(serverId);
                                          }
                                        });
                                      },
                                      title: Text(
                                        serverId,
                                        style: shadTheme.textTheme.p.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: shadTheme.colorScheme.foreground,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (server.serverType == McpServerType.stdio) ...[
                                            if (server.command != null)
                                              Text(localizations?.mcpCommand(server.command!) ?? '命令: ${server.command}'),
                                            if (server.args != null && server.args!.isNotEmpty)
                                              Text(localizations?.mcpArgs(server.args!.join(' ')) ?? '参数: ${server.args!.join(' ')}'),
                                          ] else if (server.url != null) ...[
                                            Text(localizations?.mcpUrl(server.url!) ?? 'URL: ${server.url}'),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
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
                    onPressed: _isLoading || !_hasRead || _selectedServerIds.isEmpty
                        ? null
                        : _syncToLocal,
                    leading: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.sync, size: 18),
                    child: Text(localizations?.mcpSyncToList ?? '同步到列表'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

