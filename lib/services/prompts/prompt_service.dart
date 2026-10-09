import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/mcp_server.dart';
import '../../models/prompt.dart';
import '../ai_tool_config_service.dart';
import '../database_service.dart';
import '../live_config/live_config_writer.dart';

/// 系统提示词服务（对齐 CC Switch v4.0.6 `PromptService`）。
///
/// - 每个工具同一时间最多启用一条提示词，启用的那条写入该工具的提示词文件；
/// - 启用前先把 live 文件内容回填到当前启用项；没有启用项时自动创建“原始提示词”备份，
///   避免覆盖用户手写的内容；
/// - 停用最后一条启用项时清空文件；新建、导入或保存未启用的条目都不会动文件；
/// - 所有文件写入都经过 [LiveConfigWriter]（原子写入 + 自动备份 + 工具级锁）。
class PromptService {
  PromptService({AiToolConfigService? configService, LiveConfigWriter? writer})
      : _configService = configService ?? AiToolConfigService(),
        _writer = writer ?? LiveConfigWriter.instance;

  final AiToolConfigService _configService;
  final LiveConfigWriter _writer;
  final DatabaseService _db = DatabaseService.instance;

  /// 支持 Prompts 的工具（Claude Desktop 不支持；Cursor / Windsurf 不在 CC Switch 范围内）
  static const List<AiToolType> supportedTools = [
    AiToolType.claudecode,
    AiToolType.codex,
    AiToolType.gemini,
    AiToolType.grokBuild,
    AiToolType.opencode,
    AiToolType.openclaw,
    AiToolType.hermes,
    AiToolType.pi,
    AiToolType.mcode,
  ];

  /// MiniMax Code 全局指令上限（与 CC Switch 一致）
  static const int mcodeMaxBytes = 32 * 1024;

  /// 测试专用：固定时间
  static DateTime Function() clock = DateTime.now;

  static String fileNameFor(AiToolType tool) {
    switch (tool) {
      case AiToolType.claudecode:
        return 'CLAUDE.md';
      case AiToolType.gemini:
        return 'GEMINI.md';
      case AiToolType.hermes:
        return 'SOUL.md';
      case AiToolType.codex:
      case AiToolType.grokBuild:
      case AiToolType.opencode:
      case AiToolType.openclaw:
      case AiToolType.pi:
      case AiToolType.mcode:
        return 'AGENTS.md';
      default:
        throw UnsupportedError('${tool.displayName} 不支持 Prompts');
    }
  }

  Future<String> promptFilePath(AiToolType tool) async {
    final name = fileNameFor(tool);
    return path.join(await _configService.getConfigDir(tool), name);
  }

  static void validateContent(AiToolType tool, String content) {
    if (tool == AiToolType.mcode && utf8.encode(content).length > mcodeMaxBytes) {
      throw ArgumentError('MiniMax Code 全局指令不能超过 32 KiB');
    }
  }

  // ========== 查询 ==========

  /// 列出某工具的提示词。启用项会先用 live 文件内容刷新（外部编辑器修改过文件时）。
  Future<List<Prompt>> getPrompts(AiToolType tool) async {
    final prompts = await _query(tool);
    final enabled = prompts.where((p) => p.enabled).firstOrNull;
    if (enabled != null) {
      final live = await currentFileContent(tool);
      if (live != null && live.trim().isNotEmpty && live != enabled.content) {
        final refreshed = enabled.copyWith(content: live, updatedAt: clock());
        await _save(refreshed);
        return prompts.map((p) => p.id == refreshed.id ? refreshed : p).toList();
      }
    }
    return prompts;
  }

  Future<String?> currentFileContent(AiToolType tool) async {
    final file = File(await promptFilePath(tool));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  // ========== 修改 ==========

  /// 新建或更新提示词。启用中的条目会同步写入文件；停用最后一条启用项时清空文件。
  Future<Prompt> upsert(Prompt prompt) async {
    validateContent(prompt.tool, prompt.content);
    final existing = await _query(prompt.tool);
    final previous = prompt.id == null ? null : existing.where((p) => p.id == prompt.id).firstOrNull;

    if (prompt.enabled) {
      // 先写文件，成功后再改数据库（写失败时数据库保持原状）
      await _writeLive(prompt.tool, prompt.content);
      final saved = await _save(prompt);
      await _disableOthers(prompt.tool, saved.id!);
      return saved;
    }

    final clearLive = previous != null &&
        previous.enabled &&
        !existing.any((p) => p.id != prompt.id && p.enabled);
    if (clearLive && await File(await promptFilePath(prompt.tool)).exists()) {
      await _writeLive(prompt.tool, '');
    }
    return _save(prompt);
  }

  /// 启用某条提示词（独占）：先回填 live 内容，再写入目标内容
  Future<void> enable(AiToolType tool, int id) async {
    final live = await currentFileContent(tool);
    var prompts = await _query(tool);
    final target = prompts.where((p) => p.id == id).firstOrNull;
    if (target == null) throw StateError('提示词 $id 不存在');
    validateContent(tool, target.content);

    if (live != null && live.trim().isNotEmpty) {
      final current = prompts.where((p) => p.enabled).firstOrNull;
      if (current != null) {
        if (current.content != live) {
          await _save(current.copyWith(content: live, updatedAt: clock()));
        }
      } else if (!prompts.any((p) => p.content.trim() == live.trim())) {
        final now = clock();
        await _save(Prompt(
          tool: tool,
          name: '原始提示词 ${_fmt(now)}',
          content: live,
          description: '自动备份的原始提示词',
          createdAt: now,
          updatedAt: now,
        ));
      }
      prompts = await _query(tool);
    }

    final fresh = prompts.firstWhere((p) => p.id == id);
    await _writeLive(tool, fresh.content);
    await _save(fresh.copyWith(enabled: true, updatedAt: clock()));
    await _disableOthers(tool, id);
  }

  /// 停用（停用最后一条启用项时清空文件）
  Future<void> disable(AiToolType tool, int id) async {
    final target = (await _query(tool)).where((p) => p.id == id).firstOrNull;
    if (target == null || !target.enabled) return;
    await upsert(target.copyWith(enabled: false, updatedAt: clock()));
  }

  /// 删除（启用中的条目不允许删除）
  Future<void> delete(AiToolType tool, int id) async {
    final target = (await _query(tool)).where((p) => p.id == id).firstOrNull;
    if (target == null) return;
    if (target.enabled) throw StateError('无法删除已启用的提示词');
    final db = await _db.database;
    await db.delete('prompts', where: 'id = ?', whereArgs: [id]);
  }

  /// 把当前提示词文件导入为一条新的（未启用）提示词
  Future<Prompt> importFromFile(AiToolType tool) async {
    final content = await currentFileContent(tool);
    if (content == null) throw StateError('提示词文件不存在');
    final now = clock();
    return upsert(Prompt(
      tool: tool,
      name: '导入的提示词 ${_fmt(now)}',
      content: content,
      description: '从现有配置文件导入',
      createdAt: now,
      updatedAt: now,
    ));
  }

  /// 首次使用时自动导入各工具已有的提示词文件（每个工具只做一次；已有提示词则跳过）
  Future<int> importOnFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    var imported = 0;
    for (final tool in supportedTools) {
      final flag = 'prompts_auto_imported_${tool.value}';
      if (prefs.getBool(flag) == true) continue;
      try {
        if ((await _query(tool)).isEmpty) {
          final content = await currentFileContent(tool);
          if (content != null && content.trim().isNotEmpty) {
            validateContent(tool, content);
            final now = clock();
            await _save(Prompt(
              tool: tool,
              name: '自动导入的提示词 ${_fmt(now)}',
              content: content,
              description: '首次使用时自动导入',
              enabled: true,
              createdAt: now,
              updatedAt: now,
            ));
            imported++;
          }
        }
        await prefs.setBool(flag, true);
      } catch (_) {
        // 单个工具失败不影响其他工具；下次再试
      }
    }
    return imported;
  }

  // ========== 内部 ==========

  Future<List<Prompt>> _query(AiToolType tool) async {
    final db = await _db.database;
    final rows = await db.query('prompts', where: 'tool = ?', whereArgs: [tool.value], orderBy: 'id ASC');
    return rows.map(Prompt.fromMap).toList();
  }

  Future<Prompt> _save(Prompt prompt) async {
    final db = await _db.database;
    if (prompt.id == null) {
      final id = await db.insert('prompts', prompt.toMap());
      return prompt.copyWith(id: id);
    }
    await db.update('prompts', prompt.toMap(), where: 'id = ?', whereArgs: [prompt.id]);
    return prompt;
  }

  Future<void> _disableOthers(AiToolType tool, int keepId) async {
    final db = await _db.database;
    await db.update('prompts', {'enabled': 0},
        where: 'tool = ? AND id != ? AND enabled = 1', whereArgs: [tool.value, keepId]);
  }

  Future<void> _writeLive(AiToolType tool, String content) async {
    final file = await promptFilePath(tool);
    await _writer.updateText(tool, file, (_) => content);
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
