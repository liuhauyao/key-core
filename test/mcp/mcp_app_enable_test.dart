import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';
import 'package:key_core/services/mcp_database_service.dart';
import 'package:key_core/services/mcp_sync_service.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yaml/yaml.dart';

McpServer _server(String id, {McpServerType type = McpServerType.stdio}) => McpServer(
      serverId: id,
      name: id,
      serverType: type,
      command: type == McpServerType.stdio ? 'npx' : null,
      args: type == McpServerType.stdio ? ['-y', '@pkg/$id'] : null,
      url: type == McpServerType.stdio ? null : 'https://mcp.example/$id',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late Map<AiToolType, String> dirs;
  final db = McpDatabaseService();
  late McpSyncService sync;

  setUp(() async {
    // McpSyncService 缓存工具目录，每个测试用新实例
    sync = McpSyncService();
    tmp = Directory.systemTemp.createTempSync('mcp_apps_test_');
    final home = p.join(tmp.path, 'home');
    dirs = {
      AiToolType.opencode: p.join(home, '.config', 'opencode'),
      AiToolType.grokBuild: p.join(home, '.grok'),
      AiToolType.hermes: p.join(home, '.hermes'),
      AiToolType.pi: p.join(home, '.pi', 'agent'),
      AiToolType.mcode: p.join(home, '.minimax'),
      AiToolType.codex: p.join(home, '.codex'),
    };
    for (final d in dirs.values) {
      Directory(d).createSync(recursive: true);
    }
    SharedPreferences.setMockInitialValues({
      for (final e in dirs.entries) 'ai_tool_config_dir_${e.key.value}': e.value,
    });
    SettingsService.debugHomeDirOverride = home;
    LiveConfigWriter.debugBackupRootOverride = p.join(tmp.path, 'backups');
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    await DatabaseService.instance.close();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.debugDatabasePathOverride = null;
    SettingsService.debugHomeDirOverride = null;
    LiveConfigWriter.debugBackupRootOverride = null;
    tmp.deleteSync(recursive: true);
  });

  String file(AiToolType t, String name) => p.join(dirs[t]!, name);

  test('enabling writes each tool format; disabling removes; relation is stored', () async {
    final fs = _server('fs');
    await db.addMcpServer(fs);
    File(file(AiToolType.opencode, 'opencode.json'))
        .writeAsStringSync('{\n  "theme": "dark",\n  "mcp": {"mine": {"type": "local", "command": ["x"]}}\n}\n');
    File(file(AiToolType.grokBuild, 'config.toml')).writeAsStringSync('model = "grok-4"\n');
    File(file(AiToolType.hermes, 'config.yaml')).writeAsStringSync('model:\n  name: hermes-4\n');

    for (final t in [AiToolType.opencode, AiToolType.grokBuild, AiToolType.hermes, AiToolType.pi, AiToolType.mcode]) {
      await sync.setServerEnabledForTool(fs, t, true);
    }
    expect(await db.getServerApps('fs'), {
      AiToolType.opencode,
      AiToolType.grokBuild,
      AiToolType.hermes,
      AiToolType.pi,
      AiToolType.mcode,
    });

    final oc = jsonDecode(File(file(AiToolType.opencode, 'opencode.json')).readAsStringSync()) as Map;
    expect(oc['theme'], 'dark');
    expect(oc['mcp']['mine'], {'type': 'local', 'command': ['x']});
    expect(oc['mcp']['fs'], {'type': 'local', 'command': ['npx', '-y', '@pkg/fs'], 'enabled': true});

    final grok = File(file(AiToolType.grokBuild, 'config.toml')).readAsStringSync();
    expect(grok, startsWith('model = "grok-4"\n'));
    expect(grok, contains('[mcp_servers.fs]\ncommand = "npx"\nargs = ["-y", "@pkg/fs"]'));

    final hermes = loadYaml(File(file(AiToolType.hermes, 'config.yaml')).readAsStringSync()) as YamlMap;
    expect(hermes['model']['name'], 'hermes-4');
    expect(hermes['mcp_servers']['fs']['enabled'], true);

    final pi = jsonDecode(File(file(AiToolType.pi, 'mcp.json')).readAsStringSync()) as Map;
    expect(pi['mcpServers']['fs']['command'], 'npx');
    final mcode = jsonDecode(File(file(AiToolType.mcode, 'mcp.json')).readAsStringSync()) as Map;
    expect(mcode['mcpServers']['fs']['enabled'], true);

    // 读取（用于导入）
    final read = await sync.readMcpServersFromTool(AiToolType.opencode);
    expect(read.servers.keys, containsAll(['mine', 'fs']));
    expect(read.servers['fs']!.args, ['-y', '@pkg/fs']);
    expect((await sync.readMcpServersFromTool(AiToolType.hermes)).servers['fs']!.command, 'npx');
    expect((await sync.readMcpServersFromTool(AiToolType.grokBuild)).servers['fs']!.command, 'npx');

    // 停用
    await sync.setServerEnabledForTool(fs, AiToolType.opencode, false);
    await sync.setServerEnabledForTool(fs, AiToolType.hermes, false);
    final oc2 = jsonDecode(File(file(AiToolType.opencode, 'opencode.json')).readAsStringSync()) as Map;
    expect((oc2['mcp'] as Map).keys, ['mine']);
    expect(File(file(AiToolType.hermes, 'config.yaml')).readAsStringSync(), 'model:\n  name: hermes-4\n');
    expect(await db.getServerApps('fs'), isNot(contains(AiToolType.opencode)));
  });

  test('unsupported or unparsable targets fail without changing the relation', () async {
    final sse = _server('events', type: McpServerType.sse);
    await db.addMcpServer(sse);
    await expectLater(sync.setServerEnabledForTool(sse, AiToolType.pi, true), throwsStateError);

    final fs = _server('fs');
    await db.addMcpServer(fs);
    const broken = '{ "mcp": { oops';
    File(file(AiToolType.opencode, 'opencode.json')).writeAsStringSync(broken);
    await expectLater(sync.setServerEnabledForTool(fs, AiToolType.opencode, true), throwsA(anything));
    expect(File(file(AiToolType.opencode, 'opencode.json')).readAsStringSync(), broken);
    expect(await db.getServerApps('fs'), isEmpty);
    expect(await db.getServerApps('events'), isEmpty);
  });

  test('syncAllEnabled restores live configs; importFromTools adds and links servers', () async {
    final fs = _server('fs');
    await db.addMcpServer(fs);
    await sync.setServerEnabledForTool(fs, AiToolType.mcode, true);
    File(file(AiToolType.mcode, 'mcp.json')).writeAsStringSync('{"mcpServers": {}}');

    expect(await sync.syncAllEnabled(), {AiToolType.mcode: true});
    final mcode = jsonDecode(File(file(AiToolType.mcode, 'mcp.json')).readAsStringSync()) as Map;
    expect((mcode['mcpServers'] as Map).keys, ['fs']);

    File(file(AiToolType.codex, 'config.toml'))
        .writeAsStringSync('[mcp_servers.from-codex]\ncommand = "uvx"\nargs = ["mcp-server-time"]\n');
    final r = await sync.importFromTools([AiToolType.codex, AiToolType.mcode]);
    expect(r.added, ['from-codex']);
    expect(r.linked[AiToolType.mcode], {'fs'});
    expect(await db.getServerApps('from-codex'), {AiToolType.codex});
    expect((await db.getMcpServerByServerId('from-codex'))!.command, 'uvx');

    // 删除服务时关系一并删除
    await sync.removeServerFromEnabledTools('fs');
    await db.deleteMcpServerByServerId('fs');
    expect(await db.getServerApps('fs'), isEmpty);
    final after = jsonDecode(File(file(AiToolType.mcode, 'mcp.json')).readAsStringSync()) as Map;
    expect((after['mcpServers'] as Map), isEmpty);
  });

  test('resyncServer follows a renamed serverId', () async {
    final fs = _server('fs');
    await db.addMcpServer(fs);
    await sync.setServerEnabledForTool(fs, AiToolType.mcode, true);
    final stored = (await db.getMcpServerByServerId('fs'))!;
    final renamed = stored.copyWith(serverId: 'files');
    await db.updateMcpServer(renamed); // 与 McpViewModel.updateServer 的顺序一致：先存库再同步
    await sync.resyncServer(renamed, previousServerId: 'fs');
    final m = jsonDecode(File(file(AiToolType.mcode, 'mcp.json')).readAsStringSync()) as Map;
    expect((m['mcpServers'] as Map).keys, ['files']);
    expect(await db.getServerApps('files'), {AiToolType.mcode});
  });
}
