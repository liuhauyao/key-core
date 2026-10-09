import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/skill.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/skills/skills_market_service.dart';
import 'package:key_core/services/skills_database_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  setUp(() async {
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    await DatabaseService.instance.close();
  });
  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.debugDatabasePathOverride = null;
  });

  Skill skill(String id) => Skill(
        skillId: id,
        relativePath: id,
        name: id,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  test('新装的 Skill 排在末尾；调整顺序不改 updated_at', () async {
    final db = SkillsDatabaseService();
    for (final id in ['a', 'b', 'c']) {
      await db.addSkill(skill(id));
    }
    var all = await db.getAllSkills();
    expect(all.map((s) => s.skillId), ['a', 'b', 'c']);
    expect(all.map((s) => s.sortOrder), [0, 1, 2]);

    await db.updateSortOrders([all[2], all[0], all[1]]);
    await db.addSkill(skill('d'));
    all = await db.getAllSkills();
    expect(all.map((s) => s.skillId), ['c', 'a', 'b', 'd']);
    expect(all.every((s) => s.updatedAt == DateTime(2026)), isTrue);
  });

  test('清理遗留临时目录：只删本应用前缀且足够旧的目录', () async {
    final root = Directory.systemTemp.createTempSync('kc_tmp_root_');
    addTearDown(() => root.deleteSync(recursive: true));
    final old = Directory(p.join(root.path, '${SkillsMarketService.repoTempPrefix}old'))..createSync();
    final fresh = Directory(p.join(root.path, '${SkillsMarketService.zipTempPrefix}fresh'))..createSync();
    final other = Directory(p.join(root.path, 'someone-else'))..createSync();
    for (final d in [old, other]) {
      Process.runSync('touch', ['-d', '2 days ago', d.path]);
    }

    final n = await SkillsMarketService.cleanupStaleTempDirs(tempRoot: root, force: true);
    expect(n, 1);
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  }, skip: Platform.isWindows ? '依赖 touch' : false);
}
