import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'mcp_server.dart';

/// Skills 支持分发的目标工具
enum SkillTargetTool {
  cursor,
  claudecode,
  codex,
  // 与 CC Switch v4.0.6 对齐的其他工具
  gemini,
  opencode,
  grokBuild,
  openclaw,
  hermes,
  pi,
  mcode;

  static const Map<SkillTargetTool, AiToolType> _aiTools = {
    SkillTargetTool.cursor: AiToolType.cursor,
    SkillTargetTool.claudecode: AiToolType.claudecode,
    SkillTargetTool.codex: AiToolType.codex,
    SkillTargetTool.gemini: AiToolType.gemini,
    SkillTargetTool.opencode: AiToolType.opencode,
    SkillTargetTool.grokBuild: AiToolType.grokBuild,
    SkillTargetTool.openclaw: AiToolType.openclaw,
    SkillTargetTool.hermes: AiToolType.hermes,
    SkillTargetTool.pi: AiToolType.pi,
    SkillTargetTool.mcode: AiToolType.mcode,
  };

  String get value => _aiTools[this]!.value;

  String get displayName => _aiTools[this]!.displayName;

  String? get iconPath => _aiTools[this]!.iconPath;

  static SkillTargetTool fromString(String value) {
    for (final t in SkillTargetTool.values) {
      if (t.value == value) return t;
    }
    return SkillTargetTool.cursor;
  }

  static SkillTargetTool? fromAiToolType(AiToolType tool) {
    for (final e in _aiTools.entries) {
      if (e.value == tool) return e.key;
    }
    return null;
  }

  AiToolType toAiToolType() => _aiTools[this]!;
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

  /// 来源仓库 `owner/name`（从仓库 / skills.sh 安装时记录）
  final String? sourceRepo;

  /// 来源分支（为空表示默认分支）
  final String? sourceRef;

  /// 在仓库中的目录
  final String? sourceSubdir;

  /// 安装 / 更新时的内容哈希（用于检查更新与本地修改）
  final String? contentHash;
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
    this.sourceRepo,
    this.sourceRef,
    this.sourceSubdir,
    this.contentHash,
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
    String? sourceRepo,
    String? sourceRef,
    String? sourceSubdir,
    String? contentHash,
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
      sourceRepo: sourceRepo ?? this.sourceRepo,
      sourceRef: sourceRef ?? this.sourceRef,
      sourceSubdir: sourceSubdir ?? this.sourceSubdir,
      contentHash: contentHash ?? this.contentHash,
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
      'source_repo': sourceRepo,
      'source_ref': sourceRef,
      'source_subdir': sourceSubdir,
      'content_hash': contentHash,
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
      sourceRepo: map['source_repo'] as String?,
      sourceRef: map['source_ref'] as String?,
      sourceSubdir: map['source_subdir'] as String?,
      contentHash: map['content_hash'] as String?,
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
        sourceRepo,
        sourceRef,
        sourceSubdir,
        contentHash,
        createdAt,
        updatedAt,
      ];
}
