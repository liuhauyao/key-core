import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Set<String>> _tables(Database db) async {
  final rows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Database> _memoryDb() =>
    databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));

void main() {
  sqfliteFfiInit();
  final service = DatabaseService.instance;

  test('fresh install creates providers table and claude desktop columns', () async {
    final db = await _memoryDb();
    await service.runCreateForTest(db, 16);
    expect(await _tables(db), containsAll(['ai_keys', 'mcp_servers', 'skills', 'providers']));
    expect(await _columns(db, 'ai_keys'), contains('claude_desktop_opus_model'));
    await db.close();
  });

  test('upgrade from main v15 (no providers table) creates providers table', () async {
    final db = await _memoryDb();
    await service.runCreateForTest(db, 16);
    await db.execute('DROP TABLE providers');
    expect(await _tables(db), isNot(contains('providers')));

    await service.runUpgradeForTest(db, 15, 16);

    expect(await _tables(db), contains('providers'));
    await db.insert('providers', {
      'id': 'p1',
      'name': 'Test',
      'provider_type': 'custom',
      'created_at': 1,
      'updated_at': 1,
    });
    expect(await db.query('providers'), hasLength(1));
    await db.close();
  });

  test('upgrade from early branch v14 (providers exists, no claude desktop columns) is safe', () async {
    final db = await _memoryDb();
    await db.execute('CREATE TABLE ai_keys (id INTEGER PRIMARY KEY, name TEXT)');
    // 早期分支构建在 v14 用完整的 providers 结构建表
    final scratch = await _memoryDb();
    await service.runCreateForTest(scratch, 16);
    final ddl = await scratch.rawQuery(
        "SELECT sql FROM sqlite_master WHERE tbl_name='providers' AND sql IS NOT NULL");
    await scratch.close();
    for (final row in ddl) {
      await db.execute(row['sql'] as String);
    }
    await db.insert('providers', {
      'id': 'keep', 'name': 'Keep', 'provider_type': 'custom', 'created_at': 1, 'updated_at': 1,
    });

    await service.runUpgradeForTest(db, 14, 16);

    final cols = await _columns(db, 'ai_keys');
    expect(cols, containsAll([
      'enable_claude_desktop',
      'claude_desktop_base_url',
      'claude_desktop_model',
      'claude_desktop_sonnet_model',
    ]));
    expect(await db.query('providers'), hasLength(1));
    await db.close();
  });
}
