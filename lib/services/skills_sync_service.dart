import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/mcp_server.dart';
import '../models/skill.dart';
import 'skill_parser_service.dart';
import 'skills_database_service.dart';
import 'skills_path_service.dart';
import 'skills_store_service.dart';

/// Skill 同步单项结果
class SkillSyncItemResult {
  final String relativePath;
  final SkillTargetTool tool;
  final bool success;
  final SkillSyncState state;
  final String? message;

  const SkillSyncItemResult({
    required this.relativePath,
    required this.tool,
    required this.success,
    required this.state,
    this.message,
  });
}

/// Skill 同步汇总结果
class SkillSyncSummary {
  final int synced;
  final int skipped;
  final int conflicts;
  final int failed;
  final List<SkillSyncItemResult> items;

  const SkillSyncSummary({
    this.synced = 0,
    this.skipped = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.items = const [],
  });
}

/// Skill 导入汇总结果
class SkillImportSummary {
  final int imported;
  final int skipped;
  final int conflicts;
  final int failed;
  final List<String> messages;

  const SkillImportSummary({
    this.imported = 0,
    this.skipped = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.messages = const [],
  });
}

/// Skills 符号链接同步服务
class SkillsSyncService {
  final SkillsPathService _pathService = SkillsPathService();
  final SkillsStoreService _storeService = SkillsStoreService();
  final SkillsDatabaseService _databaseService = SkillsDatabaseService();
  final SkillParserService _parserService = SkillParserService();

  /// 扫描工具目录中的 Skills
  Future<List<ToolSkillEntry>> scanToolSkills(SkillTargetTool tool) async {
    final toolDirPath = await _pathService.getToolSkillsDir(tool);
    final toolDir = Directory(toolDirPath);
    if (!await toolDir.exists()) return [];

    final sourceDir = await _pathService.getSkillsSourceDir();
    final entries = <ToolSkillEntry>[];

    await for (final entity in toolDir.list(recursive: true, followLinks: true)) {
      if (entity is! File) continue;
      if (path.basename(entity.path) != SkillParserService.skillFileName) continue;

      final skillDir = entity.parent;
      final relativePath = path.relative(skillDir.path, from: toolDirPath);
      if (relativePath.startsWith('..')) continue;

      final parsed = await _parserService.readSkillFromDir(skillDir);
      final linkInfo = await _resolveLinkInfo(skillDir, sourceDir);

      entries.add(ToolSkillEntry(
        relativePath: relativePath,
        absolutePath: skillDir.path,
        name: parsed?.name ?? path.basename(skillDir.path),
        description: parsed?.description,
        isSymlink: linkInfo.isSymlink,
        isKeyCoreManaged: linkInfo.isKeyCoreManaged,
        symlinkTarget: linkInfo.target,
      ));
    }

    entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return entries;
  }

  /// 从工具目录导入 Skills 到 Key Core
  Future<SkillImportSummary> importFromTool(
    SkillTargetTool tool, {
    SkillImportConflictAction defaultConflictAction = SkillImportConflictAction.skip,
    Map<String, SkillImportConflictAction>? conflictActions,
  }) async {
    final entries = await scanToolSkills(tool);
    var imported = 0;
    var skipped = 0;
    var conflicts = 0;
    var failed = 0;
    final messages = <String>[];

    for (final entry in entries) {
      if (entry.isKeyCoreManaged) {
        skipped++;
        continue;
      }

      if (entry.isSymlink) {
        skipped++;
        messages.add('${entry.relativePath}: skipped external symlink');
        continue;
      }

      final existing = await _databaseService.getSkillByRelativePath(entry.relativePath);
      if (existing != null) {
        final action = conflictActions?[entry.relativePath] ?? defaultConflictAction;
        if (action == SkillImportConflictAction.skip) {
          skipped++;
          conflicts++;
          continue;
        }
      }

      try {
        var relativePath = entry.relativePath;
        final action = conflictActions?[entry.relativePath] ?? defaultConflictAction;

        if (existing != null && action == SkillImportConflictAction.rename) {
          relativePath = await _storeService.generateUniqueRelativePath(entry.relativePath);
        }

        await _storeService.importSkillFromFolder(
          entry.absolutePath,
          targetRelativePath: relativePath,
          overwrite: existing != null && action == SkillImportConflictAction.overwrite,
        );

        final now = DateTime.now();
        final parsed = await _parserService.readSkillFromDir(
          Directory(await _pathService.getSkillSourcePath(relativePath)),
        );

        final enabledTools = <SkillTargetTool>{tool};
        if (existing != null) {
          enabledTools.addAll(existing.enabledTools);
        }

        final skill = Skill(
          id: existing?.id,
          skillId: path.basename(relativePath),
          relativePath: relativePath,
          name: parsed?.name ?? entry.name,
          description: parsed?.description ?? entry.description,
          enabledTools: enabledTools.toList(),
          sourceTool: tool,
          isActive: true,
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        );

        if (existing != null) {
          await _databaseService.updateSkill(skill);
        } else {
          await _databaseService.addSkill(skill);
        }

        imported++;
      } catch (e) {
        failed++;
        messages.add('${entry.relativePath}: $e');
      }
    }

    return SkillImportSummary(
      imported: imported,
      skipped: skipped,
      conflicts: conflicts,
      failed: failed,
      messages: messages,
    );
  }

  /// 同步所有激活 Skill 到指定工具
  Future<SkillSyncSummary> syncToTool(
    SkillTargetTool tool, {
    bool replaceExisting = false,
  }) async {
    final skills = await _databaseService.getAllSkills();
    final activeSkills = skills.where((s) => s.isActive && s.enabledTools.contains(tool));

    final items = <SkillSyncItemResult>[];
    var synced = 0;
    var skipped = 0;
    var conflicts = 0;
    var failed = 0;

    for (final skill in activeSkills) {
      final result = await _syncSingleSkill(skill, tool, replaceExisting: replaceExisting);
      items.add(result);

      if (result.success && result.state == SkillSyncState.synced) {
        if (result.message == 'already synced') {
          skipped++;
        } else {
          synced++;
        }
      } else if (result.state == SkillSyncState.conflict) {
        conflicts++;
      } else if (!result.success) {
        failed++;
      }
    }

    await _cleanupOrphanLinks(tool, activeSkills.map((s) => s.relativePath).toSet());
    await _refreshSyncStatusForTool(tool);

    return SkillSyncSummary(
      synced: synced,
      skipped: skipped,
      conflicts: conflicts,
      failed: failed,
      items: items,
    );
  }

  /// 同步到所有已启用工具
  Future<Map<SkillTargetTool, SkillSyncSummary>> syncAll({
    bool replaceExisting = false,
  }) async {
    final summaries = <SkillTargetTool, SkillSyncSummary>{};
    for (final tool in SkillsPathService.supportedTools) {
      summaries[tool] = await syncToTool(tool, replaceExisting: replaceExisting);
    }
    return summaries;
  }

  /// 一键迁移：导入 + 替换 symlink
  Future<({SkillImportSummary importSummary, SkillSyncSummary? syncSummary})> migrateFromTool(
    SkillTargetTool tool, {
    bool replaceWithSymlink = true,
    SkillImportConflictAction defaultConflictAction = SkillImportConflictAction.skip,
  }) async {
    final importSummary = await importFromTool(
      tool,
      defaultConflictAction: defaultConflictAction,
    );

    SkillSyncSummary? syncSummary;
    if (replaceWithSymlink && importSummary.imported > 0) {
      syncSummary = await syncToTool(tool, replaceExisting: true);
    }

    return (importSummary: importSummary, syncSummary: syncSummary);
  }

  /// 计算 Skill 在指定工具下的同步状态
  Future<SkillSyncState> computeSyncState(Skill skill, SkillTargetTool tool) async {
    if (!skill.isActive || !skill.enabledTools.contains(tool)) {
      return SkillSyncState.notSynced;
    }

    final sourcePath = await _pathService.getSkillSourcePath(skill.relativePath);
    if (!await Directory(sourcePath).exists()) {
      return SkillSyncState.outdated;
    }

    final toolPath = await _pathService.getSkillToolPath(tool, skill.relativePath);
    final toolEntityType = await FileSystemEntity.type(toolPath, followLinks: false);

    if (toolEntityType == FileSystemEntityType.notFound) {
      return SkillSyncState.notSynced;
    }

    final normalizedSource = path.normalize(sourcePath);
    try {
      final resolvedToolPath = path.normalize(await Directory(toolPath).resolveSymbolicLinks());
      if (_pathsEqual(resolvedToolPath, normalizedSource)) {
        return SkillSyncState.synced;
      }
    } catch (_) {}

    if (toolEntityType == FileSystemEntityType.link) {
      final link = Link(toolPath);
      var target = await link.target();
      if (!path.isAbsolute(target)) {
        target = path.normalize(path.join(path.dirname(toolPath), target));
      }
      if (_pathsEqual(target, normalizedSource)) {
        return SkillSyncState.synced;
      }
    }

    return SkillSyncState.conflict;
  }

  /// 刷新所有 Skill 的同步状态
  Future<List<Skill>> refreshAllSyncStatus() async {
    final skills = await _databaseService.getAllSkills();
    final updated = <Skill>[];

    for (final skill in skills) {
      final syncStatus = <SkillTargetTool, SkillSyncState>{};
      for (final tool in SkillsPathService.supportedTools) {
        syncStatus[tool] = await computeSyncState(skill, tool);
      }

      final refreshed = skill.copyWith(
        syncStatus: syncStatus,
        updatedAt: DateTime.now(),
      );
      await _databaseService.updateSkill(refreshed);
      updated.add(refreshed);
    }

    return updated;
  }

  Future<SkillSyncItemResult> _syncSingleSkill(
    Skill skill,
    SkillTargetTool tool, {
    required bool replaceExisting,
  }) async {
    try {
      final sourcePath = await _pathService.getSkillSourcePath(skill.relativePath);
      final sourceDir = Directory(sourcePath);

      if (!await sourceDir.exists()) {
        return SkillSyncItemResult(
          relativePath: skill.relativePath,
          tool: tool,
          success: false,
          state: SkillSyncState.outdated,
          message: 'Source directory missing',
        );
      }

      await _pathService.ensureToolSkillsDir(tool);
      final toolPath = await _pathService.getSkillToolPath(tool, skill.relativePath);
      final entityType = await FileSystemEntity.type(toolPath, followLinks: false);

      if (entityType == FileSystemEntityType.link) {
        final link = Link(toolPath);
        final target = await link.target();
        if (_pathsEqual(target, sourcePath)) {
          await _writeManagedMarker(toolPath);
          return SkillSyncItemResult(
            relativePath: skill.relativePath,
            tool: tool,
            success: true,
            state: SkillSyncState.synced,
            message: 'already synced',
          );
        }

        if (!replaceExisting) {
          return SkillSyncItemResult(
            relativePath: skill.relativePath,
            tool: tool,
            success: false,
            state: SkillSyncState.conflict,
            message: 'Existing symlink points elsewhere',
          );
        }

        await link.delete();
      } else if (entityType != FileSystemEntityType.notFound) {
        if (!replaceExisting) {
          return SkillSyncItemResult(
            relativePath: skill.relativePath,
            tool: tool,
            success: false,
            state: SkillSyncState.conflict,
            message: 'Target path exists and is not a symlink',
          );
        }

        final existing = Directory(toolPath);
        if (await existing.exists()) {
          await existing.delete(recursive: true);
        } else {
          await File(toolPath).delete();
        }
      }

      await Directory(path.dirname(toolPath)).create(recursive: true);
      await Link(toolPath).create(sourcePath);
      await _writeManagedMarker(toolPath);

      return SkillSyncItemResult(
        relativePath: skill.relativePath,
        tool: tool,
        success: true,
        state: SkillSyncState.synced,
      );
    } catch (e) {
      return SkillSyncItemResult(
        relativePath: skill.relativePath,
        tool: tool,
        success: false,
        state: SkillSyncState.conflict,
        message: e.toString(),
      );
    }
  }

  Future<void> _cleanupOrphanLinks(
    SkillTargetTool tool,
    Set<String> activeRelativePaths,
  ) async {
    final toolDirPath = await _pathService.getToolSkillsDir(tool);
    final toolDir = Directory(toolDirPath);
    if (!await toolDir.exists()) return;

    final managedLinks = await _findManagedLinks(toolDirPath);
    for (final linkPath in managedLinks) {
      final relativePath = path.relative(linkPath, from: toolDirPath);
      if (!activeRelativePaths.contains(relativePath)) {
        final link = Link(linkPath);
        if (await link.exists()) {
          await link.delete();
        }
        final marker = File(_pathService.getManagedMarkerPath(linkPath));
        if (await marker.exists()) {
          await marker.delete();
        }
      }
    }
  }

  Future<void> _refreshSyncStatusForTool(SkillTargetTool tool) async {
    final skills = await _databaseService.getAllSkills();
    for (final skill in skills) {
      final state = await computeSyncState(skill, tool);
      final syncStatus = Map<SkillTargetTool, SkillSyncState>.from(skill.syncStatus);
      syncStatus[tool] = state;
      await _databaseService.updateSkill(
        skill.copyWith(syncStatus: syncStatus, updatedAt: DateTime.now()),
      );
    }
  }

  Future<({bool isSymlink, bool isKeyCoreManaged, String? target})> _resolveLinkInfo(
    Directory skillDir,
    String sourceDir,
  ) async {
    final entityType = await FileSystemEntity.type(skillDir.path, followLinks: false);
    if (entityType == FileSystemEntityType.link) {
      final link = Link(skillDir.path);
      final target = await link.target();
      final resolved = path.normalize(_resolvePath(skillDir.parent.path, target));
      final normalizedSource = path.normalize(sourceDir);
      final isManaged = resolved.startsWith(normalizedSource);
      return (isSymlink: true, isKeyCoreManaged: isManaged, target: target);
    }

    return (isSymlink: false, isKeyCoreManaged: false, target: null);
  }

  Future<List<String>> _findManagedLinks(String toolDirPath) async {
    final links = <String>[];
    final toolDir = Directory(toolDirPath);
    if (!await toolDir.exists()) return links;

    final sourceDir = path.normalize(await _pathService.getSkillsSourceDir());

    await for (final entity in toolDir.list(recursive: true, followLinks: false)) {
      final entityType = await FileSystemEntity.type(entity.path, followLinks: false);
      if (entityType != FileSystemEntityType.link) continue;

      final link = Link(entity.path);
      final target = await link.target();
      final resolved = path.normalize(_resolvePath(entity.parent.path, target));
      if (resolved.startsWith(sourceDir)) {
        links.add(entity.path);
      }
    }
    return links;
  }

  Future<void> _writeManagedMarker(String linkPath) async {
    final marker = File(_pathService.getManagedMarkerPath(linkPath));
    if (!await marker.exists()) {
      await marker.writeAsString('managed-by=keycore\n');
    }
  }

  bool _pathsEqual(String a, String b) {
    return path.normalize(a) == path.normalize(b);
  }

  String _resolvePath(String base, String target) {
    if (path.isAbsolute(target)) {
      return path.normalize(target);
    }
    return path.normalize(path.join(base, target));
  }

  /// 从 AiToolType 导入
  Future<SkillImportSummary> importFromAiTool(AiToolType tool, {SkillImportConflictAction defaultConflictAction = SkillImportConflictAction.skip}) {
    final target = SkillTargetTool.fromAiToolType(tool);
    if (target == null) {
      throw UnsupportedError('Tool does not support skills');
    }
    return importFromTool(target, defaultConflictAction: defaultConflictAction);
  }
}
