import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mcp_server.dart';
import 'skills/skills_fs.dart';
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

  /// 同步方式设置键（auto / symlink / copy）
  static const String syncMethodKey = 'skills_sync_method';

  /// 测试专用：覆盖同步方式
  static SkillSyncMethod? debugSyncMethodOverride;

  /// 测试专用：模拟创建符号链接失败（用于验证 auto 模式回退为复制）
  static bool debugFailSymlinks = false;

  static Future<SkillSyncMethod> getSyncMethod() async {
    if (debugSyncMethodOverride != null) return debugSyncMethodOverride!;
    try {
      final prefs = await SharedPreferences.getInstance();
      return SkillSyncMethod.fromString(prefs.getString(syncMethodKey));
    } catch (_) {
      return SkillSyncMethod.auto;
    }
  }

  static Future<void> setSyncMethod(SkillSyncMethod method) async {
    if (debugSyncMethodOverride != null) {
      debugSyncMethodOverride = method;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(syncMethodKey, method.value);
  }

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
    await SkillsFs.cleanupLegacySourceMarkers(await _pathService.getSkillsSourceDir());
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

    if (toolEntityType == FileSystemEntityType.directory) {
      final marker = await SkillsFs.readCopyMarker(toolPath);
      if (marker != null && marker.relativePath == skill.relativePath) {
        final sourceHash = await SkillsFs.computeDirHash(sourcePath);
        final copyHash = await SkillsFs.computeDirHash(toolPath);
        return copyHash == sourceHash ? SkillSyncState.synced : SkillSyncState.outdated;
      }
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
      final method = await getSyncMethod();

      if (entityType == FileSystemEntityType.link) {
        final link = Link(toolPath);
        final target = _resolvePath(path.dirname(toolPath), await link.target());
        final pointsToSource = _pathsEqual(target, sourcePath);
        if (pointsToSource && method != SkillSyncMethod.copy) {
          return SkillSyncItemResult(
            relativePath: skill.relativePath,
            tool: tool,
            success: true,
            state: SkillSyncState.synced,
            message: 'already synced',
          );
        }

        // 指向 Key Core 的链接（如切换为复制模式）属于自己，可直接替换
        if (!pointsToSource && !replaceExisting) {
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
        final marker = entityType == FileSystemEntityType.directory
            ? await SkillsFs.readCopyMarker(toolPath)
            : null;
        final ownCopy = marker != null && marker.relativePath == skill.relativePath;
        if (ownCopy && method == SkillSyncMethod.copy) {
          final sourceHash = await SkillsFs.computeDirHash(sourcePath);
          if (await SkillsFs.computeDirHash(toolPath) == sourceHash) {
            return SkillSyncItemResult(
              relativePath: skill.relativePath,
              tool: tool,
              success: true,
              state: SkillSyncState.synced,
              message: 'already synced',
            );
          }
        }

        if (!ownCopy && !replaceExisting) {
          return SkillSyncItemResult(
            relativePath: skill.relativePath,
            tool: tool,
            success: false,
            state: SkillSyncState.conflict,
            message: 'Target path exists and is not a symlink',
          );
        }

        if (ownCopy) {
          await Directory(toolPath).delete(recursive: true);
        } else {
          // 用户自己的目录/文件：不直接删除，移动到 skill-backups/_replaced 下
          await _moveAsideReplaced(tool, skill.relativePath, toolPath);
        }
      }

      await Directory(path.dirname(toolPath)).create(recursive: true);
      var linked = false;
      if (method != SkillSyncMethod.copy) {
        try {
          if (debugFailSymlinks) {
            throw const FileSystemException('symlink disabled for test');
          }
          await Link(toolPath).create(sourcePath);
          linked = true;
        } on FileSystemException {
          if (method == SkillSyncMethod.symlink) rethrow;
        }
      }
      if (!linked) {
        await SkillsFs.copyDirectory(sourcePath, toolPath);
        await SkillsFs.writeCopyMarker(
          toolPath,
          relativePath: skill.relativePath,
          hash: await SkillsFs.computeDirHash(sourcePath),
        );
      }

      return SkillSyncItemResult(
        relativePath: skill.relativePath,
        tool: tool,
        success: true,
        state: SkillSyncState.synced,
        message: linked ? null : 'copied',
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
        await removeManagedEntry(linkPath);
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
      final isManaged = _isWithinOrEqual(normalizedSource, resolved);
      return (isSymlink: true, isKeyCoreManaged: isManaged, target: target);
    }

    final marker = await SkillsFs.readCopyMarker(skillDir.path);
    return (isSymlink: false, isKeyCoreManaged: marker != null, target: null);
  }

  /// 查找工具目录中由 Key Core 管理的条目：指向源目录的符号链接，或带受管标记的副本目录
  Future<List<String>> _findManagedLinks(String toolDirPath) async {
    final links = <String>[];
    final toolDir = Directory(toolDirPath);
    if (!await toolDir.exists()) return links;

    final sourceDir = path.normalize(await _pathService.getSkillsSourceDir());

    Future<void> walk(Directory dir) async {
      await for (final entity in dir.list(followLinks: false)) {
        final entityType = await FileSystemEntity.type(entity.path, followLinks: false);
        if (entityType == FileSystemEntityType.link) {
          final target = await Link(entity.path).target();
          final resolved = path.normalize(_resolvePath(entity.parent.path, target));
          if (_isWithinOrEqual(sourceDir, resolved)) {
            links.add(entity.path);
          }
        } else if (entityType == FileSystemEntityType.directory) {
          if (await SkillsFs.readCopyMarker(entity.path) != null) {
            links.add(entity.path);
          } else {
            await walk(Directory(entity.path));
          }
        }
      }
    }

    await walk(toolDir);
    return links;
  }

  /// 删除工具目录中的受管条目（符号链接或受管副本）；非受管的真实目录不会被删除
  Future<bool> removeManagedEntry(String entryPath) async {
    final type = await FileSystemEntity.type(entryPath, followLinks: false);
    if (type == FileSystemEntityType.link) {
      await Link(entryPath).delete();
      return true;
    }
    if (type == FileSystemEntityType.directory &&
        await SkillsFs.readCopyMarker(entryPath) != null) {
      await Directory(entryPath).delete(recursive: true);
      return true;
    }
    return false;
  }

  /// 从所有工具目录移除某个 Skill 的受管条目
  Future<void> removeSkillFromTools(Skill skill) async {
    final sourcePath = path.normalize(await _pathService.getSkillSourcePath(skill.relativePath));
    for (final tool in SkillsPathService.supportedTools) {
      final toolPath = await _pathService.getSkillToolPath(tool, skill.relativePath);
      final type = await FileSystemEntity.type(toolPath, followLinks: false);
      if (type == FileSystemEntityType.link) {
        final target = _resolvePath(path.dirname(toolPath), await Link(toolPath).target());
        if (_pathsEqual(target, sourcePath)) await Link(toolPath).delete();
      } else if (type == FileSystemEntityType.directory) {
        final marker = await SkillsFs.readCopyMarker(toolPath);
        if (marker != null && marker.relativePath == skill.relativePath) {
          await Directory(toolPath).delete(recursive: true);
        }
      }
    }
  }

  /// 列出所有工具中由 Key Core 管理的条目（用于存储迁移前清理）
  Future<Map<SkillTargetTool, List<String>>> listManagedEntries() async {
    final result = <SkillTargetTool, List<String>>{};
    for (final tool in SkillsPathService.supportedTools) {
      result[tool] = await _findManagedLinks(await _pathService.getToolSkillsDir(tool));
    }
    return result;
  }

  Future<void> _moveAsideReplaced(SkillTargetTool tool, String relativePath, String toolPath) async {
    final ts = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final dest = path.join(
      await _pathService.getBackupsDir(),
      '_replaced',
      tool.value,
      '${relativePath.replaceAll(RegExp(r'[\\/]'), '__')}-$ts',
    );
    await Directory(path.dirname(dest)).create(recursive: true);
    try {
      if (await FileSystemEntity.isDirectory(toolPath)) {
        await Directory(toolPath).rename(dest);
      } else {
        await File(toolPath).rename(dest);
      }
    } on FileSystemException {
      if (await FileSystemEntity.isDirectory(toolPath)) {
        await SkillsFs.copyDirectory(toolPath, dest);
        await Directory(toolPath).delete(recursive: true);
      } else {
        await File(toolPath).copy(dest);
        await File(toolPath).delete();
      }
    }
  }

  bool _isWithinOrEqual(String parent, String child) {
    return _pathsEqual(parent, child) || path.isWithin(parent, child);
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

  /// 扫描所有工具目录中尚未被 Key Core 管理的 Skill（不含指向外部的符号链接）
  Future<Map<SkillTargetTool, List<ToolSkillEntry>>> scanUnmanaged() async {
    final result = <SkillTargetTool, List<ToolSkillEntry>>{};
    for (final tool in SkillsPathService.supportedTools) {
      final entries = (await scanToolSkills(tool))
          .where((e) => !e.isKeyCoreManaged && !e.isSymlink)
          .toList();
      if (entries.isNotEmpty) result[tool] = entries;
    }
    return result;
  }

  /// 从所有工具目录导入未管理的 Skill（同名冲突默认跳过）
  Future<Map<SkillTargetTool, SkillImportSummary>> importFromAllTools({
    SkillImportConflictAction defaultConflictAction = SkillImportConflictAction.skip,
  }) async {
    final result = <SkillTargetTool, SkillImportSummary>{};
    for (final tool in SkillsPathService.supportedTools) {
      final dir = Directory(await _pathService.getToolSkillsDir(tool));
      if (!await dir.exists()) continue;
      result[tool] = await importFromTool(tool, defaultConflictAction: defaultConflictAction);
    }
    return result;
  }

  /// 迁移 Skills 存储位置（`keycore` ↔ `agents`）。
  /// 先移除各工具中指向旧位置的受管条目，再移动目录、切换设置，最后重新同步。
  Future<({int moved, int skipped})> migrateStorage(String location) async {
    if (location != 'keycore' && location != 'agents') {
      throw ArgumentError.value(location, 'location');
    }
    final current = await _pathService.getStorageLocation();
    if (current == location) return (moved: 0, skipped: 0);

    final oldRoot = await _pathService.getSkillsSourceDir();
    final newRoot = location == 'agents'
        ? await _pathService.getAgentsSkillsDir()
        : await _pathService.getKeyCoreSkillsDir();

    // 先检查冲突，任何目标已存在就不做任何修改
    final skills = await _databaseService.getAllSkills();
    final conflicts = <String>[];
    for (final skill in skills) {
      final to = path.join(newRoot, skill.relativePath);
      if (await Directory(path.join(oldRoot, skill.relativePath)).exists() &&
          await FileSystemEntity.type(to, followLinks: false) != FileSystemEntityType.notFound) {
        conflicts.add(skill.relativePath);
      }
    }
    if (conflicts.isNotEmpty) {
      throw StateError('目标位置已存在同名 Skill: ${conflicts.join(', ')}');
    }

    final managed = await listManagedEntries();
    for (final entries in managed.values) {
      for (final e in entries) {
        await removeManagedEntry(e);
      }
    }

    var moved = 0;
    var skipped = 0;
    await Directory(newRoot).create(recursive: true);
    for (final skill in skills) {
      final from = Directory(path.join(oldRoot, skill.relativePath));
      final to = path.join(newRoot, skill.relativePath);
      if (!await from.exists()) continue;
      if (await FileSystemEntity.type(to, followLinks: false) != FileSystemEntityType.notFound) {
        skipped++;
        continue;
      }
      await Directory(path.dirname(to)).create(recursive: true);
      try {
        await from.rename(to);
      } on FileSystemException {
        await SkillsFs.copyDirectory(from.path, to);
        await from.delete(recursive: true);
      }
      moved++;
    }

    await _pathService.setStorageLocation(location);
    await syncAll();
    return (moved: moved, skipped: skipped);
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
