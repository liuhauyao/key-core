import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
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

  /// 当前数据库结构版本。
  ///
  /// - v15：PR #5 之前的 main。
  /// - v16：PR #5「供应商中心」新增 `providers` 表（已回退）。
  /// - v17：把 `providers` 表中保存过的 API Key 导入 `ai_keys` 后删除该表，
  ///   回到以密钥为唯一实体的设计。版本号只增不减，避免 v16 的数据库被静默降级。
  /// - v18：`ai_keys.claude_code_config`（Claude Code 的密钥字段名与供应商专属 env）。
  /// - v19：`mcp_server_apps`（MCP 服务按工具启用的关系表）。
  /// - v20：`skills` 增加来源仓库与内容哈希（source_repo/source_ref/source_subdir/content_hash）。
  /// - v21：新增 `prompts` 表（系统提示词，CC Switch Prompts 对齐）。
  static const int schemaVersion = 21;

  static const String promptsDdl = '''
    CREATE TABLE IF NOT EXISTS prompts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tool TEXT NOT NULL,
      name TEXT NOT NULL,
      content TEXT NOT NULL DEFAULT '',
      description TEXT,
      enabled INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  /// MCP 服务 × 工具 启用关系（主键 server_id + tool；删除服务时一并删除）
  static const String mcpServerAppsDdl = '''
    CREATE TABLE IF NOT EXISTS mcp_server_apps (
      server_id TEXT NOT NULL,
      tool TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (server_id, tool)
    )
  ''';

  /// 迁移前备份最多保留的份数
  static const int maxMigrationBackups = 5;

  /// 仅供测试：数据库路径（如 `inMemoryDatabasePath`）。设置后需调用 [close] 重新打开
  @visibleForTesting
  static String? debugDatabasePathOverride;

  /// 仅供测试：在给定数据库上执行建表逻辑
  @visibleForTesting
  Future<void> runCreateForTest(Database db, int version) => _onCreate(db, version);

  /// 仅供测试：在给定数据库上执行升级迁移
  @visibleForTesting
  Future<void> runUpgradeForTest(Database db, int oldVersion, int newVersion) =>
      _onUpgrade(db, oldVersion, newVersion);

  /// 仅供测试：执行降级保护逻辑
  @visibleForTesting
  Future<void> runDowngradeForTest(Database db, int oldVersion, int newVersion) =>
      _onDowngrade(db, oldVersion, newVersion);

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

    final override = debugDatabasePathOverride;
    if (override != null) {
      return await databaseFactoryFfi.openDatabase(
        override,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          singleInstance: false,
        ),
      );
    }

    final directory = await getApplicationDocumentsDirectory();
    final path = join(directory.path, AppConstants.databaseName);

    // 升级前先备份数据库文件，迁移出错时可手动恢复
    await backupBeforeMigrationIfNeeded(path, schemaVersion);

    return await openDatabase(
      path,
      version: schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: _onDowngrade,
    );
  }

  /// 数据库来自更新版本的应用时拒绝打开，避免 sqflite 静默把 user_version 改小
  /// （之后再升级时会重复执行已执行过的迁移）。
  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) async {
    throw DatabaseVersionTooNewException(oldVersion, newVersion);
  }

  /// 若数据库文件存在且版本低于 [targetVersion]，在迁移前复制一份备份。
  ///
  /// 备份位于数据库同目录的 `backups/` 下：
  /// `key_core.db.pre-v<target>.<时间戳>`，最多保留 [maxMigrationBackups] 份。
  /// 返回备份文件路径（未备份时返回 null）。备份失败不阻断启动。
  @visibleForTesting
  static Future<String?> backupBeforeMigrationIfNeeded(String dbPath, int targetVersion) async {
    try {
      final file = File(dbPath);
      if (!file.existsSync()) return null;

      final probe = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      int currentVersion;
      try {
        currentVersion = await probe.getVersion();
      } finally {
        await probe.close();
      }
      if (currentVersion <= 0 || currentVersion >= targetVersion) return null;

      final backupDir = Directory(join(dirname(dbPath), 'backups'));
      await backupDir.create(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final prefix = '${basename(dbPath)}.pre-v$targetVersion.';
      final backupPath = join(backupDir.path, '$prefix$stamp');
      await file.copy(backupPath);

      // 只保留最近的若干份（文件名带时间戳，可按名称排序）
      final backups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => basename(f.path).startsWith('${basename(dbPath)}.pre-v'))
          .toList()
        ..sort((a, b) => basename(b.path).compareTo(basename(a.path)));
      for (final old in backups.skip(maxMigrationBackups)) {
        try {
          await old.delete();
        } catch (_) {}
      }
      return backupPath;
    } catch (e) {
      debugPrint('数据库迁移前备份失败（不影响启动）: $e');
      return null;
    }
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
        claude_code_config TEXT,
        enable_gemini INTEGER DEFAULT 0,
        gemini_api_endpoint TEXT,
        gemini_model TEXT,
        gemini_base_url TEXT,
        enable_openclaw INTEGER DEFAULT 0,
        openclaw_base_url TEXT,
        openclaw_model TEXT,
        enable_claude_desktop INTEGER DEFAULT 0,
        claude_desktop_base_url TEXT,
        claude_desktop_model TEXT,
        claude_desktop_sonnet_model TEXT,
        claude_desktop_haiku_model TEXT,
        claude_desktop_opus_model TEXT,
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
    await db.execute(mcpServerAppsDdl);
    await db.execute(promptsDdl);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_prompts_tool ON prompts(tool)');

    await _createSkillsTable(db);
  }

  Future<void> _createSkillsTable(Database db) async {
    await db.execute('''
      CREATE TABLE skills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        skill_id TEXT NOT NULL UNIQUE,
        relative_path TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        enabled_tools TEXT,
        sync_status TEXT,
        tags TEXT,
        notes TEXT,
        sort_order INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        source_tool TEXT,
        source_repo TEXT,
        source_ref TEXT,
        source_subdir TEXT,
        content_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_skills_skill_id ON skills(skill_id)');
    await db.execute('CREATE INDEX idx_skills_relative_path ON skills(relative_path)');
    await db.execute('CREATE INDEX idx_skills_active ON skills(is_active)');
  }

  /// 检查表中是否存在指定列
  Future<bool> _columnExists(Database db, String tableName, String columnName) async {
    try {
      final result = await db.rawQuery(
        "PRAGMA table_info($tableName)",
      );
      return result.any((row) => row['name'] == columnName);
    } catch (e) {
      return false;
    }
  }

  /// 安全地添加列（如果列不存在）
  Future<void> _addColumnIfNotExists(
    Database db,
    String tableName,
    String columnName,
    String columnDefinition,
  ) async {
    final exists = await _columnExists(db, tableName, columnName);
    if (!exists) {
      await db.execute('''
        ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition
      ''');
    }
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 添加 ClaudeCode 和 Codex 相关字段
      await _addColumnIfNotExists(db, 'ai_keys', 'enable_claude_code', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_api_endpoint', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_haiku_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_sonnet_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_opus_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_base_url', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'enable_codex', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'ai_keys', 'codex_api_endpoint', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'codex_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'codex_base_url', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'codex_config', 'TEXT');
      
      // 创建新索引（如果不存在）
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_keys_claude_code ON ai_keys(enable_claude_code)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_keys_codex ON ai_keys(enable_codex)');
      } catch (e) {
        // 索引可能已存在，忽略错误
      }
    }
    
    if (oldVersion < 3) {
      // 添加新的模型字段
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_haiku_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_sonnet_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_opus_model', 'TEXT');
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
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mcp_servers_server_id ON mcp_servers(server_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mcp_servers_active ON mcp_servers(is_active)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mcp_servers_type ON mcp_servers(server_type)');
      } catch (e) {
        // 索引可能已存在，忽略错误
      }
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
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mcp_servers_server_id ON mcp_servers(server_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mcp_servers_active ON mcp_servers(is_active)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_mcp_servers_type ON mcp_servers(server_type)');
      } catch (e) {
        // 索引可能已存在，忽略错误
      }
    }

    if (oldVersion < 6) {
      // 添加 icon 字段到 ai_keys 表
      await _addColumnIfNotExists(db, 'ai_keys', 'icon', 'TEXT');
    }

    if (oldVersion < 7) {
      // 添加 Gemini 相关字段
      await _addColumnIfNotExists(db, 'ai_keys', 'enable_gemini', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'ai_keys', 'gemini_api_endpoint', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'gemini_model', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'gemini_base_url', 'TEXT');
      
      // 创建新索引（如果不存在）
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ai_keys_gemini ON ai_keys(enable_gemini)');
      } catch (e) {
        // 索引可能已存在，忽略错误
      }
    }

    if (oldVersion < 8) {
      // 添加校验状态字段
      await _addColumnIfNotExists(db, 'ai_keys', 'is_validated', 'INTEGER DEFAULT 0');
    }

    if (oldVersion < 9) {
      // 添加 platform_type_id 字段，用于存储平台ID（字符串）而不是索引
      await _addColumnIfNotExists(db, 'ai_keys', 'platform_type_id', 'TEXT');
    }

    if (oldVersion < 10) {
      // 添加 OpenClaw 模型字段
      await _addColumnIfNotExists(db, 'ai_keys', 'openclaw_model', 'TEXT');
    }

    if (oldVersion < 11) {
      // 添加 OpenClaw 启用字段
      await _addColumnIfNotExists(db, 'ai_keys', 'enable_openclaw', 'INTEGER DEFAULT 0');
    }

    if (oldVersion < 12) {
      // 添加 OpenClaw 请求地址字段
      await _addColumnIfNotExists(db, 'ai_keys', 'openclaw_base_url', 'TEXT');
    }

    if (oldVersion < 13) {
      await _createSkillsTable(db);
    }

    if (oldVersion < 14) {
      // 添加 Claude Desktop 相关字段
      await _addColumnIfNotExists(db, 'ai_keys', 'enable_claude_desktop', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_base_url', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_model', 'TEXT');
    }

    // Claude Desktop 模型映射列（每次升级都尝试添加，_addColumnIfNotExists 内部会检查是否存在）
    await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_sonnet_model', 'TEXT');
    await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_haiku_model', 'TEXT');
    await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_opus_model', 'TEXT');

    if (oldVersion < 17) {
      // 曾运行过 PR #5 早期分支构建的数据库（当时在 v14 建 providers 表、
      // 未执行 main 的 v14 迁移），幂等补齐 Claude Desktop 列。
      await _addColumnIfNotExists(db, 'ai_keys', 'enable_claude_desktop', 'INTEGER DEFAULT 0');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_base_url', 'TEXT');
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_desktop_model', 'TEXT');

      // 回退 PR #5 的「供应商中心」：保存过 API Key 的供应商导入为密钥，然后删除 providers 表。
      await _migrateProviderCenterToAiKeys(db);
    }

    if (oldVersion < 18) {
      await _addColumnIfNotExists(db, 'ai_keys', 'claude_code_config', 'TEXT');
    }
    if (oldVersion < 19) {
      await db.execute(mcpServerAppsDdl);
    }
    if (oldVersion < 20) {
      // 早期 PR #5 分支的 v14 数据库没有 skills 表（main 在 v13 才创建），这里补建
      final hasSkills = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='skills'",
      );
      if (hasSkills.isEmpty) {
        await _createSkillsTable(db);
      }
      for (final col in ['source_repo', 'source_ref', 'source_subdir', 'content_hash']) {
        await _addColumnIfNotExists(db, 'skills', col, 'TEXT');
      }
    }
    if (oldVersion < 21) {
      await db.execute(promptsDdl);
      await db.execute('CREATE INDEX IF NOT EXISTS idx_prompts_tool ON prompts(tool)');
    }
  }

  /// v17：把 PR #5 `providers` 表中保存过 API Key 的行导入 `ai_keys`，然后删除该表。
  ///
  /// - `api_key_encrypted` 与 `ai_keys.key_value` 使用同一 CryptService、同一加密密钥、
  ///   同一 `{"data","iv"}` 格式，原样复制即可；未设置主密码时两边都是明文，
  ///   之后设置主密码时由 `reEncryptAllPlaintextKeys` 统一加密。
  /// - 没有 API Key 的行（PR #5 启动时自动播种的预设）直接丢弃。
  /// - 不打开任何工具开关：`supported_tools` 是预设声明的“能力”而非用户的启用状态，
  ///   原样映射会把密钥放进不匹配的工具列表；原信息写入备注，由用户在表单中按需启用。
  /// - 以 (name, api_endpoint) 或相同 key_value 去重，重复执行安全。
  Future<int> _migrateProviderCenterToAiKeys(Database db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='providers'",
    );
    if (tables.isEmpty) return 0;

    var imported = 0;
    final rows = await db.query('providers');
    for (final row in rows) {
      final keyValue = (row['api_key_encrypted'] as String?)?.trim();
      if (keyValue == null || keyValue.isEmpty) continue;

      final name = ((row['name_zh'] as String?)?.trim().isNotEmpty ?? false)
          ? (row['name_zh'] as String).trim()
          : ((row['name'] as String?)?.trim().isNotEmpty ?? false)
              ? (row['name'] as String).trim()
              : (row['id']?.toString() ?? 'Provider');
      final endpoint = (row['api_endpoint'] as String?)?.trim();

      final duplicates = await db.query(
        'ai_keys',
        columns: ['id'],
        where: endpoint == null || endpoint.isEmpty
            ? 'key_value = ? OR (name = ? AND (api_endpoint IS NULL OR api_endpoint = \'\'))'
            : 'key_value = ? OR (name = ? AND api_endpoint = ?)',
        whereArgs: endpoint == null || endpoint.isEmpty
            ? [keyValue, name]
            : [keyValue, name, endpoint],
        limit: 1,
      );
      if (duplicates.isNotEmpty) continue;

      final createdAt = _millisToIso(row['created_at']);
      final updatedAt = _millisToIso(row['updated_at']) ?? createdAt;
      final now = DateTime.now().toIso8601String();

      await db.insert('ai_keys', {
        'name': name,
        'platform': PlatformType.custom.value,
        'platform_type': PlatformType.custom.index,
        'platform_type_id': PlatformType.custom.id,
        'management_url': _firstNonEmpty([row['api_key_url'], row['website_url']]),
        'api_endpoint': endpoint == null || endpoint.isEmpty ? null : endpoint,
        'key_value': keyValue,
        'notes': _describeLegacyProvider(row),
        'is_active': (row['is_active'] as int? ?? 1) == 1 ? 1 : 0,
        'created_at': createdAt ?? now,
        'updated_at': updatedAt ?? now,
      });
      imported++;
    }

    await db.execute('DROP INDEX IF EXISTS idx_providers_type');
    await db.execute('DROP INDEX IF EXISTS idx_providers_active');
    await db.execute('DROP INDEX IF EXISTS idx_providers_region');
    await db.execute('DROP TABLE IF EXISTS providers');
    debugPrint('v17 迁移：从供应商中心导入 $imported 个密钥，已删除 providers 表');
    return imported;
  }

  static String? _millisToIso(Object? value) {
    final ms = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static List<String> _decodeStringList(Object? raw, {String? field}) {
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is! List) return const [];
      return decoded
          .map((e) => field != null && e is Map ? e[field]?.toString() : e?.toString())
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _describeLegacyProvider(Map<String, Object?> row) {
    final lines = <String>['从「供应商中心」(PR #5) 迁移'];
    final tools = _decodeStringList(row['supported_tools']);
    if (tools.isNotEmpty) lines.add('原支持工具：${tools.join(', ')}');
    final models = _decodeStringList(row['models'], field: 'id');
    if (models.isNotEmpty) lines.add('原模型：${models.join(', ')}');
    final description = (row['description'] as String?)?.trim();
    if (description != null && description.isNotEmpty) lines.add(description);
    return lines.join('\n');
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

  /// 获取启用了 Claude Desktop 的密钥列表
  Future<List<AIKey>> getClaudeDesktopKeys() async {
    final db = await database;
    final maps = await db.query(
      'ai_keys',
      where: 'enable_claude_desktop = ?',
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
         AND expiry_date <= ?
         AND expiry_date >= ?''',
      [cutoff.toIso8601String(), now.toIso8601String()],
    );
    final expiring = expiringMaps.first['count'] as int;

    // 已过期
    final expiredMaps = await db.rawQuery(
      '''SELECT COUNT(*) as count FROM ai_keys
         WHERE expiry_date IS NOT NULL
         AND expiry_date < ?''',
      [now.toIso8601String()],
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

/// 数据库由更新版本的应用创建，当前版本无法安全打开
class DatabaseVersionTooNewException implements Exception {
  final int databaseVersion;
  final int supportedVersion;

  DatabaseVersionTooNewException(this.databaseVersion, this.supportedVersion);

  @override
  String toString() =>
      '数据库版本 v$databaseVersion 高于当前应用支持的 v$supportedVersion，请升级 Key Core 后再打开';
}
