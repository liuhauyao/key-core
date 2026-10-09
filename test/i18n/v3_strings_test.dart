// v3 新文案（AppLocalizations.tr）在 zh / en / zh_TW 中都必须有译文。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final keys = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    keys.addAll(RegExp(r"\.tr\(\s*'([a-z0-9_]+)'").allMatches(f.readAsStringSync()).map((m) => m.group(1)!));
  }

  for (final lang in ['zh', 'en', 'zh_TW']) {
    test('$lang 覆盖所有 v3 文案', () {
      final have = (jsonDecode(File('assets/locales/$lang.json').readAsStringSync()) as Map<String, dynamic>).keys.toSet();
      expect(keys.difference(have), isEmpty);
    });
  }
}
