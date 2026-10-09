import 'package:equatable/equatable.dart';

import 'mcp_server.dart';

/// 系统提示词（CLAUDE.md / AGENTS.md / GEMINI.md / SOUL.md），与 CC Switch Prompts 对齐。
/// 每个工具同一时间最多启用一条，启用的那条写入该工具的提示词文件。
class Prompt extends Equatable {
  final int? id;
  final AiToolType tool;
  final String name;
  final String content;
  final String? description;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Prompt({
    this.id,
    required this.tool,
    required this.name,
    required this.content,
    this.description,
    this.enabled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Prompt copyWith({
    int? id,
    String? name,
    String? content,
    String? description,
    bool? enabled,
    DateTime? updatedAt,
  }) {
    return Prompt(
      id: id ?? this.id,
      tool: tool,
      name: name ?? this.name,
      content: content ?? this.content,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'tool': tool.value,
        'name': name,
        'content': content,
        'description': description,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Prompt.fromMap(Map<String, dynamic> map) => Prompt(
        id: map['id'] as int?,
        tool: AiToolType.values.firstWhere((t) => t.value == map['tool'],
            orElse: () => AiToolType.claudecode),
        name: map['name'] as String,
        content: map['content'] as String? ?? '',
        description: map['description'] as String?,
        enabled: (map['enabled'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props => [id, tool, name, content, description, enabled, createdAt, updatedAt];
}
