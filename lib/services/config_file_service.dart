import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// 配置文件操作服务
/// 支持 JSON 配置文件的原子性读写和备份
class ConfigFileService {
  static ConfigFileService? _instance;

  ConfigFileService._();

  static ConfigFileService get instance {
    _instance ??= ConfigFileService._();
    return _instance!;
  }

  /// 读取 JSON 配置文件
  Future<Map<String, dynamic>> readJsonConfig(String filePath) async {
    final file = File(filePath);
    
    if (!file.existsSync()) {
      throw Exception('配置文件不存在: $filePath');
    }

    try {
      final content = await file.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('读取配置文件失败: $e');
    }
  }

  /// 写入 JSON 配置文件（原子性操作）
  /// 
  /// 1. 创建临时文件
  /// 2. 写入内容到临时文件
  /// 3. 验证临时文件内容
  /// 4. 原子性重命名（替换原文件）
  Future<void> writeJsonConfig(
    String filePath,
    Map<String, dynamic> config, {
    bool createBackup = true,
  }) async {
    final file = File(filePath);
    final tempFilePath = '$filePath.tmp';
    final tempFile = File(tempFilePath);

    try {
      // 如果原文件存在且需要备份，先创建备份
      if (createBackup && file.existsSync()) {
        await _createBackup(filePath);
      }

      // 确保目录存在
      final dir = Directory(path.dirname(filePath));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      // 写入临时文件
      final content = const JsonEncoder.withIndent('  ').convert(config);
      await tempFile.writeAsString(content);

      // 验证临时文件内容
      final verifyContent = await tempFile.readAsString();
      final verifyConfig = json.decode(verifyContent);
      if (verifyConfig.toString() != config.toString()) {
        throw Exception('写入验证失败：内容不匹配');
      }

      // 保留原文件权限；新文件可能包含 API Key，默认仅当前用户可读写
      await _copyPermissions(file, tempFile);

      // 原子性重命名（替换原文件）
      await tempFile.rename(filePath);
      
      debugPrint('配置文件写入成功: $filePath');
    } catch (e) {
      // 清理临时文件
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      throw Exception('写入配置文件失败: $e');
    }
  }

  /// 读取文本配置文件（.env / TOML 等），文件不存在时返回 null
  Future<String?> readTextConfig(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    return file.readAsString();
  }

  /// 写入文本配置文件（原子性操作，可选自动备份）
  ///
  /// 与 [writeJsonConfig] 相同：先备份 → 写临时文件 → 校验 → 原子性重命名。
  Future<void> writeTextConfig(
    String filePath,
    String content, {
    bool createBackup = true,
  }) async {
    final file = File(filePath);
    final tempFile = File('$filePath.tmp');
    try {
      if (createBackup && file.existsSync()) {
        await _createBackup(filePath);
      }
      final dir = Directory(path.dirname(filePath));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      await tempFile.writeAsString(content, flush: true);
      if (await tempFile.readAsString() != content) {
        throw Exception('写入验证失败：内容不匹配');
      }
      await _copyPermissions(file, tempFile);
      await tempFile.rename(filePath);
    } catch (e) {
      if (tempFile.existsSync()) {
        await tempFile.delete();
      }
      throw Exception('写入配置文件失败: $e');
    }
  }

  /// 把 [original] 的权限复制到 [target]；原文件不存在时设为 600（POSIX）
  Future<void> _copyPermissions(File original, File target) async {
    if (Platform.isWindows) return;
    try {
      final mode = original.existsSync()
          ? (original.statSync().mode & 0x1FF).toRadixString(8)
          : '600';
      await Process.run('chmod', [mode, target.path]);
    } catch (_) {
      // 权限设置失败不影响写入
    }
  }

  /// 从备份文件名中解析创建时间（文件名格式：`<原文件名>.backup.<毫秒时间戳>`）
  static DateTime? backupTimestamp(String backupPath) {
    final name = path.basename(backupPath);
    final idx = name.lastIndexOf('.backup.');
    if (idx < 0) return null;
    final ms = int.tryParse(name.substring(idx + '.backup.'.length));
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// 更新 JSON 配置文件的指定字段
  /// 
  /// 只修改指定的字段，保留其他字段不变
  Future<void> updateJsonFields(
    String filePath,
    Map<String, dynamic> updates, {
    bool createBackup = true,
  }) async {
    // 读取现有配置
    final config = await readJsonConfig(filePath);

    // 合并更新
    updates.forEach((key, value) {
      if (value == null) {
        config.remove(key);
      } else {
        config[key] = value;
      }
    });

    // 写入配置
    await writeJsonConfig(filePath, config, createBackup: createBackup);
  }

  /// 创建配置文件备份
  Future<String> _createBackup(String filePath) async {
    final file = File(filePath);
    
    if (!file.existsSync()) {
      throw Exception('源文件不存在，无法创建备份');
    }

    // 生成备份文件名：原文件名.backup.时间戳
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    var backupPath = '$filePath.backup.$timestamp';
    // 同一毫秒内多次备份时顺延时间戳，避免覆盖已有备份
    while (File(backupPath).existsSync()) {
      timestamp++;
      backupPath = '$filePath.backup.$timestamp';
    }
    
    try {
      await file.copy(backupPath);
      debugPrint('配置备份已创建: $backupPath');
      return backupPath;
    } catch (e) {
      throw Exception('创建备份失败: $e');
    }
  }

  /// 恢复配置文件备份
  Future<void> restoreBackup(String backupPath, String targetPath) async {
    final backupFile = File(backupPath);
    
    if (!backupFile.existsSync()) {
      throw Exception('备份文件不存在: $backupPath');
    }

    try {
      // 恢复前先备份当前文件，保证恢复操作本身可撤销
      if (File(targetPath).existsSync()) {
        await _createBackup(targetPath);
      }
      await backupFile.copy(targetPath);
      debugPrint('配置已从备份恢复: $backupPath -> $targetPath');
    } catch (e) {
      throw Exception('恢复备份失败: $e');
    }
  }

  /// 获取配置文件的所有备份
  Future<List<String>> listBackups(String filePath) async {
    final dir = Directory(path.dirname(filePath));
    final fileName = path.basename(filePath);
    
    if (!dir.existsSync()) {
      return [];
    }

    final backups = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        final name = path.basename(entity.path);
        if (name.startsWith('$fileName.backup.')) {
          backups.add(entity.path);
        }
      }
    }

    // 按时间戳排序（新的在前）；无法解析时间戳时回退到字符串比较
    backups.sort((a, b) {
      final ta = backupTimestamp(a);
      final tb = backupTimestamp(b);
      if (ta != null && tb != null) return tb.compareTo(ta);
      return b.compareTo(a);
    });
    return backups;
  }

  /// 清理旧备份（保留最近 N 个）
  Future<void> cleanupOldBackups(String filePath, {int keep = 5}) async {
    final backups = await listBackups(filePath);
    
    if (backups.length <= keep) {
      return; // 不需要清理
    }

    // 删除多余的备份
    for (int i = keep; i < backups.length; i++) {
      try {
        final file = File(backups[i]);
        await file.delete();
        debugPrint('已删除旧备份: ${backups[i]}');
      } catch (e) {
        debugPrint('删除备份失败: $e');
      }
    }
  }

  /// 检查配置文件是否存在
  Future<bool> exists(String filePath) async {
    return File(filePath).existsSync();
  }

  /// 获取配置文件路径（根据平台和工具）
  String getConfigPath(String tool) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) {
      throw Exception('无法获取用户主目录');
    }

    switch (tool.toLowerCase()) {
      case 'claude_code':
        return path.join(home, '.claude.json');
      
      case 'codex':
        // Codex 使用 TOML 格式，这里返回配置目录
        return path.join(home, '.config', 'codex', 'config.toml');
      
      case 'gemini_cli':
        return path.join(home, '.gemini', 'config.json');
      
      case 'openclaw':
        return path.join(home, '.openclaw', 'config.json');
      
      case 'grok_build':
        return path.join(home, '.grok', 'config.json');
      
      default:
        throw Exception('不支持的工具: $tool');
    }
  }

  /// 获取工具的配置目录
  String getConfigDir(String tool) {
    final configPath = getConfigPath(tool);
    return path.dirname(configPath);
  }
}
