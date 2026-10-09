import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/live_config/live_patches.dart';

void main() {
  group('JsonPatch.parseObject', () {
    test('missing or blank content is a new empty document', () {
      expect(JsonPatch.parseObject('x', null), isEmpty);
      expect(JsonPatch.parseObject('x', '  \n'), isEmpty);
    });

    test('invalid JSON throws instead of returning an empty object', () {
      expect(() => JsonPatch.parseObject('x', '{"env": {'), throwsA(isA<LiveConfigParseException>()));
      expect(() => JsonPatch.parseObject('x', '// comment\n{}'), throwsA(isA<LiveConfigParseException>()));
    });

    test('non-object top level throws', () {
      expect(() => JsonPatch.parseObject('x', '[1,2]'), throwsA(isA<LiveConfigParseException>()));
      expect(() => JsonPatch.parseObject('x', '"str"'), throwsA(isA<LiveConfigParseException>()));
    });

    test('preprocess hook enables JSON5-like input', () {
      final doc = JsonPatch.parseObject('x', '{a: 1}', preprocess: (s) => s.replaceAll('a:', '"a":'));
      expect(doc, {'a': 1});
    });
  });

  group('JsonPatch.encode', () {
    test('keeps key order, removes in place and appends new keys at the end', () {
      const original = '{\n  "z": 1,\n  "a": 2,\n  "m": 3\n}\n';
      final doc = JsonPatch.parseObject('x', original);
      doc.remove('a');
      doc['b'] = 4;
      expect(JsonPatch.encode(doc, original: original), '{\n  "z": 1,\n  "m": 3,\n  "b": 4\n}\n');
    });

    test('preserves 4-space and tab indentation', () {
      const four = '{\n    "a": {\n        "b": 1\n    }\n}';
      expect(JsonPatch.encode(JsonPatch.parseObject('x', four), original: four), four);
      const tab = '{\n\t"a": 1\n}';
      expect(JsonPatch.encode(JsonPatch.parseObject('x', tab), original: tab), tab);
    });

    test('preserves CRLF and trailing newline (or its absence)', () {
      const crlf = '{\r\n  "a": 1\r\n}\r\n';
      expect(JsonPatch.encode(JsonPatch.parseObject('x', crlf), original: crlf), crlf);
      const noNl = '{\n  "a": 1\n}';
      expect(JsonPatch.encode(JsonPatch.parseObject('x', noNl), original: noNl), noNl);
    });

    test('new file defaults to two-space indent without trailing newline', () {
      expect(JsonPatch.encode({'a': 1}), '{\n  "a": 1\n}');
    });
  });

  group('DotEnvPatch', () {
    test('replaces in place, keeps comments, blank lines and order', () {
      const original = '# Gemini\nFOO=1\n\nGEMINI_API_KEY=old\n# trailing comment\nBAR="x y"\n';
      final out = DotEnvPatch.apply(original, set: {'GEMINI_API_KEY': 'new'});
      expect(out, '# Gemini\nFOO=1\n\nGEMINI_API_KEY=new\n# trailing comment\nBAR="x y"\n');
    });

    test('appends missing keys and removes requested keys', () {
      const original = 'GEMINI_BASE_URL=https://proxy\nKEEP=1\nGEMINI_MODEL=m\n';
      final out = DotEnvPatch.apply(original,
          set: {'GEMINI_API_KEY': 'k'}, remove: {'GEMINI_BASE_URL', 'GEMINI_MODEL'});
      expect(out, 'KEEP=1\nGEMINI_API_KEY=k\n');
    });

    test('keeps export prefix and collapses duplicate definitions', () {
      const original = 'export TOKEN=a\nOTHER=1\nTOKEN=b\n';
      expect(DotEnvPatch.apply(original, set: {'TOKEN': 'c'}), 'export TOKEN=c\nOTHER=1\n');
    });

    test('commented-out assignments are left alone', () {
      const original = '# TOKEN=commented\nTOKEN=a\n';
      expect(DotEnvPatch.apply(original, set: {'TOKEN': 'b'}), '# TOKEN=commented\nTOKEN=b\n');
    });

    test('preserves CRLF and missing trailing newline', () {
      expect(DotEnvPatch.apply('A=1\r\nB=2', set: {'B': '3'}), 'A=1\r\nB=3');
    });

    test('new file gets a trailing newline', () {
      expect(DotEnvPatch.apply(null, set: {'A': '1'}), 'A=1\n');
    });

    test('parse strips quotes and export', () {
      expect(DotEnvPatch.parse('export A="1"\nB=\'2\'\n# C=3\nD=4'), {'A': '1', 'B': '2', 'D': '4'});
    });
  });
}
