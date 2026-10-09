// 写入各工具配置文件时使用的纯函数补丁器。
//
// 借鉴 CC Switch `src-tauri/src/live/patch/*` 的原则：以现有文件为底，只改补丁点名的键，
// 其余键、值和顺序不变；解析不了就报错，绝不退回空文档。
import 'dart:convert';

/// 配置文件解析失败（为避免覆盖用户配置，本次写入被中止）
class LiveConfigParseException implements Exception {
  final String path;
  final String message;

  LiveConfigParseException(this.path, this.message);

  @override
  String toString() => '无法解析配置文件 $path（已中止写入，文件未被修改）：$message';
}

/// JSON 补丁：解析、修改、按原文件风格重新序列化。
class JsonPatch {
  JsonPatch._();

  /// 解析 JSON 文档为对象。
  ///
  /// - [content] 为 null（文件不存在）或只有空白时返回空对象（新建文件）；
  /// - 解析失败或顶层不是对象时抛出 [LiveConfigParseException]。
  /// - [preprocess] 可用于 JSON5/JSONC（去注释、尾逗号）。
  static Map<String, dynamic> parseObject(
    String path,
    String? content, {
    String Function(String raw)? preprocess,
  }) {
    if (content == null || content.trim().isEmpty) return <String, dynamic>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(preprocess != null ? preprocess(content) : content);
    } on FormatException catch (e) {
      throw LiveConfigParseException(path, e.message);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw LiveConfigParseException(path, '顶层不是 JSON 对象');
  }

  /// 检测原文件的缩进（空格或 Tab），默认两个空格。
  static String detectIndent(String? content) {
    if (content == null) return '  ';
    for (final line in const LineSplitter().convert(content)) {
      final match = RegExp(r'^([ \t]+)\S').firstMatch(line);
      if (match != null) return match.group(1)!;
    }
    return '  ';
  }

  /// 按原文件的缩进、换行符和末尾换行重新序列化。
  ///
  /// Dart 的 `jsonDecode` 返回保序的 `LinkedHashMap`，`remove` 不会打乱其余键顺序，
  /// 新增的键追加到所在对象末尾，因此键序与原文件保持一致。
  static String encode(Map<String, dynamic> doc, {String? original}) {
    final indent = detectIndent(original);
    var out = JsonEncoder.withIndent(indent).convert(doc);
    final crlf = original != null && original.contains('\r\n');
    if (crlf) out = out.replaceAll('\n', '\r\n');
    final trailingNewline = original != null && original.endsWith('\n');
    if (trailingNewline) out += crlf ? '\r\n' : '\n';
    return out;
  }

  /// 两个 JSON 值是否完全相同（含键序）
  static bool sameDocument(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
}

/// `.env` 补丁：按行处理，注释、空行、认不出的行和其他变量的顺序都原样保留。
class DotEnvPatch {
  DotEnvPatch._();

  static final RegExp _assignment = RegExp(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=');

  /// 解析为键值对（只用于读取，不参与写入）
  static Map<String, String> parse(String? content) {
    final map = <String, String>{};
    if (content == null) return map;
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final match = _assignment.firstMatch(line);
      if (match == null) continue;
      var value = line.substring(match.end).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      map[match.group(1)!] = value;
    }
    return map;
  }

  /// 设置 [set] 中的变量（原位替换，不存在则追加到末尾），删除 [remove] 中的变量。
  ///
  /// 同一变量出现多次时全部替换/删除。其余行逐字保留。
  static String apply(
    String? content, {
    Map<String, String> set = const {},
    Set<String> remove = const {},
  }) {
    final original = content ?? '';
    final crlf = original.contains('\r\n');
    final newline = crlf ? '\r\n' : '\n';
    final lines = original.isEmpty ? <String>[] : original.split(RegExp(r'\r?\n'));
    // split 后末尾的空串代表原文件以换行结尾
    final hadTrailingNewline = lines.isNotEmpty && lines.last.isEmpty;
    if (hadTrailingNewline) lines.removeLast();

    final written = <String>{};
    final out = <String>[];
    for (final line in lines) {
      final trimmed = line.trimLeft();
      final match = trimmed.startsWith('#') ? null : _assignment.firstMatch(line);
      final key = match?.group(1);
      if (key != null && remove.contains(key) && !set.containsKey(key)) {
        continue;
      }
      if (key != null && set.containsKey(key)) {
        if (written.contains(key)) continue; // 重复定义只保留第一处
        final exportPrefix = trimmed.startsWith('export ') ? 'export ' : '';
        out.add('$exportPrefix$key=${set[key]}');
        written.add(key);
        continue;
      }
      out.add(line);
    }
    for (final entry in set.entries) {
      if (!written.contains(entry.key)) out.add('${entry.key}=${entry.value}');
    }
    if (out.isEmpty) return '';
    return out.join(newline) + (hadTrailingNewline || original.isEmpty ? newline : '');
  }
}
