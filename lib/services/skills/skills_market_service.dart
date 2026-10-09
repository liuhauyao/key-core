import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/skill.dart';
import '../skill_parser_service.dart';
import '../skills_database_service.dart';
import '../skills_path_service.dart';
import '../skills_store_service.dart';
import 'skills_backup_service.dart';
import 'skills_fs.dart';

/// Skills 仓库（GitHub）
class SkillRepo {
  final String owner;
  final String name;

  /// 分支；为空表示默认分支（HEAD）
  final String? branch;
  final bool enabled;

  const SkillRepo({required this.owner, required this.name, this.branch, this.enabled = true});

  String get fullName => '$owner/$name';

  /// GitHub zip 下载地址（codeload）
  Uri get zipUrl => Uri.parse(branch == null || branch!.isEmpty
      ? 'https://codeload.github.com/$owner/$name/zip/HEAD'
      : 'https://codeload.github.com/$owner/$name/zip/refs/heads/$branch');

  Map<String, dynamic> toJson() =>
      {'owner': owner, 'name': name, if (branch != null) 'branch': branch, 'enabled': enabled};

  factory SkillRepo.fromJson(Map<String, dynamic> json) => SkillRepo(
        owner: json['owner'] as String,
        name: json['name'] as String,
        branch: json['branch'] as String?,
        enabled: json['enabled'] as bool? ?? true,
      );

  /// 解析 `owner/name`、`owner/name@branch` 或 GitHub URL
  static SkillRepo? parse(String input) {
    var s = input.trim();
    s = s.replaceFirst(RegExp(r'^https?://github\.com/'), '').replaceFirst(RegExp(r'\.git$'), '');
    String? branch;
    final tree = RegExp(r'^([^/]+)/([^/]+)/tree/([^/]+)').firstMatch(s);
    if (tree != null) {
      return SkillRepo(owner: tree.group(1)!, name: tree.group(2)!, branch: tree.group(3));
    }
    final at = s.indexOf('@');
    if (at > 0) {
      branch = s.substring(at + 1);
      s = s.substring(0, at);
    }
    final parts = s.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length != 2) return null;
    final valid = RegExp(r'^[A-Za-z0-9_.-]+$');
    if (!valid.hasMatch(parts[0]) || !valid.hasMatch(parts[1])) return null;
    return SkillRepo(owner: parts[0], name: parts[1], branch: branch);
  }
}

/// 仓库中可安装的 Skill
class RemoteSkill {
  final SkillRepo repo;

  /// 在仓库中的相对目录（`/` 分隔；仓库根即 Skill 时为空串）
  final String subdir;
  final String directoryName;
  final String name;
  final String? description;
  final String contentHash;

  /// 是否已安装（同仓库同目录）
  final bool installed;

  const RemoteSkill({
    required this.repo,
    required this.subdir,
    required this.directoryName,
    required this.name,
    this.description,
    required this.contentHash,
    this.installed = false,
  });
}

/// skills.sh 搜索结果
class SkillsShResult {
  final String id;
  final String source;
  final String skillId;
  final String name;
  final int installs;

  const SkillsShResult({
    required this.id,
    required this.source,
    required this.skillId,
    required this.name,
    required this.installs,
  });

  factory SkillsShResult.fromJson(Map<String, dynamic> json) => SkillsShResult(
        id: json['id']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        skillId: json['skillId']?.toString() ?? json['name']?.toString() ?? '',
        name: json['name']?.toString() ?? json['skillId']?.toString() ?? '',
        installs: (json['installs'] as num?)?.toInt() ?? 0,
      );
}

/// 更新检查结果
class SkillUpdateInfo {
  final Skill skill;
  final String? remoteHash;
  final bool hasUpdate;

  /// 本地内容与安装时记录的哈希不一致（用户改过）
  final bool locallyModified;
  final String? error;

  const SkillUpdateInfo({
    required this.skill,
    this.remoteHash,
    this.hasUpdate = false,
    this.locallyModified = false,
    this.error,
  });
}

/// Skills 市场服务：仓库管理、GitHub zip 下载安装、skills.sh 搜索、ZIP 安装、更新检查
class SkillsMarketService {
  SkillsMarketService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final SkillsPathService _pathService = SkillsPathService();
  final SkillsStoreService _storeService = SkillsStoreService();
  final SkillsDatabaseService _databaseService = SkillsDatabaseService();
  final SkillParserService _parserService = SkillParserService();
  final SkillsBackupService _backupService = SkillsBackupService();

  static const String reposKey = 'skills_repos';

  /// 与 CC Switch v4.0.6 相同的默认仓库
  static const List<SkillRepo> defaultRepos = [
    SkillRepo(owner: 'anthropics', name: 'skills', branch: 'main'),
    SkillRepo(owner: 'ComposioHQ', name: 'awesome-claude-skills', branch: 'master'),
    SkillRepo(owner: 'cexll', name: 'myclaude', branch: 'master'),
    SkillRepo(owner: 'JimLiu', name: 'baoyu-skills', branch: 'main'),
  ];

  /// 本次运行内的仓库解压缓存（key: owner/name@branch）
  final Map<String, String> _extracted = {};

  // ========== 仓库管理 ==========

  Future<List<SkillRepo>> getRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(reposKey);
    if (raw == null) return List.of(defaultRepos);
    try {
      return (jsonDecode(raw) as List)
          .map((e) => SkillRepo.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return List.of(defaultRepos);
    }
  }

  Future<void> saveRepos(List<SkillRepo> repos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(reposKey, jsonEncode(repos.map((r) => r.toJson()).toList()));
  }

  Future<List<SkillRepo>> addRepo(SkillRepo repo) async {
    final repos = await getRepos();
    repos.removeWhere((r) => r.fullName.toLowerCase() == repo.fullName.toLowerCase());
    repos.add(repo);
    await saveRepos(repos);
    return repos;
  }

  Future<List<SkillRepo>> removeRepo(String owner, String name) async {
    final repos = await getRepos();
    repos.removeWhere((r) =>
        r.owner.toLowerCase() == owner.toLowerCase() && r.name.toLowerCase() == name.toLowerCase());
    await saveRepos(repos);
    return repos;
  }

  // ========== 下载与发现 ==========

  /// 下载并解压仓库，返回仓库根目录（zip 内唯一的顶层目录）
  Future<String> downloadRepo(SkillRepo repo, {bool force = false}) async {
    final cacheKey = '${repo.fullName}@${repo.branch ?? 'HEAD'}';
    final cached = _extracted[cacheKey];
    if (!force && cached != null && await Directory(cached).exists()) return cached;

    final response = await _client.get(repo.zipUrl);
    if (response.statusCode != 200) {
      throw HttpException('下载仓库 ${repo.fullName} 失败: HTTP ${response.statusCode}', uri: repo.zipUrl);
    }
    final tmp = await Directory.systemTemp.createTemp('keycore-skill-repo-');
    await extractZipBytes(response.bodyBytes, tmp.path);
    final root = await _singleTopLevelDir(tmp.path);
    _extracted[cacheKey] = root;
    return root;
  }

  /// 列出仓库中的 Skill
  Future<List<RemoteSkill>> listRepoSkills(SkillRepo repo, {bool force = false}) async {
    final root = await downloadRepo(repo, force: force);
    final installed = await _databaseService.getAllSkills();
    final result = <RemoteSkill>[];
    for (final dir in await SkillsFs.findSkillDirs(root)) {
      final parsed = await _parserService.readSkillFromDir(Directory(dir));
      final rel = path.relative(dir, from: root).replaceAll('\\', '/');
      final subdir = rel == '.' ? '' : rel;
      result.add(RemoteSkill(
        repo: repo,
        subdir: subdir,
        directoryName: subdir.isEmpty ? repo.name : path.basename(dir),
        name: parsed?.name ?? path.basename(dir),
        description: parsed?.description,
        contentHash: await SkillsFs.computeDirHash(dir),
        installed: installed.any((s) =>
            s.sourceRepo?.toLowerCase() == repo.fullName.toLowerCase() &&
            (s.sourceSubdir ?? '') == subdir),
      ));
    }
    return result;
  }

  /// 列出所有启用仓库中的 Skill（单个仓库失败不影响其他仓库）
  Future<({List<RemoteSkill> skills, Map<String, String> errors})> discoverAll() async {
    final skills = <RemoteSkill>[];
    final errors = <String, String>{};
    for (final repo in (await getRepos()).where((r) => r.enabled)) {
      try {
        skills.addAll(await listRepoSkills(repo));
      } catch (e) {
        errors[repo.fullName] = e.toString();
      }
    }
    return (skills: skills, errors: errors);
  }

  /// 安装仓库中的 Skill 到 Key Core 存储
  Future<Skill> installRemote(
    RemoteSkill remote, {
    List<SkillTargetTool> enabledTools = const [],
  }) async {
    final root = await downloadRepo(remote.repo);
    final dir = remote.subdir.isEmpty ? root : path.join(root, remote.subdir);
    return _installFromDir(
      dir,
      dirName: remote.directoryName,
      enabledTools: enabledTools,
      sourceRepo: remote.repo.fullName,
      sourceRef: remote.repo.branch,
      sourceSubdir: remote.subdir,
    );
  }

  // ========== skills.sh ==========

  Future<List<SkillsShResult>> searchSkillsSh(String query, {int limit = 20, int offset = 0}) async {
    final uri = Uri.https('skills.sh', '/api/search', {
      'q': query,
      'limit': '$limit',
      'offset': '$offset',
    });
    final response = await _client.get(uri, headers: {'Accept': 'application/json'});
    if (response.statusCode != 200) {
      throw HttpException('skills.sh 搜索失败: HTTP ${response.statusCode}', uri: uri);
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final list = data is Map ? data['skills'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => SkillsShResult.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.source.contains('/') && r.skillId.isNotEmpty)
        .toList();
  }

  /// 安装 skills.sh 搜索结果：下载其来源仓库（默认分支），按目录名 → 唯一 metadata 名 → 仓库根定位 Skill
  Future<Skill> installFromSkillsSh(
    SkillsShResult result, {
    List<SkillTargetTool> enabledTools = const [],
  }) async {
    final repo = SkillRepo.parse(result.source);
    if (repo == null) throw StateError('无效的来源仓库: ${result.source}');
    final skills = await listRepoSkills(repo);
    final target = resolveRemoteSkill(skills, result.skillId);
    if (target == null) {
      throw StateError('在 ${repo.fullName} 中未找到 Skill "${result.skillId}"');
    }
    return installRemote(target, enabledTools: enabledTools);
  }

  /// 在仓库扫描结果中定位 Skill：目录名优先，其次唯一 metadata name，最后仓库根
  static RemoteSkill? resolveRemoteSkill(List<RemoteSkill> skills, String skillId) {
    final id = skillId.toLowerCase();
    for (final s in skills) {
      if (s.subdir.isNotEmpty && path.basename(s.subdir).toLowerCase() == id) return s;
    }
    final byName = skills.where((s) => s.name.trim().toLowerCase() == id).toList();
    if (byName.length == 1) return byName.first;
    if (byName.length > 1) return null;
    for (final s in skills) {
      if (s.subdir.isEmpty) return s;
    }
    return null;
  }

  // ========== ZIP 安装 ==========

  /// 从本地 ZIP 安装（支持包含多个 Skill 的压缩包）
  Future<List<Skill>> installFromZip(
    String zipPath, {
    List<SkillTargetTool> enabledTools = const [],
  }) async {
    final tmp = await Directory.systemTemp.createTemp('keycore-skill-zip-');
    try {
      await extractZipBytes(await File(zipPath).readAsBytes(), tmp.path);
      final dirs = await SkillsFs.findSkillDirs(tmp.path);
      if (dirs.isEmpty) throw StateError('ZIP 中没有找到 SKILL.md');
      final installed = <Skill>[];
      for (final dir in dirs) {
        final isRoot = path.equals(dir, tmp.path);
        final parsed = await _parserService.readSkillFromDir(Directory(dir));
        final dirName = isRoot
            ? SkillsFs.sanitizeDirName(parsed?.name ?? path.basenameWithoutExtension(zipPath))
            : path.basename(dir);
        installed.add(await _installFromDir(dir, dirName: dirName, enabledTools: enabledTools));
      }
      return installed;
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  // ========== 更新 ==========

  /// 检查所有来自仓库的 Skill 是否有更新（比较远端目录哈希与安装时记录的哈希）
  Future<List<SkillUpdateInfo>> checkUpdates() async {
    final skills = (await _databaseService.getAllSkills())
        .where((s) => s.sourceRepo != null && s.sourceRepo!.isNotEmpty)
        .toList();
    final result = <SkillUpdateInfo>[];
    for (final skill in skills) {
      final repo = SkillRepo.parse(skill.sourceRepo!);
      if (repo == null) continue;
      try {
        final root = await downloadRepo(
            SkillRepo(owner: repo.owner, name: repo.name, branch: skill.sourceRef));
        final subdir = skill.sourceSubdir ?? '';
        final dir = subdir.isEmpty ? root : path.join(root, subdir);
        if (!await File(path.join(dir, SkillParserService.skillFileName)).exists()) {
          result.add(SkillUpdateInfo(skill: skill, error: '远端已不存在该 Skill'));
          continue;
        }
        final remoteHash = await SkillsFs.computeDirHash(dir);
        final localDir = await _pathService.getSkillSourcePath(skill.relativePath);
        final localHash =
            await Directory(localDir).exists() ? await SkillsFs.computeDirHash(localDir) : null;
        result.add(SkillUpdateInfo(
          skill: skill,
          remoteHash: remoteHash,
          hasUpdate: skill.contentHash == null
              ? remoteHash != localHash
              : remoteHash != skill.contentHash,
          locallyModified: skill.contentHash != null && localHash != skill.contentHash,
        ));
      } catch (e) {
        result.add(SkillUpdateInfo(skill: skill, error: e.toString()));
      }
    }
    return result;
  }

  /// 更新单个 Skill：先把当前内容备份到 skill-backups，再替换为远端内容
  Future<Skill> updateSkill(Skill skill) async {
    final repo = SkillRepo.parse(skill.sourceRepo ?? '');
    if (repo == null) throw StateError('该 Skill 不是从仓库安装的');
    final root =
        await downloadRepo(SkillRepo(owner: repo.owner, name: repo.name, branch: skill.sourceRef));
    final subdir = skill.sourceSubdir ?? '';
    final remoteDir = subdir.isEmpty ? root : path.join(root, subdir);
    if (!await File(path.join(remoteDir, SkillParserService.skillFileName)).exists()) {
      throw StateError('远端已不存在该 Skill');
    }
    final localDir = await _pathService.getSkillSourcePath(skill.relativePath);
    if (await Directory(localDir).exists()) {
      await _backupService.backupDirectory(skill, localDir, reason: 'update');
    }
    // 先复制到临时目录再替换，避免中途失败留下半个目录
    final staging = '$localDir.keycore-staging';
    if (await Directory(staging).exists()) await Directory(staging).delete(recursive: true);
    await SkillsFs.copyDirectory(remoteDir, staging);
    if (await Directory(localDir).exists()) await Directory(localDir).delete(recursive: true);
    await Directory(staging).rename(localDir);

    final parsed = await _parserService.readSkillFromDir(Directory(localDir));
    final updated = skill.copyWith(
      name: parsed?.name ?? skill.name,
      description: parsed?.description ?? skill.description,
      contentHash: await SkillsFs.computeDirHash(localDir),
      updatedAt: DateTime.now(),
    );
    await _databaseService.updateSkill(updated);
    return updated;
  }

  // ========== 内部 ==========

  Future<Skill> _installFromDir(
    String dir, {
    required String dirName,
    required List<SkillTargetTool> enabledTools,
    String? sourceRepo,
    String? sourceRef,
    String? sourceSubdir,
  }) async {
    final parsed = await _parserService.readSkillFromDir(Directory(dir));
    if (parsed == null) throw StateError('缺少 SKILL.md: $dir');

    if (sourceRepo != null) {
      final existing = (await _databaseService.getAllSkills()).where((s) =>
          s.sourceRepo?.toLowerCase() == sourceRepo.toLowerCase() &&
          (s.sourceSubdir ?? '') == (sourceSubdir ?? ''));
      if (existing.isNotEmpty) {
        throw StateError('Skill "${parsed.name}" 已安装（${existing.first.relativePath}）');
      }
    }

    await _storeService.ensureSkillsRoot();
    var relativePath = SkillsFs.sanitizeDirName(dirName);
    if (await _databaseService.relativePathExists(relativePath) ||
        await _databaseService.skillIdExists(relativePath) ||
        await Directory(await _pathService.getSkillSourcePath(relativePath)).exists()) {
      relativePath = await _uniqueRelativePath(relativePath);
    }
    final dest = await _pathService.getSkillSourcePath(relativePath);
    await SkillsFs.copyDirectory(dir, dest);

    final now = DateTime.now();
    final skill = Skill(
      skillId: relativePath,
      relativePath: relativePath,
      name: parsed.name,
      description: parsed.description,
      enabledTools: enabledTools,
      isActive: true,
      sourceRepo: sourceRepo,
      sourceRef: sourceRef,
      sourceSubdir: sourceSubdir,
      contentHash: await SkillsFs.computeDirHash(dest),
      createdAt: now,
      updatedAt: now,
    );
    final id = await _databaseService.addSkill(skill);
    return skill.copyWith(id: id);
  }

  Future<String> _uniqueRelativePath(String base) async {
    for (var i = 2;; i++) {
      final candidate = '$base-$i';
      if (await _databaseService.relativePathExists(candidate) ||
          await _databaseService.skillIdExists(candidate)) {
        continue;
      }
      if (await Directory(await _pathService.getSkillSourcePath(candidate)).exists()) continue;
      return candidate;
    }
  }

  Future<String> _singleTopLevelDir(String dir) async {
    final entries = await Directory(dir).list().toList();
    final dirs = entries.whereType<Directory>().toList();
    if (dirs.length == 1 && entries.length == 1) return dirs.first.path;
    return dir;
  }

  /// 解压 ZIP 字节到目标目录（拒绝 zip-slip 路径穿越与符号链接条目）
  static Future<void> extractZipBytes(List<int> bytes, String destination) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final destRoot = path.normalize(path.absolute(destination));
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.isEmpty || name.startsWith('__MACOSX/')) continue;
      final outPath = path.normalize(path.join(destRoot, name));
      if (!path.isWithin(destRoot, outPath)) {
        throw StateError('ZIP 包含非法路径: ${entry.name}');
      }
      if (entry.isSymbolicLink) continue;
      if (entry.isFile) {
        await Directory(path.dirname(outPath)).create(recursive: true);
        await File(outPath).writeAsBytes(entry.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
  }
}
