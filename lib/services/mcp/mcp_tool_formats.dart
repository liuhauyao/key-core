import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../../models/mcp_server.dart';

/// 各工具的 MCP 配置格式转换（纯函数，便于测试）。
///
/// 统一中间格式（与 Claude Code / Cursor 的 `mcpServers` 一致）：
/// `{type: stdio|http|sse, command, args, env, cwd}` 或 `{type, url, headers}`。
///
/// 对齐 CC Switch v4.0.6 `src-tauri/src/mcp/*.rs`：
/// - OpenCode：`opencode.json` 的 `mcp`，`local`（`command: [cmd, ...args]`、`environment`）/
///   `remote`（`url`、`headers`），并带 `enabled: true`；
/// - Grok Build：`~/.grok/config.toml` 的 `[mcp_servers.*]`，同 Codex，但请求头字段为 `headers` 且不写 `type`；
/// - Codex：`[mcp_servers.*]`，请求头字段为 `http_headers`；
/// - Hermes：`config.yaml` 的 `mcp_servers`，不写 `type`，带 `enabled: true`，并保留用户的
///   `timeout` / `connect_timeout` / `tools` / `sampling` / `roots` / `auth` 等字段；
/// - Pi：`~/.pi/agent/mcp.json` 的 `mcpServers`，不支持 SSE，服务名只能是 `[A-Za-z0-9_-]`；
/// - MiniMax Code：`~/.minimax/mcp.json` 的 `mcpServers`，带 `enabled: true`。
class McpToolFormats {
  McpToolFormats._();

  static final RegExp piNamePattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// Hermes 中由用户维护、同步时需保留的字段
  static const Set<String> hermesPreservedFields = {
    'timeout',
    'connect_timeout',
    'tools',
    'sampling',
    'roots',
    'auth',
  };

  /// 工具不支持该服务时返回原因，否则返回 null
  static String? unsupportedReason(AiToolType tool, McpServer server) {
    if (tool == AiToolType.pi) {
      if (server.serverType == McpServerType.sse) return 'Pi 不支持 SSE 类型的 MCP 服务';
      if (!piNamePattern.hasMatch(server.serverId)) {
        return 'Pi 的 MCP 服务名只能包含字母、数字、下划线和连字符';
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // OpenCode
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> toOpenCode(McpServer s) {
    if (s.serverType == McpServerType.stdio) {
      return {
        'type': 'local',
        'command': [if (s.command != null && s.command!.isNotEmpty) s.command!, ...?s.args],
        if (s.env != null && s.env!.isNotEmpty) 'environment': Map<String, String>.from(s.env!),
        'enabled': true,
      };
    }
    return {
      'type': 'remote',
      if (s.url != null) 'url': s.url,
      if (s.headers != null && s.headers!.isNotEmpty) 'headers': Map<String, String>.from(s.headers!),
      'enabled': true,
    };
  }

  /// OpenCode 条目 → 统一格式
  static Map<String, dynamic> fromOpenCode(Map<dynamic, dynamic> m) {
    final type = m['type'];
    if (type == 'remote' || (m['url'] is String && m['command'] == null)) {
      return {
        'type': 'http',
        'url': m['url'],
        if (m['headers'] is Map) 'headers': _stringMap(m['headers'] as Map),
      };
    }
    final cmd = m['command'];
    final list = cmd is List ? cmd.map((e) => '$e').toList() : (cmd is String ? [cmd] : <String>[]);
    return {
      'type': 'stdio',
      if (list.isNotEmpty) 'command': list.first,
      if (list.length > 1) 'args': list.sublist(1),
      if (m['environment'] is Map) 'env': _stringMap(m['environment'] as Map),
    };
  }

  // ---------------------------------------------------------------------------
  // MiniMax Code / Pi（mcpServers JSON）
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> toMCode(McpServer s) => {...s.toToolConfigFormat(), 'enabled': true};

  static Map<String, dynamic> toPi(McpServer s) => s.toToolConfigFormat();

  // ---------------------------------------------------------------------------
  // Hermes（YAML）
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> toHermes(McpServer s, {Map<dynamic, dynamic>? existing}) {
    final out = <String, dynamic>{};
    if (s.serverType == McpServerType.stdio) {
      if (s.command != null) out['command'] = s.command;
      if (s.args != null && s.args!.isNotEmpty) out['args'] = List<String>.from(s.args!);
      if (s.env != null && s.env!.isNotEmpty) out['env'] = Map<String, String>.from(s.env!);
      if (s.cwd != null && s.cwd!.isNotEmpty) out['cwd'] = s.cwd;
    } else {
      if (s.url != null) out['url'] = s.url;
      if (s.headers != null && s.headers!.isNotEmpty) out['headers'] = Map<String, String>.from(s.headers!);
    }
    out['enabled'] = true;
    if (existing != null) {
      for (final k in hermesPreservedFields) {
        if (existing.containsKey(k)) out[k] = _plain(existing[k]);
      }
    }
    return out;
  }

  /// 读取 Hermes `config.yaml` 中的 `mcp_servers`（统一格式）
  static Map<String, Map<String, dynamic>> readHermes(String yamlText) {
    final servers = _hermesServers(yamlText);
    return servers.map((name, cfg) {
      final m = Map<String, dynamic>.from(cfg);
      m['type'] = m.containsKey('url') ? 'http' : 'stdio';
      m.remove('enabled');
      for (final k in hermesPreservedFields) {
        m.remove(k);
      }
      return MapEntry(name, m);
    });
  }

  static Map<String, Map<String, dynamic>> _hermesServers(String yamlText) {
    if (yamlText.trim().isEmpty) return {};
    final doc = loadYaml(yamlText);
    if (doc == null) return {};
    if (doc is! YamlMap) throw const FormatException('Hermes config.yaml 顶层不是映射');
    final raw = doc['mcp_servers'];
    if (raw == null) return {};
    if (raw is! YamlMap) throw const FormatException('Hermes config.yaml 的 mcp_servers 不是映射');
    final out = <String, Map<String, dynamic>>{};
    raw.forEach((k, v) {
      if (v is YamlMap) out['$k'] = (_plain(v) as Map).cast<String, dynamic>();
    });
    return out;
  }

  /// 在 Hermes `config.yaml` 中更新 / 删除 MCP 服务，只重写顶层 `mcp_servers:` 块，其余内容原样保留。
  /// YAML 解析失败时抛出异常（调用方中止写入）。
  static String applyHermes(
    String yamlText, {
    Map<String, McpServer> upserts = const {},
    Set<String> removals = const {},
  }) {
    final existing = _hermesServers(yamlText);
    final next = <String, dynamic>{};
    existing.forEach((k, v) {
      if (!removals.contains(k)) next[k] = v;
    });
    upserts.forEach((name, server) {
      next[name] = toHermes(server, existing: existing[name]);
    });

    final lines = yamlText.isEmpty ? <String>[] : yamlText.split('\n');
    final start = lines.indexWhere((l) => RegExp(r'^mcp_servers\s*:').hasMatch(l));
    final block = next.isEmpty ? <String>[] : ['mcp_servers:', ...emitYaml(next, 1)];

    if (start < 0) {
      if (block.isEmpty) return yamlText;
      final body = yamlText.trimRight();
      return '${body.isEmpty ? '' : '$body\n\n'}${block.join('\n')}\n';
    }
    var end = start + 1;
    while (end < lines.length) {
      final l = lines[end];
      if (l.isNotEmpty && !l.startsWith(' ') && !l.startsWith('\t') && !l.startsWith('#')) break;
      end++;
    }
    // 块尾部的空行 / 顶格注释属于下一段
    while (end > start + 1 && (lines[end - 1].trim().isEmpty || lines[end - 1].startsWith('#'))) {
      end--;
    }
    final before = lines.sublist(0, start);
    final after = lines.sublist(end);
    if (block.isEmpty) {
      // 整块删除：去掉块前多余的空行，避免空行累积
      while (before.isNotEmpty && before.last.trim().isEmpty) {
        before.removeLast();
      }
      final rest = after.skipWhile((l) => l.trim().isEmpty).toList();
      final text = [...before, if (before.isNotEmpty && rest.isNotEmpty) '', ...rest].join('\n');
      return text.isEmpty ? '' : (text.endsWith('\n') ? text : '$text\n');
    }
    final out = [...before, ...block, ...after];
    var text = out.join('\n');
    if (yamlText.endsWith('\n') && !text.endsWith('\n')) text = '$text\n';
    return text;
  }

  /// 极简 YAML 发射器（块风格；字符串一律用 JSON 风格双引号，保证是合法 YAML）
  static List<String> emitYaml(Object? value, int level) {
    final pad = '  ' * level;
    final out = <String>[];
    if (value is Map) {
      value.forEach((k, v) {
        final key = _yamlKey('$k');
        if (v is Map && v.isNotEmpty) {
          out.add('$pad$key:');
          out.addAll(emitYaml(v, level + 1));
        } else if (v is List && v.isNotEmpty) {
          out.add('$pad$key:');
          out.addAll(emitYaml(v, level + 1));
        } else {
          out.add('$pad$key: ${_yamlScalar(v)}');
        }
      });
    } else if (value is List) {
      for (final v in value) {
        if (v is Map && v.isNotEmpty) {
          final inner = emitYaml(v, level + 1);
          out.add('$pad- ${inner.first.trimLeft()}');
          out.addAll(inner.skip(1));
        } else if (v is List && v.isNotEmpty) {
          out.add('$pad-');
          out.addAll(emitYaml(v, level + 1));
        } else {
          out.add('$pad- ${_yamlScalar(v)}');
        }
      }
    }
    return out;
  }

  static String _yamlKey(String k) =>
      RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.\-]*$').hasMatch(k) ? k : jsonEncode(k);

  static String _yamlScalar(Object? v) {
    if (v == null) return 'null';
    if (v is bool || v is num) return '$v';
    if (v is Map) return '{}';
    if (v is List) return '[]';
    return jsonEncode('$v');
  }

  // ---------------------------------------------------------------------------
  // Codex / Grok Build（TOML）
  // ---------------------------------------------------------------------------

  /// 由我们维护的字段（其余字段如 `startup_timeout_sec`、`enabled`、`tool_timeout_sec` 保留）
  static const Set<String> tomlManagedKeys = {
    'command',
    'args',
    'env',
    'cwd',
    'url',
    'headers',
    'http_headers',
    'type',
  };

  /// TOML 中服务名：Codex 要求 `^[a-zA-Z0-9_-]+$`，空格转为连字符
  static String tomlServerName(String id) => id.trim().replaceAll(RegExp(r'\s+'), '-');

  static String _tomlKey(String k) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(k) ? k : tomlString(k);

  static String tomlString(String v) {
    final b = StringBuffer('"');
    for (final r in v.runes) {
      final c = String.fromCharCode(r);
      switch (c) {
        case '"':
          b.write(r'\"');
        case '\\':
          b.write(r'\\');
        case '\n':
          b.write(r'\n');
        case '\r':
          b.write(r'\r');
        case '\t':
          b.write(r'\t');
        default:
          if (r < 0x20) {
            b.write('\\u${r.toRadixString(16).padLeft(4, '0')}');
          } else {
            b.write(c);
          }
      }
    }
    b.write('"');
    return b.toString();
  }

  static String _inlineTable(Map<String, String> m) =>
      '{ ${m.entries.map((e) => '${_tomlKey(e.key)} = ${tomlString(e.value)}').join(', ')} }';

  /// 生成单个服务的 TOML 表体（不含表头）
  static List<String> tomlBody(McpServer s, {required bool grok}) {
    final out = <String>[];
    if (s.serverType == McpServerType.stdio) {
      if (s.command != null) out.add('command = ${tomlString(s.command!)}');
      if (s.args != null && s.args!.isNotEmpty) {
        out.add('args = [${s.args!.map(tomlString).join(', ')}]');
      }
      if (s.env != null && s.env!.isNotEmpty) out.add('env = ${_inlineTable(s.env!)}');
      if (s.cwd != null && s.cwd!.isNotEmpty) out.add('cwd = ${tomlString(s.cwd!)}');
    } else {
      if (s.url != null) out.add('url = ${tomlString(s.url!)}');
      if (s.headers != null && s.headers!.isNotEmpty) {
        out.add('${grok ? 'headers' : 'http_headers'} = ${_inlineTable(s.headers!)}');
      }
    }
    return out;
  }

  /// 在 config.toml 中更新 / 删除 `[mcp_servers.*]`。只动涉及的服务表，其他表与顶层内容原样保留；
  /// 已有服务表中我们不维护的字段（如 `startup_timeout_sec`）与子表（`[mcp_servers.x.tools]`）保留。
  static String applyToml(
    String toml, {
    Map<String, McpServer> upserts = const {},
    Set<String> removals = const {},
    required bool grok,
  }) {
    String norm(String s) => tomlServerName(s).toLowerCase();
    final touched = {...upserts.keys.map(norm), ...removals.map(norm)};
    final doc = TomlDoc.parse(toml);
    final extras = <String, List<String>>{}; // 服务 → 保留的键行
    final keptSub = <String, List<List<String>>>{}; // 服务 → 保留的子表
    final out = <String>[..._trimBlank(doc.preamble)];

    for (final t in doc.tables) {
      final path = t.path;
      final isServer = path.length >= 2 && path[0] == 'mcp_servers';
      if (!isServer || !touched.contains(norm(path[1]))) {
        out
          ..add('')
          ..addAll(_trimBlank(t.lines));
        continue;
      }
      final id = norm(path[1]);
      if (path.length == 2) {
        for (final e in TomlDoc.parseEntries(t.lines.skip(1).join('\n'))) {
          if (!tomlManagedKeys.contains(e.key)) (extras[id] ??= []).add(e.raw);
        }
      } else if (!const {'env', 'headers', 'http_headers'}.contains(path[2])) {
        (keptSub[id] ??= []).add(_trimBlank(t.lines));
      }
    }

    for (final entry in upserts.entries) {
      final name = tomlServerName(entry.key);
      final id = norm(entry.key);
      out
        ..add('')
        ..add('[mcp_servers.${_tomlKey(name)}]')
        ..addAll(tomlBody(entry.value, grok: grok))
        ..addAll(extras[id] ?? const []);
      for (final sub in keptSub[id] ?? const <List<String>>[]) {
        out
          ..add('')
          ..addAll(sub);
      }
    }
    while (out.isNotEmpty && out.first.trim().isEmpty) {
      out.removeAt(0);
    }
    return out.isEmpty ? '' : '${out.join('\n')}\n';
  }

  /// 读取 config.toml 中的 `[mcp_servers.*]`（统一格式）
  static Map<String, Map<String, dynamic>> readToml(String toml) {
    final doc = TomlDoc.parse(toml);
    final out = <String, Map<String, dynamic>>{};
    for (final t in doc.tables) {
      final path = t.path;
      if (path.length < 2 || path[0] != 'mcp_servers') continue;
      final cfg = out.putIfAbsent(path[1], () => <String, dynamic>{});
      final entries = TomlDoc.parseEntries(t.lines.skip(1).join('\n'));
      if (path.length == 2) {
        for (final e in entries) {
          cfg[e.key] = e.value;
        }
      } else if (path.length == 3 && const {'env', 'headers', 'http_headers'}.contains(path[2])) {
        cfg[path[2]] = {for (final e in entries) e.key: e.value};
      }
    }
    return out.map((name, cfg) {
      final m = <String, dynamic>{};
      if (cfg['url'] is String) {
        m['type'] = cfg['type'] == 'sse' ? 'sse' : 'http';
        m['url'] = cfg['url'];
        final h = cfg['http_headers'] ?? cfg['headers'];
        if (h is Map) m['headers'] = _stringMap(h);
      } else {
        m['type'] = 'stdio';
        if (cfg['command'] is String) m['command'] = cfg['command'];
        if (cfg['args'] is List) m['args'] = (cfg['args'] as List).map((e) => '$e').toList();
        if (cfg['env'] is Map) m['env'] = _stringMap(cfg['env'] as Map);
        if (cfg['cwd'] is String) m['cwd'] = cfg['cwd'];
      }
      return MapEntry(name, m);
    });
  }

  // ---------------------------------------------------------------------------

  static Map<String, String> _stringMap(Map m) => m.map((k, v) => MapEntry('$k', '$v'));

  static Object? _plain(Object? v) {
    if (v is Map) return {for (final e in v.entries) '${e.key}': _plain(e.value)};
    if (v is List) return v.map(_plain).toList();
    return v;
  }

  static List<String> _trimBlank(List<String> lines) {
    var a = 0, b = lines.length;
    while (a < b && lines[a].trim().isEmpty) {
      a++;
    }
    while (b > a && lines[b - 1].trim().isEmpty) {
      b--;
    }
    return lines.sublist(a, b);
  }
}

/// TOML 文档的轻量切分：顶层区 + 若干表（逐行保留原文）。
class TomlDoc {
  final List<String> preamble;
  final List<TomlTable> tables;

  TomlDoc(this.preamble, this.tables);

  static final RegExp _header = RegExp(r'^\s*\[(\[?)\s*(.+?)\s*\]\]?\s*(#.*)?$');

  static TomlDoc parse(String content) {
    final preamble = <String>[];
    final tables = <TomlTable>[];
    List<String>? current;
    var inMultiline = false;
    var bracketDepth = 0;
    for (final line in content.split('\n')) {
      final header = (inMultiline || bracketDepth > 0) ? null : _header.firstMatch(line);
      if (header != null && header.group(1)!.isEmpty) {
        current = [line];
        tables.add(TomlTable(splitKey(header.group(2)!), current));
      } else if (header != null) {
        // [[array.of.tables]]：原样保留为独立段
        current = [line];
        tables.add(TomlTable(['[[${header.group(2)}]]'], current));
      } else {
        (current ?? preamble).add(line);
      }
      final quotes = '"""'.allMatches(line).length + "'''".allMatches(line).length;
      if (quotes.isOdd) inMultiline = !inMultiline;
      if (!inMultiline) bracketDepth = (bracketDepth + _bracketDelta(line)).clamp(0, 1 << 20);
    }
    return TomlDoc(preamble, tables);
  }

  /// 多行数组：统计字符串外的方括号
  static int _bracketDelta(String line) {
    var d = 0;
    String? quote;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (quote != null) {
        if (c == '\\' && quote == '"') {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '#') break;
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '[') {
        d++;
      } else if (c == ']') {
        d--;
      }
    }
    // 表头行 [a.b] 自身平衡
    return d;
  }

  /// 拆分点分键：a."b.c".d → [a, b.c, d]
  static List<String> splitKey(String key) {
    final parts = <String>[];
    final b = StringBuffer();
    String? quote;
    for (var i = 0; i < key.length; i++) {
      final c = key[i];
      if (quote != null) {
        if (c == '\\' && quote == '"' && i + 1 < key.length) {
          b.write(key[++i]);
        } else if (c == quote) {
          quote = null;
        } else {
          b.write(c);
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '.') {
        parts.add(b.toString().trim());
        b.clear();
      } else {
        b.write(c);
      }
    }
    parts.add(b.toString().trim());
    return parts;
  }

  /// 解析表体中的 `key = value` 条目（支持字符串、数组、内联表、多行数组，其余值按原文保留）
  static List<TomlEntry> parseEntries(String body) {
    final p = _TomlParser(body);
    final out = <TomlEntry>[];
    while (true) {
      p.skipWsCommentsNewlines();
      if (p.eof) break;
      final start = p.i;
      final key = p.parseKey();
      p.skipWs();
      if (!p.consume('=')) {
        p.skipLine();
        continue;
      }
      p.skipWs();
      final value = p.parseValue();
      p.skipWs();
      if (!p.eof && p.peek == '#') p.skipLine();
      final raw = body.substring(start, p.i).trimRight();
      out.add(TomlEntry(key.join('.'), value, raw));
    }
    return out;
  }
}

class TomlTable {
  final List<String> path;
  final List<String> lines;
  TomlTable(this.path, this.lines);
}

class TomlEntry {
  final String key;
  final Object? value;
  final String raw;
  TomlEntry(this.key, this.value, this.raw);
}

class _TomlParser {
  final String s;
  int i = 0;
  _TomlParser(this.s);

  bool get eof => i >= s.length;
  String get peek => s[i];

  bool consume(String c) {
    if (!eof && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  void skipWs() {
    while (!eof && (s[i] == ' ' || s[i] == '\t')) {
      i++;
    }
  }

  void skipLine() {
    while (!eof && s[i] != '\n') {
      i++;
    }
  }

  void skipWsCommentsNewlines() {
    while (!eof) {
      final c = s[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
      } else if (c == '#') {
        skipLine();
      } else {
        break;
      }
    }
  }

  List<String> parseKey() {
    final parts = <String>[];
    while (!eof) {
      skipWs();
      if (peek == '"' || peek == "'") {
        parts.add(parseString());
      } else {
        final b = StringBuffer();
        while (!eof && RegExp(r'[A-Za-z0-9_\-]').hasMatch(s[i])) {
          b.write(s[i++]);
        }
        if (b.isEmpty) break;
        parts.add(b.toString());
      }
      skipWs();
      if (!consume('.')) break;
    }
    return parts;
  }

  String parseString() {
    final q = s[i];
    final triple = s.startsWith(q * 3, i);
    if (triple) {
      i += 3;
      if (!eof && s[i] == '\n') i++;
      final end = s.indexOf(q * 3, i);
      final raw = s.substring(i, end < 0 ? s.length : end);
      i = end < 0 ? s.length : end + 3;
      return q == '"' ? _unescape(raw) : raw;
    }
    i++;
    final b = StringBuffer();
    while (!eof && s[i] != q && s[i] != '\n') {
      if (q == '"' && s[i] == '\\' && i + 1 < s.length) {
        b.write(s.substring(i, i + 2));
        i += 2;
        if (b.toString().endsWith(r'\u') || b.toString().endsWith(r'\U')) {
          final n = b.toString().endsWith(r'\u') ? 4 : 8;
          b.write(s.substring(i, (i + n).clamp(0, s.length)));
          i += n;
        }
        continue;
      }
      b.write(s[i++]);
    }
    i++;
    return q == '"' ? _unescape(b.toString()) : b.toString();
  }

  static String _unescape(String v) => v.replaceAllMapped(
        RegExp(r'\\(u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8}|.)', dotAll: true),
        (m) {
          final g = m.group(1)!;
          switch (g[0]) {
            case 'n':
              return '\n';
            case 't':
              return '\t';
            case 'r':
              return '\r';
            case 'b':
              return '\b';
            case 'f':
              return '\f';
            case 'u':
            case 'U':
              return String.fromCharCode(int.parse(g.substring(1), radix: 16));
            default:
              return g;
          }
        },
      );

  Object? parseValue() {
    if (eof) return null;
    final c = peek;
    if (c == '"' || c == "'") return parseString();
    if (c == '[') {
      i++;
      final list = <Object?>[];
      while (true) {
        skipWsCommentsNewlines();
        if (eof) break;
        if (consume(']')) break;
        list.add(parseValue());
        skipWsCommentsNewlines();
        consume(',');
      }
      return list;
    }
    if (c == '{') {
      i++;
      final map = <String, Object?>{};
      while (true) {
        skipWs();
        if (eof || consume('}')) break;
        final k = parseKey().join('.');
        skipWs();
        consume('=');
        skipWs();
        map[k] = parseValue();
        skipWs();
        consume(',');
      }
      return map;
    }
    final b = StringBuffer();
    while (!eof && !',]}\n#'.contains(s[i])) {
      b.write(s[i++]);
    }
    final raw = b.toString().trim();
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return num.tryParse(raw.replaceAll('_', '')) ?? raw;
  }
}
