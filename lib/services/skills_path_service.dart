import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mcp_server.dart';
import '../models/skill.dart';
import 'settings_service.dart';

/// Skills 路径服务
class SkillsPathService {
  static const String keyCoreDirName = '.keycore';
  static const String skillsDirName = 'skills';
  static const String managedMarkerFileName = '.keycore-managed';

  /// 测试专用：覆盖用户主目录
  static String? debugHomeDirOverride;

  /// 支持 Skills 符号链接分发的工具
  static const List<SkillTargetTool> supportedTools = SkillTargetTool.values;

  /// 新建 Skill 时默认勾选的工具（保持原有行为，避免向未安装的工具目录写入）
  static const List<SkillTargetTool> defaultEnabledTools = [
    SkillTargetTool.cursor,
    SkillTargetTool.claudecode,
    SkillTargetTool.codex,
  ];

  /// 测试专用：覆盖环境变量（HERMES_HOME / PI_CODING_AGENT_DIR / MINIMAX_DATA_DIR）
  static Map<String, String>? debugEnvironmentOverride;

  /// Skills 存储位置设置键：`keycore`（~/.keycore/skills，默认）或 `agents`（~/.agents/skills，
  /// 与 CC Switch 的统一存储一致）
  static const String storageLocationKey = 'skills_storage_location';

  /// 测试专用：覆盖存储位置
  static String? debugStorageLocationOverride;

  Future<String> _homeDir() async {
    return debugHomeDirOverride ?? await SettingsService.getUserHomeDir();
  }

  /// 获取 Key Core 用户目录 ~/.keycore
  Future<String> getKeyCoreRoot() async {
    final homeDir = await _homeDir();
    return path.join(homeDir, keyCoreDirName);
  }

  /// 获取 Skills 源目录 ~/.keycore/skills
  Future<String> getSkillsSourceDir() async {
    final location = await getStorageLocation();
    if (location == 'agents') {
      return getAgentsSkillsDir();
    }
    final root = await getKeyCoreRoot();
    return path.join(root, skillsDirName);
  }

  /// 默认存储目录 ~/.keycore/skills
  Future<String> getKeyCoreSkillsDir() async {
    final root = await getKeyCoreRoot();
    return path.join(root, skillsDirName);
  }

  /// 统一存储目录 ~/.agents/skills
  Future<String> getAgentsSkillsDir() async {
    final homeDir = await _homeDir();
    return path.join(homeDir, '.agents', skillsDirName);
  }

  Future<String> getStorageLocation() async {
    if (debugStorageLocationOverride != null) return debugStorageLocationOverride!;
    if (debugHomeDirOverride != null) return 'keycore';
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(storageLocationKey) ?? 'keycore';
    } catch (_) {
      return 'keycore';
    }
  }

  Future<void> setStorageLocation(String location) async {
    if (debugStorageLocationOverride != null || debugHomeDirOverride != null) {
      debugStorageLocationOverride = location;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageLocationKey, location);
  }

  /// 卸载备份目录 ~/.keycore/skill-backups
  Future<String> getBackupsDir() async {
    final root = await getKeyCoreRoot();
    return path.join(root, 'skill-backups');
  }

  String? _env(String name) {
    final env = debugEnvironmentOverride ??
        (debugHomeDirOverride != null ? const <String, String>{} : Platform.environment);
    final v = env[name];
    return (v == null || v.trim().isEmpty) ? null : v.trim();
  }

  /// 获取工具的 skills 目录
  Future<String> getToolSkillsDir(SkillTargetTool tool) async {
    final homeDir = await _homeDir();
    switch (tool) {
      case SkillTargetTool.cursor:
        return path.join(homeDir, '.cursor', skillsDirName);
      case SkillTargetTool.claudecode:
        return path.join(homeDir, '.claude', skillsDirName);
      case SkillTargetTool.codex:
        return path.join(homeDir, '.codex', skillsDirName);
      case SkillTargetTool.gemini:
        return path.join(homeDir, '.gemini', skillsDirName);
      case SkillTargetTool.opencode:
        return path.join(homeDir, '.config', 'opencode', skillsDirName);
      case SkillTargetTool.grokBuild:
        return path.join(homeDir, '.grok', skillsDirName);
      case SkillTargetTool.openclaw:
        return path.join(homeDir, '.openclaw', skillsDirName);
      case SkillTargetTool.hermes:
        return path.join(_env('HERMES_HOME') ?? path.join(homeDir, '.hermes'), skillsDirName);
      case SkillTargetTool.pi:
        return path.join(
            _env('PI_CODING_AGENT_DIR') ?? path.join(homeDir, '.pi', 'agent'), skillsDirName);
      case SkillTargetTool.mcode:
        return path.join(_env('MINIMAX_DATA_DIR') ?? path.join(homeDir, '.minimax'), skillsDirName);
    }
  }

  Future<String> getToolSkillsDirFromAiTool(AiToolType tool) async {
    final target = SkillTargetTool.fromAiToolType(tool);
    if (target == null) {
      throw UnsupportedError('Tool $tool does not support skills sync');
    }
    return getToolSkillsDir(target);
  }

  /// 已安装的工具（其 skills 目录的父目录存在，如 ~/.claude）；用于安装时默认启用
  Future<List<SkillTargetTool>> detectInstalledTools() async {
    final result = <SkillTargetTool>[];
    for (final tool in supportedTools) {
      final dir = await getToolSkillsDir(tool);
      if (await Directory(path.dirname(dir)).exists()) result.add(tool);
    }
    return result;
  }

  /// 获取 Skill 在源目录中的绝对路径
  Future<String> getSkillSourcePath(String relativePath) async {
    final sourceDir = await getSkillsSourceDir();
    return path.join(sourceDir, relativePath);
  }

  /// 获取 Skill 在工具目录中的绝对路径
  Future<String> getSkillToolPath(SkillTargetTool tool, String relativePath) async {
    final toolDir = await getToolSkillsDir(tool);
    return path.join(toolDir, relativePath);
  }

  /// 确保目录存在
  Future<Directory> ensureDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 确保 Skills 源目录存在
  Future<String> ensureSkillsSourceDir() async {
    final dirPath = await getSkillsSourceDir();
    await ensureDirectory(dirPath);
    return dirPath;
  }

  /// 确保工具 skills 目录存在
  Future<String> ensureToolSkillsDir(SkillTargetTool tool) async {
    final dirPath = await getToolSkillsDir(tool);
    await ensureDirectory(dirPath);
    return dirPath;
  }

  /// Key Core 管理标记文件路径
  String getManagedMarkerPath(String skillDirPath) {
    return path.join(skillDirPath, managedMarkerFileName);
  }
}
