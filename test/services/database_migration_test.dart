import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/crypt_service.dart';
import 'package:key_core/services/database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// PR #5（v16）创建 providers 表时使用的 DDL，原样保留用于构造 v16 数据库。
const _v16ProvidersDdl = '''
  CREATE TABLE IF NOT EXISTS providers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_zh TEXT,
    provider_type TEXT NOT NULL,
    api_endpoint TEXT,
    api_key_encrypted TEXT,
    api_key_nonce TEXT,
    models TEXT,
    supported_tools TEXT,
    region TEXT,
    plan_type TEXT,
    icon_url TEXT,
    website_url TEXT,
    api_key_url TEXT,
    is_active INTEGER DEFAULT 1,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    description TEXT,
    is_sponsored INTEGER DEFAULT 0,
    family TEXT
  )
''';

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Set<String>> _indexes(Database db) async {
  final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index'");
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Database> _memoryDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );

/// 构造一个 v16（PR #5）数据库：v15 结构 + providers 表及索引。
Future<Database> _v16Db(DatabaseService service) async {
  final db = await _memoryDb();
  await service.runCreateForTest(db, 15);
  await db.execute(_v16ProvidersDdl);
  await db.execute('CREATE INDEX IF NOT EXISTS idx_providers_type ON providers(provider_type)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_providers_active ON providers(is_active)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_providers_region ON providers(region)');
  return db;
}

Map<String, Object?> _providerRow(
  String id, {
  String name = 'Provider',
  String? nameZh,
  String? endpoint,
  String? key,
  List<String> tools = const ['claude_code'],
  List<String> models = const [],
  int isActive = 1,
}) =>
    {
      'id': id,
      'name': name,
      'name_zh': nameZh,
      'provider_type': 'custom',
      'api_endpoint': endpoint,
      'api_key_encrypted': key,
      'api_key_nonce': key == null ? null : '',
      'models': jsonEncode(models.map((m) => {'id': m}).toList()),
      'supported_tools': jsonEncode(tools),
      'website_url': 'https://example.com',
      'api_key_url': 'https://example.com/keys',
      'is_active': isActive,
      'created_at': DateTime(2026, 10, 9, 14).millisecondsSinceEpoch,
      'updated_at': DateTime(2026, 10, 9, 15).millisecondsSinceEpoch,
    };

Map<String, Object?> _aiKeyRow(String name, String keyValue, {String? endpoint}) => {
      'name': name,
      'platform': 'Custom',
      'platform_type': PlatformType.custom.index,
      'platform_type_id': 'custom',
      'api_endpoint': endpoint,
      'key_value': keyValue,
      'created_at': DateTime(2026).toIso8601String(),
      'updated_at': DateTime(2026).toIso8601String(),
    };

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final service = DatabaseService.instance;

  test('schema version is 17', () {
    expect(DatabaseService.schemaVersion, 17);
  });

  test('fresh install (v17) has no providers table and has all ai_keys columns', () async {
    final db = await _memoryDb();
    await service.runCreateForTest(db, DatabaseService.schemaVersion);
    final tables = await _tables(db);
    expect(tables, containsAll(['ai_keys', 'mcp_servers', 'skills']));
    expect(tables, isNot(contains('providers')));
    expect(
      await _columns(db, 'ai_keys'),
      containsAll(['enable_claude_desktop', 'claude_desktop_opus_model', 'enable_openclaw']),
    );
    await db.close();
  });

  test('upgrade from main v15 keeps existing keys and creates nothing new', () async {
    final db = await _memoryDb();
    await service.runCreateForTest(db, 15);
    await db.insert('ai_keys', _aiKeyRow('Existing', 'sk-existing'));

    await service.runUpgradeForTest(db, 15, DatabaseService.schemaVersion);

    expect(await _tables(db), isNot(contains('providers')));
    final keys = await db.query('ai_keys');
    expect(keys, hasLength(1));
    expect(keys.single['key_value'], 'sk-existing');
    await db.close();
  });

  test('upgrade from v16 imports saved provider keys into ai_keys and drops providers', () async {
    final db = await _v16Db(service);
    final crypt = CryptService();
    final encryptionKey = await crypt.generateEncryptionKey('test-master-password');
    final encrypted = await crypt.encrypt('sk-encrypted-secret', encryptionKey);

    await db.insert(
      'providers',
      _providerRow('enc', name: 'DeepSeek', nameZh: '深度求索', endpoint: 'https://api.deepseek.com',
          key: encrypted, tools: ['claude_code', 'codex'], models: ['deepseek-chat']),
    );
    await db.insert(
      'providers',
      _providerRow('plain', name: 'Relay', endpoint: 'https://relay.example.com', key: 'sk-plain', isActive: 0),
    );
    // PR #5 启动时自动播种的预设：没有 Key，应被丢弃
    await db.insert('providers', _providerRow('preset', name: 'OpenAI Official', endpoint: 'https://api.openai.com/v1'));
    await db.insert('providers', _providerRow('blank', name: 'Blank', key: '   '));

    await service.runUpgradeForTest(db, 16, DatabaseService.schemaVersion);

    expect(await _tables(db), isNot(contains('providers')));
    expect(await _indexes(db), isNot(anyElement(startsWith('idx_providers_'))));

    final rows = await db.query('ai_keys', orderBy: 'id');
    expect(rows, hasLength(2));

    final enc = rows.firstWhere((r) => r['api_endpoint'] == 'https://api.deepseek.com');
    expect(enc['name'], '深度求索');
    expect(enc['key_value'], encrypted, reason: '密文原样复制，格式与 ai_keys 相同');
    expect(await crypt.decrypt(enc['key_value'] as String, encryptionKey), 'sk-encrypted-secret');
    expect(enc['platform_type_id'], 'custom');
    expect(enc['management_url'], 'https://example.com/keys');
    expect(enc['is_active'], 1);
    expect(enc['notes'] as String, contains('claude_code, codex'));
    expect(enc['notes'] as String, contains('deepseek-chat'));
    for (final flag in [
      'enable_claude_code',
      'enable_codex',
      'enable_gemini',
      'enable_openclaw',
      'enable_claude_desktop',
    ]) {
      expect(enc[flag], 0, reason: '迁移不自动启用任何工具：$flag');
    }

    final plain = rows.firstWhere((r) => r['name'] == 'Relay');
    expect(plain['key_value'], 'sk-plain');
    expect(plain['is_active'], 0);

    // 迁移后的行能被 AIKey 正常读取
    final key = AIKey.fromMap(enc);
    expect(key.name, '深度求索');
    expect(key.apiEndpoint, 'https://api.deepseek.com');
    expect(key.enableClaudeCode, isFalse);
    expect(key.createdAt, DateTime(2026, 10, 9, 14));
    await db.close();
  });

  test('v16 import skips keys that already exist in ai_keys', () async {
    final db = await _v16Db(service);
    await db.insert('ai_keys', _aiKeyRow('Relay', 'sk-other', endpoint: 'https://relay.example.com'));
    await db.insert('ai_keys', _aiKeyRow('Same value', 'sk-same'));
    await db.insert('providers', _providerRow('a', name: 'Relay', endpoint: 'https://relay.example.com', key: 'sk-a'));
    await db.insert('providers', _providerRow('b', name: 'Different name', key: 'sk-same'));
    await db.insert('providers', _providerRow('c', name: 'New', endpoint: 'https://new.example.com', key: 'sk-new'));

    await service.runUpgradeForTest(db, 16, DatabaseService.schemaVersion);

    final names = (await db.query('ai_keys')).map((r) => r['name']).toList();
    expect(names, unorderedEquals(['Relay', 'Same value', 'New']));
    await db.close();
  });

  test('running the v17 migration twice is safe', () async {
    final db = await _v16Db(service);
    await db.insert('providers', _providerRow('x', name: 'X', key: 'sk-x'));
    await service.runUpgradeForTest(db, 16, DatabaseService.schemaVersion);
    await service.runUpgradeForTest(db, 16, DatabaseService.schemaVersion);
    expect(await db.query('ai_keys'), hasLength(1));
    await db.close();
  });

  test('upgrade from early PR #5 branch v14 (providers, no claude desktop columns) is safe', () async {
    final db = await _memoryDb();
    await db.execute('''
      CREATE TABLE ai_keys (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, platform TEXT NOT NULL, platform_type INTEGER NOT NULL,
        platform_type_id TEXT, management_url TEXT, api_endpoint TEXT,
        key_value TEXT NOT NULL, key_nonce TEXT, expiry_date TEXT, tags TEXT, notes TEXT,
        is_active INTEGER DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(_v16ProvidersDdl);
    await db.insert('providers', _providerRow('early', name: 'Early', key: 'sk-early'));

    await service.runUpgradeForTest(db, 14, DatabaseService.schemaVersion);

    expect(
      await _columns(db, 'ai_keys'),
      containsAll([
        'enable_claude_desktop',
        'claude_desktop_base_url',
        'claude_desktop_model',
        'claude_desktop_sonnet_model',
        'claude_desktop_haiku_model',
        'claude_desktop_opus_model',
      ]),
    );
    expect(await _tables(db), isNot(contains('providers')));
    final rows = await db.query('ai_keys');
    expect(rows.single['key_value'], 'sk-early');
    await db.close();
  });

  test('opening a database from a newer app version is refused (no silent downgrade)', () async {
    final db = await _memoryDb();
    await expectLater(
      service.runDowngradeForTest(db, 18, DatabaseService.schemaVersion),
      throwsA(isA<DatabaseVersionTooNewException>()),
    );
    await db.close();
  });

  test('real open with onDowngrade keeps user_version untouched', () async {
    final dir = await Directory.systemTemp.createTemp('kc_db_');
    addTearDown(() => dir.delete(recursive: true));
    final path = p.join(dir.path, 'key_core.db');
    final newer = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(version: 18, onCreate: (db, v) async {}));
    await newer.close();

    await expectLater(
      databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DatabaseService.schemaVersion,
          onDowngrade: (db, o, n) => service.runDowngradeForTest(db, o, n),
        ),
      ),
      throwsA(anything),
    );

    final check = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    expect(await check.getVersion(), 18);
    await check.close();
  });

  group('backupBeforeMigrationIfNeeded', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kc_backup_');
      path = p.join(dir.path, 'key_core.db');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> createDbAtVersion(int version) async {
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(version: version, onCreate: (db, v) async {
        await db.execute('CREATE TABLE t (x INTEGER)');
      }));
      await db.close();
    }

    test('backs up an older database before migrating', () async {
      await createDbAtVersion(16);
      final backup = await DatabaseService.backupBeforeMigrationIfNeeded(path, 17);
      expect(backup, isNotNull);
      expect(File(backup!).existsSync(), isTrue);
      expect(p.basename(backup), startsWith('key_core.db.pre-v17.'));
      expect(p.dirname(backup), p.join(dir.path, 'backups'));
    });

    test('does nothing for missing, current or newer databases', () async {
      expect(await DatabaseService.backupBeforeMigrationIfNeeded(path, 17), isNull);
      await createDbAtVersion(17);
      expect(await DatabaseService.backupBeforeMigrationIfNeeded(path, 17), isNull);
      expect(Directory(p.join(dir.path, 'backups')).existsSync(), isFalse);
    });

    test('keeps at most maxMigrationBackups backups', () async {
      await createDbAtVersion(15);
      for (var i = 0; i < DatabaseService.maxMigrationBackups + 2; i++) {
        await DatabaseService.backupBeforeMigrationIfNeeded(path, 17);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final backups = Directory(p.join(dir.path, 'backups')).listSync();
      expect(backups, hasLength(DatabaseService.maxMigrationBackups));
    });
  });
}
