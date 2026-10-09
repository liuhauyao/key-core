import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/skill.dart';
import '../services/skills_database_service.dart';
import '../services/skills_path_service.dart';
import '../services/skills_store_service.dart';
import '../services/skills_sync_service.dart';
import '../services/skills/skills_backup_service.dart';
import '../services/skills/skills_fs.dart';
import '../services/skills/skills_market_service.dart';
import 'base_viewmodel.dart';

/// Skills 同步状态汇总
class SkillsSyncStatusSummary {
  final int total;
  final int synced;
  final int pending;
  final int conflicts;

  const SkillsSyncStatusSummary({
    this.total = 0,
    this.synced = 0,
    this.pending = 0,
    this.conflicts = 0,
  });
}

/// 分类分组信息
class SkillsCategoryGroup {
  final String category;
  final List<Skill> skills;

  const SkillsCategoryGroup({required this.category, required this.skills});

  int get total => skills.length;
  int get synced => skills.where((s) => s.syncStatus.values.any((st) => st == SkillSyncState.synced)).length;
}

/// Skills 管理 ViewModel
class SkillsViewModel extends BaseViewModel {
  final SkillsDatabaseService _databaseService = SkillsDatabaseService();
  final SkillsStoreService _storeService = SkillsStoreService();
  final SkillsSyncService _syncService = SkillsSyncService();
  final SkillsPathService _pathService = SkillsPathService();
  final SkillsMarketService _marketService = SkillsMarketService();

  /// 释放仓库下载的临时解压目录
  Future<void> clearMarketDownloadCache() => _marketService.clearDownloadCache();

  @override
  void dispose() {
    unawaited(_marketService.clearDownloadCache());
    super.dispose();
  }
  final SkillsBackupService _backupService = SkillsBackupService();

  List<Skill> _allSkills = [];
  List<Skill> _filteredSkills = [];
  String _searchQuery = '';
  String? _skillsSourceDir;
  String? _activeCategory; // null = all, '' = uncategorized
  bool _searchInContent = false; // 搜索扩展到 body 内容

  List<Skill> get skills => _filteredSkills;
  List<Skill> get allSkills => _allSkills;
  String get searchQuery => _searchQuery;
  String? get skillsSourceDir => _skillsSourceDir;
  String? get activeCategory => _activeCategory;
  bool get searchInContent => _searchInContent;

  /// 获取所有分类（从 relativePath 推导）
  List<String> get categories {
    final cats = <String>{};
    for (final skill in _allSkills) {
      final parts = skill.relativePath.split('/');
      if (parts.length > 1) {
        cats.add(parts.first);
      } else {
        cats.add(''); // uncategorized
      }
    }
    return cats.toList()..sort();
  }

  /// 获取指定分类的技能列表
  List<Skill> getSkillsByCategory(String category) {
    if (category.isEmpty) {
      return _allSkills.where((s) => !s.relativePath.contains('/')).toList();
    }
    return _allSkills.where((s) => s.relativePath.startsWith('$category/')).toList();
  }

  /// 获取分类分组
  List<SkillsCategoryGroup> get categoryGroups {
    final groups = <SkillsCategoryGroup>[];
    for (final cat in categories) {
      final skills = getSkillsByCategory(cat);
      groups.add(SkillsCategoryGroup(category: cat, skills: skills));
    }
    return groups;
  }

  /// 设置分类过滤
  void setActiveCategory(String? category) {
    _activeCategory = category;
    _updateFilteredSkills();
  }

  /// 切换内容搜索开关
  void toggleSearchInContent() {
    _searchInContent = !_searchInContent;
    _updateFilteredSkills();
  }

  Future<void> init() async {
    if (_allSkills.isEmpty) {
      await loadSkills(showLoading: true);
    }
  }

  Future<void> loadSkills({bool showLoading = true}) async {
    await executeAsync(() async {
      _skillsSourceDir = await _pathService.ensureSkillsSourceDir();
      await _reconcileFilesystemWithDatabase();
      _allSkills = await _syncService.refreshAllSyncStatus();
      _updateFilteredSkills();
    }, showLoading: showLoading);
  }

  Future<void> refresh() async {
    await loadSkills(showLoading: _allSkills.isEmpty);
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _updateFilteredSkills();
    notifyListeners();
  }

  void _updateFilteredSkills() {
    var filtered = _allSkills;

    // 分类过滤
    if (_activeCategory != null) {
      if (_activeCategory!.isEmpty) {
        filtered = filtered.where((s) => !s.relativePath.contains('/')).toList();
      } else {
        filtered = filtered.where((s) => s.relativePath.startsWith('${_activeCategory}/')).toList();
      }
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((skill) {
        final basicMatch = skill.name.toLowerCase().contains(q) ||
            skill.skillId.toLowerCase().contains(q) ||
            skill.relativePath.toLowerCase().contains(q) ||
            (skill.description?.toLowerCase().contains(q) ?? false) ||
            (skill.tags?.any((tag) => tag.toLowerCase().contains(q)) ?? false);

        if (basicMatch) return true;

        // 内容搜索需要异步读取文件，在同步过滤器中无法实现
        // 未来可通过预建 content 缓存索引来优化
        // searchInContent flag 保留供 UI 层切换状态

        return false;
      }).toList();
    }

    _filteredSkills = filtered;
  }

  SkillsSyncStatusSummary getSyncSummary() => summarizeSkills(_allSkills);

  /// 同步概览（纯函数，便于测试）
  @visibleForTesting
  static SkillsSyncStatusSummary summarizeSkills(List<Skill> allSkills) {
    var synced = 0;
    var pending = 0;
    var conflicts = 0;

    // 按「技能」计数（而不是技能 × 工具的组合数）：一个技能只落入一类，
    // 优先级 冲突 > 待同步 > 已同步。启用了某工具但还没有状态的，视为待同步。
    for (final skill in allSkills.where((s) => s.isActive)) {
      final states = skill.enabledTools.isNotEmpty
          ? skill.enabledTools.map((t) => skill.syncStatus[t] ?? SkillSyncState.notSynced).toList()
          : skill.syncStatus.values.toList();
      if (states.isEmpty) continue;
      if (states.contains(SkillSyncState.conflict)) {
        conflicts++;
      } else if (states.any((s) => s == SkillSyncState.notSynced || s == SkillSyncState.outdated)) {
        pending++;
      } else {
        synced++;
      }
    }

    return SkillsSyncStatusSummary(
      total: allSkills.length,
      synced: synced,
      pending: pending,
      conflicts: conflicts,
    );
  }

  Future<bool> addSkill({
    required String skillId,
    required String name,
    required String description,
    String body = '',
    List<SkillTargetTool> enabledTools = const [],
    List<String>? tags,
    String? notes,
    String? categoryPath,
  }) async {
    return await executeAsync(() async {
      final exists = await _databaseService.skillIdExists(skillId);
      if (exists) {
        setError('Skill ID "$skillId" already exists');
        return false;
      }

      await _storeService.createSkill(
        skillId: skillId,
        name: name,
        description: description,
        body: body,
        categoryPath: categoryPath,
      );

      final relativePath = categoryPath != null && categoryPath.isNotEmpty
          ? path.join(categoryPath, skillId)
          : skillId;

      final now = DateTime.now();
      await _databaseService.addSkill(
        Skill(
          skillId: skillId,
          relativePath: relativePath,
          name: name,
          description: description,
          enabledTools: enabledTools,
          tags: tags,
          notes: notes,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await loadSkills(showLoading: false);
      return true;
    }) ?? false;
  }

  Future<bool> updateSkill(Skill skill, {String? skillMdContent}) async {
    return await executeAsync(() async {
      if (skillMdContent != null) {
        await _storeService.updateSkillContent(skill.relativePath, skillMdContent);
      }

      await _databaseService.updateSkill(
        skill.copyWith(updatedAt: DateTime.now()),
      );
      await loadSkills(showLoading: false);
      return true;
    }) ?? false;
  }

  /// 删除（卸载）Skill：移除各工具中的受管链接/副本，源目录移入 skill-backups 以便恢复。
  /// [removeSymlinks] 为 false 时保留工具目录中的条目（仅移除 Key Core 记录与源目录备份）。
  Future<bool> deleteSkill(Skill skill, {bool removeSymlinks = true}) async {
    return await executeAsync(() async {
      if (removeSymlinks) {
        await _syncService.removeSkillFromTools(skill);
      }
      await _backupService.uninstall(skill, syncService: _NoopRemoveSync());
      await loadSkills(showLoading: false);
      return true;
    }) ?? false;
  }

  /// 批量删除技能
  Future<int> batchDelete(List<Skill> skills, {bool removeSymlinks = true}) async {
    var deleted = 0;
    for (final skill in skills) {
      final ok = await deleteSkill(skill, removeSymlinks: removeSymlinks);
      if (ok) deleted++;
    }
    return deleted;
  }

  /// 批量启用/禁用
  Future<int> batchToggleActive(List<Skill> skills, bool active) async {
    var updated = 0;
    for (final skill in skills) {
      if (skill.isActive == active) continue;
      await _databaseService.updateSkill(
        skill.copyWith(isActive: active, updatedAt: DateTime.now()),
      );
      updated++;
    }
    if (updated > 0) {
      await loadSkills(showLoading: false);
    }
    return updated;
  }

  /// 批量设置分发工具
  Future<int> batchSetEnabledTools(List<Skill> skills, List<SkillTargetTool> tools) async {
    var updated = 0;
    for (final skill in skills) {
      await _databaseService.updateSkill(
        skill.copyWith(enabledTools: tools, updatedAt: DateTime.now()),
      );
      updated++;
    }
    if (updated > 0) {
      await loadSkills(showLoading: false);
    }
    return updated;
  }

  /// 批量同步到工具
  Future<int> batchSyncToFirstTool(List<Skill> skills, {bool replaceExisting = false}) async {
    var synced = 0;
    for (final skill in skills) {
      if (skill.enabledTools.isEmpty) continue;
      final summary = await _syncService.syncToTool(
        skill.enabledTools.first,
        replaceExisting: replaceExisting,
      );
      synced += summary.synced;
    }
    await loadSkills(showLoading: false);
    return synced;
  }

  Future<bool> toggleActive(Skill skill) async {
    return await executeAsync(() async {
      await _databaseService.updateSkill(
        skill.copyWith(isActive: !skill.isActive, updatedAt: DateTime.now()),
      );
      await loadSkills(showLoading: false);
      return true;
    }) ?? false;
  }

  Future<bool> setEnabledTools(Skill skill, List<SkillTargetTool> tools) async {
    return await executeAsync(() async {
      await _databaseService.updateSkill(
        skill.copyWith(enabledTools: tools, updatedAt: DateTime.now()),
      );
      await loadSkills(showLoading: false);
      return true;
    }) ?? false;
  }

  Future<bool> importFromFolder(String folderPath) async {
    return await executeAsync(() async {
      final importDir = Directory(folderPath);
      final skillId = path.basename(folderPath);

      await _storeService.importSkillFromFolder(folderPath);
      final now = DateTime.now();

      final existing = await _databaseService.getSkillByRelativePath(skillId);
      if (existing != null) {
        setError('Skill already exists');
        return false;
      }

      final scanned = await _storeService.scanSkills();
      final match = scanned.where((s) => s.relativePath == skillId).firstOrNull;
      final name = match?.parsed.name ?? skillId;
      final description = match?.parsed.description;

      await _databaseService.addSkill(
        Skill(
          skillId: skillId,
          relativePath: skillId,
          name: name,
          description: description,
          enabledTools: SkillsPathService.supportedTools,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await loadSkills(showLoading: false);
      return true;
    }) ?? false;
  }

  Future<SkillImportSummary?> importFromTool(
    SkillTargetTool tool, {
    SkillImportConflictAction defaultConflictAction = SkillImportConflictAction.skip,
  }) async {
    return await executeAsync(() async {
      final summary = await _syncService.importFromTool(
        tool,
        defaultConflictAction: defaultConflictAction,
      );
      await loadSkills(showLoading: false);
      return summary;
    });
  }

  Future<SkillSyncSummary?> syncToTool(
    SkillTargetTool tool, {
    bool replaceExisting = false,
  }) async {
    return await executeAsync(() async {
      final summary = await _syncService.syncToTool(
        tool,
        replaceExisting: replaceExisting,
      );
      await loadSkills(showLoading: false);
      return summary;
    });
  }

  Future<Map<SkillTargetTool, SkillSyncSummary>?> syncAll({
    bool replaceExisting = false,
  }) async {
    return await executeAsync(() async {
      final summaries = await _syncService.syncAll(replaceExisting: replaceExisting);
      await loadSkills(showLoading: false);
      return summaries;
    });
  }

  Future<({SkillImportSummary importSummary, SkillSyncSummary? syncSummary})?> migrateFromTool(
    SkillTargetTool tool, {
    bool replaceWithSymlink = true,
  }) async {
    return await executeAsync(() async {
      final result = await _syncService.migrateFromTool(
        tool,
        replaceWithSymlink: replaceWithSymlink,
      );
      await loadSkills(showLoading: false);
      return result;
    });
  }

  Future<List<ToolSkillEntry>> scanToolSkills(SkillTargetTool tool) async {
    return _syncService.scanToolSkills(tool);
  }

  Future<String> readSkillContent(Skill skill) async {
    return _storeService.readSkillContent(skill.relativePath);
  }

  Future<void> updateSortOrder(List<Skill> orderedSkills) async {
    await executeAsync(() async {
      await _databaseService.updateSortOrders(orderedSkills);
      await loadSkills(showLoading: false);
    }, showLoading: false);
  }

  // ========== CC Switch 对齐：仓库 / skills.sh / ZIP / 备份 / 更新 / 同步方式 ==========

  Future<SkillSyncMethod> getSyncMethod() => SkillsSyncService.getSyncMethod();

  Future<void> setSyncMethod(SkillSyncMethod method) async {
    await SkillsSyncService.setSyncMethod(method);
    notifyListeners();
  }

  Future<List<SkillRepo>> getRepos() => _marketService.getRepos();

  Future<List<SkillRepo>> addRepo(String input) async {
    final repo = SkillRepo.parse(input);
    if (repo == null) throw FormatException('无法识别的仓库: $input');
    return _marketService.addRepo(repo);
  }

  Future<List<SkillRepo>> removeRepo(SkillRepo repo) => _marketService.removeRepo(repo.owner, repo.name);

  Future<({List<RemoteSkill> skills, Map<String, String> errors})?> discoverRepoSkills() {
    return executeAsync(() => _marketService.discoverAll());
  }

  Future<Skill?> installRemote(RemoteSkill remote, {List<SkillTargetTool> enabledTools = const []}) {
    return executeAsync(() async {
      final skill = await _marketService.installRemote(remote, enabledTools: enabledTools);
      await _syncEnabled(enabledTools);
      await loadSkills(showLoading: false);
      return skill;
    });
  }

  Future<List<SkillsShResult>?> searchSkillsSh(String query) {
    return executeAsync(() => _marketService.searchSkillsSh(query));
  }

  Future<Skill?> installFromSkillsSh(SkillsShResult result, {List<SkillTargetTool> enabledTools = const []}) {
    return executeAsync(() async {
      final skill = await _marketService.installFromSkillsSh(result, enabledTools: enabledTools);
      await _syncEnabled(enabledTools);
      await loadSkills(showLoading: false);
      return skill;
    });
  }

  Future<List<Skill>?> installFromZip(String zipPath, {List<SkillTargetTool> enabledTools = const []}) {
    return executeAsync(() async {
      final skills = await _marketService.installFromZip(zipPath, enabledTools: enabledTools);
      await _syncEnabled(enabledTools);
      await loadSkills(showLoading: false);
      return skills;
    });
  }

  Future<List<SkillUpdateInfo>?> checkUpdates() => executeAsync(() => _marketService.checkUpdates());

  Future<Skill?> updateFromRemote(Skill skill) {
    return executeAsync(() async {
      final updated = await _marketService.updateSkill(skill);
      await _syncEnabled(updated.enabledTools);
      await loadSkills(showLoading: false);
      return updated;
    });
  }

  Future<List<SkillBackupEntry>> listBackups() => _backupService.listBackups();

  Future<Skill?> restoreBackup(SkillBackupEntry entry) {
    return executeAsync(() async {
      final skill = await _backupService.restore(entry);
      await _syncEnabled(skill.enabledTools);
      await loadSkills(showLoading: false);
      return skill;
    });
  }

  Future<void> deleteBackup(SkillBackupEntry entry) => _backupService.deleteBackup(entry);

  Future<Map<SkillTargetTool, SkillImportSummary>?> importFromAllTools() {
    return executeAsync(() async {
      final result = await _syncService.importFromAllTools();
      await loadSkills(showLoading: false);
      return result;
    });
  }

  Future<String> getStorageLocation() => _pathService.getStorageLocation();

  Future<({int moved, int skipped})?> migrateStorage(String location) {
    return executeAsync(() async {
      final result = await _syncService.migrateStorage(location);
      await loadSkills(showLoading: false);
      return result;
    });
  }

  Future<void> _syncEnabled(Iterable<SkillTargetTool> tools) async {
    for (final tool in tools.toSet()) {
      await _syncService.syncToTool(tool);
    }
  }

  Future<void> _reconcileFilesystemWithDatabase() async {
    final scanned = await _storeService.scanSkills();
    final existing = await _databaseService.getAllSkills();
    final existingPaths = existing.map((s) => s.relativePath).toSet();

    for (final item in scanned) {
      if (existingPaths.contains(item.relativePath)) continue;

      final now = DateTime.now();
      await _databaseService.addSkill(
        Skill(
          skillId: path.basename(item.relativePath),
          relativePath: item.relativePath,
          name: item.parsed.name,
          description: item.parsed.description,
          enabledTools: const [],
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }
}

/// deleteSkill 已自行决定是否移除工具条目，备份时不再重复处理
class _NoopRemoveSync extends SkillsSyncService {
  @override
  Future<void> removeSkillFromTools(Skill skill) async {}
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
