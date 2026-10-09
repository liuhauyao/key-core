import 'dart:io';
import 'dart:convert';
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
    
    if (!await file.exists()) {
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
      if (createBackup && await file.exists()) {
        await _createBackup(filePath);
      }

      // 确保目录存在
      final dir = Directory(path.dirname(filePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 写入临时文件
      final content = JsonEncoder.withIndent('  ').convert(config);
      await tempFile.writeAsString(content);

      // 验证临时文件内容
      final verifyContent = await tempFile.readAsString();
      final verifyConfig = json.decode(verifyContent);
      if (verifyConfig.toString() != config.toString()) {
        throw Exception('写入验证失败：内容不匹配');
      }

      // 原子性重命名（替换原文件）
      await tempFile.rename(filePath);
      
      print('配置文件写入成功: $filePath');
    } catch (e) {
      // 清理临时文件
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      throw Exception('写入配置文件失败: $e');
    }
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
    
    if (!await file.exists()) {
      throw Exception('源文件不存在，无法创建备份');
    }

    // 生成备份文件名：原文件名.backup.时间戳
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '$filePath.backup.$timestamp';
    
    try {
      await file.copy(backupPath);
      print('配置备份已创建: $backupPath');
      return backupPath;
    } catch (e) {
      throw Exception('创建备份失败: $e');
    }
  }

  /// 恢复配置文件备份
  Future<void> restoreBackup(String backupPath, String targetPath) async {
    final backupFile = File(backupPath);
    
    if (!await backupFile.exists()) {
      throw Exception('备份文件不存在: $backupPath');
    }

    try {
      await backupFile.copy(targetPath);
      print('配置已从备份恢复: $backupPath -> $targetPath');
    } catch (e) {
      throw Exception('恢复备份失败: $e');
    }
  }

  /// 获取配置文件的所有备份
  Future<List<String>> listBackups(String filePath) async {
    final dir = Directory(path.dirname(filePath));
    final fileName = path.basename(filePath);
    
    if (!await dir.exists()) {
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

    // 按时间戳排序（新的在前）
    backups.sort((a, b) => b.compareTo(a));
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
        print('已删除旧备份: ${backups[i]}');
      } catch (e) {
        print('删除备份失败: $e');
      }
    }
  }

  /// 检查配置文件是否存在
  Future<bool> exists(String filePath) async {
    return await File(filePath).exists();
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
