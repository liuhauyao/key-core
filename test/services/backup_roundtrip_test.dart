import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/models/skill.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/export_service.dart';
import 'package:key_core/services/import_service.dart';
import 'package:key_core/services/mcp_database_service.dart';
import 'package:key_core/services/platform_registry.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:key_core/services/skills/skills_market_service.dart';
import 'package:key_core/services/skills_database_service.dart';
import 'package:key_core/services/skills_path_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 导出 → 清空数据库 → 导入 的完整往返：密钥（含 Desktop 字段、稳定平台 ID）、MCP（含按工具启用）、
/// 提示词、Skills（仓库列表 + 记录），以及导出文件权限。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late String home;

  Future<void> freshDb() async {
    await DatabaseService.instance.close();
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('backup_roundtrip_');
    home = p.join(tmp.path, 'home');
    Directory(home).createSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SettingsService.debugHomeDirOverride = home;
    SkillsPathService.debugHomeDirOverride = home;
    PlatformRegistry.initBuiltinPlatforms();
    await freshDb();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    SettingsService.debugHomeDirOverride = null;
    SkillsPathService.debugHomeDirOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('export → wipe → import restores keys, MCP apps, prompts and skills', () async {
    final now = DateTime(2026, 10, 10);
    await DatabaseService.instance.insertKey(AIKey(
      name: 'DS',
      platform: 'DeepSeek',
      platformType: PlatformType.deepSeek,
      keyValue: 'sk-ds',
      tags: const ['a'],
      createdAt: now,
      updatedAt: now,
      enableClaudeDesktop: true,
      claudeDesktopBaseUrl: 'https://api.deepseek.com/anthropic',
      claudeDesktopModel: 'deepseek-v4-pro',
      enableGemini: false,
      geminiModel: 'gemini-x',
    ));
    final mcp = McpDatabaseService();
    await mcp.addMcpServer(McpServer(
      serverId: 'fetch',
      name: 'Fetch',
      serverType: McpServerType.stdio,
      command: 'uvx',
      args: const ['mcp-server-fetch'],
      env: const {'TOKEN': 'secret'},
      createdAt: now,
      updatedAt: now,
    ));
    await mcp.setServerApp('fetch', AiToolType.claudecode, true);
    await mcp.setServerApp('fetch', AiToolType.hermes, true);
    final db = await DatabaseService.instance.database;
    await db.insert('prompts', {
      'tool': 'claudecode',
      'name': 'Team rules',
      'content': '# rules',
      'enabled': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    // 一个文件存在的 Skill、一个文件已丢失的 Skill
    final store = await SkillsPathService().getSkillsSourceDir();
    Directory(p.join(store, 'pdf')).createSync(recursive: true);
    File(p.join(store, 'pdf', 'SKILL.md')).writeAsStringSync('---\nname: pdf\n---\n');
    final skills = SkillsDatabaseService();
    for (final id in ['pdf', 'gone']) {
      await skills.addSkill(Skill(
        skillId: id,
        relativePath: id,
        name: id,
        enabledTools: const [SkillTargetTool.claudecode],
        sourceRepo: 'anthropics/skills',
        sourceSubdir: 'skills/$id',
        createdAt: now,
        updatedAt: now,
      ));
    }
    await SkillsMarketService().saveRepos([
      ...SkillsMarketService.defaultRepos,
      const SkillRepo(owner: 'me', name: 'my-skills', branch: 'main'),
    ]);

    final out = p.join(tmp.path, 'export.json');
    await ExportService().exportKeys(out);
    if (!Platform.isWindows) expect(File(out).statSync().mode & 0x1FF, 0x180, reason: '导出文件含明文密钥，应为 0600');
    final data = jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>;
    final k = (data['keys'] as List).single as Map;
    expect(k['platform_type_id'], 'deepSeek');
    expect(k['claude_desktop_model'], 'deepseek-v4-pro');
    expect(k['gemini_model'], 'gemini-x');
    expect((data['mcp_servers'] as List).single['enabled_tools'], ['claudecode', 'hermes']);
    expect((data['prompts'] as List).single['name'], 'Team rules');
    expect(((data['skills'] as Map)['items'] as List).map((e) => e['skill_id']), ['pdf', 'gone']);

    // 清空：新数据库 + 默认仓库列表
    await freshDb();
    await SkillsMarketService().saveRepos(SkillsMarketService.defaultRepos);

    final r = await ImportService().importKeys(out, null);
    expect(r.success, isTrue, reason: r.errors.join('\n'));
    expect(r.importedCount, 1);
    expect(r.promptCount, 1);
    expect(r.skillCount, 1);
    expect(r.skillRepoCount, 1);
    expect(r.errors.single, contains('gone'), reason: '文件丢失的 Skill 提示需重新安装');

    final key = (await DatabaseService.instance.getAllKeys()).single;
    expect(key.platformType.id, 'deepSeek');
    expect(key.keyValue, 'sk-ds');
    expect(key.claudeDesktopModel, 'deepseek-v4-pro');
    expect(key.geminiModel, 'gemini-x');
    expect(await McpDatabaseService().getServerApps('fetch'), {AiToolType.claudecode, AiToolType.hermes});
    final prompts = await (await DatabaseService.instance.database).query('prompts');
    expect(prompts.single['enabled'], 0, reason: '导入的提示词不自动启用（避免数据库与 CLAUDE.md 不一致）');
    final restored = await SkillsDatabaseService().getAllSkills();
    expect(restored.map((s) => s.skillId), ['pdf']);
    expect(restored.single.sourceRepo, 'anthropics/skills');
    expect((await SkillsMarketService().getRepos()).map((r) => r.fullName), contains('me/my-skills'));

    // 再导入一次：不重复
    final again = await ImportService().importKeys(out, null);
    expect(again.importedCount, 0);
    expect(again.updatedCount, 1);
    expect(again.promptCount, 0);
    expect(again.skillCount, 0);
    expect(again.skillRepoCount, 0);
  });

  test('old export files (index-only platform_type, no extras) still import', () async {
    final out = p.join(tmp.path, 'old.json');
    File(out).writeAsStringSync(jsonEncode({
      'version': '1.0.0',
      'keys': [
        {'name': 'Old', 'platform': 'DeepSeek', 'platform_type': 999, 'key_value': 'sk-old'}
      ],
    }));
    final r = await ImportService().importKeys(out, null);
    expect(r.success, isTrue, reason: r.errors.join());
    expect(r.importedCount, 1);
    expect((await DatabaseService.instance.getAllKeys()).single.platformType.id, 'deepSeek');
  });
}
