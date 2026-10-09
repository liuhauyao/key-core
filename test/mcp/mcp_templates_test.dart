import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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

  // 2026-10-10 复核：每个 stdio 模板的包都在 npm / PyPI 上查过（见 review_2026-10-10.md）
  const verifiedPackages = <String, String>{
    'context7': 'npm:@upstash/context7-mcp',
    'supabase': 'npm:@supabase/mcp-server-supabase',
    'n8n': 'npm:n8n-mcp',
    'alipay': 'npm:@alipay/mcp-server-alipay',
    'postgres': 'npm:@modelcontextprotocol/server-postgres',
    'sqlite': 'pypi:mcp-server-sqlite',
    'mysql': 'npm:@benborla29/mcp-server-mysql',
    'brave-search': 'npm:@brave/brave-search-mcp-server',
    'bing-cn': 'npm:bing-cn-mcp',
    'baidu-maps': 'npm:@baidumap/mcp-server-baidu-map',
    'filesystem': 'npm:@modelcontextprotocol/server-filesystem',
    'git': 'pypi:mcp-server-git',
    'aws': 'pypi:awslabs.aws-api-mcp-server',
    'sequential-thinking': 'npm:@modelcontextprotocol/server-sequential-thinking',
    'time': 'pypi:mcp-server-time',
    'slack': 'npm:@modelcontextprotocol/server-slack',
    'notion': 'npm:@notionhq/notion-mcp-server',
    'playwright': 'npm:@playwright/mcp',
    'fetch': 'pypi:mcp-server-fetch',
    'memory': 'npm:@modelcontextprotocol/server-memory',
    'dingtalk': 'npm:dingtalk-mcp',
  };

  String? packageOf(Map<String, dynamic> t) {
    final args = (t['args'] as List?)?.cast<String>() ?? const [];
    final pkg = args.firstWhere((a) => !a.startsWith('-'), orElse: () => '');
    if (pkg.isEmpty) return null;
    final bare = pkg.replaceFirst(RegExp(r'@[^@/]+$'), '');
    return '${t['command'] == 'uvx' ? 'pypi' : 'npm'}:$bare';
  }

  test('每个 stdio 模板都指向已核实存在的包', () {
    for (final t in templates.values.where((t) => t['serverType'] == 'stdio')) {
      expect(packageOf(t), verifiedPackages[t['serverId']], reason: '${t['serverId']} 的包未核实');
    }
  });

  test('不存在对应包的模板已删除；远程 MCP 用官方端点', () {
    for (final id in ['openai', 'anthropic', 'unionpay', 'google-search', 'gcp', 'puppeteer']) {
      expect(templates.containsKey(id), isFalse, reason: id);
    }
    expect(templates['github']!['url'], 'https://api.githubcopilot.com/mcp/');
    expect(templates['zhipu-web-search']!['url'], 'https://open.bigmodel.cn/api/mcp/web_search_prime/mcp');
    expect((templates['supabase']!['env'] as Map).keys, ['SUPABASE_ACCESS_TOKEN']);
    expect((templates['alipay']!['env'] as Map).keys, ['AP_APP_ID', 'AP_APP_KEY', 'AP_PUB_KEY']);
    expect((templates['postgres']!['args'] as List).last, startsWith('postgresql://'),
        reason: 'server-postgres 从参数读连接串，不读环境变量');
  });

  test(
    '（联网）模板引用的包在 npm / PyPI 注册表中真实存在',
    () async {
      for (final ref in verifiedPackages.values.toSet()) {
        final kind = ref.substring(0, ref.indexOf(':'));
        final name = ref.substring(ref.indexOf(':') + 1);
        final url = kind == 'npm'
            ? 'https://registry.npmjs.org/${name.replaceAll('/', '%2F')}'
            : 'https://pypi.org/pypi/$name/json';
        final res = await http.get(Uri.parse(url));
        expect(res.statusCode, 200, reason: ref);
      }
    },
    tags: ['network'],
    skip: Platform.environment['KEYCORE_NETWORK_TESTS'] == '1' ? false : '联网测试：设置 KEYCORE_NETWORK_TESTS=1 运行',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
