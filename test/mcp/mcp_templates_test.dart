import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// MCP 模板数据校验：CC Switch v4.0.6 的 5 个内置预设必须存在且启动命令一致
void main() {
  final config = jsonDecode(File('assets/config/app_config.json').readAsStringSync())['config'];
  final templates = {
    for (final t in (config['mcpServerTemplates'] as List).cast<Map<String, dynamic>>()) t['serverId']: t,
  };

  test('覆盖 CC Switch 内置 MCP 预设，命令与包名一致', () {
    final expected = {
      'fetch': ('uvx', ['mcp-server-fetch']),
      'time': ('uvx', ['mcp-server-time']),
      'memory': ('npx', ['-y', '@modelcontextprotocol/server-memory']),
      'sequential-thinking': ('npx', ['-y', '@modelcontextprotocol/server-sequential-thinking']),
      'context7': ('npx', ['-y', '@upstash/context7-mcp']),
    };
    for (final e in expected.entries) {
      final t = templates[e.key];
      expect(t, isNotNull, reason: e.key);
      expect(t!['command'], e.value.$1, reason: e.key);
      final args = (t['args'] as List).map((a) => (a as String).replaceFirst(RegExp(r'@latest$'), '')).toList();
      expect(args, e.value.$2, reason: e.key);
    }
  });

  test('已修正的模板使用真实存在的包与环境变量名', () {
    expect(templates['git']!['args'], ['mcp-server-git']);
    expect(templates['notion']!['args'], ['-y', '@notionhq/notion-mcp-server']);
    expect((templates['notion']!['env'] as Map).keys, ['NOTION_TOKEN']);
    expect(templates['baidu-maps']!['args'], ['-y', '@baidumap/mcp-server-baidu-map']);
    expect((templates['baidu-maps']!['env'] as Map).keys, ['BAIDU_MAP_API_KEY']);
  });
}
