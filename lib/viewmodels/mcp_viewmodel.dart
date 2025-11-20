import '../models/mcp_server.dart';
import '../services/mcp_database_service.dart';
import '../services/mcp_sync_service.dart';
import 'base_viewmodel.dart';

/// MCP 管理 ViewModel
class McpViewModel extends BaseViewModel {
  final McpDatabaseService _databaseService = McpDatabaseService();
  final McpSyncService _syncService = McpSyncService();

  List<McpServer> _allServers = [];
  List<McpServer> _filteredServers = [];
  String _searchQuery = '';

  List<McpServer> get servers => _filteredServers;
  List<McpServer> get allServers => _allServers;
  String get searchQuery => _searchQuery;

  /// 初始化
  Future<void> init() async {
    // 如果数据已经加载过，就不需要重新加载，避免页面闪烁
    if (_allServers.isEmpty) {
      // 首次加载时显示加载状态
      await loadServers(showLoading: true);
    }
  }

  /// 加载所有 MCP 服务器
  Future<void> loadServers({bool showLoading = true}) async {
    await executeAsync(() async {
      _allServers = await _databaseService.getAllMcpServers();
      _updateFilteredServers();
    }, showLoading: showLoading);
  }

  /// 刷新服务器列表
  Future<void> refresh() async {
    // 如果数据已经加载过，就不显示加载状态，避免切换页面时闪烁
    await loadServers(showLoading: _allServers.isEmpty);
  }

  /// 设置搜索查询
  void setSearchQuery(String query) {
    _searchQuery = query;
    _updateFilteredServers();
    notifyListeners();
  }

  /// 更新筛选后的服务器列表
  void _updateFilteredServers() {
    var filtered = _allServers;

    // 应用搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((server) {
        return server.name.toLowerCase().contains(query) ||
            server.serverId.toLowerCase().contains(query) ||
            (server.description?.toLowerCase().contains(query) ?? false) ||
            (server.tags?.any((tag) => tag.toLowerCase().contains(query)) ?? false);
      }).toList();
    }

    _filteredServers = filtered;
  }

  /// 添加 MCP 服务器
  Future<bool> addServer(McpServer server) async {
    return await executeAsync(() async {
      // 检查 serverId 是否已存在
      final exists = await _databaseService.serverIdExists(server.serverId);
      if (exists) {
        setError('服务器 ID "${server.serverId}" 已存在');
        return false;
      }

      await _databaseService.addMcpServer(server);
      await loadServers();
      return true;
    }) ?? false;
  }

  /// 更新 MCP 服务器
  Future<bool> updateServer(McpServer server) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      // 检查 serverId 是否与其他服务器冲突
      final exists = await _databaseService.serverIdExists(server.serverId, excludeId: server.id);
      if (exists) {
        setError('服务器 ID "${server.serverId}" 已被其他服务器使用');
        return false;
      }

      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      final index = _allServers.indexWhere((s) => s.id == server.id);
      if (index != -1) {
        _allServers[index] = server;
        _updateFilteredServers();
        notifyListeners();
      }

      // 然后在后台更新数据库，不阻塞 UI
      await _databaseService.updateMcpServer(server);
      
      return true;
    } catch (e) {
      // 如果更新失败，重新加载数据恢复状态
      await loadServers(showLoading: false);
      return false;
    }
  }

  /// 删除 MCP 服务器
  Future<bool> deleteServer(int id) async {
    return await executeAsync(() async {
      await _databaseService.deleteMcpServer(id);
      await loadServers();
      return true;
    }) ?? false;
  }

  /// 切换激活状态
  Future<bool> toggleActive(int id, bool isActive) async {
    return await executeAsync(() async {
      await _databaseService.toggleActive(id, isActive);
      await loadServers();
      return true;
    }) ?? false;
  }

  /// 重新排序服务器列表
  Future<bool> reorderServers(List<McpServer> reorderedServers) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      _allServers = reorderedServers;
      _updateFilteredServers();
      notifyListeners();
      
      // 然后在后台更新数据库，不阻塞 UI
      final now = DateTime.now();
      for (int i = 0; i < reorderedServers.length; i++) {
        final server = reorderedServers[i];
        // 创建一个新的时间戳，确保顺序正确
        // 使用微秒来确保每个服务器有不同的时间戳
        final updatedAt = now.add(Duration(microseconds: i));
        final updatedServer = server.copyWith(updatedAt: updatedAt);
        await _databaseService.updateMcpServer(updatedServer);
      }
      
      return true;
    } catch (e) {
      // 如果更新失败，重新加载数据恢复状态
      await loadServers();
      return false;
    }
  }

  /// 从工具配置文件导入 MCP 服务器
  /// [tool] 工具类型
  /// [selectedServerIds] 选中的 MCP 服务 ID 列表
  /// 返回导入结果：新增数量、覆盖数量、失败列表
  Future<ImportResult> importFromTool(AiToolType tool, Set<String> selectedServerIds) async {
    final result = ImportResult();
    
    await executeAsync(() async {
      try {
        // 从工具读取 MCP 配置
        final toolResult = await _syncService.readMcpServersFromTool(tool);
        final toolServers = toolResult.servers;
        
        if (toolServers.isEmpty) {
          setError('工具 ${tool.displayName} 中没有找到 MCP 配置');
          return;
        }

        // 筛选选中的服务器
        final serversToImport = toolServers.entries
            .where((entry) => selectedServerIds.contains(entry.key))
            .toList();

        if (serversToImport.isEmpty) {
          setError('未选择任何 MCP 服务');
          return;
        }

        // 遍历导入
        for (final entry in serversToImport) {
          final serverId = entry.key;
          final server = entry.value;

          try {
            // 检查是否已存在
            final existingServer = await _databaseService.getMcpServerByServerId(serverId);
            
            if (existingServer != null) {
              // 已存在，更新（覆盖）
              final updatedServer = server.copyWith(
                id: existingServer.id,
                createdAt: existingServer.createdAt, // 保留原始创建时间
                updatedAt: DateTime.now(),
              );
              await _databaseService.updateMcpServer(updatedServer);
              result.overridden.add(serverId);
            } else {
              // 不存在，新增
              await _databaseService.addMcpServer(server);
              result.added.add(serverId);
            }
          } catch (e) {
            print('导入 MCP 服务器 "$serverId" 失败: $e');
            result.failed.add(serverId);
          }
        }

        // 刷新列表
        await loadServers();
      } catch (e) {
        setError('导入失败: $e');
      }
    });

    return result;
  }

  /// 下发 MCP 服务到工具配置文件
  /// [tool] 目标工具
  /// [serverIds] 要下发的 MCP 服务 ID 列表
  /// [scope] 对于 claudecode，可以是 'global' 或项目路径
  Future<bool> exportToTool(AiToolType tool, Set<String> serverIds, {String? scope}) async {
    return await executeAsync(() async {
      return await _syncService.syncToTool(tool, serverIds, scope: scope);
    }) ?? false;
  }

  /// 获取激活的服务器
  Future<List<McpServer>> getActiveServers() async {
    return await _databaseService.getActiveMcpServers();
  }

  /// 根据 ID 获取服务器
  Future<McpServer?> getServerById(int id) async {
    return await _databaseService.getMcpServerById(id);
  }

  /// 检查 serverId 是否存在
  Future<bool> serverIdExists(String serverId, {int? excludeId}) async {
    return await _databaseService.serverIdExists(serverId, excludeId: excludeId);
  }
}

/// 导入结果
class ImportResult {
  final List<String> added = []; // 新增的服务 ID
  final List<String> overridden = []; // 覆盖的服务 ID
  final List<String> failed = []; // 失败的服务 ID

  int get addedCount => added.length;
  int get overriddenCount => overridden.length;
  int get failedCount => failed.length;
  int get totalCount => addedCount + overriddenCount + failedCount;
}

