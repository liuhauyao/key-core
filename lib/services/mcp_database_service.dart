import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/mcp_server.dart';
import 'database_service.dart';

/// MCP 数据库服务
/// 提供 MCP 服务器的 CRUD 操作
class McpDatabaseService {
  final DatabaseService _databaseService = DatabaseService.instance;

  /// 获取所有 MCP 服务器
  Future<List<McpServer>> getAllMcpServers() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'mcp_servers',
      orderBy: 'updated_at ASC', // 改为升序，确保拖动排序正确
    );
    return maps.map((map) => McpServer.fromMap(map)).toList();
  }

  /// 根据 ID 获取 MCP 服务器
  Future<McpServer?> getMcpServerById(int id) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'mcp_servers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return McpServer.fromMap(maps.first);
    }
    return null;
  }

  /// 根据 serverId 获取 MCP 服务器
  Future<McpServer?> getMcpServerByServerId(String serverId) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'mcp_servers',
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
    if (maps.isNotEmpty) {
      return McpServer.fromMap(maps.first);
    }
    return null;
  }

  /// 添加 MCP 服务器
  Future<int> addMcpServer(McpServer server) async {
    final db = await _databaseService.database;
    return await db.insert('mcp_servers', server.toMap());
  }

  /// 更新 MCP 服务器
  Future<int> updateMcpServer(McpServer server) async {
    final db = await _databaseService.database;
    return await db.update(
      'mcp_servers',
      server.toMap(),
      where: 'id = ?',
      whereArgs: [server.id],
    );
  }

  /// 删除 MCP 服务器（同时删除其工具启用关系）
  Future<int> deleteMcpServer(int id) async {
    final db = await _databaseService.database;
    final rows = await db.query('mcp_servers', columns: ['server_id'], where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) {
      await db.delete('mcp_server_apps', where: 'server_id = ?', whereArgs: [rows.first['server_id']]);
    }
    return await db.delete(
      'mcp_servers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 根据 serverId 删除 MCP 服务器
  Future<int> deleteMcpServerByServerId(String serverId) async {
    final db = await _databaseService.database;
    await db.delete('mcp_server_apps', where: 'server_id = ?', whereArgs: [serverId]);
    return await db.delete(
      'mcp_servers',
      where: 'server_id = ?',
      whereArgs: [serverId],
    );
  }

  /// 获取激活的 MCP 服务器
  Future<List<McpServer>> getActiveMcpServers() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'mcp_servers',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => McpServer.fromMap(map)).toList();
  }

  /// 切换激活状态
  Future<int> toggleActive(int id, bool isActive) async {
    final db = await _databaseService.database;
    // 不更新 updated_at，避免激活/取消激活时改变卡片位置
    return await db.update(
      'mcp_servers',
      {
        'is_active': isActive ? 1 : 0,
        // 移除 updated_at 更新，保持原有顺序
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 搜索 MCP 服务器
  Future<List<McpServer>> searchMcpServers(String query) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'mcp_servers',
      where: 'name LIKE ? OR description LIKE ? OR server_id LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => McpServer.fromMap(map)).toList();
  }

  /// 检查 serverId 是否存在
  Future<bool> serverIdExists(String serverId, {int? excludeId}) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'mcp_servers',
      where: excludeId != null ? 'server_id = ? AND id != ?' : 'server_id = ?',
      whereArgs: excludeId != null ? [serverId, excludeId] : [serverId],
    );
    return maps.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 按工具启用（对齐 CC Switch 的 enabled_<app>）
  // ---------------------------------------------------------------------------

  /// 全部启用关系：serverId → 已启用的工具
  Future<Map<String, Set<AiToolType>>> getAllServerApps() async {
    final db = await _databaseService.database;
    final rows = await db.query('mcp_server_apps');
    final out = <String, Set<AiToolType>>{};
    for (final r in rows) {
      final tool = _toolFromValue(r['tool'] as String);
      if (tool == null) continue;
      (out[r['server_id'] as String] ??= <AiToolType>{}).add(tool);
    }
    return out;
  }

  /// 某个服务已启用的工具
  Future<Set<AiToolType>> getServerApps(String serverId) async {
    final db = await _databaseService.database;
    final rows = await db.query('mcp_server_apps', where: 'server_id = ?', whereArgs: [serverId]);
    return rows.map((r) => _toolFromValue(r['tool'] as String)).whereType<AiToolType>().toSet();
  }

  /// 某个工具上已启用的服务 ID
  Future<Set<String>> getServerIdsForTool(AiToolType tool) async {
    final db = await _databaseService.database;
    final rows = await db.query('mcp_server_apps', where: 'tool = ?', whereArgs: [tool.value]);
    return rows.map((r) => r['server_id'] as String).toSet();
  }

  /// 设置服务在某工具上的启用状态
  Future<void> setServerApp(String serverId, AiToolType tool, bool enabled) async {
    final db = await _databaseService.database;
    if (enabled) {
      await db.insert(
        'mcp_server_apps',
        {'server_id': serverId, 'tool': tool.value, 'created_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.delete('mcp_server_apps', where: 'server_id = ? AND tool = ?', whereArgs: [serverId, tool.value]);
    }
  }

  /// serverId 改名时迁移启用关系
  Future<void> renameServerApps(String oldId, String newId) async {
    if (oldId == newId) return;
    final db = await _databaseService.database;
    await db.update('mcp_server_apps', {'server_id': newId}, where: 'server_id = ?', whereArgs: [oldId],
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static AiToolType? _toolFromValue(String v) {
    for (final t in AiToolType.values) {
      if (t.value == v) return t;
    }
    return null;
  }
}
