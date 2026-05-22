import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'mcp_server.dart';

/// Skills 支持分发的目标工具
enum SkillTargetTool {
  cursor,
  claudecode,
  codex;

  String get value {
    switch (this) {
      case SkillTargetTool.cursor:
        return 'cursor';
      case SkillTargetTool.claudecode:
        return 'claudecode';
      case SkillTargetTool.codex:
        return 'codex';
    }
  }

  String get displayName {
    switch (this) {
      case SkillTargetTool.cursor:
        return 'Cursor';
      case SkillTargetTool.claudecode:
        return 'ClaudeCode';
      case SkillTargetTool.codex:
        return 'Codex';
    }
  }

  String? get iconPath {
    switch (this) {
      case SkillTargetTool.cursor:
        return 'assets/icons/platforms/cursor.svg';
      case SkillTargetTool.claudecode:
        return 'assets/icons/platforms/anthropic.svg';
      case SkillTargetTool.codex:
        return 'assets/icons/platforms/openai.svg';
    }
  }

  static SkillTargetTool fromString(String value) {
    switch (value) {
      case 'cursor':
        return SkillTargetTool.cursor;
      case 'claudecode':
        return SkillTargetTool.claudecode;
      case 'codex':
        return SkillTargetTool.codex;
      default:
        return SkillTargetTool.cursor;
    }
  }

  static SkillTargetTool? fromAiToolType(AiToolType tool) {
    switch (tool) {
      case AiToolType.cursor:
        return SkillTargetTool.cursor;
      case AiToolType.claudecode:
        return SkillTargetTool.claudecode;
      case AiToolType.codex:
        return SkillTargetTool.codex;
      default:
        return null;
    }
  }

  AiToolType toAiToolType() {
    switch (this) {
      case SkillTargetTool.cursor:
        return AiToolType.cursor;
      case SkillTargetTool.claudecode:
        return AiToolType.claudecode;
      case SkillTargetTool.codex:
        return AiToolType.codex;
    }
  }
}

/// Skill 同步状态
enum SkillSyncState {
  synced,
  outdated,
  conflict,
  notSynced;

  String get value {
    switch (this) {
      case SkillSyncState.synced:
        return 'synced';
      case SkillSyncState.outdated:
        return 'outdated';
      case SkillSyncState.conflict:
        return 'conflict';
      case SkillSyncState.notSynced:
        return 'not_synced';
    }
  }

  static SkillSyncState fromString(String value) {
    switch (value) {
      case 'synced':
        return SkillSyncState.synced;
      case 'outdated':
        return SkillSyncState.outdated;
      case 'conflict':
        return SkillSyncState.conflict;
      default:
        return SkillSyncState.notSynced;
    }
  }
}

/// Skill 导入冲突策略
enum SkillImportConflictAction {
  skip,
  overwrite,
  rename,
}

/// 工具目录中的 Skill 扫描结果
class ToolSkillEntry {
  final String relativePath;
  final String absolutePath;
  final String name;
  final String? description;
  final bool isSymlink;
  final bool isKeyCoreManaged;
  final String? symlinkTarget;

  const ToolSkillEntry({
    required this.relativePath,
    required this.absolutePath,
    required this.name,
    this.description,
    this.isSymlink = false,
    this.isKeyCoreManaged = false,
    this.symlinkTarget,
  });
}

/// Skill 数据模型
class Skill extends Equatable {
  final int? id;
  final String skillId;
  final String relativePath;
  final String name;
  final String? description;
  final List<SkillTargetTool> enabledTools;
  final Map<SkillTargetTool, SkillSyncState> syncStatus;
  final List<String>? tags;
  final String? notes;
  final int sortOrder;
  final bool isActive;
  final SkillTargetTool? sourceTool;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Skill({
    this.id,
    required this.skillId,
    required this.relativePath,
    required this.name,
    this.description,
    this.enabledTools = const [],
    this.syncStatus = const {},
    this.tags,
    this.notes,
    this.sortOrder = 0,
    this.isActive = true,
    this.sourceTool,
    required this.createdAt,
    required this.updatedAt,
  });

  Skill copyWith({
    int? id,
    String? skillId,
    String? relativePath,
    String? name,
    String? description,
    List<SkillTargetTool>? enabledTools,
    Map<SkillTargetTool, SkillSyncState>? syncStatus,
    List<String>? tags,
    String? notes,
    int? sortOrder,
    bool? isActive,
    SkillTargetTool? sourceTool,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Skill(
      id: id ?? this.id,
      skillId: skillId ?? this.skillId,
      relativePath: relativePath ?? this.relativePath,
      name: name ?? this.name,
      description: description ?? this.description,
      enabledTools: enabledTools ?? this.enabledTools,
      syncStatus: syncStatus ?? this.syncStatus,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      sourceTool: sourceTool ?? this.sourceTool,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get hasConflict =>
      syncStatus.values.any((state) => state == SkillSyncState.conflict);

  bool get needsSync => syncStatus.values.any(
        (state) =>
            state == SkillSyncState.notSynced ||
            state == SkillSyncState.outdated,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'skill_id': skillId,
      'relative_path': relativePath,
      'name': name,
      'description': description,
      'enabled_tools': jsonEncode(enabledTools.map((t) => t.value).toList()),
      'sync_status': jsonEncode(
        syncStatus.map((key, value) => MapEntry(key.value, value.value)),
      ),
      'tags': tags != null ? tags!.join(',') : null,
      'notes': notes,
      'sort_order': sortOrder,
      'is_active': isActive ? 1 : 0,
      'source_tool': sourceTool?.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Skill.fromMap(Map<String, dynamic> map) {
    List<SkillTargetTool> enabledTools = [];
    if (map['enabled_tools'] != null) {
      try {
        final list = List<String>.from(jsonDecode(map['enabled_tools'] as String));
        enabledTools = list.map(SkillTargetTool.fromString).toList();
      } catch (_) {}
    }

    Map<SkillTargetTool, SkillSyncState> syncStatus = {};
    if (map['sync_status'] != null) {
      try {
        final raw = Map<String, dynamic>.from(jsonDecode(map['sync_status'] as String));
        syncStatus = raw.map(
          (key, value) => MapEntry(
            SkillTargetTool.fromString(key),
            SkillSyncState.fromString(value.toString()),
          ),
        );
      } catch (_) {}
    }

    List<String>? tags;
    if (map['tags'] != null && (map['tags'] as String).isNotEmpty) {
      tags = (map['tags'] as String).split(',').where((t) => t.isNotEmpty).toList();
    }

    SkillTargetTool? sourceTool;
    if (map['source_tool'] != null && (map['source_tool'] as String).isNotEmpty) {
      sourceTool = SkillTargetTool.fromString(map['source_tool'] as String);
    }

    return Skill(
      id: map['id']?.toInt(),
      skillId: map['skill_id'] ?? '',
      relativePath: map['relative_path'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      enabledTools: enabledTools,
      syncStatus: syncStatus,
      tags: tags,
      notes: map['notes'],
      sortOrder: map['sort_order']?.toInt() ?? 0,
      isActive: (map['is_active']?.toInt() ?? 1) == 1,
      sourceTool: sourceTool,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        skillId,
        relativePath,
        name,
        description,
        enabledTools,
        syncStatus,
        tags,
        notes,
        sortOrder,
        isActive,
        sourceTool,
        createdAt,
        updatedAt,
      ];
}
