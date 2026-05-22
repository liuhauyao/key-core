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

  Future<int> addSkill(Skill skill) async {
    final db = await _databaseService.database;
    return await db.insert('skills', skill.toMap());
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
        {
          'sort_order': i,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [skill.id],
      );
    }
    await batch.commit(noResult: true);
  }
}
