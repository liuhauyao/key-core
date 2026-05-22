import 'dart:io';
import 'package:path/path.dart' as path;
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
  static const List<SkillTargetTool> supportedTools = [
    SkillTargetTool.cursor,
    SkillTargetTool.claudecode,
    SkillTargetTool.codex,
  ];

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
    final root = await getKeyCoreRoot();
    return path.join(root, skillsDirName);
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
    }
  }

  Future<String> getToolSkillsDirFromAiTool(AiToolType tool) async {
    final target = SkillTargetTool.fromAiToolType(tool);
    if (target == null) {
      throw UnsupportedError('Tool $tool does not support skills sync');
    }
    return getToolSkillsDir(target);
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
