import 'dart:convert';
import '../models/mcp_server.dart';
import '../models/mcp_server.dart' as models;

/// MCP 服务比对状态枚举
enum McpComparisonStatus {
  /// 仅在本应用中存在
  onlyInLocal,
  /// 仅在工具配置中存在
  onlyInTool,
  /// 两边都存在且配置完全一致
  identical,
  /// 两边都存在但配置不同
  different,
}

/// MCP 服务比对结果
class McpComparisonResult {
  final McpServer server;
  final McpComparisonStatus status;
  final McpServer? toolServer; // 工具中的服务器（如果存在）

  McpComparisonResult({
    required this.server,
    required this.status,
    this.toolServer,
  });
}

/// MCP 配置比对工具类
/// 以 serverId 为唯一标识进行所有比对
class McpComparison {
  /// 规范化服务器名称用于比对（将空格和连字符统一处理）
  /// 用于比对时容错：空格和连字符视为相同
  static String _normalizeServerNameForComparison(String name) {
    // 移除首尾空格
    name = name.trim();
    // 将空格和制表符替换为连字符
    name = name.replaceAll(RegExp(r'[\s\t]+'), '-');
    // 合并连续的连字符
    name = name.replaceAll(RegExp(r'-+'), '-');
    // 移除首尾的连字符
    name = name.replaceAll(RegExp(r'^-+|-$'), '');
    return name.toLowerCase(); // 转换为小写以支持大小写不敏感比对
  }

  /// 比对本地和工具中的 MCP 服务列表
  /// 
  /// [localServers] 本应用中的 MCP 服务列表（已激活的）
  /// [toolServers] 工具配置文件中的 MCP 服务列表（Map<serverId, McpServer>）
  /// [toolType] 工具类型，用于特殊处理（如codex需要转换为JSON格式）
  /// 
  /// 返回比对结果列表
  static List<McpComparisonResult> compare({
    required List<McpServer> localServers,
    required Map<String, McpServer> toolServers,
    models.AiToolType? toolType,
  }) {
    final results = <McpComparisonResult>[];
    final processedToolServerIds = <String>{};
    
    // 创建规范化名称到原始名称的映射，用于容错比对
    final normalizedToOriginal = <String, String>{};
    for (final key in toolServers.keys) {
      final normalized = _normalizeServerNameForComparison(key);
      normalizedToOriginal[normalized] = key;
    }

    // 处理本地服务器
    for (final localServer in localServers) {
      final normalizedLocalId = _normalizeServerNameForComparison(localServer.serverId);
      
      // 使用规范化名称进行容错比对（空格和连字符视为相同）
      String? matchedToolKey;
      if (normalizedToOriginal.containsKey(normalizedLocalId)) {
        matchedToolKey = normalizedToOriginal[normalizedLocalId];
      } else if (toolServers.containsKey(localServer.serverId)) {
        matchedToolKey = localServer.serverId;
      }
      
      if (matchedToolKey == null) {
        // 仅在本应用中存在
        results.add(McpComparisonResult(
          server: localServer,
          status: McpComparisonStatus.onlyInLocal,
        ));
      } else {
        // 两边都存在，比较配置
        processedToolServerIds.add(matchedToolKey);
        final toolServer = toolServers[matchedToolKey]!;
        
        // 规范化配置格式：对于codex工具，确保都转换为JSON格式
        final localConfig = _normalizeConfigForComparison(
          localServer.toToolConfigFormat(),
          toolType,
        );
        final toolConfig = _normalizeConfigForComparison(
          toolServer.toToolConfigFormat(),
          toolType,
        );
        
        final isIdentical = _compareConfigurations(
          localConfig,
          toolConfig,
        );
        
        results.add(McpComparisonResult(
          server: localServer,
          status: isIdentical
              ? McpComparisonStatus.identical
              : McpComparisonStatus.different,
          toolServer: toolServer,
        ));
      }
    }

    // 处理仅在工具中存在的服务器
    for (final entry in toolServers.entries) {
      if (!processedToolServerIds.contains(entry.key)) {
        results.add(McpComparisonResult(
          server: entry.value,
          status: McpComparisonStatus.onlyInTool,
          toolServer: entry.value,
        ));
      }
    }

    return results;
  }

  /// 从 args 数组中提取环境变量到 env（用于比对时统一处理）
  static (List<String> args, Map<String, String> env) _extractEnvFromArgsForComparison(List<String> args) {
    final fixedArgs = <String>[];
    final envVars = <String, String>{};
    
    for (final arg in args) {
      final argStr = arg.toString();
      // 检查是否是环境变量格式：KEY=VALUE（可能包含转义的引号）
      final envMatch = RegExp(r'^"?([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$').firstMatch(argStr);
      if (envMatch != null) {
        final key = envMatch.group(1)!;
        var value = envMatch.group(2)!;
        // 移除引号（处理转义引号和嵌套引号）
        value = value.replaceAll(r'\"', '"');
        while ((value.startsWith('"') && value.endsWith('"')) ||
               (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        envVars[key] = value;
      } else {
        fixedArgs.add(argStr);
      }
    }
    
    return (fixedArgs, envVars);
  }

  /// 规范化配置格式用于对比
  /// 将配置转换为标准JSON格式，确保格式完全统一（与toToolConfigFormat保持一致）
  /// 统一字段顺序、空值处理和类型转换
  /// 对于codex工具，需要特别处理，因为从TOML读取的配置格式可能不同
  /// 同时需要从 args 中提取环境变量到 env，确保比对一致性
  static Map<String, dynamic> _normalizeConfigForComparison(
    Map<String, dynamic> config,
    models.AiToolType? toolType,
  ) {
    final normalized = <String, dynamic>{};
    
    // 确定服务器类型（与toToolConfigFormat的逻辑一致）
    String type;
    if (config.containsKey('type') && config['type'] != null) {
      type = config['type'].toString();
    } else if (config.containsKey('url') && config['url'] != null) {
      // 有url字段，但没有type字段，需要判断是http还是sse
      // 检查是否有其他标识，如果没有则默认为http
      type = 'http'; // 默认http，因为无法从url判断是http还是sse
    } else {
      // 没有url，默认为stdio
      type = 'stdio';
    }
    
    // 按toToolConfigFormat的顺序添加字段（完全模拟toToolConfigFormat的行为）
    if (type == 'stdio') {
      // stdio类型字段（与toToolConfigFormat保持一致）
      // 处理 command：如果包含空格，需要拆分
      Map<String, String>? extractedEnv;
      List<String>? extractedArgs;
      
      if (config.containsKey('command') && config['command'] != null) {
        final command = config['command'];
        if (command is String && command.isNotEmpty) {
          // 如果 command 包含空格，拆分
          if (command.contains(' ')) {
            final parts = command.split(RegExp(r'\s+'));
            if (parts.isNotEmpty) {
              normalized['command'] = parts[0];
              if (parts.length > 1) {
                extractedArgs = parts.sublist(1);
              }
            }
          } else {
            normalized['command'] = command;
          }
        }
      }
      
      // 处理 args：提取环境变量和合并从 command 拆分出的 args
      if (config.containsKey('args') && config['args'] != null) {
        final args = config['args'];
        if (args is List && args.isNotEmpty) {
          final argsList = List<String>.from(args.map((e) => e.toString()));
          final result = _extractEnvFromArgsForComparison(argsList);
          
          // 合并从 command 拆分出的 args（如果有）
          List<String> finalArgs = result.$1;
          if (extractedArgs != null && extractedArgs.isNotEmpty) {
            finalArgs = [...extractedArgs, ...finalArgs];
          }
          
          // 保存处理后的 args（移除环境变量）
          if (finalArgs.isNotEmpty) {
            normalized['args'] = finalArgs;
          }
          
          // 保存提取的环境变量
          if (result.$2.isNotEmpty) {
            extractedEnv = result.$2;
          }
        } else if (extractedArgs != null && extractedArgs.isNotEmpty) {
          // 如果没有 args，但 command 拆分出了 args，使用拆分出的 args
          normalized['args'] = extractedArgs;
        }
      } else if (extractedArgs != null && extractedArgs.isNotEmpty) {
        // 如果没有 args，但 command 拆分出了 args，使用拆分出的 args
        normalized['args'] = extractedArgs;
      }
      
      // 处理 env：合并提取的环境变量和原有的 env
      Map<String, String> finalEnv = {};
      if (config.containsKey('env') && config['env'] != null) {
        final env = config['env'];
        if (env is Map) {
          env.forEach((key, value) {
            if (value != null && value.toString().isNotEmpty) {
              finalEnv[key.toString()] = value.toString();
            }
          });
        }
      }
      // 合并提取的环境变量
      if (extractedEnv != null) {
        finalEnv.addAll(extractedEnv);
      }
      if (finalEnv.isNotEmpty) {
        normalized['env'] = finalEnv;
      }
      
      if (config.containsKey('cwd') && config['cwd'] != null) {
        final cwd = config['cwd'];
        if (cwd is String && cwd.isNotEmpty) {
          normalized['cwd'] = cwd;
        }
      }
      // type字段总是存在（放在最后，与toToolConfigFormat一致）
      normalized['type'] = 'stdio';
    } else {
      // http 或 sse 类型字段（与toToolConfigFormat保持一致）
      if (config.containsKey('url') && config['url'] != null) {
        final url = config['url'];
        if (url is String && url.isNotEmpty) {
          normalized['url'] = url;
        }
      }
      if (config.containsKey('headers') && config['headers'] != null) {
        final headers = config['headers'];
        if (headers is Map) {
          // 确保headers是Map<String, String>，且不为空
          final headersMap = <String, String>{};
          headers.forEach((key, value) {
            if (value != null && value.toString().isNotEmpty) {
              headersMap[key.toString()] = value.toString();
            }
          });
          if (headersMap.isNotEmpty) {
            normalized['headers'] = headersMap;
          }
        }
      }
      // type字段总是存在（放在最后，与toToolConfigFormat一致）
      normalized['type'] = type;
    }
    
    return normalized;
  }

  /// 深度比较两个配置对象是否一致
  /// 
  /// 按照 MCP JSON 中的变量名一一比对，当配置项只是顺序不同但变量名对应的值完全相同时，认为是相同的
  static bool _compareConfigurations(
    Map<String, dynamic> config1,
    Map<String, dynamic> config2,
  ) {
    return _deepCompare(config1, config2);
  }

  /// 深度比较两个值是否相等（忽略顺序）
  static bool _deepCompare(dynamic value1, dynamic value2) {
    // 处理 null 值
    if (value1 == null && value2 == null) return true;
    if (value1 == null || value2 == null) return false;

    // 处理 Map：按照键名比较，忽略键的顺序
    if (value1 is Map && value2 is Map) {
      final map1 = Map<String, dynamic>.from(value1);
      final map2 = Map<String, dynamic>.from(value2);
      
      // 获取所有键的并集
      final allKeys = <String>{
        ...map1.keys.map((k) => k.toString()),
        ...map2.keys.map((k) => k.toString()),
      };
      
      for (final key in allKeys) {
        final v1 = map1[key];
        final v2 = map2[key];
        
        // 如果键只在一个 Map 中存在，返回 false
        if (v1 == null && v2 != null) return false;
        if (v1 != null && v2 == null) return false;
        
        // 递归比较值
        if (!_deepCompare(v1, v2)) return false;
      }
      
      return true;
    }
    
    // 处理 List：比较内容是否相同（忽略顺序）
    if (value1 is List && value2 is List) {
      final list1 = List<dynamic>.from(value1);
      final list2 = List<dynamic>.from(value2);
      
      if (list1.length != list2.length) return false;
      
      // 对于列表，需要比较每个元素是否都存在（忽略顺序）
      // 使用一个标记数组来记录 list2 中已匹配的元素
      final matched2 = List<bool>.filled(list2.length, false);
      
      for (final item1 in list1) {
        bool found = false;
        for (int i = 0; i < list2.length; i++) {
          if (!matched2[i] && _deepCompare(item1, list2[i])) {
            matched2[i] = true;
            found = true;
            break;
          }
        }
        if (!found) return false;
      }
      
      return true;
    }
    
    // 处理基本类型：直接比较
    return value1 == value2;
  }

  /// 逐字段比较配置对象（保留用于兼容性）
  static bool _compareConfigurationsFieldByField(
    Map<String, dynamic> config1,
    Map<String, dynamic> config2,
  ) {
    return _deepCompare(config1, config2);
  }

  /// 比较两个配置并返回不同的字段列表
  /// 返回 Map，key 为字段路径（如 "args[0]" 或 "env.KEY"），value 为差异描述
  /// [toolType] 工具类型，用于规范化配置格式
  static Map<String, String> getDifferences(
    Map<String, dynamic> config1,
    Map<String, dynamic> config2, {
    models.AiToolType? toolType,
  }) {
    // 规范化配置格式
    final normalizedConfig1 = _normalizeConfigForComparison(config1, toolType);
    final normalizedConfig2 = _normalizeConfigForComparison(config2, toolType);
    
    final differences = <String, String>{};
    _findDifferences(normalizedConfig1, normalizedConfig2, '', differences);
    return differences;
  }

  /// 递归查找差异
  static void _findDifferences(
    dynamic value1,
    dynamic value2,
    String path,
    Map<String, String> differences,
  ) {
    // 处理 null 值
    if (value1 == null && value2 == null) return;
    if (value1 == null) {
      differences[path] = '左侧为空，右侧为: ${_valueToString(value2)}';
      return;
    }
    if (value2 == null) {
      differences[path] = '左侧为: ${_valueToString(value1)}，右侧为空';
      return;
    }

    // 处理 Map
    if (value1 is Map && value2 is Map) {
      final map1 = Map<String, dynamic>.from(value1);
      final map2 = Map<String, dynamic>.from(value2);
      
      final allKeys = <String>{
        ...map1.keys.map((k) => k.toString()),
        ...map2.keys.map((k) => k.toString()),
      };
      
      for (final key in allKeys) {
        final v1 = map1[key];
        final v2 = map2[key];
        final newPath = path.isEmpty ? key : '$path.$key';
        
        if (v1 == null && v2 != null) {
          differences[newPath] = '左侧为空，右侧为: ${_valueToString(v2)}';
        } else if (v1 != null && v2 == null) {
          differences[newPath] = '左侧为: ${_valueToString(v1)}，右侧为空';
        } else if (!_deepCompare(v1, v2)) {
          _findDifferences(v1, v2, newPath, differences);
        }
      }
      return;
    }
    
    // 处理 List
    if (value1 is List && value2 is List) {
      final list1 = List<dynamic>.from(value1);
      final list2 = List<dynamic>.from(value2);
      
      if (list1.length != list2.length) {
        differences[path] = '左侧长度: ${list1.length}，右侧长度: ${list2.length}';
        return;
      }
      
      // 比较每个位置的元素
      for (int i = 0; i < list1.length; i++) {
        final newPath = '$path[$i]';
        if (!_deepCompare(list1[i], list2[i])) {
          _findDifferences(list1[i], list2[i], newPath, differences);
        }
      }
      return;
    }
    
    // 处理基本类型
    if (value1 != value2) {
      differences[path] = '左侧: ${_valueToString(value1)}，右侧: ${_valueToString(value2)}';
    }
  }

  /// 将值转换为字符串表示
  static String _valueToString(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    if (value is List) return '[${value.length} items]';
    if (value is Map) return '{${value.length} keys}';
    return value.toString();
  }

  /// 根据状态获取显示标签
  static String getStatusLabel(McpComparisonStatus status) {
    switch (status) {
      case McpComparisonStatus.onlyInLocal:
        return '仅本地';
      case McpComparisonStatus.onlyInTool:
        return '仅工具';
      case McpComparisonStatus.identical:
        return '一致';
      case McpComparisonStatus.different:
        return '不同';
    }
  }

  /// 根据状态获取颜色
  static int getStatusColor(McpComparisonStatus status) {
    switch (status) {
      case McpComparisonStatus.onlyInLocal:
        return 0xFF2196F3; // 蓝色
      case McpComparisonStatus.onlyInTool:
        return 0xFFFF9800; // 橙色
      case McpComparisonStatus.identical:
        return 0xFF4CAF50; // 绿色
      case McpComparisonStatus.different:
        return 0xFFFF5722; // 深橙色/红色
    }
  }
}

