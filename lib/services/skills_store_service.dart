import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/skill.dart';
import 'skill_parser_service.dart';
import 'skills_path_service.dart';

/// Skills 文件存储服务
class SkillsStoreService {
  final SkillsPathService _pathService = SkillsPathService();
  final SkillParserService _parserService = SkillParserService();

  Future<String> ensureSkillsRoot() => _pathService.ensureSkillsSourceDir();

  /// 递归扫描源目录，发现所有含 SKILL.md 的目录
  Future<List<({String relativePath, Directory dir, SkillParseResult parsed})>> scanSkills() async {
    final sourceDir = await ensureSkillsRoot();
    final root = Directory(sourceDir);
    if (!await root.exists()) return [];

    final results = <({String relativePath, Directory dir, SkillParseResult parsed})>[];

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (path.basename(entity.path) != SkillParserService.skillFileName) continue;

      final skillDir = entity.parent;
      final relativePath = path.relative(skillDir.path, from: sourceDir);
      if (relativePath.startsWith('..')) continue;

      final content = await entity.readAsString();
      final parsed = _parserService.parseSkillMd(content);
      results.add((relativePath: relativePath, dir: skillDir, parsed: parsed));
    }

    results.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return results;
  }

  /// 从本地文件夹导入 Skill
  Future<Directory> importSkillFromFolder(
    String sourceDirPath, {
    String? targetRelativePath,
    bool overwrite = false,
  }) async {
    final sourceDir = Directory(sourceDirPath);
    if (!await sourceDir.exists()) {
      throw StateError('Source directory does not exist');
    }

    final validation = await _parserService.validateSkillFolder(sourceDir);
    if (!validation.isValid) {
      throw StateError(validation.errors.join('; '));
    }

    final relativePath = targetRelativePath ?? path.basename(sourceDir.path);
    final destPath = await _pathService.getSkillSourcePath(relativePath);
    final destDir = Directory(destPath);

    if (await destDir.exists()) {
      if (!overwrite) {
        throw StateError('Skill already exists at $relativePath');
      }
      await destDir.delete(recursive: true);
    }

    await _copyDirectory(sourceDir, destDir);
    return destDir;
  }

  /// 创建新 Skill
  Future<Directory> createSkill({
    required String skillId,
    required String name,
    required String description,
    String body = '',
    String? categoryPath,
  }) async {
    await ensureSkillsRoot();

    final relativePath = categoryPath != null && categoryPath.isNotEmpty
        ? path.join(categoryPath, skillId)
        : skillId;

    final destPath = await _pathService.getSkillSourcePath(relativePath);
    final destDir = Directory(destPath);

    if (await destDir.exists()) {
      throw StateError('Skill directory already exists');
    }

    await destDir.create(recursive: true);

    final content = _parserService.generateSkillMd(
      name: skillId,
      description: description,
      body: body,
    );

    await File(path.join(destDir.path, SkillParserService.skillFileName)).writeAsString(content);
    return destDir;
  }

  /// 更新 SKILL.md 内容
  Future<void> updateSkillContent(String relativePath, String content) async {
    final skillPath = await _pathService.getSkillSourcePath(relativePath);
    final skillFile = File(path.join(skillPath, SkillParserService.skillFileName));
    if (!await skillFile.exists()) {
      throw StateError('SKILL.md not found');
    }
    await skillFile.writeAsString(content);
  }

  /// 读取 SKILL.md 内容
  Future<String> readSkillContent(String relativePath) async {
    final skillPath = await _pathService.getSkillSourcePath(relativePath);
    final skillFile = File(path.join(skillPath, SkillParserService.skillFileName));
    if (!await skillFile.exists()) {
      throw StateError('SKILL.md not found');
    }
    return skillFile.readAsString();
  }

  /// 删除 Skill 源目录
  Future<void> deleteSkillDirectory(String relativePath) async {
    final skillPath = await _pathService.getSkillSourcePath(relativePath);
    final dir = Directory(skillPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 生成唯一 relative path（用于重命名导入）
  Future<String> generateUniqueRelativePath(String baseRelativePath) async {
    var candidate = baseRelativePath;
    var counter = 1;
    while (await Directory(await _pathService.getSkillSourcePath(candidate)).exists()) {
      candidate = '$baseRelativePath-$counter';
      counter++;
    }
    return candidate;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await for (final entity in source.list(recursive: true, followLinks: false)) {
      final relative = path.relative(entity.path, from: source.path);
      final destPath = path.join(destination.path, relative);

      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(path.dirname(destPath)).create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }
}
