// getStatistics：日期比较必须用绑定参数（原先用双引号字面量，在关闭 DQS 的 SQLite 上报 no such column）
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('即将过期 / 已过期 计数正确，且不依赖双引号字符串', () async {
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    final service = DatabaseService.instance;
    await service.close();
    final db = await service.database;
    final now = DateTime.now();
    String iso(Duration d) => now.add(d).toIso8601String();
    Future<void> ins(String name, String? exp) => db.rawInsert(
        'INSERT INTO ai_keys (name, platform, platform_type, key_value, created_at, updated_at, expiry_date) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [name, 'custom', 'custom', 'x', now.toIso8601String(), now.toIso8601String(), exp]);
    await ins('soon', iso(const Duration(days: 3)));
    await ins('late', iso(const Duration(days: 30)));
    await ins('gone', iso(const Duration(days: -1)));
    await ins('none', null);
    final s = await service.getStatistics();
    expect(s.total, 4);
    expect(s.expiringSoon, 1);
    expect(s.expired, 1);
    await service.close();
    DatabaseService.debugDatabasePathOverride = null;
  });
}
