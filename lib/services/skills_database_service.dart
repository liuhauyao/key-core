import '../models/skill.dart';
import 'database_service.dart';

/// Skills 数据库服务
class SkillsDatabaseService {
  final DatabaseService _databaseService = DatabaseService.instance;

  Future<List<Skill>> getAllSkills() async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'skills',
      orderBy: 'sort_order ASC, updated_at ASC',
    );
    return maps.map((map) => Skill.fromMap(map)).toList();
  }

  Future<Skill?> getSkillById(int id) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'skills',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Skill.fromMap(maps.first);
    }
    return null;
  }

  Future<Skill?> getSkillBySkillId(String skillId) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'skills',
      where: 'skill_id = ?',
      whereArgs: [skillId],
    );
    if (maps.isNotEmpty) {
      return Skill.fromMap(maps.first);
    }
    return null;
  }

  Future<Skill?> getSkillByRelativePath(String relativePath) async {
    final db = await _databaseService.database;
    final maps = await db.query(
      'skills',
      where: 'relative_path = ?',
      whereArgs: [relativePath],
    );
    if (maps.isNotEmpty) {
      return Skill.fromMap(maps.first);
    }
    return null;
  }

  /// 新增 Skill：未指定排序时排到末尾（否则 sort_order=0 会和第一项并列，新装的 Skill 跳到最前）
  Future<int> addSkill(Skill skill) async {
    final db = await _databaseService.database;
    final map = skill.toMap();
    if (skill.sortOrder == 0) {
      final r = await db.rawQuery('SELECT MAX(sort_order) AS m, COUNT(*) AS c FROM skills');
      final count = (r.first['c'] as int?) ?? 0;
      if (count > 0) map['sort_order'] = ((r.first['m'] as int?) ?? 0) + 1;
    }
    return await db.insert('skills', map);
  }

  Future<int> updateSkill(Skill skill) async {
    final db = await _databaseService.database;
    return await db.update(
      'skills',
      skill.toMap(),
      where: 'id = ?',
      whereArgs: [skill.id],
    );
  }

  Future<int> deleteSkill(int id) async {
    final db = await _databaseService.database;
    return await db.delete(
      'skills',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> skillIdExists(String skillId) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'skills',
      columns: ['id'],
      where: 'skill_id = ?',
      whereArgs: [skillId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<bool> relativePathExists(String relativePath) async {
    final db = await _databaseService.database;
    final result = await db.query(
      'skills',
      columns: ['id'],
      where: 'relative_path = ?',
      whereArgs: [relativePath],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> updateSortOrders(List<Skill> skills) async {
    final db = await _databaseService.database;
    final batch = db.batch();
    for (var i = 0; i < skills.length; i++) {
      final skill = skills[i];
      batch.update(
        'skills',
        // 只改排序，不改 updated_at（updated_at 表示内容变更时间）
        {'sort_order': i},
        where: 'id = ?',
        whereArgs: [skill.id],
      );
    }
    await batch.commit(noResult: true);
  }
}
