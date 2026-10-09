import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/models/prompt.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';
import 'package:key_core/services/prompts/prompt_service.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late String home;
  late Map<AiToolType, String> dirs;
  late PromptService service;

  Prompt draft(AiToolType tool, String name, String content, {bool enabled = false}) => Prompt(
        tool: tool,
        name: name,
        content: content,
        enabled: enabled,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  File fileOf(AiToolType tool) => File(p.join(dirs[tool]!, PromptService.fileNameFor(tool)));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('prompts_test_');
    home = p.join(tmp.path, 'home');
    dirs = {
      AiToolType.claudecode: p.join(home, '.claude'),
      AiToolType.codex: p.join(home, '.codex'),
      AiToolType.gemini: p.join(home, '.gemini'),
      AiToolType.grokBuild: p.join(home, '.grok'),
      AiToolType.opencode: p.join(home, '.config', 'opencode'),
      AiToolType.openclaw: p.join(home, '.openclaw'),
      AiToolType.hermes: p.join(home, '.hermes'),
      AiToolType.pi: p.join(home, '.pi', 'agent'),
      AiToolType.mcode: p.join(home, '.minimax'),
    };
    SharedPreferences.setMockInitialValues({
      for (final e in dirs.entries) 'ai_tool_config_dir_${e.key.value}': e.value,
    });
    SettingsService.debugHomeDirOverride = home;
    LiveConfigWriter.debugBackupRootOverride = p.join(tmp.path, 'backups');
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    await DatabaseService.instance.close();
    service = PromptService();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    SettingsService.debugHomeDirOverride = null;
    LiveConfigWriter.debugBackupRootOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('各工具提示词文件名与 CC Switch 一致，Claude Desktop 不支持', () async {
    expect(PromptService.fileNameFor(AiToolType.claudecode), 'CLAUDE.md');
    expect(PromptService.fileNameFor(AiToolType.codex), 'AGENTS.md');
    expect(PromptService.fileNameFor(AiToolType.gemini), 'GEMINI.md');
    expect(PromptService.fileNameFor(AiToolType.hermes), 'SOUL.md');
    for (final t in [AiToolType.grokBuild, AiToolType.opencode, AiToolType.openclaw, AiToolType.pi, AiToolType.mcode]) {
      expect(PromptService.fileNameFor(t), 'AGENTS.md');
    }
    expect(() => PromptService.fileNameFor(AiToolType.claudeDesktop), throwsUnsupportedError);
    expect(await service.promptFilePath(AiToolType.pi), p.join(home, '.pi', 'agent', 'AGENTS.md'));
  });

  test('启用时独占写入文件；切换时回填 live 文件到原启用项', () async {
    final a = await service.upsert(draft(AiToolType.claudecode, 'A', 'alpha'));
    final b = await service.upsert(draft(AiToolType.claudecode, 'B', 'beta'));
    expect(fileOf(AiToolType.claudecode).existsSync(), isFalse, reason: '新建未启用的条目不写文件');

    await service.enable(AiToolType.claudecode, a.id!);
    expect(fileOf(AiToolType.claudecode).readAsStringSync(), 'alpha');

    // 用户在外部编辑器里改了 CLAUDE.md
    fileOf(AiToolType.claudecode).writeAsStringSync('alpha edited');
    await service.enable(AiToolType.claudecode, b.id!);
    expect(fileOf(AiToolType.claudecode).readAsStringSync(), 'beta');

    final list = await service.getPrompts(AiToolType.claudecode);
    expect(list.where((x) => x.enabled).map((x) => x.name), ['B']);
    expect(list.firstWhere((x) => x.name == 'A').content, 'alpha edited');
  });

  test('没有启用项时，启用前把已有文件备份为“原始提示词”（内容相同不重复备份）', () async {
    fileOf(AiToolType.codex)
      ..createSync(recursive: true)
      ..writeAsStringSync('hand written');
    final x = await service.upsert(draft(AiToolType.codex, 'X', 'new'));
    await service.enable(AiToolType.codex, x.id!);
    expect(fileOf(AiToolType.codex).readAsStringSync(), 'new');
    final list = await service.getPrompts(AiToolType.codex);
    final backup = list.singleWhere((x) => x.name.startsWith('原始提示词'));
    expect(backup.content, 'hand written');
    expect(backup.enabled, isFalse);

    await service.disable(AiToolType.codex, x.id!);
    fileOf(AiToolType.codex).writeAsStringSync('hand written');
    await service.enable(AiToolType.codex, x.id!);
    expect((await service.getPrompts(AiToolType.codex)).where((x) => x.name.startsWith('原始提示词')), hasLength(1));
  });

  test('停用最后一条启用项会清空文件；保存未启用条目不动文件；启用项不能删除', () async {
    final a = await service.upsert(draft(AiToolType.gemini, 'A', 'alpha', enabled: true));
    expect(fileOf(AiToolType.gemini).readAsStringSync(), 'alpha');
    await service.upsert(draft(AiToolType.gemini, 'B', 'beta'));
    expect(fileOf(AiToolType.gemini).readAsStringSync(), 'alpha');

    await expectLater(service.delete(AiToolType.gemini, a.id!), throwsStateError);
    await service.disable(AiToolType.gemini, a.id!);
    expect(fileOf(AiToolType.gemini).readAsStringSync(), '');
    await service.delete(AiToolType.gemini, a.id!);
    expect((await service.getPrompts(AiToolType.gemini)).map((x) => x.name), ['B']);
  });

  test('编辑启用中的条目会同步写文件；外部修改会在列表时回填', () async {
    final a = await service.upsert(draft(AiToolType.hermes, 'Soul', 'v1', enabled: true));
    await service.upsert(a.copyWith(content: 'v2'));
    expect(fileOf(AiToolType.hermes).readAsStringSync(), 'v2');
    fileOf(AiToolType.hermes).writeAsStringSync('v3 external');
    expect((await service.getPrompts(AiToolType.hermes)).single.content, 'v3 external');
  });

  test('写入经过 LiveConfigWriter：覆盖前留有备份', () async {
    fileOf(AiToolType.opencode)
      ..createSync(recursive: true)
      ..writeAsStringSync('original');
    final a = await service.upsert(draft(AiToolType.opencode, 'A', 'alpha'));
    await service.enable(AiToolType.opencode, a.id!);
    final backups = Directory(p.join(tmp.path, 'backups'))
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.readAsStringSync() == 'original');
    expect(backups, isNotEmpty);
  });

  test('从文件导入为未启用条目；文件不存在时报错', () async {
    await expectLater(service.importFromFile(AiToolType.grokBuild), throwsStateError);
    fileOf(AiToolType.grokBuild)
      ..createSync(recursive: true)
      ..writeAsStringSync('grok rules');
    final imported = await service.importFromFile(AiToolType.grokBuild);
    expect(imported.content, 'grok rules');
    expect(imported.enabled, isFalse);
    expect(fileOf(AiToolType.grokBuild).readAsStringSync(), 'grok rules');
  });

  test('首次使用自动导入：已有文件导入为启用项，只执行一次', () async {
    fileOf(AiToolType.claudecode)
      ..createSync(recursive: true)
      ..writeAsStringSync('my claude rules');
    fileOf(AiToolType.pi)
      ..createSync(recursive: true)
      ..writeAsStringSync('   ');
    expect(await service.importOnFirstLaunch(), 1);
    final list = await service.getPrompts(AiToolType.claudecode);
    expect(list.single.enabled, isTrue);
    expect(list.single.content, 'my claude rules');
    expect(await service.getPrompts(AiToolType.pi), isEmpty);

    await service.delete(AiToolType.claudecode, list.single.id!).catchError((_) {});
    expect(await service.importOnFirstLaunch(), 0);
  });

  test('MiniMax Code 内容超过 32 KiB 被拒绝且不写文件', () async {
    final big = 'x' * (PromptService.mcodeMaxBytes + 1);
    await expectLater(service.upsert(draft(AiToolType.mcode, 'Big', big, enabled: true)), throwsArgumentError);
    expect(fileOf(AiToolType.mcode).existsSync(), isFalse);
  });

  test('数据库 v21 创建 prompts 表', () async {
    final db = await DatabaseService.instance.database;
    final cols = (await db.rawQuery('PRAGMA table_info(prompts)')).map((r) => r['name']).toSet();
    expect(cols, containsAll(['tool', 'name', 'content', 'description', 'enabled']));
    expect(DatabaseService.schemaVersion, 21);
  });
}
