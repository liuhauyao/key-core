import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/services/live_config/live_config_writer.dart';
import 'package:path/path.dart' as p;

int _mode(String path) => File(path).statSync().mode & 0x1FF;

void main() {
  late Directory tmp;
  final writer = LiveConfigWriter.instance;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('live_writer_test_');
    LiveConfigWriter.debugBackupRootOverride = p.join(tmp.path, 'backups');
    LiveConfigWriter.debugBeforePublish = null;
  });

  tearDown(() {
    LiveConfigWriter.debugBackupRootOverride = null;
    LiveConfigWriter.debugBeforePublish = null;
    tmp.deleteSync(recursive: true);
  });

  String f(String name) => p.join(tmp.path, name);

  List<String> leftovers() => tmp
      .listSync(recursive: true)
      .whereType<File>()
      .map((e) => p.basename(e.path))
      .where((n) => n.contains('.keycore-'))
      .toList();

  group('parse failure aborts', () {
    test('invalid JSON is left byte-for-byte unchanged and nothing is backed up', () async {
      final path = f('settings.json');
      const broken = '{"env": {"ANTHROPIC_AUTH_TOKEN": "sk-old",}';
      File(path).writeAsStringSync(broken);

      await expectLater(
        writer.updateJson(AiToolType.claudecode, path, (doc) => doc['env'] = {'X': '1'}),
        throwsA(isA<LiveConfigParseException>()),
      );
      expect(File(path).readAsStringSync(), broken);
      expect(Directory(p.join(tmp.path, 'backups')).existsSync(), isFalse);
      expect(leftovers(), isEmpty);
    });

    test('invalid UTF-8 counts as a parse failure', () async {
      final path = f('bin.json');
      File(path).writeAsBytesSync([0x7B, 0xFF, 0xFE, 0x7D]);
      await expectLater(
        writer.updateJson(AiToolType.cursor, path, (doc) => doc['a'] = 1),
        throwsA(isA<LiveConfigParseException>()),
      );
      expect(File(path).readAsBytesSync(), [0x7B, 0xFF, 0xFE, 0x7D]);
    });

    test('one unparsable file aborts the whole multi-file operation', () async {
      final good = f('auth.json');
      final bad = f('config.json');
      File(good).writeAsStringSync('{"OPENAI_API_KEY": "old"}');
      File(bad).writeAsStringSync('not json');

      await expectLater(
        writer.apply(AiToolType.codex, [
          LiveEdit.json(good, (d) => d['OPENAI_API_KEY'] = 'new', containsSecrets: true),
          LiveEdit.json(bad, (d) => d['x'] = 1),
        ]),
        throwsA(isA<LiveConfigParseException>()),
      );
      expect(File(good).readAsStringSync(), '{"OPENAI_API_KEY": "old"}');
      expect(File(bad).readAsStringSync(), 'not json');
    });

    test('a throwing transform writes nothing', () async {
      final a = f('a.json');
      File(a).writeAsStringSync('{"a": 1}');
      await expectLater(
        writer.apply(AiToolType.gemini, [
          LiveEdit.json(a, (d) => d['a'] = 2),
          LiveEdit(f('b.txt'), (_) => throw StateError('boom')),
        ]),
        throwsStateError,
      );
      expect(File(a).readAsStringSync(), '{"a": 1}');
      expect(File(f('b.txt')).existsSync(), isFalse);
      expect(leftovers(), isEmpty);
    });
  });

  group('field preservation', () {
    test('only touched keys change; order, indent and newline are kept', () async {
      final path = f('settings.json');
      const original = '{\n'
          '    "permissions": {\n        "allow": [\n            "Bash(ls)"\n        ]\n    },\n'
          '    "env": {\n        "DISABLE_TELEMETRY": "1",\n        "ANTHROPIC_AUTH_TOKEN": "old"\n    },\n'
          '    "model": "opus"\n'
          '}\n';
      File(path).writeAsStringSync(original);

      await writer.updateJson(AiToolType.claudecode, path, (doc) {
        (doc['env'] as Map)['ANTHROPIC_AUTH_TOKEN'] = 'new';
      });

      expect(File(path).readAsStringSync(), original.replaceFirst('"old"', '"new"'));
    });

    test('no-op mutation does not rewrite the file or create backups', () async {
      final path = f('mcp.json');
      const original = '{"mcpServers":{}}';
      File(path).writeAsStringSync(original);
      final result = await writer.updateJson(AiToolType.cursor, path, (doc) {
        doc['mcpServers'] = <String, dynamic>{};
      });
      expect(result.changedPaths, isEmpty);
      expect(File(path).readAsStringSync(), original);
      expect(Directory(p.join(tmp.path, 'backups')).existsSync(), isFalse);
    });

    test('createIfMissing: false does not create a file', () async {
      final path = f('absent.json');
      await writer.updateJson(AiToolType.cursor, path, (d) => d['a'] = 1, createIfMissing: false);
      expect(File(path).existsSync(), isFalse);
    });

    test('missing file is created with parent directories', () async {
      final path = p.join(tmp.path, 'nested', 'dir', 'settings.json');
      await writer.updateJson(AiToolType.claudecode, path, (d) => d['a'] = 1);
      expect(jsonDecode(File(path).readAsStringSync()), {'a': 1});
    });

    test('dotenv edits keep comments and order', () async {
      final path = f('.env');
      File(path).writeAsStringSync('# mine\nB=1\nGEMINI_API_KEY=old\nA=2\n');
      await writer.updateDotEnv(AiToolType.gemini, path, set: {'GEMINI_API_KEY': 'new'});
      expect(File(path).readAsStringSync(), '# mine\nB=1\nGEMINI_API_KEY=new\nA=2\n');
    });
  });

  group('atomic publish', () {
    test('writes go through a temp file and leave no leftovers', () async {
      final path = f('config.toml');
      File(path).writeAsStringSync('model = "a"\n');
      await writer.updateText(AiToolType.codex, path, (c) => c.replaceAll('"a"', '"b"'));
      expect(File(path).readAsStringSync(), 'model = "b"\n');
      expect(leftovers(), isEmpty);
    });

    test('a symlinked config is written through to its target', () async {
      final target = f('real.json');
      File(target).writeAsStringSync('{"a": 1}');
      final link = f('link.json');
      Link(link).createSync(target);

      await writer.updateJson(AiToolType.cursor, link, (d) => d['a'] = 2);

      expect(FileSystemEntity.isLinkSync(link), isTrue);
      expect(jsonDecode(File(target).readAsStringSync()), {'a': 2});
    });

    test('concurrent external modification is detected and retried on fresh content', () async {
      final path = f('settings.json');
      File(path).writeAsStringSync('{"user": 1}');
      var injected = false;
      LiveConfigWriter.debugBeforePublish = (_) async {
        if (!injected) {
          injected = true;
          File(path).writeAsStringSync('{"user": 2}');
        }
      };

      await writer.updateJson(AiToolType.claudecode, path, (d) => d['ours'] = true);

      // 第二次尝试基于外部写入后的内容，因此外部改动不会丢失
      expect(jsonDecode(File(path).readAsStringSync()), {'user': 2, 'ours': true});
    });

    test('persistent concurrent modification gives up without overwriting', () async {
      final path = f('settings.json');
      File(path).writeAsStringSync('{"n": 0}');
      var n = 0;
      LiveConfigWriter.debugBeforePublish = (_) async {
        File(path).writeAsStringSync('{"n": ${++n}}');
      };

      await expectLater(
        writer.updateJson(AiToolType.claudecode, path, (d) => d['ours'] = true),
        throwsA(isA<LiveConfigConflictException>()),
      );
      expect(jsonDecode(File(path).readAsStringSync()), {'n': LiveConfigWriter.maxAttempts});
      expect(leftovers(), isEmpty);
    });

    test('failure while publishing the second file rolls back the first', () async {
      final a = f('a.json');
      File(a).writeAsStringSync('{"a": 1}');
      // b 的目标路径是一个目录，rename 会失败
      final b = f('b.json');
      Directory(b).createSync();

      await expectLater(
        writer.apply(AiToolType.codex, [
          LiveEdit.json(a, (d) => d['a'] = 2),
          LiveEdit(b, (_) => '{"b": 1}'),
        ]),
        throwsA(anything),
      );
      expect(File(a).readAsStringSync(), '{"a": 1}');
      expect(leftovers(), isEmpty);
    });

    test('LiveEdit.delete removes the file after backing it up', () async {
      final path = f('profile.json');
      File(path).writeAsStringSync('{"inferenceGatewayApiKey": "sk"}');
      await writer.apply(AiToolType.claudeDesktop, [LiveEdit.delete(path)]);
      expect(File(path).existsSync(), isFalse);
      final first = await writer.firstWriteBackupPath(AiToolType.claudeDesktop, path);
      expect(File(first).readAsStringSync(), '{"inferenceGatewayApiKey": "sk"}');
    });
  });

  group('backups', () {
    test('first-write backup is taken once and keeps the pristine original', () async {
      final path = f('settings.json');
      File(path).writeAsStringSync('{"v": 0}');

      for (var i = 1; i <= 3; i++) {
        await writer.updateJson(AiToolType.claudecode, path, (d) => d['v'] = i);
      }

      final first = await writer.firstWriteBackupPath(AiToolType.claudecode, path);
      expect(File(first).readAsStringSync(), '{"v": 0}');
      final source = jsonDecode(File('$first.source').readAsStringSync()) as Map;
      expect(source['path'], path);
      expect(source['existed'], isTrue);
    });

    test('first-write records a file that did not exist (restore = delete)', () async {
      final path = f('new.json');
      await writer.updateJson(AiToolType.cursor, path, (d) => d['a'] = 1);
      final first = await writer.firstWriteBackupPath(AiToolType.cursor, path);
      expect(File(first).existsSync(), isFalse);
      final source = jsonDecode(File('$first.source').readAsStringSync()) as Map;
      expect(source['existed'], isFalse);
    });

    test('rolling history keeps the newest maxHistory versions', () async {
      final path = f('settings.json');
      File(path).writeAsStringSync('{"v": 0}');
      const writes = LiveConfigWriter.maxHistory + 5;
      for (var i = 1; i <= writes; i++) {
        await writer.updateJson(AiToolType.claudecode, path, (d) => d['v'] = i);
      }
      final history = await writer.historyBackups(AiToolType.claudecode, path);
      expect(history, hasLength(LiveConfigWriter.maxHistory));
      // 最新的备份是倒数第二次写入前的内容
      expect(jsonDecode(history.first.readAsStringSync()), {'v': writes - 1});
      expect(jsonDecode(history.last.readAsStringSync()), {'v': writes - LiveConfigWriter.maxHistory});
    });
  });

  group('permissions', () {
    test('files holding keys and all backups are 0600, backup root is 0700', () async {
      final path = f('auth.json');
      File(path).writeAsStringSync('{}');
      Process.runSync('chmod', ['644', path]);

      await writer.updateJson(AiToolType.codex, path, (d) => d['OPENAI_API_KEY'] = 'sk', containsSecrets: true);

      expect(_mode(path), 0x180); // 0600
      final first = await writer.firstWriteBackupPath(AiToolType.codex, path);
      expect(_mode(first), 0x180);
      final history = await writer.historyBackups(AiToolType.codex, path);
      expect(_mode(history.single.path), 0x180);
      expect(Directory(p.join(tmp.path, 'backups')).statSync().mode & 0x1FF, 0x1C0); // 0700
    });

    test('files without keys keep their original mode', () async {
      final path = f('config.toml');
      File(path).writeAsStringSync('a = 1\n');
      Process.runSync('chmod', ['640', path]);
      await writer.updateText(AiToolType.codex, path, (c) => 'a = 2\n');
      expect(_mode(path), 0x1A0); // 0640
    });
  }, skip: Platform.isWindows ? 'POSIX permissions only' : false);

  group('per-tool lock', () {
    test('writes for the same tool are serialized', () async {
      final events = <String>[];
      final gate = Completer<void>();
      final first = writer.withToolLock(AiToolType.codex, () async {
        events.add('first:start');
        await gate.future;
        events.add('first:end');
      });
      final second = writer.withToolLock(AiToolType.codex, () async {
        events.add('second');
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, ['first:start']);
      gate.complete();
      await Future.wait([first, second]);
      expect(events, ['first:start', 'first:end', 'second']);
    });

    test('different tools do not block each other', () async {
      final gate = Completer<void>();
      final codex = writer.withToolLock(AiToolType.codex, () => gate.future);
      var geminiRan = false;
      await writer.withToolLock(AiToolType.gemini, () async => geminiRan = true);
      expect(geminiRan, isTrue);
      gate.complete();
      await codex;
    });

    test('lock is reentrant within the same operation', () async {
      final path = f('x.json');
      await writer.withToolLock(AiToolType.claudecode, () async {
        await writer.updateJson(AiToolType.claudecode, path, (d) => d['a'] = 1);
      }).timeout(const Duration(seconds: 5));
      expect(jsonDecode(File(path).readAsStringSync()), {'a': 1});
    });

    test('a failing holder releases the lock', () async {
      await expectLater(
        writer.withToolLock(AiToolType.cursor, () async => throw StateError('x')),
        throwsStateError,
      );
      var ran = false;
      await writer.withToolLock(AiToolType.cursor, () async => ran = true).timeout(const Duration(seconds: 5));
      expect(ran, isTrue);
    });

    test('parallel read-modify-write on one file loses no update', () async {
      final path = f('counter.json');
      File(path).writeAsStringSync('{"n": 0}');
      await Future.wait(List.generate(
        20,
        (_) => writer.updateJson(AiToolType.claudecode, path, (d) => d['n'] = (d['n'] as int) + 1),
      ));
      expect(jsonDecode(File(path).readAsStringSync()), {'n': 20});
    });
  });
}
