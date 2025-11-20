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

  /// 删除 MCP 服务器
  Future<int> deleteMcpServer(int id) async {
    final db = await _databaseService.database;
    return await db.delete(
      'mcp_servers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 根据 serverId 删除 MCP 服务器
  Future<int> deleteMcpServerByServerId(String serverId) async {
    final db = await _databaseService.database;
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
}

