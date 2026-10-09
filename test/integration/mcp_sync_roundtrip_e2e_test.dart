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

/// 端到端：对每一个 MCP 同步目标，启用 stdio（带 env）与 http（带 headers）两个服务 →
/// 用该工具自己的解析路径读回并比较字段 → 修改后重写 → 停用 → 读回为空。临时 HOME，真实文件格式。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late String home;
  final db = McpDatabaseService();

  final stdio = McpServer(
    serverId: 'kc-fetch',
    name: 'kc-fetch',
    serverType: McpServerType.stdio,
    command: 'uvx',
    args: const ['mcp-server-fetch', '--ignore-robots-txt'],
    env: const {'FETCH_TOKEN': 'secret "quoted" value'},
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  final http = McpServer(
    serverId: 'kc-remote',
    name: 'kc-remote',
    serverType: McpServerType.http,
    url: 'https://mcp.example.com/mcp',
    headers: const {'Authorization': 'Bearer tok'},
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('mcp_roundtrip_');
    home = p.join(tmp.path, 'home');
    final prefs = <String, Object>{};
    for (final t in McpSyncService.mcpTargetTools) {
      final d = p.join(home, 'cfg', t.value);
      Directory(d).createSync(recursive: true);
      prefs['ai_tool_config_dir_${t.value}'] = d;
    }
    SharedPreferences.setMockInitialValues(prefs);
    SettingsService.debugHomeDirOverride = home;
    LiveConfigWriter.debugBackupRootOverride = p.join(tmp.path, 'backups');
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    await DatabaseService.instance.close();
    await db.addMcpServer(stdio);
    await db.addMcpServer(http);
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    DatabaseService.debugDatabasePathOverride = null;
    SettingsService.debugHomeDirOverride = null;
    LiveConfigWriter.debugBackupRootOverride = null;
    tmp.deleteSync(recursive: true);
  });

  for (final tool in McpSyncService.mcpTargetTools) {
    test('MCP 往返：${tool.value}', () async {
      final sync = McpSyncService();
      await sync.setServerEnabledForTool(stdio, tool, true);
      await sync.setServerEnabledForTool(http, tool, true);

      final read = (await sync.readMcpServersFromTool(tool)).servers;
      expect(read.keys, containsAll(['kc-fetch', 'kc-remote']), reason: '${tool.value} 读回');
      final s = read['kc-fetch']!;
      expect(s.command, 'uvx');
      expect(s.args, ['mcp-server-fetch', '--ignore-robots-txt']);
      expect(s.env, {'FETCH_TOKEN': 'secret "quoted" value'});
      final h = read['kc-remote']!;
      expect(h.url, 'https://mcp.example.com/mcp');
      expect(h.headers, {'Authorization': 'Bearer tok'});
      expect(await db.getServerApps('kc-fetch'), contains(tool));

      // 修改后重写：同一服务只出现一次，内容更新
      final changed = stdio.copyWith(args: const ['mcp-server-fetch']);
      await db.updateMcpServer(changed.copyWith(id: (await db.getMcpServerByServerId('kc-fetch'))!.id));
      await sync.resyncServer(changed);
      expect((await sync.readMcpServersFromTool(tool)).servers['kc-fetch']!.args, ['mcp-server-fetch']);

      await sync.setServerEnabledForTool(stdio, tool, false);
      await sync.setServerEnabledForTool(http, tool, false);
      final after = (await sync.readMcpServersFromTool(tool)).servers;
      expect(after.keys, isNot(contains('kc-fetch')));
      expect(after.keys, isNot(contains('kc-remote')));
      expect(await db.getServerApps('kc-fetch'), isNot(contains(tool)));
    });
  }
}
