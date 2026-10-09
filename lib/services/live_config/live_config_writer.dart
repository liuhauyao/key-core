import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;

import '../../models/mcp_server.dart' show AiToolType;
import '../settings_service.dart';
import 'live_patches.dart';

export 'live_patches.dart' show LiveConfigParseException, JsonPatch, DotEnvPatch;

/// 读取配置文件失败（权限、编码等），本次写入被中止
class LiveConfigReadException implements Exception {
  final String path;
  final Object error;

  LiveConfigReadException(this.path, this.error);

  @override
  String toString() => '无法读取配置文件 $path（已中止写入，文件未被修改）：$error';
}

/// 写入过程中文件被其他进程反复修改，放弃本次写入
class LiveConfigConflictException implements Exception {
  final String path;

  LiveConfigConflictException(this.path);

  @override
  String toString() => '配置文件 $path 在写入期间被其他程序修改，已放弃写入，请稍后重试';
}

/// 对一个文件的修改。
///
/// [transform] 收到写前内容（文件不存在为 null），返回写后内容；返回 null 表示删除该文件。
/// 返回值与写前相同则视为未修改，不写盘、不备份。
class LiveEdit {
  final String path;
  final String? Function(String? current) transform;

  /// 文件含有 API Key 等敏感信息：写入后权限设为 0600（非 Windows）
  final bool containsSecrets;

  const LiveEdit(this.path, this.transform, {this.containsSecrets = false});

  /// 修改 JSON 对象文件。解析失败抛 [LiveConfigParseException]，不会以空对象覆盖。
  ///
  /// [mutate] 原位修改文档；修改前后内容相同则不写盘。
  factory LiveEdit.json(
    String path,
    void Function(Map<String, dynamic> doc) mutate, {
    bool containsSecrets = false,
    String Function(String raw)? preprocess,
    bool createIfMissing = true,
  }) {
    return LiveEdit(
      path,
      (current) {
        if (current == null && !createIfMissing) return null;
        final doc = JsonPatch.parseObject(path, current, preprocess: preprocess);
        final before = current == null ? null : jsonEncode(doc);
        mutate(doc);
        if (before != null && before == jsonEncode(doc)) return current;
        return JsonPatch.encode(doc, original: current);
      },
      containsSecrets: containsSecrets,
    );
  }

  /// 按行修改 `.env` 文件，保留注释、空行与其他变量顺序。
  factory LiveEdit.dotenv(
    String path, {
    Map<String, String> set = const {},
    Set<String> remove = const {},
    bool containsSecrets = true,
  }) {
    return LiveEdit(
      path,
      (current) => DotEnvPatch.apply(current, set: set, remove: remove),
      containsSecrets: containsSecrets,
    );
  }

  /// 文本文件（如 Codex 的 config.toml）。读取失败会中止，不会把空串当作原内容。
  factory LiveEdit.text(
    String path,
    String Function(String current) transform, {
    bool containsSecrets = false,
  }) {
    return LiveEdit(path, (current) => transform(current ?? ''), containsSecrets: containsSecrets);
  }

  /// 删除文件（删除前同样会备份）
  factory LiveEdit.delete(String path) => LiveEdit(path, (_) => null);
}

/// 一次写入的结果
class LiveWriteResult {
  /// 实际被修改（写入或删除）的文件
  final List<String> changedPaths;

  const LiveWriteResult(this.changedPaths);

  bool get changed => changedPaths.isNotEmpty;
}

/// 统一的“把密钥写进工具配置文件”的写入引擎。
///
/// 设计借鉴 CC Switch v4 的 `src-tauri/src/live/engine.rs`：
/// 1. **解析失败即中止**：任何一个文件读不了/解析不了，整组修改都不落盘；
/// 2. **只改关键字段**：由调用方的 [LiveEdit] 决定，补丁器保留其他键与顺序；
/// 3. **原子写**：同目录临时文件 + flush + rename，避免写到一半的半截文件；
/// 4. **首写备份**：每个文件第一次被 Key Core 改写前的原文件保存一份，永不覆盖；
/// 5. **滚动备份**：每次改写前保存带时间戳的副本，每个文件保留最近 [maxHistory] 份；
/// 6. **0600**：含密钥的文件与所有备份文件仅所有者可读写；
/// 7. **按工具串行**：同一工具的所有写入（切换、托盘、MCP 下发）排队执行；
/// 8. **写前复核**：发布前重读原文件，若期间被其他程序改动则以新内容为底重算。
///
/// 多个文件（如 Codex 的 config.toml + auth.json）在一次 [apply] 中提交：先全部解析、
/// 生成临时文件，全部成功后才依次替换；替换中途失败会把已替换的文件恢复原样。
class LiveConfigWriter {
  LiveConfigWriter._();

  static final LiveConfigWriter instance = LiveConfigWriter._();

  /// 每个文件保留的滚动备份数
  static const int maxHistory = 10;

  /// 写前复核失败时的最大重试次数
  static const int maxAttempts = 3;

  /// 测试用：覆盖备份根目录
  @visibleForTesting
  static String? debugBackupRootOverride;

  /// 测试用：在“生成临时文件之后、发布之前”调用，用于模拟并发修改或失败
  @visibleForTesting
  static Future<void> Function(String path)? debugBeforePublish;

  final Map<AiToolType, Future<void>> _tails = {};
  static final Object _heldLocksKey = Object();

  /// 备份根目录：`~/.keycore/backups/live`
  Future<String> backupRoot() async {
    final override = debugBackupRootOverride;
    if (override != null) return override;
    final home = await SettingsService.getUserHomeDir();
    return p.join(home, '.keycore', 'backups', 'live');
  }

  /// 在 [tool] 的写锁内执行 [action]。同一 Zone 内可重入。
  Future<T> withToolLock<T>(AiToolType tool, Future<T> Function() action) async {
    final held = (Zone.current[_heldLocksKey] as Set<AiToolType>?) ?? const <AiToolType>{};
    if (held.contains(tool)) return action();

    final previous = _tails[tool] ?? Future<void>.value();
    final completer = Completer<void>();
    final tail = completer.future;
    _tails[tool] = tail;
    try {
      await previous.catchError((_) {});
      return await runZoned(
        action,
        zoneValues: {_heldLocksKey: {...held, tool}},
      );
    } finally {
      completer.complete();
      if (identical(_tails[tool], tail)) _tails.remove(tool);
    }
  }

  /// 修改单个 JSON 文件
  Future<LiveWriteResult> updateJson(
    AiToolType tool,
    String path,
    void Function(Map<String, dynamic> doc) mutate, {
    bool containsSecrets = false,
    String Function(String raw)? preprocess,
    bool createIfMissing = true,
  }) =>
      apply(tool, [
        LiveEdit.json(path, mutate,
            containsSecrets: containsSecrets, preprocess: preprocess, createIfMissing: createIfMissing),
      ]);

  /// 修改单个 `.env` 文件
  Future<LiveWriteResult> updateDotEnv(
    AiToolType tool,
    String path, {
    Map<String, String> set = const {},
    Set<String> remove = const {},
    bool containsSecrets = true,
  }) =>
      apply(tool, [LiveEdit.dotenv(path, set: set, remove: remove, containsSecrets: containsSecrets)]);

  /// 修改单个文本文件
  Future<LiveWriteResult> updateText(
    AiToolType tool,
    String path,
    String Function(String current) transform, {
    bool containsSecrets = false,
  }) =>
      apply(tool, [LiveEdit.text(path, transform, containsSecrets: containsSecrets)]);

  /// 原子地提交一组修改
  Future<LiveWriteResult> apply(AiToolType tool, List<LiveEdit> edits) {
    return withToolLock(tool, () async {
      for (var attempt = 1;; attempt++) {
        try {
          return await _applyOnce(tool, edits);
        } on _ConcurrentModification catch (e) {
          if (attempt >= maxAttempts) throw LiveConfigConflictException(e.path);
        }
      }
    });
  }

  Future<LiveWriteResult> _applyOnce(AiToolType tool, List<LiveEdit> edits) async {
    final planned = <_PlannedWrite>[];
    try {
      // 1. 读取 + 计算（任何失败都不会碰磁盘）
      for (final edit in edits) {
        final target = await _resolveTarget(edit.path);
        final original = await _readBytes(target);
        final String? originalText;
        try {
          originalText = original == null ? null : utf8.decode(original);
        } on FormatException catch (e) {
          throw LiveConfigParseException(target, '不是有效的 UTF-8 文本：${e.message}');
        }
        final next = edit.transform(originalText);
        if (next == originalText) continue;
        if (next == null && original == null) continue;
        planned.add(_PlannedWrite(
          path: target,
          original: original,
          next: next,
          containsSecrets: edit.containsSecrets,
        ));
      }
      if (planned.isEmpty) return const LiveWriteResult([]);

      // 2. 生成临时文件
      for (final w in planned) {
        if (w.next == null) continue;
        final dir = Directory(p.dirname(w.path));
        if (!await dir.exists()) await dir.create(recursive: true);
        final tmp = File(p.join(dir.path, '.${p.basename(w.path)}.keycore-${_randomSuffix()}.tmp'));
        await tmp.writeAsString(w.next!, flush: true);
        w.tempPath = tmp.path;
        await _applyMode(tmp.path, secret: w.containsSecrets, originalPath: w.original != null ? w.path : null);
      }

      // 3. 备份（首写 + 滚动）
      for (final w in planned) {
        await _backup(tool, w.path, w.original);
      }

      // 4. 发布前复核：期间文件被改动则整体重来
      for (final w in planned) {
        final hook = debugBeforePublish;
        if (hook != null) await hook(w.path);
        final now = await _readBytes(w.path);
        if (!_sameBytes(now, w.original)) throw _ConcurrentModification(w.path);
      }

      // 5. 依次发布；中途失败则恢复已发布的文件
      final published = <_PlannedWrite>[];
      try {
        for (final w in planned) {
          if (w.next == null) {
            await File(w.path).delete();
          } else {
            await File(w.tempPath!).rename(w.path);
            w.tempPath = null;
          }
          published.add(w);
        }
      } catch (e) {
        for (final w in published.reversed) {
          await _restoreOriginal(w);
        }
        rethrow;
      }
      return LiveWriteResult(planned.map((w) => w.path).toList());
    } finally {
      for (final w in planned) {
        final tmp = w.tempPath;
        if (tmp != null) {
          try {
            await File(tmp).delete();
          } catch (_) {}
        }
      }
    }
  }

  /// 已存在的符号链接按目标文件写入，避免 rename 把链接替换成普通文件
  Future<String> _resolveTarget(String path) async {
    try {
      if (await FileSystemEntity.isLink(path)) {
        return await File(path).resolveSymbolicLinks();
      }
    } catch (_) {}
    return path;
  }

  Future<List<int>?> _readBytes(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw LiveConfigReadException(path, e.osError?.message ?? e.message);
    }
  }

  static bool _sameBytes(List<int>? a, List<int>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _restoreOriginal(_PlannedWrite w) async {
    try {
      final original = w.original;
      if (original == null) {
        final f = File(w.path);
        if (await f.exists()) await f.delete();
        return;
      }
      final tmp = File('${w.path}.keycore-restore-${_randomSuffix()}');
      await tmp.writeAsBytes(original, flush: true);
      await _applyMode(tmp.path, secret: w.containsSecrets);
      await tmp.rename(w.path);
    } catch (e) {
      debugPrint('LiveConfigWriter: 恢复 ${w.path} 失败（可从备份恢复）: $e');
    }
  }

  /// 设置权限：含密钥的文件 0600；否则沿用原文件权限
  Future<void> _applyMode(String path, {required bool secret, String? originalPath}) async {
    if (Platform.isWindows) return;
    String? mode;
    if (secret) {
      mode = '600';
    } else if (originalPath != null) {
      try {
        final stat = await File(originalPath).stat();
        mode = (stat.mode & 0x1FF).toRadixString(8);
      } catch (_) {}
    }
    if (mode == null) return;
    try {
      final result = await Process.run('chmod', [mode, path]);
      if (result.exitCode != 0) {
        debugPrint('LiveConfigWriter: chmod $mode $path 失败: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('LiveConfigWriter: chmod $mode $path 失败: $e');
    }
  }

  static String _pathId(String path) {
    final digest = sha256.convert(utf8.encode(p.normalize(p.absolute(path)))).toString();
    final base = p.basename(path).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${digest.substring(0, 12)}-$base';
  }

  static String _toolDir(AiToolType tool) => tool.value;

  /// 首写备份文件路径（不论是否存在）
  Future<String> firstWriteBackupPath(AiToolType tool, String path) async {
    final root = await backupRoot();
    return p.join(root, 'first-write', _toolDir(tool), _pathId(path));
  }

  /// 某文件的滚动备份，按时间从新到旧
  Future<List<File>> historyBackups(AiToolType tool, String path) async {
    final root = await backupRoot();
    final dir = Directory(p.join(root, 'history', _toolDir(tool), _pathId(path)));
    if (!await dir.exists()) return [];
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  Future<void> _backup(AiToolType tool, String path, List<int>? original) async {
    final root = await backupRoot();
    final id = _pathId(path);
    final rootDir = Directory(root);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
      // 备份里有密钥：目录仅本人可访问
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['700', root]);
        } catch (_) {}
      }
    }

    // 首写备份：每个文件只做一次；原文件不存在时只记录来源（恢复 = 删除）
    final first = File(p.join(root, 'first-write', _toolDir(tool), id));
    final source = File('${first.path}.source');
    if (!await source.exists()) {
      await source.parent.create(recursive: true);
      if (original != null) {
        await first.writeAsBytes(original, flush: true);
        await _applyMode(first.path, secret: true);
      }
      await source.writeAsString(
        jsonEncode({
          'path': path,
          'existed': original != null,
          'time': DateTime.now().toIso8601String(),
        }),
        flush: true,
      );
    }

    // 滚动备份
    if (original == null) return;
    final historyDir = Directory(p.join(root, 'history', _toolDir(tool), id));
    await historyDir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    var backup = File(p.join(historyDir.path, stamp));
    var n = 1;
    while (await backup.exists()) {
      backup = File(p.join(historyDir.path, '$stamp-${n++}'));
    }
    await backup.writeAsBytes(original, flush: true);
    await _applyMode(backup.path, secret: true);

    final all = historyDir.listSync().whereType<File>().toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final old in all.skip(maxHistory)) {
      try {
        await old.delete();
      } catch (_) {}
    }
  }

  static final Random _random = Random.secure();

  static String _randomSuffix() =>
      List.generate(8, (_) => _random.nextInt(36).toRadixString(36)).join();
}

class _PlannedWrite {
  final String path;
  final List<int>? original;
  final String? next;
  final bool containsSecrets;
  String? tempPath;

  _PlannedWrite({
    required this.path,
    required this.original,
    required this.next,
    required this.containsSecrets,
  });
}

class _ConcurrentModification implements Exception {
  final String path;

  _ConcurrentModification(this.path);
}
