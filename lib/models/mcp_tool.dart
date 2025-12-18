import 'package:equatable/equatable.dart';

/// MCP 工具数据模型
class McpTool extends Equatable {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;

  const McpTool({
    required this.name,
    this.description,
    this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String?,
      inputSchema: json['inputSchema'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };
  }

  @override
  List<Object?> get props => [name, description, inputSchema];
}

