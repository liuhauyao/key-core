import 'dart:io';
import 'package:flutter/services.dart';
import '../../theme/kc_tokens.dart';
import '../widgets/mcp_sync_board.dart';
import '../widgets/kc_menu.dart';
import '../../services/ai_tool_config_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/mcp_server.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/mcp_sync_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/mcp_comparison.dart';
import '../../views/widgets/confirm_dialog.dart';
import '../widgets/kc_window_header.dart';
import '../widgets/kc_toast.dart';

/// MCP 同步页面
/// 合并导入和导出功能，实现左右分栏对比和双向同步
class McpSyncPage extends StatefulWidget {
  const McpSyncPage({super.key});

  @override
  State<McpSyncPage> createState() => _McpSyncPageState();
}

class _McpSyncPageState extends State<McpSyncPage> {
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
      _loadSummaries();
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
        
      });
      _summaries[_selectedTool!] = _summarize(_selectedTool!, sortedResults);
      _configPath = await _pathFor(_selectedTool!);
      if (mounted) setState(() {});
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
        showKcToast(context, localizations?.mcpSyncComplete(exportCount, importCount, deleteCount, failedCount) ??
                  '同步完成：导出 $exportCount 个，导入 $importCount 个，删除 $deleteCount 个${failedCount > 0 ? '，失败 $failedCount 个' : ''}', kind: failedCount > 0 ? KcToastKind.warning : KcToastKind.success);
        
        // 如果需要关闭窗口
        if (closeAfterSave) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // 重新读取配置
          await _readFromTool();
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
        showKcToast(context, localizations?.mcpSyncFailed(e.toString()) ?? '同步失败: $e', kind: KcToastKind.error);
      }
      return false;
    }
  }

  Future<void> _requestClose() async {
                  // 检查是否有未保存的变更
                  if (_hasUnsavedChanges()) {
                    final shouldClose = await _showUnsavedChangesDialog(isClosing: true);
                    if (shouldClose == null) {
                      return;
                    } else if (shouldClose == true) {
                      await _saveChanges(closeAfterSave: true);
                      return;
                    }
                  }
                  Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 切换同步目标工具（保留「未保存变更」确认）
  Future<void> _selectTool(AiToolType tool) async {
      if (_selectedTool == tool) return;
              
              // 检查是否有未保存的变更
              if (_hasUnsavedChanges()) {
                final shouldSwitch = await _showUnsavedChangesDialog(isClosing: false);
                if (shouldSwitch == null) {
                  return;
                } else if (shouldSwitch == true) {
                  final success = await _saveChanges(closeAfterSave: false);
                  if (!mounted || !success) return;
                  setState(() {
                    _selectedTool = tool;
                    _hasRead = false;
                    if (tool != AiToolType.claudecode) {
                      _selectedScope = null;
                      _availableScopes = ['global'];
                    }
                  });
                  await _readFromTool();
                  return;
                }
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
                if (tool != AiToolType.claudecode) {
                  _selectedScope = null;
                  _availableScopes = ['global'];
                }
              });
              _readFromTool();
  }


  // ───────── v3：左侧工具状态 / 文件路径 / 待执行动作 ─────────
  final Map<AiToolType, McpToolSummary> _summaries = {};
  String? _configPath;

  McpToolSummary _summarize(AiToolType tool, List<McpComparisonResult> r) => McpToolSummary(
        tool: tool,
        total: r.length,
        pending: r.where((x) => x.status != McpComparisonStatus.identical).length,
        conflicts: r.where((x) => x.status == McpComparisonStatus.different).length,
      );

  Future<String> _pathFor(AiToolType tool) async {
    if (tool == AiToolType.claudecode) {
      return (_selectedScope == null || _selectedScope == 'global')
          ? '~/.claude.json  ·  mcpServers'
          : '~/.claude.json  ·  projects["$_selectedScope"].mcpServers${_hasProjectConfig ? '' : '  (new)'}';
    }
    try {
      final svc = AiToolConfigService();
      final p = AiToolConfigService.getConfigFilePath(tool, customConfigDir: await svc.getConfigDir(tool));
      return _tildify(AiToolConfigService.expandPath(p));
    } catch (_) {
      return '';
    }
  }

  String _tildify(String p) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home != null && p.startsWith(home) ? '~${p.substring(home.length)}' : p;
  }

  /// 只读扫描所有已启用工具，生成左侧状态徽标（不写任何文件）
  Future<void> _loadSummaries() async {
    final tools = _getEnabledTools(context);
    final local = context.read<McpViewModel>().allServers.where((s) => s.isActive).toList();
    setState(() {
      for (final t in tools) {
        _summaries.putIfAbsent(t, () => McpToolSummary(tool: t, loading: true));
      }
    });
    for (final t in tools) {
      McpToolSummary s;
      try {
        final dir = await AiToolConfigService().getConfigDir(t);
        if (t != AiToolType.claudecode && !Directory(AiToolConfigService.expandPath(dir)).existsSync()) {
          s = McpToolSummary(tool: t, notInstalled: true);
        } else {
          final r = await _syncService.readMcpServersFromTool(t, scope: t == AiToolType.claudecode ? 'global' : null);
          s = _summarize(t, McpComparison.compare(localServers: local, toolServers: r.servers, toolType: t));
        }
      } catch (_) {
        s = McpToolSummary(tool: t, error: true);
      }
      if (!mounted) return;
      // 当前工具以页面里的实时比对为准
      if (t == _selectedTool && _hasRead) continue;
      setState(() => _summaries[t] = s);
    }
  }

  Map<String, McpSyncAction> get _pending => {
        for (final id in _pendingExportServers.keys) id: McpSyncAction.push,
        for (final id in _pendingImportServers.keys) id: McpSyncAction.pull,
        for (final id in _pendingDeleteServerIds) id: McpSyncAction.delete,
      };

  void _setAction(String id, McpSyncAction? a) {
    setState(() {
      _pendingExportServers.remove(id);
      _pendingImportServers.remove(id);
      _pendingDeleteServerIds.remove(id);
    });
    switch (a) {
      case McpSyncAction.push:
        _addToPendingExport(id);
      case McpSyncAction.pull:
        _addToPendingImport(id);
      case McpSyncAction.delete:
        _addToPendingDelete(id);
      case null:
        break;
    }
  }

  Future<void> _apply() async {
    final tool = _selectedTool;
    if (tool == null || !_hasUnsavedChanges()) return;
    final ok = await showMcpSyncConfirm(
      context: context,
      tool: tool,
      configPath: _configPath ?? '',
      pending: _pending,
    );
    if (!ok || !mounted) return;
    await _saveChanges();
  }

  Widget? _scopeSelector() {
    if (_selectedTool != AiToolType.claudecode || _availableScopes.length <= 1) return null;
    final l = AppLocalizations.of(context);
    return KcSelect<String>(
      key: const ValueKey('mcpSync.scope'),
      width: 180,
      value: _selectedScope ?? 'global',
      options: [for (final s in _availableScopes) (s, s == 'global' ? (l?.mcpGlobalConfig ?? '全局配置') : s)],
      onChanged: (v) async {
        if (v == _selectedScope) return;
        if (_hasUnsavedChanges()) {
          final r = await _showUnsavedChangesDialog();
          if (r == null) return;
          if (r == true && !await _saveChanges()) return;
        }
        setState(() => _selectedScope = v);
        await _readFromTool();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final tools = _getEnabledTools(context);
    return CallbackShortcuts(
      // Esc = 关闭（含未保存变更确认）
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _requestClose},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: cs.background,
          body: Column(children: [
            KcWindowHeader(
              title: l?.tr('mcp_sync_title', 'MCP 同步') ?? 'MCP 同步',
              onClose: _requestClose,
            ),
            Divider(height: 1, thickness: 1, color: cs.border),
            Expanded(
              child: tools.isEmpty
                  ? Center(child: Text(l?.mcpNoEnabledTools ?? '没有已启用的工具', style: KcType.body.copyWith(color: cs.mutedForeground)))
                  : McpSyncBoard(
                      tools: [for (final t in tools) _summaries[t] ?? McpToolSummary(tool: t, loading: true)],
                      selectedTool: _selectedTool,
                      onSelectTool: _selectTool,
                      results: _comparisonResults,
                      pending: _pending,
                      onSetAction: _setAction,
                      onApply: _apply,
                      onDiscard: () => setState(() {
                        _pendingExportServers.clear();
                        _pendingImportServers.clear();
                        _pendingDeleteServerIds.clear();
                      }),
                      configPath: _configPath,
                      scopeSelector: _scopeSelector(),
                      loading: _isLoading,
                      error: _errorMessage,
                      onRefresh: () async {
                        if (_hasUnsavedChanges()) {
                          final r = await _showUnsavedChangesDialog();
                          if (r == null) return;
                          if (r == true && !await _saveChanges()) return;
                        }
                        await _readFromTool();
                        _loadSummaries();
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
