import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../skill_parser_service.dart';

/// Skills 同步方式（与 CC Switch 一致）
enum SkillSyncMethod {
  /// 优先符号链接，失败（如 Windows 无权限）时回退为复制
  auto,
  symlink,
  copy;

  String get value => name;

  static SkillSyncMethod fromString(String? value) {
    for (final m in SkillSyncMethod.values) {
      if (m.name == value) return m;
    }
    return SkillSyncMethod.auto;
  }
}

/// Skills 文件系统工具：内容哈希、复制、受管副本标记、安全解压路径
class SkillsFs {
  SkillsFs._();

  static const String markerFileName = '.keycore-managed';

  /// 计算目录内容哈希（SHA-256）。与 CC Switch `compute_dir_hash` 规则一致：
  /// 递归收集所有非隐藏文件（任意一级以 `.` 开头的名字都跳过），按相对路径排序，
  /// 依次写入 `相对路径\0内容\0`。
  static Future<String> computeDirHash(String dirPath) async {
    final root = Directory(dirPath);
    final files = <String>[];
    await _collect(root, root.path, files);
    files.sort();
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    for (final rel in files) {
      input.add(utf8.encode(rel));
      input.add(const [0]);
      input.add(await File(path.join(root.path, rel)).readAsBytes());
      input.add(const [0]);
    }
    input.close();
    return sink.value.toString();
  }

  static Future<void> _collect(Directory dir, String base, List<String> out) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: true)) {
      final name = path.basename(entity.path);
      if (name.startsWith('.')) continue;
      final type = await FileSystemEntity.type(entity.path);
      if (type == FileSystemEntityType.directory) {
        await _collect(Directory(entity.path), base, out);
      } else if (type == FileSystemEntityType.file) {
        out.add(path.relative(entity.path, from: base).replaceAll('\\', '/'));
      }
    }
  }

  /// 复制目录（跳过 Key Core 标记文件与 .git）
  static Future<void> copyDirectory(String source, String destination) async {
    final src = Directory(source);
    await Directory(destination).create(recursive: true);
    await for (final entity in src.list(recursive: true, followLinks: false)) {
      final relative = path.relative(entity.path, from: src.path);
      final parts = path.split(relative);
      if (parts.contains('.git') || path.basename(relative) == markerFileName) continue;
      final destPath = path.join(destination, relative);
      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(path.dirname(destPath)).create(recursive: true);
        await entity.copy(destPath);
      } else if (entity is Link) {
        final target = await entity.target();
        await Directory(path.dirname(destPath)).create(recursive: true);
        await Link(destPath).create(target);
      }
    }
  }

  /// 写入受管副本标记（复制模式下放在工具目录的副本里，不写入源目录）
  static Future<void> writeCopyMarker(
    String copyDir, {
    required String relativePath,
    required String hash,
  }) async {
    await File(path.join(copyDir, markerFileName)).writeAsString(
      'managed-by=keycore\nsource=$relativePath\nhash=$hash\n',
    );
  }

  /// 读取受管副本标记；不是 Key Core 复制出来的目录返回 null。
  /// 旧版本误写入源目录的标记只有 `managed-by=keycore` 一行，不含 `source=`，因此不会被当成副本。
  static Future<({String relativePath, String hash})?> readCopyMarker(String dir) async {
    final file = File(path.join(dir, markerFileName));
    if (!await file.exists()) return null;
    try {
      final values = <String, String>{};
      for (final line in await file.readAsLines()) {
        final i = line.indexOf('=');
        if (i > 0) values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
      }
      if (values['managed-by'] != 'keycore' || values['source'] == null) return null;
      return (relativePath: values['source']!, hash: values['hash'] ?? '');
    } catch (_) {
      return null;
    }
  }

  /// 旧版本 bug：同步时把标记文件写进了 symlink 指向的源目录。这里清理掉这些遗留标记。
  static Future<int> cleanupLegacySourceMarkers(String sourceRoot) async {
    final root = Directory(sourceRoot);
    if (!await root.exists()) return 0;
    var removed = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || path.basename(entity.path) != markerFileName) continue;
      final content = await entity.readAsString();
      if (!content.contains('source=')) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }

  /// 查找目录下所有包含 SKILL.md 的子目录（不进入已识别的 skill 内部，最多 [maxDepth] 层）
  static Future<List<String>> findSkillDirs(String root, {int maxDepth = 5}) async {
    final result = <String>[];
    Future<void> walk(Directory dir, int depth) async {
      if (await File(path.join(dir.path, SkillParserService.skillFileName)).exists()) {
        result.add(dir.path);
        return;
      }
      if (depth >= maxDepth) return;
      final children = <Directory>[];
      await for (final e in dir.list(followLinks: false)) {
        if (e is Directory && !path.basename(e.path).startsWith('.')) children.add(e);
      }
      children.sort((a, b) => a.path.compareTo(b.path));
      for (final c in children) {
        await walk(c, depth + 1);
      }
    }

    if (await Directory(root).exists()) await walk(Directory(root), 0);
    return result;
  }

  /// 把 Skill 名字规整为安全的目录名
  static String sanitizeDirName(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-').replaceAll(RegExp(r'^[-.]+|-+$'), '');
    return s.isEmpty ? 'skill' : s;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
