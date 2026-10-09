// 所有 AppLocalizations getter 用到的 key，在 zh / en 中都必须有译文（JSON 或内置表），
// 避免界面直接显示 `request_address` 这类原始 key。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('lib/utils/app_localizations.dart').readAsStringSync();
  final keys = RegExp(r"translate\('([a-z0-9_]+)'\)").allMatches(src).map((m) => m.group(1)!).toSet();

  Set<String> builtin(String lang, String next) {
    final start = src.indexOf("    '$lang': {");
    final end = next.isEmpty ? src.indexOf('\n  };', start) : src.indexOf("    '$next': {");
    return RegExp(r"'([a-z0-9_]+)':").allMatches(src.substring(start, end)).map((m) => m.group(1)!).toSet();
  }

  Set<String> json(String lang) =>
      (jsonDecode(File('assets/locales/$lang.json').readAsStringSync()) as Map<String, dynamic>).keys.toSet();

  test('zh 覆盖所有 key', () {
    final have = json('zh')..addAll(builtin('zh', 'en'));
    expect(keys.difference(have), isEmpty);
  });

  test('en 覆盖所有 key（其他语言缺词时回退到英文）', () {
    final have = json('en')..addAll(builtin('en', ''));
    expect(keys.difference(have), isEmpty);
  });

  test('Skills 统计 chip 不再写死英文', () {
    final skills = File('lib/views/screens/skills_config_screen.dart').readAsStringSync();
    expect(skills.contains("} total'"), isFalse);
    expect(skills.contains("} synced'"), isFalse);
    expect(skills.contains("} pending'"), isFalse);
  });

  test('工具页不再只显示笼统的「切换失败」', () {
    for (final f in ['claude', 'codex', 'gemini']) {
      final s = File('lib/views/screens/${f}_config_screen.dart').readAsStringSync();
      expect(s.contains('switchFailed ??'), isFalse, reason: f);
    }
  });
}
