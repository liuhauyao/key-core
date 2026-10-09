import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/skill.dart';
import '../skills_database_service.dart';
import '../skills_path_service.dart';
import '../skills_sync_service.dart';
import 'skills_fs.dart';

/// 卸载 / 更新前的 Skill 备份
class SkillBackupEntry {
  final String id;
  final String backupPath;
  final String skillName;
  final String relativePath;
  final String reason;
  final DateTime createdAt;
  final Map<String, dynamic> skillData;

  const SkillBackupEntry({
    required this.id,
    required this.backupPath,
    required this.skillName,
    required this.relativePath,
    required this.reason,
    required this.createdAt,
    required this.skillData,
  });
}

/// Skills 备份服务：卸载时移动到 `~/.keycore/skill-backups/<名称>-<时间>/`，可恢复。
class SkillsBackupService {
  final SkillsPathService _pathService = SkillsPathService();
  final SkillsDatabaseService _databaseService = SkillsDatabaseService();

  static const String metaFileName = 'meta.json';
  static const String contentDirName = 'skill';

  /// 测试专用：固定时间
  static DateTime Function() clock = DateTime.now;

  Future<String> _newBackupDir(Skill skill) async {
    final root = await _pathService.getBackupsDir();
    final ts = clock().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final base = '${SkillsFs.sanitizeDirName(skill.skillId)}-$ts';
    var candidate = path.join(root, base);
    for (var i = 2; await Directory(candidate).exists(); i++) {
      candidate = path.join(root, '$base-$i');
    }
    await Directory(candidate).create(recursive: true);
    return candidate;
  }

  Future<void> _writeMeta(String backupDir, Skill skill, String reason) async {
    final data = skill.toMap()..remove('id');
    await File(path.join(backupDir, metaFileName)).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'reason': reason,
        'createdAt': clock().toIso8601String(),
        'skill': data,
      }),
    );
  }

  /// 复制一份当前内容作为备份（用于更新前）
  Future<String> backupDirectory(Skill skill, String sourceDir, {required String reason}) async {
    final dir = await _newBackupDir(skill);
    await SkillsFs.copyDirectory(sourceDir, path.join(dir, contentDirName));
    await _writeMeta(dir, skill, reason);
    return dir;
  }

  /// 卸载：移除各工具中的受管链接/副本，把源目录移入备份，删除数据库记录
  Future<String> uninstall(Skill skill, {SkillsSyncService? syncService}) async {
    await (syncService ?? SkillsSyncService()).removeSkillFromTools(skill);
    final sourceDir = await _pathService.getSkillSourcePath(skill.relativePath);
    final dir = await _newBackupDir(skill);
    final content = path.join(dir, contentDirName);
    if (await Directory(sourceDir).exists()) {
      try {
        await Directory(sourceDir).rename(content);
      } on FileSystemException {
        // 跨分区时 rename 会失败，回退为复制 + 删除
        await SkillsFs.copyDirectory(sourceDir, content);
        await Directory(sourceDir).delete(recursive: true);
      }
    }
    await _writeMeta(dir, skill, 'uninstall');
    if (skill.id != null) await _databaseService.deleteSkill(skill.id!);
    return dir;
  }

  Future<List<SkillBackupEntry>> listBackups() async {
    final root = Directory(await _pathService.getBackupsDir());
    if (!await root.exists()) return const [];
    final result = <SkillBackupEntry>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File(path.join(entity.path, metaFileName));
      if (!await meta.exists()) continue;
      try {
        final json = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        final skill = Map<String, dynamic>.from(json['skill'] as Map);
        result.add(SkillBackupEntry(
          id: path.basename(entity.path),
          backupPath: entity.path,
          skillName: skill['name']?.toString() ?? path.basename(entity.path),
          relativePath: skill['relative_path']?.toString() ?? '',
          reason: json['reason']?.toString() ?? 'uninstall',
          createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime(1970),
          skillData: skill,
        ));
      } catch (_) {
        continue;
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  /// 从备份恢复：内容放回存储目录（重名时自动改名），重新写入数据库
  Future<Skill> restore(SkillBackupEntry entry) async {
    final content = Directory(path.join(entry.backupPath, contentDirName));
    if (!await content.exists()) throw StateError('备份内容缺失: ${entry.backupPath}');

    var relativePath = entry.relativePath.isEmpty ? entry.id : entry.relativePath;
    final base = relativePath;
    for (var i = 2;
        await _databaseService.relativePathExists(relativePath) ||
            await _databaseService.skillIdExists(path.basename(relativePath)) ||
            await Directory(await _pathService.getSkillSourcePath(relativePath)).exists();
        i++) {
      relativePath = '$base-$i';
    }
    final dest = await _pathService.getSkillSourcePath(relativePath);
    await SkillsFs.copyDirectory(content.path, dest);

    final now = DateTime.now();
    final data = Map<String, dynamic>.from(entry.skillData)
      ..['relative_path'] = relativePath
      ..['skill_id'] = path.basename(relativePath)
      ..['sync_status'] = null
      ..['content_hash'] = entry.skillData['content_hash']
      ..['updated_at'] = now.toIso8601String();
    data['created_at'] ??= now.toIso8601String();
    final skill = Skill.fromMap(data);
    final id = await _databaseService.addSkill(skill);
    await Directory(entry.backupPath).delete(recursive: true);
    return skill.copyWith(id: id);
  }

  Future<void> deleteBackup(SkillBackupEntry entry) async {
    final root = path.normalize(await _pathService.getBackupsDir());
    if (!path.isWithin(root, path.normalize(entry.backupPath))) {
      throw StateError('拒绝删除备份目录之外的路径');
    }
    await Directory(entry.backupPath).delete(recursive: true);
  }
}
