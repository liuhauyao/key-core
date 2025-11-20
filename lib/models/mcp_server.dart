import 'dart:convert';
import 'package:equatable/equatable.dart';

/// MCP 服务器类型枚举
enum McpServerType {
  stdio,
  http,
  sse;

  String get value {
    switch (this) {
      case McpServerType.stdio:
        return 'stdio';
      case McpServerType.http:
        return 'http';
      case McpServerType.sse:
        return 'sse';
    }
  }

  static McpServerType fromString(String value) {
    switch (value) {
      case 'stdio':
        return McpServerType.stdio;
      case 'http':
        return McpServerType.http;
      case 'sse':
        return McpServerType.sse;
      default:
        return McpServerType.stdio;
    }
  }
}

/// AI 工具类型枚举
enum AiToolType {
  cursor,
  claudecode,
  codex,
  windsurf,
  cline,
  gemini;

  String get value {
    switch (this) {
      case AiToolType.cursor:
        return 'cursor';
      case AiToolType.claudecode:
        return 'claudecode';
      case AiToolType.codex:
        return 'codex';
      case AiToolType.windsurf:
        return 'windsurf';
      case AiToolType.cline:
        return 'cline';
      case AiToolType.gemini:
        return 'gemini';
    }
  }

  String get displayName {
    switch (this) {
      case AiToolType.cursor:
        return 'Cursor';
      case AiToolType.claudecode:
        return 'ClaudeCode';
      case AiToolType.codex:
        return 'Codex';
      case AiToolType.windsurf:
        return 'Windsurf';
      case AiToolType.cline:
        return 'Cline';
      case AiToolType.gemini:
        return 'Gemini';
    }
  }

  /// 获取工具的SVG图标路径
  String? get iconPath {
    switch (this) {
      case AiToolType.cursor:
        return 'assets/icons/platforms/cursor.svg';
      case AiToolType.claudecode:
        return 'assets/icons/platforms/anthropic.svg';
      case AiToolType.codex:
        return 'assets/icons/platforms/openai.svg';
      case AiToolType.windsurf:
        return 'assets/icons/platforms/windsurf.svg';
      case AiToolType.cline:
        return 'assets/icons/platforms/cline.svg';
      case AiToolType.gemini:
        return 'assets/icons/platforms/gemini-color.svg';
    }
  }

  static AiToolType fromString(String value) {
    switch (value) {
      case 'cursor':
        return AiToolType.cursor;
      case 'claudecode':
        return AiToolType.claudecode;
      case 'codex':
        return AiToolType.codex;
      case 'windsurf':
        return AiToolType.windsurf;
      case 'cline':
        return AiToolType.cline;
      case 'gemini':
        return AiToolType.gemini;
      default:
        return AiToolType.cursor;
    }
  }
}

/// MCP 服务器数据模型
class McpServer extends Equatable {
  final int? id;
  final String serverId; // 唯一标识符
  final String name; // 显示名称
  final String? description; // 描述
  final String? icon; // 图标路径（SVG）
  final McpServerType serverType; // 服务器类型（stdio/http/sse）
  
  // stdio 类型字段
  final String? command; // stdio 命令
  final List<String>? args; // 命令参数
  final Map<String, String>? env; // 环境变量
  final String? cwd; // 工作目录
  
  // http/sse 类型字段
  final String? url; // HTTP/SSE URL
  final Map<String, String>? headers; // HTTP 请求头
  
  final List<String>? tags; // 标签
  final String? homepage; // 主页地址
  final String? docs; // 文档地址
  final bool isActive; // 是否激活
  final DateTime createdAt; // 创建时间
  final DateTime updatedAt; // 更新时间

  const McpServer({
    this.id,
    required this.serverId,
    required this.name,
    this.description,
    this.icon,
    required this.serverType,
    this.command,
    this.args,
    this.env,
    this.cwd,
    this.url,
    this.headers,
    this.tags,
    this.homepage,
    this.docs,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  McpServer copyWith({
    int? id,
    String? serverId,
    String? name,
    String? description,
    String? icon,
    McpServerType? serverType,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? cwd,
    String? url,
    Map<String, String>? headers,
    List<String>? tags,
    String? homepage,
    String? docs,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return McpServer(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      serverType: serverType ?? this.serverType,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      cwd: cwd ?? this.cwd,
      url: url ?? this.url,
      headers: headers ?? this.headers,
      tags: tags ?? this.tags,
      homepage: homepage ?? this.homepage,
      docs: docs ?? this.docs,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'name': name,
      'description': description,
      'icon': icon,
      'server_type': serverType.value,
      'command': command,
      'args': args != null ? jsonEncode(args) : null,
      'env': env != null ? jsonEncode(env) : null,
      'cwd': cwd,
      'url': url,
      'headers': headers != null ? jsonEncode(headers) : null,
      'tags': tags != null ? tags!.join(',') : null,
      'homepage': homepage,
      'docs': docs,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory McpServer.fromMap(Map<String, dynamic> map) {
    // 解析 args
    List<String>? args;
    if (map['args'] != null) {
      try {
        args = List<String>.from(jsonDecode(map['args'] as String));
      } catch (e) {
        args = null;
      }
    }

    // 解析 env
    Map<String, String>? env;
    if (map['env'] != null) {
      try {
        env = Map<String, String>.from(jsonDecode(map['env'] as String));
      } catch (e) {
        env = null;
      }
    }

    // 解析 headers
    Map<String, String>? headers;
    if (map['headers'] != null) {
      try {
        headers = Map<String, String>.from(jsonDecode(map['headers'] as String));
      } catch (e) {
        headers = null;
      }
    }

    // 解析 tags
    List<String>? tags;
    if (map['tags'] != null && (map['tags'] as String).isNotEmpty) {
      tags = (map['tags'] as String).split(',').where((tag) => tag.isNotEmpty).toList();
    }

    return McpServer(
      id: map['id']?.toInt(),
      serverId: map['server_id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      icon: map['icon'],
      serverType: McpServerType.fromString(map['server_type'] ?? 'stdio'),
      command: map['command'],
      args: args,
      env: env,
      cwd: map['cwd'],
      url: map['url'],
      headers: headers,
      tags: tags,
      homepage: map['homepage'],
      docs: map['docs'],
      isActive: (map['is_active']?.toInt() ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// 转换为工具配置文件格式（mcpServers 对象中的单个服务器配置）
  Map<String, dynamic> toToolConfigFormat() {
    final config = <String, dynamic>{};

    if (serverType == McpServerType.stdio) {
      if (command != null && command!.isNotEmpty) {
        config['command'] = command;
      }
      if (args != null && args!.isNotEmpty) {
        config['args'] = args;
      }
      if (env != null && env!.isNotEmpty) {
        config['env'] = env;
      }
      if (cwd != null && cwd!.isNotEmpty) {
        config['cwd'] = cwd;
      }
      // 某些工具可能需要 type 字段
      config['type'] = 'stdio';
    } else if (serverType == McpServerType.http || serverType == McpServerType.sse) {
      if (url != null && url!.isNotEmpty) {
        config['url'] = url;
      }
      if (headers != null && headers!.isNotEmpty) {
        config['headers'] = headers;
      }
      config['type'] = serverType.value;
    }

    return config;
  }

  @override
  List<Object?> get props => [
        id,
        serverId,
        name,
        description,
        icon,
        serverType,
        command,
        args,
        env,
        cwd,
        url,
        headers,
        tags,
        homepage,
        docs,
        isActive,
        createdAt,
        updatedAt,
      ];
}

