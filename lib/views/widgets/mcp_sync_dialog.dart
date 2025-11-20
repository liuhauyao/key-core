import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/mcp_server.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/mcp_sync_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/mcp_comparison.dart';
import '../../services/clipboard_service.dart';
import '../../services/url_launcher_service.dart';
import '../widgets/confirm_dialog.dart';
import 'dart:convert';

/// MCP 同步对话框
/// 合并导入和导出功能，实现左右分栏对比和双向同步
class McpSyncDialog extends StatefulWidget {
  const McpSyncDialog({super.key});

  @override
  State<McpSyncDialog> createState() => _McpSyncDialogState();
}

class _McpSyncDialogState extends State<McpSyncDialog> {
  AiToolType? _selectedTool;
  Map<String, McpServer> _toolServers = {};
  List<McpComparisonResult> _comparisonResults = [];
  bool _isLoading = false;
  bool _hasRead = false;
  String? _errorMessage;

  // ClaudeCode 配置范围选择（全局或项目路径）
  String? _selectedScope;
  List<String> _availableScopes = ['global'];
  bool _hasProjectConfig = false; // 当前选择的项目是否有 MCP 配置

  // 缓存机制：存储待同步的配置
  final Map<String, McpServer> _pendingExportServers = {}; // 待同步到工具的服务
  final Map<String, McpServer> _pendingImportServers = {}; // 待同步到本应用的服务
  final Set<String> _pendingDeleteServerIds = {}; // 待删除的服务ID

  final McpSyncService _syncService = McpSyncService();

  @override
  void initState() {
    super.initState();
    // 默认选择第一个已启用的工具
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settingsViewModel = context.read<SettingsViewModel>();
      final enabledTools = settingsViewModel.getEnabledTools();
      if (enabledTools.isNotEmpty) {
        final firstTool = enabledTools.first;
        setState(() {
          _selectedTool = firstTool;
        });
        
        // 如果是 claudecode，先加载配置范围
        if (firstTool == AiToolType.claudecode) {
          try {
            final scopes = await _syncService.getClaudeCodeScopes();
            setState(() {
              _availableScopes = scopes;
              _selectedScope = scopes.first;
            });
          } catch (e) {
            print('获取 ClaudeCode 配置范围失败: $e');
            setState(() {
              _availableScopes = ['global'];
              _selectedScope = 'global';
            });
          }
        }
        
        _readFromTool();
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

  /// 从工具读取配置
  Future<void> _readFromTool() async {
    final localizations = AppLocalizations.of(context);
    if (_selectedTool == null) {
      setState(() {
        _errorMessage = localizations?.mcpPleaseSelectTool ?? '请先选择工具';
      });
      return;
    }

    // 如果是 claudecode，加载可用的配置范围（只在第一次或范围列表为空时更新）
    if (_selectedTool == AiToolType.claudecode) {
      try {
        final scopes = await _syncService.getClaudeCodeScopes();
        setState(() {
          _availableScopes = scopes;
          // 只在 _selectedScope 为空或不在新列表中时才设置默认值
          if (_selectedScope == null || !scopes.contains(_selectedScope)) {
            _selectedScope = scopes.first;
          }
        });
      } catch (e) {
        print('获取 ClaudeCode 配置范围失败: $e');
        setState(() {
          _availableScopes = ['global'];
          _selectedScope = 'global';
        });
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasRead = false;
      _toolServers = {};
      _comparisonResults = [];
      // 清空缓存
      _pendingExportServers.clear();
      _pendingImportServers.clear();
      _pendingDeleteServerIds.clear();
    });

    try {
      final result = await _syncService.readMcpServersFromTool(
        _selectedTool!,
        scope: _selectedTool == AiToolType.claudecode ? _selectedScope : null,
      );
      final toolServers = result.servers;
      final hasProjectConfig = result.hasProjectConfig;
      
      final viewModel = context.read<McpViewModel>();
      final localServers = viewModel.allServers.where((s) => s.isActive).toList();
      
      // 执行比对（传递工具类型用于codex的特殊处理）
      final comparisonResults = McpComparison.compare(
        localServers: localServers,
        toolServers: toolServers,
        toolType: _selectedTool,
      );
      
      // 排序：将本地和工具中都有的服务（identical 和 different）排在前面
      final sortedResults = List<McpComparisonResult>.from(comparisonResults);
      sortedResults.sort((a, b) {
        // 优先显示 identical 和 different（两边都有的）
        final aHasBoth = a.status == McpComparisonStatus.identical || 
                         a.status == McpComparisonStatus.different;
        final bHasBoth = b.status == McpComparisonStatus.identical || 
                         b.status == McpComparisonStatus.different;
        
        if (aHasBoth && !bHasBoth) return -1;
        if (!aHasBoth && bHasBoth) return 1;
        
        // 如果都是两边都有的，identical 排在 different 前面
        if (aHasBoth && bHasBoth) {
          if (a.status == McpComparisonStatus.identical && 
              b.status == McpComparisonStatus.different) return -1;
          if (a.status == McpComparisonStatus.different && 
              b.status == McpComparisonStatus.identical) return 1;
        }
        
        // 其他情况按 serverId 排序
        return a.server.serverId.compareTo(b.server.serverId);
      });
      
      setState(() {
        _toolServers = toolServers;
        _comparisonResults = sortedResults;
        _hasRead = true;
        _isLoading = false;
        _hasProjectConfig = hasProjectConfig;
        
        if (toolServers.isEmpty && localServers.isEmpty) {
          _errorMessage = localizations?.mcpNoConfigFound ?? '未找到 MCP 配置';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = localizations?.mcpReadFailed(e.toString()) ?? '读取失败: $e';
        _isLoading = false;
      });
    }
  }

  /// 同步到工具（添加到待同步列表）
  void _addToPendingExport(String serverId) {
    final viewModel = context.read<McpViewModel>();
    final server = viewModel.allServers.firstWhere(
      (s) => s.serverId == serverId,
      orElse: () => throw Exception('服务器不存在'),
    );
    
    setState(() {
      _pendingExportServers[serverId] = server;
    });
  }

  /// 从工具同步到本应用（添加到待导入列表）
  void _addToPendingImport(String serverId) {
    final server = _toolServers[serverId];
    if (server != null) {
      setState(() {
        _pendingImportServers[serverId] = server;
      });
    }
  }

  /// 删除工具中的服务（添加到待删除列表）
  void _addToPendingDelete(String serverId) {
    setState(() {
      _pendingDeleteServerIds.add(serverId);
      // 如果该服务在待导入列表中，也移除
      _pendingImportServers.remove(serverId);
    });
  }

  /// 检查是否有未保存的变更
  bool _hasUnsavedChanges() {
    return _pendingExportServers.isNotEmpty ||
        _pendingImportServers.isNotEmpty ||
        _pendingDeleteServerIds.isNotEmpty;
  }

  /// 显示未保存变更确认对话框
  /// [isClosing] 是否为关闭窗口场景，默认为 false（切换场景）
  /// 返回 true: 保存并关闭/切换
  /// 返回 false: 放弃并关闭/切换
  /// 返回 null: 取消，不关闭/切换
  Future<bool?> _showUnsavedChangesDialog({bool isClosing = false}) async {
    final localizations = AppLocalizations.of(context);
    
    return ConfirmDialog.showUnsavedChanges(
      context: context,
      title: localizations?.mcpUnsavedChanges ?? '有未保存的变更',
      message: isClosing
          ? (localizations?.mcpUnsavedChangesMessage ?? '您有未保存的变更，关闭前请选择操作方式。如果选择放弃，所有未保存的更改将丢失。')
          : (localizations?.mcpUnsavedChangesMessageSwitch ?? '您有未保存的变更，切换前请选择操作方式。如果选择放弃，所有未保存的更改将丢失。'),
      cancelText: localizations?.cancel ?? '取消',
      discardText: localizations?.mcpDiscard ?? '放弃',
      saveText: localizations?.mcpSave ?? '保存',
    );
  }

  /// 保存所有更改
  /// [closeAfterSave] 保存完成后是否关闭窗口，默认为 false
  Future<bool> _saveChanges({bool closeAfterSave = false}) async {
    final localizations = AppLocalizations.of(context);
    if (_selectedTool == null) {
      return false;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final viewModel = context.read<McpViewModel>();
      int exportCount = 0;
      int importCount = 0;
      int deleteCount = 0;
      int failedCount = 0;

      // 1. 同步到工具
      if (_pendingExportServers.isNotEmpty) {
        final serverIds = _pendingExportServers.keys.toSet();
        final scope = _selectedTool == AiToolType.claudecode ? _selectedScope : null;
        final success = await viewModel.exportToTool(_selectedTool!, serverIds, scope: scope);
        if (success) {
          exportCount = serverIds.length;
        } else {
          failedCount += serverIds.length;
        }
      }

      // 2. 从工具同步到本应用
      if (_pendingImportServers.isNotEmpty) {
        final serverIds = _pendingImportServers.keys.toSet();
        try {
          final result = await viewModel.importFromTool(_selectedTool!, serverIds);
          importCount = result.addedCount + result.overriddenCount;
          failedCount += result.failedCount;
        } catch (e) {
          failedCount += serverIds.length;
        }
      }

      // 3. 删除工具中的服务
      if (_pendingDeleteServerIds.isNotEmpty) {
        final scope = _selectedTool == AiToolType.claudecode ? _selectedScope : null;
        final success = await _syncService.deleteFromTool(_selectedTool!, _pendingDeleteServerIds, scope: scope);
        if (success) {
          deleteCount = _pendingDeleteServerIds.length;
        } else {
          failedCount += _pendingDeleteServerIds.length;
        }
      }

      if (mounted) {
        // 清空待同步列表
        setState(() {
          _pendingExportServers.clear();
          _pendingImportServers.clear();
          _pendingDeleteServerIds.clear();
          _isLoading = false;
        });
        
        // 显示成功通知
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.mcpSyncComplete(exportCount, importCount, deleteCount, failedCount) ??
                  '同步完成：导出 $exportCount 个，导入 $importCount 个，删除 $deleteCount 个${failedCount > 0 ? '，失败 $failedCount 个' : ''}',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: failedCount > 0 ? Colors.orange : Colors.green,
          ),
        );
        
        // 重新读取工具配置并刷新列表（修复codex刷新问题）
        await _readFromTool();
        
        // 如果需要关闭窗口
        if (closeAfterSave) {
          Navigator.pop(context);
        }
        
        return true;
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = localizations?.mcpSyncFailed(e.toString()) ?? '同步失败: $e';
          _isLoading = false;
        });
        // 显示失败通知
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.mcpSyncFailed(e.toString()) ?? '同步失败: $e',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// 构建工具切换滑块
  Widget _buildToolSwitcher(BuildContext context, ShadThemeData shadTheme) {
    final enabledTools = _getEnabledTools(context);
    if (enabledTools.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          AppLocalizations.of(context)?.mcpNoEnabledTools ?? '没有已启用的工具',
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: enabledTools.map((tool) {
          final isSelected = _selectedTool == tool;
          return GestureDetector(
            onTap: () async {
              // 如果选择了相同的工具，不需要切换
              if (_selectedTool == tool) return;
              
              // 检查是否有未保存的变更
              if (_hasUnsavedChanges()) {
                final shouldSwitch = await _showUnsavedChangesDialog(isClosing: false);
                if (shouldSwitch == null) {
                  // 取消，不切换
                  return;
                } else if (shouldSwitch == true) {
                  // 保存并切换
                  final success = await _saveChanges(closeAfterSave: false);
                  if (!mounted || !success) return;
                  // 保存成功后切换工具并重新读取配置
                  setState(() {
                    _selectedTool = tool;
                    _hasRead = false;
                    // 切换工具时重置配置范围
                    if (tool != AiToolType.claudecode) {
                      _selectedScope = null;
                      _availableScopes = ['global'];
                    }
                  });
                  await _readFromTool();
                  return;
                }
                // shouldSwitch == false 表示放弃并切换，清空待同步列表后继续执行切换逻辑
                if (shouldSwitch == false) {
                  setState(() {
                    _pendingExportServers.clear();
                    _pendingImportServers.clear();
                    _pendingDeleteServerIds.clear();
                  });
                }
              }
              
              setState(() {
                _selectedTool = tool;
                _hasRead = false;
                // 切换工具时重置配置范围
                if (tool != AiToolType.claudecode) {
                  _selectedScope = null;
                  _availableScopes = ['global'];
                }
              });
              _readFromTool();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? shadTheme.colorScheme.background
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tool.iconPath != null)
                    _buildToolSvgIcon(
                      tool.iconPath!,
                      isSelected,
                      shadTheme,
                    ),
                  if (tool.iconPath != null) const SizedBox(width: 6),
                  Text(
                    tool.displayName,
                    style: shadTheme.textTheme.small.copyWith(
                      color: isSelected
                          ? shadTheme.colorScheme.foreground
                          : shadTheme.colorScheme.mutedForeground,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建工具 SVG 图标，所有图标都显示原始颜色
  Widget _buildToolSvgIcon(String iconPath, bool isSelected, ShadThemeData shadTheme) {
    return SvgPicture.asset(
      iconPath,
      width: 16,
      height: 16,
      // 所有图标都显示原始颜色，不使用 colorFilter
      allowDrawingOutsideViewBox: true,
    );
  }

  /// 构建简化的列表项
  Widget _buildServerListItem({
    required McpServer server,
    required McpComparisonStatus? status,
    required bool isLeftSide,
    required ShadThemeData shadTheme,
  }) {
    final localizations = AppLocalizations.of(context);
    final isPendingExport = isLeftSide && _pendingExportServers.containsKey(server.serverId);
    final isPendingImport = !isLeftSide && _pendingImportServers.containsKey(server.serverId);
    final isPendingDelete = !isLeftSide && _pendingDeleteServerIds.contains(server.serverId);
    
    // 获取比对结果，用于判断是否两边都有
    // 注意：当 isLeftSide == false 时，server 是工具中的服务器
    // 需要正确匹配 comparisonResult 中的 toolServer
    McpComparisonResult comparisonResult;
    try {
      comparisonResult = _comparisonResults.firstWhere(
        (r) {
          // 如果 server 是本地服务器，匹配 r.server
          if (r.server.serverId == server.serverId) return true;
          // 如果 server 是工具服务器，匹配 r.toolServer
          if (r.toolServer != null && r.toolServer!.serverId == server.serverId) return true;
          return false;
        },
      );
    } catch (e) {
      // 如果找不到匹配的结果，使用传入的 status 创建
      comparisonResult = McpComparisonResult(
        server: server,
        status: status ?? (isLeftSide ? McpComparisonStatus.onlyInLocal : McpComparisonStatus.onlyInTool),
      );
    }
    
    // 使用 comparisonResult.status 作为最终状态（优先使用查找结果，如果没有则使用传入的 status）
    final finalStatus = comparisonResult.status;
    
    // 判断是否两边都有（identical 或 different）
    final hasBothSides = finalStatus == McpComparisonStatus.identical ||
                         finalStatus == McpComparisonStatus.different;
    
    // 判断是否选择了对侧的同步（用于different状态）
    final isOppositeSidePending = hasBothSides && finalStatus == McpComparisonStatus.different &&
        ((isLeftSide && _pendingImportServers.containsKey(server.serverId)) ||
         (!isLeftSide && _pendingExportServers.containsKey(server.serverId)));
    
    // 确定状态标签和颜色
    String? statusLabel;
    Color? statusColor;
    
    if (isPendingDelete) {
      // 将删除
      statusLabel = localizations?.mcpWillDelete ?? '将删除';
      statusColor = Colors.red;
    } else if (isPendingExport || isPendingImport) {
      // 将同步
      statusLabel = localizations?.mcpWillSync ?? '将同步';
      statusColor = shadTheme.colorScheme.primary;
    } else if (isOppositeSidePending) {
      // 将被覆盖
      statusLabel = localizations?.mcpWillBeOverridden ?? '将被覆盖';
      statusColor = Colors.orange;
    } else {
      // 正常状态标签
      statusLabel = McpComparison.getStatusLabel(finalStatus);
      statusColor = Color(McpComparison.getStatusColor(finalStatus));
    }
    
    // 判断是否显示同步按钮
    // 1. identical状态：两边都不显示同步按钮
    // 2. different状态：如果对侧已选择同步，则本侧不显示按钮
    // 3. 如果本侧已选择同步，则按钮亮起
    final shouldShowSyncButton = finalStatus != McpComparisonStatus.identical &&
        (!hasBothSides || 
         (finalStatus == McpComparisonStatus.different && !isOppositeSidePending));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPendingDelete
              ? Colors.red
              : (isPendingExport || isPendingImport)
                  ? shadTheme.colorScheme.primary
                  : shadTheme.colorScheme.border,
          width: (isPendingExport || isPendingImport || isPendingDelete) ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          // 图标 - 如果有图标则显示，否则使用默认 mcp.svg
          SvgPicture.asset(
            'assets/icons/platforms/${server.icon ?? 'mcp.svg'}',
            width: 24,
            height: 24,
            allowDrawingOutsideViewBox: true,
            placeholderBuilder: (context) => Icon(
              Icons.extension,
              size: 24,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          // 名称和状态
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: shadTheme.textTheme.p.copyWith(
                    fontWeight: FontWeight.w600,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
                if (statusLabel != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor?.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: statusColor ?? Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: shadTheme.textTheme.small.copyWith(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: (isPendingExport || isPendingImport || isPendingDelete || isOppositeSidePending)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 操作按钮
          if (isLeftSide) ...[
            // 左侧：向右箭头（同步到工具）
            // 只在应该显示同步按钮时显示
            if (shouldShowSyncButton) ...[
              IconButton(
                icon: Icon(
                  Icons.arrow_forward,
                  size: 20,
                  color: isPendingExport
                      ? shadTheme.colorScheme.primary
                      : shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  if (isPendingExport) {
                    setState(() {
                      _pendingExportServers.remove(server.serverId);
                    });
                  } else {
                    // 如果是different状态，需要清除对侧的待导入状态
                    if (comparisonResult.status == McpComparisonStatus.different) {
                      _pendingImportServers.remove(server.serverId);
                    }
                    _addToPendingExport(server.serverId);
                  }
                },
                tooltip: localizations?.mcpSyncToTool ?? '同步到工具',
              ),
            ],
          ] else ...[
            // 右侧：向左箭头（同步到本应用）+ 删除按钮
            // 只在应该显示同步按钮时显示（且不是待删除状态）
            if (shouldShowSyncButton && !isPendingDelete) ...[
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: isPendingImport
                      ? shadTheme.colorScheme.primary
                      : shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  if (isPendingImport) {
                    setState(() {
                      _pendingImportServers.remove(server.serverId);
                    });
                  } else {
                    // 如果是different状态，需要清除对侧的待导出状态
                    if (finalStatus == McpComparisonStatus.different) {
                      _pendingExportServers.remove(server.serverId);
                    }
                    _addToPendingImport(server.serverId);
                  }
                },
                tooltip: localizations?.mcpSyncToLocal ?? '同步到本应用',
              ),
            ],
            // 删除按钮（右侧工具列表中的服务都可以删除）
            // 注意：删除按钮始终显示在工具侧，不受状态影响
            // 只有同步按钮在identical状态时不显示
            if (!isLeftSide) ...[
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: isPendingDelete
                      ? Colors.red
                      : shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  if (isPendingDelete) {
                    setState(() {
                      _pendingDeleteServerIds.remove(server.serverId);
                      // 如果该服务在待导入列表中，也移除
                      _pendingImportServers.remove(server.serverId);
                    });
                  } else {
                    _addToPendingDelete(server.serverId);
                  }
                },
                tooltip: localizations?.mcpDelete ?? '删除',
              ),
            ],
          ],
          // 查看详情按钮
          IconButton(
            icon: Icon(
              Icons.info_outline,
              size: 20,
              color: shadTheme.colorScheme.mutedForeground,
            ),
            onPressed: () => _showMcpDetails(server),
            tooltip: localizations?.mcpViewDetails ?? '查看详情',
          ),
        ],
      ),
    );
  }

  /// 显示MCP详情
  void _showMcpDetails(McpServer server) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    // 检查是否是两边都有的服务
    final comparisonResult = _comparisonResults.firstWhere(
      (r) => r.server.serverId == server.serverId ||
             (r.toolServer != null && r.toolServer!.serverId == server.serverId),
      orElse: () => McpComparisonResult(
        server: server,
        status: McpComparisonStatus.onlyInLocal,
      ),
    );
    
    final isBothSides = comparisonResult.status == McpComparisonStatus.identical ||
                        comparisonResult.status == McpComparisonStatus.different;
    
    if (isBothSides && comparisonResult.toolServer != null) {
      // 两边都有的服务，显示对比视图
      _showComparisonDetails(comparisonResult);
    } else {
      // 只有一边有的服务，显示单个详情
      _showSingleDetails(server);
    }
  }

  /// 显示单个服务的详情
  void _showSingleDetails(McpServer server) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: shadTheme.colorScheme.muted,
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/platforms/${server.icon ?? 'mcp.svg'}',
                          width: 20,
                          height: 20,
                          allowDrawingOutsideViewBox: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        server.name,
                        style: shadTheme.textTheme.h4.copyWith(
                          color: shadTheme.colorScheme.foreground,
                        ),
                      ),
                    ),
                    ShadButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      onPressed: () async {
                      // 检查是否有未保存的变更
                      if (_hasUnsavedChanges()) {
                        final shouldClose = await _showUnsavedChangesDialog(isClosing: true);
                        if (shouldClose == null) {
                          // 取消，不关闭
                          return;
                        } else if (shouldClose == true) {
                          // 保存并关闭
                          await _saveChanges(closeAfterSave: true);
                          return;
                        }
                        // shouldClose == false 表示放弃并关闭，直接关闭
                      }
                      Navigator.pop(context);
                    },
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
                    children: _buildServerDetailsContent(server, shadTheme, localizations),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示对比详情（左右两边都有的服务）
  void _showComparisonDetails(McpComparisonResult result) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    final localServer = result.server;
    final toolServer = result.toolServer!;
    
    // 获取配置差异（传递工具类型用于codex的特殊处理）
    final localConfig = localServer.toToolConfigFormat();
    final toolConfig = toolServer.toToolConfigFormat();
    final differences = McpComparison.getDifferences(
      localConfig, 
      toolConfig,
      toolType: _selectedTool,
    );
    
    final screenHeight = MediaQuery.of(context).size.height;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 1400,
          constraints: BoxConstraints(maxHeight: screenHeight * 0.8),
          decoration: BoxDecoration(
            color: shadTheme.colorScheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: shadTheme.colorScheme.border,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
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
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: shadTheme.colorScheme.muted,
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/platforms/${localServer.icon ?? 'mcp.svg'}',
                          width: 20,
                          height: 20,
                          allowDrawingOutsideViewBox: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        localServer.name,
                        style: shadTheme.textTheme.h4.copyWith(
                          color: shadTheme.colorScheme.foreground,
                        ),
                      ),
                    ),
                    // 状态标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Color(McpComparison.getStatusColor(result.status)).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Color(McpComparison.getStatusColor(result.status)),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        McpComparison.getStatusLabel(result.status),
                        style: shadTheme.textTheme.small.copyWith(
                          color: Color(McpComparison.getStatusColor(result.status)),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ShadButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      onPressed: () async {
                      // 检查是否有未保存的变更
                      if (_hasUnsavedChanges()) {
                        final shouldClose = await _showUnsavedChangesDialog(isClosing: true);
                        if (shouldClose == null) {
                          // 取消，不关闭
                          return;
                        } else if (shouldClose == true) {
                          // 保存并关闭
                          await _saveChanges(closeAfterSave: true);
                          return;
                        }
                        // shouldClose == false 表示放弃并关闭，直接关闭
                      }
                      Navigator.pop(context);
                    },
                    ),
                  ],
                ),
              ),
              // 内容区域：左右分栏（移除顶部padding，使竖向分割线与横向分割线相连）
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧：本应用中的配置
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: shadTheme.colorScheme.border,
                                width: 1,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localizations?.mcpLocalServers ?? '本应用中的配置',
                                style: shadTheme.textTheme.small.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: shadTheme.colorScheme.foreground,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ..._buildServerDetailsContent(
                                localServer, 
                                shadTheme, 
                                localizations,
                                differences: differences,
                                isLeftSide: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 右侧：工具中的配置
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localizations?.mcpToolServers(_selectedTool?.displayName ?? '') ??
                                    '工具 ${_selectedTool?.displayName ?? ''} 中的配置',
                                style: shadTheme.textTheme.small.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: shadTheme.colorScheme.foreground,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ..._buildServerDetailsContent(
                                toolServer, 
                                shadTheme, 
                                localizations,
                                differences: differences,
                                isLeftSide: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建服务器详情内容
  List<Widget> _buildServerDetailsContent(
    McpServer server,
    ShadThemeData shadTheme,
    AppLocalizations? localizations, {
    Map<String, String>? differences,
    bool isLeftSide = true,
  }) {
    // 检查字段是否有差异
    bool _isFieldDifferent(String fieldPath) {
      if (differences == null) return false;
      // 检查差异中是否包含该字段路径
      return differences.keys.any((key) => key.startsWith(fieldPath));
    }
    
    return [
      _buildDetailRow(
        context, 
        localizations?.mcpServerIdLabel ?? '服务器ID', 
        server.serverId,
        isDifferent: _isFieldDifferent('serverId'),
      ),
      const SizedBox(height: 10),
      _buildDetailRow(
        context,
        localizations?.mcpServerType ?? '服务器类型',
        server.serverType.value.toUpperCase(),
        isDifferent: _isFieldDifferent('type'),
      ),
      const SizedBox(height: 10),
      _buildDetailRow(
        context,
        localizations?.mcpStatus ?? '状态',
        server.isActive
            ? (localizations?.mcpActive ?? '已激活')
            : (localizations?.mcpInactive ?? '未激活'),
        isDifferent: false, // 状态字段不参与比对
      ),
      const SizedBox(height: 10),
      // 根据服务器类型显示不同字段
      if (server.serverType == McpServerType.stdio) ...[
        if (server.command != null && server.command!.isNotEmpty) ...[
          _buildDetailRow(
            context,
            localizations?.mcpCommandLabel ?? '命令',
            server.command!,
            isMonospace: true,
            isDifferent: _isFieldDifferent('command'),
          ),
          const SizedBox(height: 10),
        ],
        if (server.args != null && server.args!.isNotEmpty) ...[
          _buildDetailRow(
            context,
            localizations?.mcpArgsLabel ?? '参数',
            server.args!.join(' '),
            isMonospace: true,
            isDifferent: _isFieldDifferent('args'),
          ),
          const SizedBox(height: 10),
        ],
        if (server.env != null && server.env!.isNotEmpty) ...[
          _buildDetailRow(
            context,
            localizations?.mcpEnv ?? '环境变量',
            server.env!.entries.map((e) => '${e.key}=${e.value}').join('\n'),
            isMonospace: true,
            isDifferent: _isFieldDifferent('env'),
          ),
          const SizedBox(height: 10),
        ],
        if (server.cwd != null && server.cwd!.isNotEmpty) ...[
          _buildDetailRow(
            context,
            localizations?.mcpCwd ?? '工作目录',
            server.cwd!,
            isMonospace: true,
            isDifferent: _isFieldDifferent('cwd'),
          ),
          const SizedBox(height: 10),
        ],
      ] else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) ...[
        if (server.url != null && server.url!.isNotEmpty) ...[
          _buildActionRow(
            context,
            localizations?.mcpUrlLabel ?? 'URL',
            server.url!,
            Icons.language,
            localizations?.open ?? '打开',
            () {
              if (server.url != null) {
                UrlLauncherService().openUrl(server.url!);
              }
            },
            isMonospace: true,
            isDifferent: _isFieldDifferent('url'),
          ),
          const SizedBox(height: 10),
        ],
        if (server.headers != null && server.headers!.isNotEmpty) ...[
          _buildDetailRow(
            context,
            localizations?.mcpHeaders ?? '请求头',
            server.headers!.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            isMonospace: true,
            isDifferent: _isFieldDifferent('headers'),
          ),
          const SizedBox(height: 10),
        ],
      ],
      // 管理地址
      if (server.homepage != null && server.homepage!.isNotEmpty) ...[
        _buildActionRow(
          context,
          localizations?.mcpHomepage ?? '管理地址',
          server.homepage!,
          Icons.language,
          localizations?.open ?? '打开',
          () => UrlLauncherService().openUrl(server.homepage!),
        ),
        const SizedBox(height: 10),
      ],
      // 文档地址
      if (server.docs != null && server.docs!.isNotEmpty) ...[
        _buildActionRow(
          context,
          localizations?.mcpDocs ?? '文档地址',
          server.docs!,
          Icons.description_outlined,
          localizations?.open ?? '打开',
          () => UrlLauncherService().openUrl(server.docs!),
        ),
        const SizedBox(height: 10),
      ],
      // 描述
      if (server.description != null && server.description!.isNotEmpty) ...[
        _buildDetailRow(
          context,
          localizations?.mcpDescription ?? '描述',
          server.description!,
        ),
        const SizedBox(height: 10),
      ],
      // JSON配置
      _buildJsonConfigRow(context, server),
    ];
  }

  /// 构建详情行（参照 mcp_config_screen.dart 的样式）
  Widget _buildDetailRow(
    BuildContext context, 
    String label, 
    String value, {
    bool isMonospace = false,
    bool isDifferent = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      decoration: isDifferent
          ? BoxDecoration(
              color: shadTheme.colorScheme.destructive.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: shadTheme.colorScheme.destructive.withValues(alpha: 0.3),
                width: 1,
              ),
            )
          : null,
      padding: isDifferent ? const EdgeInsets.all(8) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$label:',
                style: shadTheme.textTheme.small.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isDifferent
                      ? shadTheme.colorScheme.destructive
                      : shadTheme.colorScheme.mutedForeground,
                ),
              ),
              if (isDifferent) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: shadTheme.colorScheme.destructive,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: shadTheme.textTheme.small.copyWith(
              color: isDifferent
                  ? shadTheme.colorScheme.destructive
                  : shadTheme.colorScheme.foreground,
              fontFamily: isMonospace ? 'monospace' : null,
              fontSize: isMonospace ? 13 : null,
              fontWeight: isDifferent ? FontWeight.w500 : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建操作行（参照 mcp_config_screen.dart 的样式）
  Widget _buildActionRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isMonospace = false,
    bool isDifferent = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      decoration: isDifferent
          ? BoxDecoration(
              color: shadTheme.colorScheme.destructive.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: shadTheme.colorScheme.destructive.withValues(alpha: 0.3),
                width: 1,
              ),
            )
          : null,
      padding: isDifferent ? const EdgeInsets.all(8) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$label:',
                style: shadTheme.textTheme.small.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isDifferent
                      ? shadTheme.colorScheme.destructive
                      : shadTheme.colorScheme.mutedForeground,
                ),
              ),
              if (isDifferent) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: shadTheme.colorScheme.destructive,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: shadTheme.textTheme.small.copyWith(
                    color: isDifferent
                        ? shadTheme.colorScheme.destructive
                        : shadTheme.colorScheme.primary,
                    fontFamily: isMonospace ? 'monospace' : null,
                    fontSize: isMonospace ? 13 : null,
                    fontWeight: isDifferent ? FontWeight.w500 : null,
                  ),
                ),
              ),
              Tooltip(
                message: tooltip,
                child: ShadButton.ghost(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(6),
                  onPressed: onPressed,
                  child: Icon(icon, size: 18, color: shadTheme.colorScheme.mutedForeground),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建JSON配置行（参照 mcp_config_screen.dart 的样式）
  Widget _buildJsonConfigRow(BuildContext context, McpServer server) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    final jsonConfig = _generateJsonConfig(server);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${localizations?.mcpJsonConfigLabel ?? 'JSON配置'}:',
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
                child: SelectableText(
                  jsonConfig,
                  style: shadTheme.textTheme.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: localizations?.mcpCopyJson ?? '复制JSON配置',
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                onPressed: () {
                  ClipboardService().copyToClipboard(jsonConfig);
                  final loc = AppLocalizations.of(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(loc?.mcpJsonCopied ?? 'JSON配置已复制'),
                    ),
                  );
                },
                child: Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建时间行（参照 mcp_config_screen.dart 的样式）
  Widget _buildTimeRow(
    BuildContext context,
    String createdLabel,
    String createdValue,
    String updatedLabel,
    String updatedValue,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$createdLabel / $updatedLabel:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$createdValue / $updatedValue',
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
          ),
        ),
      ],
    );
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// 生成JSON配置
  String _generateJsonConfig(McpServer server) {
    final config = server.toToolConfigFormat();
    final jsonWithId = <String, dynamic>{
      server.serverId: config,
    };
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    final screenHeight = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 1200,
        height: screenHeight * 0.8, // 使用屏幕高度的65%，之前是固定700px
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
                    localizations?.mcpSyncDialogTitle ?? 'MCP 配置同步',
                    style: shadTheme.textTheme.h4.copyWith(
                      color: shadTheme.colorScheme.foreground,
                    ),
                  ),
                  const Spacer(),
                  // 工具切换滑块
                  _buildToolSwitcher(context, shadTheme),
                  const SizedBox(width: 12),
                  ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                    onPressed: () async {
                      // 检查是否有未保存的变更
                      if (_hasUnsavedChanges()) {
                        final shouldClose = await _showUnsavedChangesDialog(isClosing: true);
                        if (shouldClose == null) {
                          // 取消，不关闭
                          return;
                        } else if (shouldClose == true) {
                          // 保存并关闭
                          await _saveChanges(closeAfterSave: true);
                          return;
                        }
                        // shouldClose == false 表示放弃并关闭，直接关闭
                      }
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            // 内容区域：左右分栏
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: shadTheme.colorScheme.primary,
                      ),
                    )
                  : _hasRead
                      ? Row(
                          children: [
                            // 左侧：本应用中的MCP服务
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(
                                      color: shadTheme.colorScheme.border,
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 左侧标题区域（与右侧高度对齐）
                                    SizedBox(
                                      height: 40, // 固定高度，与右侧对齐
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          localizations?.mcpLocalServers ?? '本应用中的 MCP 服务',
                                          style: shadTheme.textTheme.small.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: shadTheme.colorScheme.foreground,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: Consumer<McpViewModel>(
                                        builder: (context, viewModel, child) {
                                          // 获取排序后的本地服务列表（按照比对结果排序）
                                          // 优先显示两边都有的服务（identical 和 different），然后是 onlyInLocal
                                          final sortedLocalServers = _comparisonResults
                                              .where((r) => r.status == McpComparisonStatus.onlyInLocal ||
                                                           r.status == McpComparisonStatus.identical ||
                                                           r.status == McpComparisonStatus.different)
                                              .map((r) => r.server)
                                              .toList();
                                          
                                          if (sortedLocalServers.isEmpty) {
                                            return Center(
                                              child: Text(
                                                localizations?.mcpNoServers ?? '暂无 MCP 服务',
                                                style: shadTheme.textTheme.p.copyWith(
                                                  color: shadTheme.colorScheme.mutedForeground,
                                                ),
                                              ),
                                            );
                                          }

                                          return ListView.builder(
                                            itemCount: sortedLocalServers.length,
                                            itemBuilder: (context, index) {
                                              final server = sortedLocalServers[index];
                                              final result = _comparisonResults.firstWhere(
                                                (r) => r.server.serverId == server.serverId,
                                                orElse: () => McpComparisonResult(
                                                  server: server,
                                                  status: McpComparisonStatus.onlyInLocal,
                                                ),
                                              );
                                              return _buildServerListItem(
                                                server: server,
                                                status: result.status,
                                                isLeftSide: true,
                                                shadTheme: shadTheme,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 右侧：工具配置文件中的MCP服务
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 右侧标题区域（固定高度，与左侧对齐）
                                    SizedBox(
                                      height: 40, // 固定高度，与左侧对齐
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              localizations?.mcpToolServers(_selectedTool?.displayName ?? '') ??
                                                  '工具 ${_selectedTool?.displayName ?? ''} 中的 MCP 服务',
                                              style: shadTheme.textTheme.small.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: shadTheme.colorScheme.foreground,
                                              ),
                                            ),
                                          ),
                                          // ClaudeCode 配置范围选择（帮助图标 + 下拉框）
                                          if (_selectedTool == AiToolType.claudecode) ...[
                                            // 帮助图标（放在下拉框左侧）
                                            Tooltip(
                                              message: localizations?.mcpClaudeCodeScopeHelp ?? 
                                                  'ClaudeCode 支持全局配置和项目配置。项目配置优先级高于全局配置。\n\n'
                                                  '全局配置：存储在 ~/.claude.json 的 mcpServers 字段\n'
                                                  '项目配置：存储在 ~/.claude.json 的 projects[项目路径].mcpServers 字段',
                                              waitDuration: const Duration(milliseconds: 500),
                                              preferBelow: false,
                                              child: Icon(
                                                Icons.help_outline,
                                                size: 16,
                                                color: shadTheme.colorScheme.mutedForeground,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // ShadSelect 下拉选择框（始终显示，即使只有一个选项）
                                            SizedBox(
                                              width: 140,
                                              child: ShadSelect<String>(
                                                initialValue: _selectedScope,
                                                placeholder: Text(
                                                  localizations?.mcpGlobalConfig ?? '全局配置',
                                                  style: shadTheme.textTheme.small.copyWith(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                options: _availableScopes.map((scope) {
                                                  final displayName = scope == 'global' 
                                                      ? (localizations?.mcpGlobalConfig ?? '全局配置')
                                                      : scope;
                                                  return ShadOption<String>(
                                                    value: scope,
                                                    child: Text(
                                                      displayName,
                                                      style: shadTheme.textTheme.small.copyWith(
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                                selectedOptionBuilder: (context, value) {
                                                  final displayName = value == 'global' 
                                                      ? (localizations?.mcpGlobalConfig ?? '全局配置')
                                                      : value;
                                                  return Text(
                                                    displayName,
                                                    style: shadTheme.textTheme.small.copyWith(
                                                      fontSize: 12,
                                                    ),
                                                  );
                                                },
                                                onChanged: (String? newScope) async {
                                                  if (newScope != null && newScope != _selectedScope) {
                                                    // 保存旧值，以便取消时恢复
                                                    final oldScope = _selectedScope;
                                                    
                                                    // 检查是否有未保存的变更
                                                    if (_hasUnsavedChanges()) {
                                                      final shouldSwitch = await _showUnsavedChangesDialog(isClosing: false);
                                                      if (shouldSwitch == null) {
                                                        // 取消，不切换，恢复原值
                                                        setState(() {
                                                          _selectedScope = oldScope;
                                                        });
                                                        return;
                                                      } else if (shouldSwitch == true) {
                                                        // 保存并切换
                                                        final success = await _saveChanges(closeAfterSave: false);
                                                        if (!mounted || !success) {
                                                          // 保存失败，恢复原值
                                                          setState(() {
                                                            _selectedScope = oldScope;
                                                          });
                                                          return;
                                                        }
                                                        // 保存成功后切换项目并重新读取配置
                                                        setState(() {
                                                          _selectedScope = newScope;
                                                          _hasRead = false;
                                                        });
                                                        await _readFromTool();
                                                        return;
                                                      }
                                                      // shouldSwitch == false 表示放弃并切换，清空待同步列表后继续执行切换逻辑
                                                      if (shouldSwitch == false) {
                                                        setState(() {
                                                          _pendingExportServers.clear();
                                                          _pendingImportServers.clear();
                                                          _pendingDeleteServerIds.clear();
                                                        });
                                                      }
                                                    }
                                                    
                                                    setState(() {
                                                      _selectedScope = newScope;
                                                      _hasRead = false;
                                                    });
                                                    _readFromTool();
                                                  }
                                                },
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: Builder(
                                        builder: (context) {
                                          // 如果是项目配置且没有项目 MCP 配置，显示提示信息
                                          if (_selectedTool == AiToolType.claudecode && 
                                              _selectedScope != null && 
                                              _selectedScope != 'global' && 
                                              !_hasProjectConfig && 
                                              _toolServers.isEmpty) {
                                            return Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.info_outline,
                                                    size: 48,
                                                    color: shadTheme.colorScheme.mutedForeground,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    localizations?.mcpProjectUsesGlobalConfig ?? 
                                                        '该项目没有单独配置，将使用全局配置',
                                                    style: shadTheme.textTheme.p.copyWith(
                                                      color: shadTheme.colorScheme.mutedForeground,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                          
                                          // 其他情况：没有配置或正常显示列表
                                          if (_toolServers.isEmpty) {
                                            return Center(
                                              child: Text(
                                                localizations?.mcpNoConfigInTool(_selectedTool?.displayName ?? '') ??
                                                    '工具 ${_selectedTool?.displayName ?? ''} 中没有找到 MCP 配置',
                                                style: shadTheme.textTheme.p.copyWith(
                                                  color: shadTheme.colorScheme.mutedForeground,
                                                ),
                                              ),
                                            );
                                          }
                                          
                                          // 获取排序后的工具服务列表（按照比对结果排序，与左侧一一对应）
                                          // 优先显示两边都有的服务（identical 和 different），然后是 onlyInTool
                                          // 注意：不过滤待删除的服务，以便显示"将删除"标签
                                          final sortedToolServers = _comparisonResults
                                              .where((r) => r.status == McpComparisonStatus.onlyInTool ||
                                                           r.status == McpComparisonStatus.identical ||
                                                           r.status == McpComparisonStatus.different)
                                              .map((r) {
                                                // 如果是 identical 或 different，使用工具中的服务器（如果有）
                                                if (r.status == McpComparisonStatus.identical || 
                                                    r.status == McpComparisonStatus.different) {
                                                  return r.toolServer ?? r.server;
                                                }
                                                return r.server;
                                              })
                                              .toList();
                                          
                                          if (sortedToolServers.isEmpty) {
                                            return Center(
                                              child: Text(
                                                localizations?.mcpNoConfigInTool(_selectedTool?.displayName ?? '') ??
                                                    '工具 ${_selectedTool?.displayName ?? ''} 中没有找到 MCP 配置',
                                                style: shadTheme.textTheme.p.copyWith(
                                                  color: shadTheme.colorScheme.mutedForeground,
                                                ),
                                              ),
                                            );
                                          }
                                          
                                          return ListView.builder(
                                            itemCount: sortedToolServers.length,
                                            itemBuilder: (context, index) {
                                              final server = sortedToolServers[index];
                                              final result = _comparisonResults.firstWhere(
                                                (r) => r.server.serverId == server.serverId ||
                                                       (r.toolServer != null && r.toolServer!.serverId == server.serverId),
                                                orElse: () => McpComparisonResult(
                                                  server: server,
                                                  status: McpComparisonStatus.onlyInTool,
                                                ),
                                              );
                                              return _buildServerListItem(
                                                server: server,
                                                status: result.status,
                                                isLeftSide: false,
                                                shadTheme: shadTheme,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.cloud_download,
                                size: 48,
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                localizations?.mcpClickRead ?? '请点击工具切换滑块或等待自动读取',
                                style: shadTheme.textTheme.p.copyWith(
                                  color: shadTheme.colorScheme.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
            // 错误信息
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: shadTheme.colorScheme.border,
                      width: 1,
                    ),
                  ),
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
                  Text(
                    localizations?.mcpPendingChanges(
                      _pendingExportServers.length,
                      _pendingImportServers.length,
                      _pendingDeleteServerIds.length,
                    ) ??
                        '待同步：导出 ${_pendingExportServers.length} 个，导入 ${_pendingImportServers.length} 个，删除 ${_pendingDeleteServerIds.length} 个',
                    style: shadTheme.textTheme.small.copyWith(
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ShadButton.outline(
                    onPressed: () async {
                      // 检查是否有未保存的变更
                      if (_hasUnsavedChanges()) {
                        final shouldClose = await _showUnsavedChangesDialog(isClosing: true);
                        if (shouldClose == null) {
                          // 取消，不关闭
                          return;
                        } else if (shouldClose == true) {
                          // 保存并关闭
                          await _saveChanges(closeAfterSave: true);
                          return;
                        }
                        // shouldClose == false 表示放弃并关闭，直接关闭
                      }
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(localizations?.cancel ?? '取消'),
                  ),
                  const SizedBox(width: 12),
                  ShadButton(
                    onPressed: _isLoading ||
                            !_hasRead ||
                            (_pendingExportServers.isEmpty &&
                                _pendingImportServers.isEmpty &&
                                _pendingDeleteServerIds.isEmpty)
                        ? null
                        : () => _saveChanges(closeAfterSave: false),
                    leading: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save, size: 18),
                    child: Text(localizations?.save ?? '保存'),
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

