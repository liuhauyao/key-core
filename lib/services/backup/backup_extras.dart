import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/mcp_server.dart';
import '../../models/skill.dart';
import '../database_service.dart';
import '../mcp_database_service.dart';
import '../skills/skills_market_service.dart';
import '../skills_database_service.dart';
import '../skills_path_service.dart';

/// 导出 / 导入中除密钥、MCP 服务本体、官方 Key 以外的部分：
/// - MCP 按工具启用关系（`mcp_server_apps`）
/// - 系统提示词（`prompts`）
/// - Skills：仓库列表 + Skill 记录（元数据；Skill 文件本身不在导出文件中）
///
/// 导入策略（保证数据库与工具配置文件一致）：
/// - 只写数据库，不直接写任何工具配置文件；
/// - 提示词一律以“未启用”导入（启用会改写 CLAUDE.md 等文件，需要用户在提示词页手动启用）；
/// - MCP 启用关系只记录，用户在 MCP 页“重新写入全部已启用的服务”后才写入工具；
/// - Skill 记录仅在其文件仍在 Skills 存储目录中时恢复，否则提示需重新安装。
class BackupExtras {
  BackupExtras({
    DatabaseService? db,
    McpDatabaseService? mcp,
    SkillsDatabaseService? skills,
    SkillsMarketService? market,
    SkillsPathService? skillsPath,
  })  : _db = db ?? DatabaseService.instance,
        _mcp = mcp ?? McpDatabaseService(),
        _skills = skills ?? SkillsDatabaseService(),
        _market = market,
        _skillsPath = skillsPath ?? SkillsPathService();

  final DatabaseService _db;
  final McpDatabaseService _mcp;
  final SkillsDatabaseService _skills;
  final SkillsMarketService? _market;
  final SkillsPathService _skillsPath;

  SkillsMarketService get _marketService => _market ?? SkillsMarketService();

  /// MCP serverId → 启用的工具（写入每个 mcp_servers 条目的 `enabled_tools`）
  Future<Map<String, List<String>>> mcpEnabledTools() async {
    final apps = await _mcp.getAllServerApps();
    return {for (final e in apps.entries) e.key: (e.value.map((t) => t.value).toList()..sort())};
  }

  Future<List<Map<String, dynamic>>> exportPrompts() async {
    final db = await _db.database;
    final rows = await db.query('prompts', orderBy: 'tool ASC, id ASC');
    return rows.map((r) => Map<String, dynamic>.from(r)..remove('id')).toList();
  }

  Future<Map<String, dynamic>> exportSkills() async {
    final repos = await _marketService.getRepos();
    final items = (await _skills.getAllSkills()).map((s) {
      final m = s.toMap()..remove('id');
      m.remove('sync_status'); // 同步状态依赖本机工具目录，导入后重新计算
      return m;
    }).toList();
    return {'repos': repos.map((r) => r.toJson()).toList(), 'items': items};
  }

  /// 导入 MCP 启用关系（只写数据库）
  Future<int> importMcpEnabledTools(String serverId, Object? tools) async {
    if (tools is! List) return 0;
    var n = 0;
    for (final t in tools) {
      final tool = AiToolType.values.where((x) => x.value == t).firstOrNull;
      if (tool == null) continue;
      await _mcp.setServerApp(serverId, tool, true);
      n++;
    }
    return n;
  }

  /// 导入提示词：同一工具下名称与内容都相同的跳过；一律以未启用状态导入
  Future<int> importPrompts(Object? data, List<String> errors) async {
    if (data is! List) return 0;
    final db = await _db.database;
    var n = 0;
    for (final item in data) {
      try {
        final m = Map<String, dynamic>.from(item as Map);
        final tool = m['tool'] as String?;
        final name = m['name'] as String?;
        final content = m['content'] as String?;
        if (tool == null || name == null || content == null) continue;
        if (AiToolType.values.every((t) => t.value != tool)) continue;
        final dup = await db.query('prompts',
            where: 'tool = ? AND name = ? AND content = ?', whereArgs: [tool, name, content], limit: 1);
        if (dup.isNotEmpty) continue;
        final now = DateTime.now().toIso8601String();
        await db.insert('prompts', {
          'tool': tool,
          'name': name,
          'content': content,
          'description': m['description'],
          'enabled': 0,
          'created_at': m['created_at'] ?? now,
          'updated_at': m['updated_at'] ?? now,
        });
        n++;
      } catch (e) {
        errors.add('导入提示词失败: $e');
      }
    }
    return n;
  }

  /// 导入 Skills：合并仓库列表；恢复文件仍存在但数据库中缺失的 Skill 记录
  Future<({int repos, int skills, List<String> missing})> importSkills(Object? data, List<String> errors) async {
    final missing = <String>[];
    if (data is! Map) return (repos: 0, skills: 0, missing: missing);
    var repoCount = 0;
    var skillCount = 0;
    try {
      final current = await _marketService.getRepos();
      final known = current.map((r) => r.fullName.toLowerCase()).toSet();
      final merged = [...current];
      for (final r in (data['repos'] as List? ?? const [])) {
        try {
          final repo = SkillRepo.fromJson(Map<String, dynamic>.from(r as Map));
          if (known.add(repo.fullName.toLowerCase())) {
            merged.add(repo);
            repoCount++;
          }
        } catch (_) {}
      }
      if (repoCount > 0) await _marketService.saveRepos(merged);
    } catch (e) {
      errors.add('导入 Skills 仓库失败: $e');
    }

    final root = await _skillsPath.getSkillsSourceDir();
    for (final item in (data['items'] as List? ?? const [])) {
      try {
        final m = Map<String, dynamic>.from(item as Map)..remove('id');
        final skillId = m['skill_id'] as String?;
        final rel = m['relative_path'] as String?;
        if (skillId == null || rel == null) continue;
        if (await _skills.getSkillBySkillId(skillId) != null || await _skills.relativePathExists(rel)) continue;
        // 防路径穿越：relative_path 必须落在存储目录内
        final dir = path.normalize(path.join(root, rel));
        if (!path.isWithin(root, dir) || !await File(path.join(dir, 'SKILL.md')).exists()) {
          missing.add((m['name'] as String?) ?? skillId);
          continue;
        }
        m['sync_status'] = jsonEncode(const {});
        await _skills.addSkill(Skill.fromMap(m));
        skillCount++;
      } catch (e) {
        errors.add('导入 Skill 记录失败: $e');
      }
    }
    if (missing.isNotEmpty) {
      errors.add('以下 Skill 的文件不在本机 Skills 存储目录中，需要重新安装：${missing.join('、')}');
    }
    return (repos: repoCount, skills: skillCount, missing: missing);
  }
}
