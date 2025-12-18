import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/ai_key.dart';
import '../constants/app_constants.dart';
import '../services/platform_registry.dart';
import '../services/cloud_config_service.dart';
import '../models/platform_type.dart';

/// 数据库服务
/// 提供AI密钥的CRUD操作
class DatabaseService {
  static DatabaseService? _instance;
  static Database? _database;
  static bool _isFfiInitialized = false;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  /// 获取数据库实例
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    // 初始化FFI加载器（仅在macOS/Windows/Linux上需要）
    // 注意：这会改变sqflite的全局默认factory，这是预期的行为
    // 使用静态标志避免重复初始化，减少警告
    if (!_isFfiInitialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _isFfiInitialized = true;
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ai_keys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        platform TEXT NOT NULL,
        platform_type INTEGER NOT NULL,
        platform_type_id TEXT,
        management_url TEXT,
        api_endpoint TEXT,
        key_value TEXT NOT NULL,
        key_nonce TEXT,
        expiry_date TEXT,
        tags TEXT,
        notes TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_used_at TEXT,
        is_favorite INTEGER DEFAULT 0,
        icon TEXT,
        enable_claude_code INTEGER DEFAULT 0,
        claude_code_api_endpoint TEXT,
        claude_code_model TEXT,
        claude_code_haiku_model TEXT,
        claude_code_sonnet_model TEXT,
        claude_code_opus_model TEXT,
        claude_code_base_url TEXT,
        enable_codex INTEGER DEFAULT 0,
        codex_api_endpoint TEXT,
        codex_model TEXT,
        codex_base_url TEXT,
        codex_config TEXT,
        enable_gemini INTEGER DEFAULT 0,
        gemini_api_endpoint TEXT,
        gemini_model TEXT,
        gemini_base_url TEXT,
        is_validated INTEGER DEFAULT 0
      )
    ''');

    // 创建索引
    await db.execute('CREATE INDEX idx_ai_keys_platform ON ai_keys(platform)');
    await db.execute('CREATE INDEX idx_ai_keys_expiry ON ai_keys(expiry_date)');
    await db.execute('CREATE INDEX idx_ai_keys_active ON ai_keys(is_active)');
    await db.execute('CREATE INDEX idx_ai_keys_favorite ON ai_keys(is_favorite)');
    await db.execute('CREATE INDEX idx_ai_keys_claude_code ON ai_keys(enable_claude_code)');
    await db.execute('CREATE INDEX idx_ai_keys_codex ON ai_keys(enable_codex)');
    await db.execute('CREATE INDEX idx_ai_keys_gemini ON ai_keys(enable_gemini)');

    // 创建 MCP 服务器表
    await db.execute('''
      CREATE TABLE mcp_servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        icon TEXT,
        server_type TEXT NOT NULL DEFAULT 'stdio',
        command TEXT,
        args TEXT,
        env TEXT,
        cwd TEXT,
        url TEXT,
        headers TEXT,
        tags TEXT,
        homepage TEXT,
        docs TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // 创建 MCP 服务器索引
    await db.execute('CREATE INDEX idx_mcp_servers_server_id ON mcp_servers(server_id)');
    await db.execute('CREATE INDEX idx_mcp_servers_active ON mcp_servers(is_active)');
    await db.execute('CREATE INDEX idx_mcp_servers_type ON mcp_servers(server_type)');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 添加 ClaudeCode 和 Codex 相关字段
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN enable_claude_code INTEGER DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_api_endpoint TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_haiku_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_sonnet_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_opus_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_base_url TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN enable_codex INTEGER DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN codex_api_endpoint TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN codex_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN codex_base_url TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN codex_config TEXT
      ''');
      
      // 创建新索引
      await db.execute('CREATE INDEX idx_ai_keys_claude_code ON ai_keys(enable_claude_code)');
      await db.execute('CREATE INDEX idx_ai_keys_codex ON ai_keys(enable_codex)');
    }
    
    if (oldVersion < 3) {
      // 添加新的模型字段
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_haiku_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_sonnet_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN claude_code_opus_model TEXT
      ''');
    }

    if (oldVersion < 4) {
      // 创建 MCP 服务器表
      await db.execute('''
        CREATE TABLE mcp_servers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          server_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          description TEXT,
          icon TEXT,
          server_type TEXT NOT NULL DEFAULT 'stdio',
          command TEXT,
          args TEXT,
          env TEXT,
          cwd TEXT,
          url TEXT,
          headers TEXT,
          enabled_tools TEXT,
          tags TEXT,
          homepage TEXT,
          docs TEXT,
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // 创建 MCP 服务器索引
      await db.execute('CREATE INDEX idx_mcp_servers_server_id ON mcp_servers(server_id)');
      await db.execute('CREATE INDEX idx_mcp_servers_active ON mcp_servers(is_active)');
      await db.execute('CREATE INDEX idx_mcp_servers_type ON mcp_servers(server_type)');
    }

    if (oldVersion < 5) {
      // 移除 enabled_tools 列（SQLite 不支持直接删除列，需要重建表）
      // 创建新表（不包含 enabled_tools）
      await db.execute('''
        CREATE TABLE mcp_servers_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          server_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          description TEXT,
          icon TEXT,
          server_type TEXT NOT NULL DEFAULT 'stdio',
          command TEXT,
          args TEXT,
          env TEXT,
          cwd TEXT,
          url TEXT,
          headers TEXT,
          tags TEXT,
          homepage TEXT,
          docs TEXT,
          is_active INTEGER DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // 迁移数据（排除 enabled_tools 列）
      await db.execute('''
        INSERT INTO mcp_servers_new (
          id, server_id, name, description, icon, server_type,
          command, args, env, cwd, url, headers,
          tags, homepage, docs, is_active, created_at, updated_at
        )
        SELECT 
          id, server_id, name, description, icon, server_type,
          command, args, env, cwd, url, headers,
          tags, homepage, docs, is_active, created_at, updated_at
        FROM mcp_servers
      ''');

      // 删除旧表
      await db.execute('DROP TABLE mcp_servers');

      // 重命名新表
      await db.execute('ALTER TABLE mcp_servers_new RENAME TO mcp_servers');

      // 重新创建索引
      await db.execute('CREATE INDEX idx_mcp_servers_server_id ON mcp_servers(server_id)');
      await db.execute('CREATE INDEX idx_mcp_servers_active ON mcp_servers(is_active)');
      await db.execute('CREATE INDEX idx_mcp_servers_type ON mcp_servers(server_type)');
    }

    if (oldVersion < 6) {
      // 添加 icon 字段到 ai_keys 表
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN icon TEXT
      ''');
    }

    if (oldVersion < 7) {
      // 添加 Gemini 相关字段
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN enable_gemini INTEGER DEFAULT 0
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN gemini_api_endpoint TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN gemini_model TEXT
      ''');
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN gemini_base_url TEXT
      ''');
      
      // 创建新索引
      await db.execute('CREATE INDEX idx_ai_keys_gemini ON ai_keys(enable_gemini)');
    }

    if (oldVersion < 8) {
      // 添加校验状态字段
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN is_validated INTEGER DEFAULT 0
      ''');
    }

    if (oldVersion < 9) {
      // 添加 platform_type_id 字段，用于存储平台ID（字符串）而不是索引
      await db.execute('''
        ALTER TABLE ai_keys ADD COLUMN platform_type_id TEXT
      ''');
    }
  }

  /// 插入密钥
  Future<int> insertKey(AIKey key) async {
    final db = await database;
    return await db.insert('ai_keys', key.toMap());
  }

  /// 批量插入密钥
  Future<List<int>> insertKeys(List<AIKey> keys) async {
    final db = await database;
    final batch = db.batch();

    for (final key in keys) {
      batch.insert('ai_keys', key.toMap());
    }

    final results = await batch.commit();
    return results.map((e) => e as int).toList();
  }

  /// 更新密钥
  Future<int> updateKey(AIKey key) async {
    final db = await database;
    return await db.update(
      'ai_keys',
      key.toMap(),
      where: 'id = ?',
      whereArgs: [key.id],
    );
  }

  /// 删除密钥
  Future<int> deleteKey(int id) async {
    final db = await database;
    return await db.delete(
      'ai_keys',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 安全删除密钥（先覆写再删除）
  Future<int> secureDeleteKey(int id) async {
    final db = await database;
    // 先用随机数据覆盖
    await db.update(
      'ai_keys',
      {'key_value': '0' * AppConstants.maxKeyValueLength},
      where: 'id = ?',
      whereArgs: [id],
    );
    // 再删除记录
    return await db.delete(
      'ai_keys',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 根据ID获取密钥
  /// 根据 name 和 platform 查找密钥（用于导入时检查是否已存在）
  Future<AIKey?> getKeyByNameAndPlatform(String name, String platform) async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'name = ? AND platform = ?',
      whereArgs: [name, platform],
    );
    if (maps.isNotEmpty) {
      return AIKey.fromMap(maps.first);
    }
    return null;
  }

  Future<AIKey?> getKeyById(int id) async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return AIKey.fromMap(maps.first);
    }
    return null;
  }

  /// 获取所有密钥
  Future<List<AIKey>> getAllKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      orderBy: 'is_favorite DESC, updated_at DESC', // 改为 DESC，新增密钥排在最前面
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取所有活跃密钥
  Future<List<AIKey>> getActiveKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'is_favorite DESC, updated_at DESC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取启用了 ClaudeCode 的密钥
  /// 注意：不限制激活状态，因为用户可能想要切换到未激活的密钥
  Future<List<AIKey>> getClaudeCodeKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'enable_claude_code = ?',
      whereArgs: [1],
      orderBy: 'is_favorite DESC, updated_at DESC', // 改为 DESC，新增密钥排在最前面
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取启用了 Codex 的密钥
  /// 注意：不限制激活状态，因为用户可能想要切换到未激活的密钥
  Future<List<AIKey>> getCodexKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'enable_codex = ?',
      whereArgs: [1],
      orderBy: 'is_favorite DESC, updated_at DESC', // 改为 DESC，新增密钥排在最前面
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取启用了 Gemini 的密钥列表
  Future<List<AIKey>> getGeminiKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'enable_gemini = ?',
      whereArgs: [1],
      orderBy: 'is_favorite DESC, updated_at DESC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 根据平台获取密钥
  Future<List<AIKey>> getKeysByPlatform(String platform) async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'platform = ?',
      whereArgs: [platform],
      orderBy: 'is_favorite DESC, updated_at DESC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 搜索密钥
  Future<List<AIKey>> searchKeys(String query) async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'name LIKE ? OR platform LIKE ? OR notes LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'is_favorite DESC, updated_at DESC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取收藏的密钥
  Future<List<AIKey>> getFavoriteKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'is_favorite = ?',
      whereArgs: [1],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取即将过期的密钥
  Future<List<AIKey>> getExpiringKeys(int daysAhead) async {
    final db = await database;
    final now = DateTime.now();
    final cutoff = now.add(Duration(days: daysAhead));

    final maps = await db.query(
      'ai_keys',
      where: 'expiry_date IS NOT NULL AND expiry_date <= ? AND expiry_date >= ?',
      whereArgs: [cutoff.toIso8601String(), now.toIso8601String()],
      orderBy: 'expiry_date ASC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 获取已过期的密钥
  Future<List<AIKey>> getExpiredKeys() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final maps = await db.query(
      'ai_keys',
      where: 'expiry_date IS NOT NULL AND expiry_date < ?',
      whereArgs: [now],
      orderBy: 'expiry_date ASC',
    );
    return maps.map((map) => AIKey.fromMap(map)).toList();
  }

  /// 更新最后使用时间
  Future<void> updateLastUsed(int id) async {
    final db = await database;
    await db.update(
      'ai_keys',
      {'last_used_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 切换收藏状态
  Future<int> toggleFavorite(int id, bool isFavorite) async {
    final db = await database;
    return await db.update(
      'ai_keys',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 切换活跃状态
  Future<int> toggleActive(int id, bool isActive) async {
    final db = await database;
    return await db.update(
      'ai_keys',
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取统计数据
  Future<KeyStatistics> getStatistics() async {
    final db = await database;

    // 总数
    final totalMaps = await db.rawQuery('SELECT COUNT(*) as count FROM ai_keys');
    final total = totalMaps.first['count'] as int;

    // 活跃数
    final activeMaps = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ai_keys WHERE is_active = 1',
    );
    final active = activeMaps.first['count'] as int;

    // 即将过期
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 7));
    final expiringMaps = await db.rawQuery(
      '''SELECT COUNT(*) as count FROM ai_keys
         WHERE expiry_date IS NOT NULL
         AND expiry_date <= "${cutoff.toIso8601String()}"
         AND expiry_date >= "${now.toIso8601String()}"''',
    );
    final expiring = expiringMaps.first['count'] as int;

    // 已过期
    final expiredMaps = await db.rawQuery(
      '''SELECT COUNT(*) as count FROM ai_keys
         WHERE expiry_date IS NOT NULL
         AND expiry_date < "${now.toIso8601String()}"''',
    );
    final expired = expiredMaps.first['count'] as int;

    // 收藏数
    final favoriteMaps = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ai_keys WHERE is_favorite = 1',
    );
    final favorites = favoriteMaps.first['count'] as int;

    return KeyStatistics(
      total: total,
      active: active,
      inactive: total - active,
      expiringSoon: expiring,
      expired: expired,
      favorites: favorites,
    );
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// 清除所有数据（删除数据库文件）
  /// 注意：这会删除所有密钥数据，请谨慎使用
  Future<void> clearAllData() async {
    // 关闭数据库连接
    await close();
    
    // 删除数据库文件
    final directory = await getApplicationDocumentsDirectory();
    final dbPath = join(directory.path, AppConstants.databaseName);
    final dbFile = File(dbPath);
    
    if (await dbFile.exists()) {
      await dbFile.delete();
      print('数据库文件已删除: $dbPath');
    }
    
    // 重置静态变量
    _database = null;
    _isFfiInitialized = false;
  }
}

/// 密钥统计数据
class KeyStatistics {
  final int total;
  final int active;
  final int inactive;
  final int expiringSoon;
  final int expired;
  final int favorites;

  const KeyStatistics({
    required this.total,
    required this.active,
    required this.inactive,
    required this.expiringSoon,
    required this.expired,
    required this.favorites,
  });

  @override
  String toString() {
    return 'KeyStatistics(total: $total, active: $active, inactive: $inactive, expiringSoon: $expiringSoon, expired: $expired, favorites: $favorites)';
  }
}
