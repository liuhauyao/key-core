import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/services/mcp/mcp_tool_formats.dart';
import 'package:yaml/yaml.dart';

McpServer _stdio(String id, {List<String>? args, Map<String, String>? env}) => McpServer(
      serverId: id,
      name: id,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: args ?? ['-y', '@pkg/server'],
      env: env,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

McpServer _remote(String id, {McpServerType type = McpServerType.http}) => McpServer(
      serverId: id,
      name: id,
      serverType: type,
      url: 'https://mcp.example/$id',
      headers: const {'Authorization': 'Bearer "t"'},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('OpenCode', () {
    test('stdio → local with command array and environment', () {
      expect(McpToolFormats.toOpenCode(_stdio('fs', env: {'A': '1'})), {
        'type': 'local',
        'command': ['npx', '-y', '@pkg/server'],
        'environment': {'A': '1'},
        'enabled': true,
      });
    });

    test('http → remote, and round trip back to the unified format', () {
      final oc = McpToolFormats.toOpenCode(_remote('r'));
      expect(oc['type'], 'remote');
      expect(oc['headers'], {'Authorization': 'Bearer "t"'});
      expect(McpToolFormats.fromOpenCode(oc), {
        'type': 'http',
        'url': 'https://mcp.example/r',
        'headers': {'Authorization': 'Bearer "t"'},
      });
      expect(McpToolFormats.fromOpenCode(McpToolFormats.toOpenCode(_stdio('fs'))), {
        'type': 'stdio',
        'command': 'npx',
        'args': ['-y', '@pkg/server'],
      });
    });
  });

  group('Pi / MiniMax Code', () {
    test('Pi rejects SSE and invalid names', () {
      expect(McpToolFormats.unsupportedReason(AiToolType.pi, _remote('ok', type: McpServerType.sse)), isNotNull);
      expect(McpToolFormats.unsupportedReason(AiToolType.pi, _stdio('bad name')), isNotNull);
      expect(McpToolFormats.unsupportedReason(AiToolType.pi, _stdio('good_name-1')), isNull);
      expect(McpToolFormats.unsupportedReason(AiToolType.mcode, _stdio('bad name')), isNull);
    });

    test('MiniMax Code adds enabled: true', () {
      expect(McpToolFormats.toMCode(_stdio('fs'))['enabled'], isTrue);
    });
  });

  group('Hermes YAML', () {
    const yaml = '# Hermes config\n'
        'model:\n'
        '  provider: nous\n'
        '  name: hermes-4\n'
        '\n'
        'mcp_servers:\n'
        '  keep:\n'
        '    command: uvx\n'
        '    args: ["mcp-server-time"]\n'
        '  fs:\n'
        '    command: old\n'
        '    timeout: 120\n'
        '    tools:\n'
        '      include: [read_file]\n'
        '\n'
        '# trailing section\n'
        'terminal:\n'
        '  backend: local\n';

    test('upsert rewrites only mcp_servers and keeps user fields', () {
      final out = McpToolFormats.applyHermes(yaml, upserts: {'fs': _stdio('fs', env: {'TOKEN': 'a:b'})});
      expect(out, startsWith('# Hermes config\nmodel:\n  provider: nous\n  name: hermes-4\n\nmcp_servers:\n'));
      expect(out, endsWith('\n# trailing section\nterminal:\n  backend: local\n'));
      final doc = loadYaml(out) as YamlMap;
      final fs = doc['mcp_servers']['fs'] as YamlMap;
      expect(fs['command'], 'npx');
      expect(fs['env']['TOKEN'], 'a:b');
      expect(fs['enabled'], true);
      expect(fs['timeout'], 120);
      expect(fs['tools']['include'], ['read_file']);
      expect(fs.containsKey('type'), isFalse);
      expect(doc['mcp_servers']['keep']['command'], 'uvx');
      expect(doc['terminal']['backend'], 'local');
    });

    test('removing the last server removes the block; adding to a file without the block appends it', () {
      final removed = McpToolFormats.applyHermes(yaml, removals: {'fs', 'keep'});
      expect(removed, isNot(contains('mcp_servers')));
      expect((loadYaml(removed) as YamlMap)['model']['name'], 'hermes-4');

      final added = McpToolFormats.applyHermes('model:\n  name: x\n', upserts: {'r': _remote('r')});
      final doc = loadYaml(added) as YamlMap;
      expect(doc['mcp_servers']['r']['url'], 'https://mcp.example/r');
      expect(doc['mcp_servers']['r']['headers']['Authorization'], 'Bearer "t"');
      expect(McpToolFormats.applyHermes('', upserts: {'a': _stdio('a')}), startsWith('mcp_servers:\n  a:\n'));
    });

    test('readHermes returns the unified format; invalid YAML throws', () {
      final servers = McpToolFormats.readHermes(yaml);
      expect(servers['fs'], {'command': 'old', 'type': 'stdio'});
      expect(servers['keep']!['args'], ['mcp-server-time']);
      expect(() => McpToolFormats.applyHermes('a: [unclosed', upserts: {'a': _stdio('a')}), throwsA(anything));
    });
  });

  group('Codex / Grok TOML', () {
    const toml = 'model_provider = "keycore"\n'
        '\n'
        '[model_providers.keycore]\n'
        'name = "k"\n'
        '\n'
        '[mcp_servers.fs]\n'
        'command = "old"\n'
        'startup_timeout_sec = 30\n'
        'args = [\n'
        '  "a",\n'
        '  "b",\n'
        ']\n'
        '\n'
        '[mcp_servers.fs.env]\n'
        'X = "1"\n'
        '\n'
        '[mcp_servers.other]\n'
        'url = "https://o.example"\n'
        'http_headers = { "X-Key" = "v" }\n'
        '\n'
        '[projects."/tmp/a"]\n'
        'trust_level = "trusted"\n';

    test('upsert replaces the server table, keeps unknown keys and other tables', () {
      final out = McpToolFormats.applyToml(toml,
          upserts: {'fs': _stdio('fs', args: ['-y', 'x "q"'], env: {'K': 'v\\1'})}, grok: false);
      expect(out, contains('[model_providers.keycore]\nname = "k"'));
      expect(out, contains('[mcp_servers.other]\nurl = "https://o.example"\nhttp_headers = { "X-Key" = "v" }'));
      expect(out, contains('[projects."/tmp/a"]\ntrust_level = "trusted"'));
      expect(out, contains('[mcp_servers.fs]\ncommand = "npx"\nargs = ["-y", "x \\"q\\""]\nenv = { K = "v\\\\1" }\n'
          'startup_timeout_sec = 30'));
      expect(out, isNot(contains('[mcp_servers.fs.env]')));
      expect(out, isNot(contains('"old"')));

      final parsed = McpToolFormats.readToml(out);
      expect(parsed['fs'], {
        'type': 'stdio',
        'command': 'npx',
        'args': ['-y', 'x "q"'],
        'env': {'K': 'v\\1'},
      });
      expect(parsed['other'], {'type': 'http', 'url': 'https://o.example', 'headers': {'X-Key': 'v'}});
    });

    test('read multi-line arrays and env sub-tables', () {
      expect(McpToolFormats.readToml(toml)['fs'], {
        'type': 'stdio',
        'command': 'old',
        'args': ['a', 'b'],
        'env': {'X': '1'},
      });
    });

    test('Grok writes headers (not http_headers); Codex writes http_headers', () {
      expect(McpToolFormats.applyToml('', upserts: {'r': _remote('r')}, grok: true),
          contains('headers = { Authorization = "Bearer \\"t\\"" }'));
      final codex = McpToolFormats.applyToml('', upserts: {'r': _remote('r')}, grok: false);
      expect(codex, contains('http_headers = '));
      expect(codex, isNot(contains('type =')));
    });

    test('removal deletes the server and its sub-tables only; names with spaces are normalized', () {
      final out = McpToolFormats.applyToml(toml, removals: {'fs'}, grok: false);
      expect(out, isNot(contains('mcp_servers.fs')));
      expect(out, contains('[mcp_servers.other]'));
      expect(out, startsWith('model_provider = "keycore"\n'));

      final spaced = McpToolFormats.applyToml('', upserts: {'my server': _stdio('my server')}, grok: false);
      expect(spaced, startsWith('[mcp_servers.my-server]\n'));
      expect(McpToolFormats.applyToml(spaced, removals: {'my server'}, grok: false), '');
    });

    test('is idempotent', () {
      final once = McpToolFormats.applyToml(toml, upserts: {'fs': _stdio('fs')}, grok: false);
      expect(McpToolFormats.applyToml(once, upserts: {'fs': _stdio('fs')}, grok: false), once);
    });
  });
}
