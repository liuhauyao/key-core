import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/mcp_server.dart';
import 'mcp_database_service.dart';
import 'ai_tool_config_service.dart';
import 'settings_service.dart';

/// MCP 配置同步服务
/// 负责将激活的 MCP 服务器同步到各 AI 工具的配置文件中
class McpSyncService {
  final McpDatabaseService _databaseService = McpDatabaseService();
  final AiToolConfigService _configService = AiToolConfigService();

  /// 规范化服务器名称用于 codex（将空格替换为连字符）
  /// codex 要求服务器名称符合模式 ^[a-zA-Z0-9_-]+$，不允许空格
  String _normalizeCodexServerName(String name) {
    // 移除首尾空格
    name = name.trim();
    // 将空格和制表符替换为连字符
    name = name.replaceAll(RegExp(r'[\s\t]+'), '-');
    // 移除其他不允许的字符（保留 a-zA-Z0-9_-）
    name = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
    // 合并连续的连字符
    name = name.replaceAll(RegExp(r'-+'), '-');
    // 移除首尾的连字符
    name = name.replaceAll(RegExp(r'^-+|-$'), '');
    return name.isEmpty ? 'mcp-server' : name;
  }

  /// 规范化 TOML 表名（写入时使用）
  /// 对于 codex，将空格替换为连字符，不使用引号
  String _normalizeTomlTableName(String name) {
    // 规范化服务器名称（将空格替换为连字符）
    return _normalizeCodexServerName(name);
  }

  /// 解析 TOML 表名（读取时使用）
  /// 从 [mcp_servers.xxx] 格式中提取表名
  /// 兼容处理：移除可能的引号（旧格式支持）
  String _parseTomlTableName(String line) {
    // 匹配 [mcp_servers.xxx] 格式
    final match = RegExp(r'\[mcp_servers\.(.+)\]').firstMatch(line);
    if (match != null) {
      var name = match.group(1)!;
      // 移除可能的引号（兼容旧格式）
      if ((name.startsWith('"') && name.endsWith('"')) ||
          (name.startsWith("'") && name.endsWith("'"))) {
        name = name.substring(1, name.length - 1);
      }
      return name;
    }
    return '';
  }

  /// 规范化服务器名称用于比对（将空格和连字符统一处理）
  /// 用于比对时容错：空格和连字符视为相同
  String _normalizeServerNameForComparison(String name) {
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

  /// 拆分 command 字符串为 command 和 args
  /// 如果 command 包含空格，将第一个单词作为 command，其余作为 args
  /// 返回 (command, args)
  (String command, List<String> args) _splitCommand(String commandStr) {
    commandStr = commandStr.trim();
    if (commandStr.isEmpty) {
      return ('', []);
    }
    
    // 如果包含空格，拆分
    final parts = commandStr.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return (parts[0], []);
    }
    
    // 第一个部分是 command，其余是 args
    final command = parts[0];
    final args = parts.sublist(1);
    return (command, args);
  }

  /// 从 args 数组中提取环境变量到 env
  /// 检测格式如：API_KEY=value 或 "API_KEY=\"value\"" 或 API_KEY="value"
  /// 返回处理后的 (args列表, env映射)
  (List<String> args, Map<String, String> env) _extractEnvFromArgs(List<String> args) {
    final fixedArgs = <String>[];
    final envVars = <String, String>{};
    
    for (final arg in args) {
      final argStr = arg.toString();
      // 检查是否是环境变量格式：KEY=VALUE（可能包含转义的引号）
      // 匹配格式如：API_KEY=value 或 API_KEY="value" 或 "API_KEY=\"value\""
      final envMatch = RegExp(r'^"?([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$').firstMatch(argStr);
      if (envMatch != null) {
        // 这是环境变量，提取到 env 中
        final key = envMatch.group(1)!;
        var value = envMatch.group(2)!;
        
        // 移除引号（处理转义引号和嵌套引号）
        // 先处理转义的引号 \" -> "
        value = value.replaceAll(r'\"', '"');
        // 然后移除外层引号
        while ((value.startsWith('"') && value.endsWith('"')) ||
               (value.startsWith("'") && value.endsWith("'"))) {
          value = value.substring(1, value.length - 1);
        }
        
        envVars[key] = value;
      } else {
        // 不是环境变量，保留在 args 中
        fixedArgs.add(argStr);
      }
    }
    
    return (fixedArgs, envVars);
  }

  /// 解析 TOML 数组字符串，自动检测并提取环境变量
  /// 返回 (args列表, env映射)
  (List<String> args, Map<String, String> env) _parseTomlArrayWithEnvExtraction(String arrayContent) {
    final args = <String>[];
    final envVars = <String, String>{};
    
    var currentItem = StringBuffer();
    var inQuotes = false;
    var quoteChar = '';
    
    for (int i = 0; i < arrayContent.length; i++) {
      final char = arrayContent[i];
      
      if (!inQuotes && (char == '"' || char == "'")) {
        inQuotes = true;
        quoteChar = char;
        currentItem.write(char);
      } else if (inQuotes && char == quoteChar) {
        // 检查是否是嵌套引号（下一个字符也是引号）
        if (i + 1 < arrayContent.length && arrayContent[i + 1] == quoteChar) {
          currentItem.write(char);
          currentItem.write(char);
          i++; // 跳过下一个引号
        } else {
          inQuotes = false;
          currentItem.write(char);
        }
      } else if (!inQuotes && char == ',') {
        // 遇到逗号，结束当前元素
        final item = currentItem.toString().trim();
        if (item.isNotEmpty) {
          // 检查是否是环境变量格式
          final envMatch = RegExp(r'^"?([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$').firstMatch(item);
          if (envMatch != null) {
            final envKey = envMatch.group(1)!;
            var envVal = envMatch.group(2)!;
            // 移除引号（处理转义引号和嵌套引号）
            // 先处理转义的引号 \" -> "
            envVal = envVal.replaceAll(r'\"', '"');
            // 然后移除外层引号
            while ((envVal.startsWith('"') && envVal.endsWith('"')) ||
                   (envVal.startsWith("'") && envVal.endsWith("'"))) {
              envVal = envVal.substring(1, envVal.length - 1);
            }
            envVars[envKey] = envVal;
          } else {
            // 移除引号
            var cleanItem = item;
            while ((cleanItem.startsWith('"') && cleanItem.endsWith('"')) ||
                   (cleanItem.startsWith("'") && cleanItem.endsWith("'"))) {
              cleanItem = cleanItem.substring(1, cleanItem.length - 1);
            }
            args.add(cleanItem);
          }
        }
        currentItem.clear();
      } else {
        currentItem.write(char);
      }
    }
    
    // 处理最后一个元素
    final lastItem = currentItem.toString().trim();
    if (lastItem.isNotEmpty) {
      final envMatch = RegExp(r'^"?([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$').firstMatch(lastItem);
      if (envMatch != null) {
        final envKey = envMatch.group(1)!;
        var envVal = envMatch.group(2)!;
        // 移除引号（处理转义引号和嵌套引号）
        // 先处理转义的引号 \" -> "
        envVal = envVal.replaceAll(r'\"', '"');
        // 然后移除外层引号
        while ((envVal.startsWith('"') && envVal.endsWith('"')) ||
               (envVal.startsWith("'") && envVal.endsWith("'"))) {
          envVal = envVal.substring(1, envVal.length - 1);
        }
        envVars[envKey] = envVal;
      } else {
        var cleanItem = lastItem;
        while ((cleanItem.startsWith('"') && cleanItem.endsWith('"')) ||
               (cleanItem.startsWith("'") && cleanItem.endsWith("'"))) {
          cleanItem = cleanItem.substring(1, cleanItem.length - 1);
        }
        args.add(cleanItem);
      }
    }
    
    return (args, envVars);
  }

  /// 同步指定 MCP 服务到工具配置文件
  /// [tool] 目标工具
  /// [serverIds] 要下发的 MCP 服务 ID 列表
  /// 同步 MCP 服务到工具
  /// [scope] 对于 claudecode，可以是 'global' 或项目路径
  Future<bool> syncToTool(AiToolType tool, Set<String> serverIds, {String? scope}) async {
    try {
      if (serverIds.isEmpty) {
        return false;
      }

      // 获取要下发的 MCP 服务器
      final allServers = await _databaseService.getAllMcpServers();
      final serversToSync = allServers
          .where((server) => serverIds.contains(server.serverId))
          .toList();

      if (serversToSync.isEmpty) {
        return false;
      }

      // ClaudeCode 使用特殊的配置文件位置：~/.claude.json
      if (tool == AiToolType.claudecode) {
        return await _syncToClaudeCode(serversToSync, scope: scope);
      }

      // 获取配置文件路径
      final configDir = await _configService.getConfigDir(tool);
      await _configService.ensureConfigDirExists(tool, customConfigDir: configDir);
      final configFilePath = AiToolConfigService.getConfigFilePath(tool, customConfigDir: configDir);
      final expandedPath = AiToolConfigService.expandPath(configFilePath);

      final configFile = File(expandedPath);

      // 备份原文件
      if (await configFile.exists()) {
        final backupPath = '$expandedPath.backup';
        await configFile.copy(backupPath);
      }

      // Codex 使用 TOML 格式，需要特殊处理
      if (tool == AiToolType.codex) {
        return await _syncToCodexToml(configFile, serversToSync);
      }

      // Gemini 使用 JSON 格式（settings.json），但需要特殊处理以保留 apiKey 字段
      if (tool == AiToolType.gemini) {
        return await _syncToGeminiJson(configFile, serversToSync);
      }

      // 其他工具使用 JSON 格式
      // 读取现有配置文件（如果存在）
      Map<String, dynamic> config = {};
      if (await configFile.exists()) {
        try {
          final content = await configFile.readAsString();
          config = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          // 如果解析失败，使用空配置
          config = {};
        }
      }

      // 获取现有的 mcpServers（如果不存在则创建）
      Map<String, dynamic> mcpServers = {};
      if (config['mcpServers'] != null) {
        mcpServers = Map<String, dynamic>.from(config['mcpServers'] as Map);
      }

      // 合并策略：完全覆盖同名（serverId）的 MCP 服务，保留其他 MCP 服务
      for (final server in serversToSync) {
        mcpServers[server.serverId] = server.toToolConfigFormat();
      }

      // 更新配置中的 mcpServers 字段
      config['mcpServers'] = mcpServers;

      // 写入配置文件
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      return true;
    } catch (e) {
      print('同步到工具 ${tool.displayName} 失败: $e');
      return false;
    }
  }

  /// 同步 MCP 服务到 Gemini 配置文件（~/.gemini/settings.json）
  Future<bool> _syncToGeminiJson(File configFile, List<McpServer> serversToSync) async {
    try {
      // 读取现有配置
      Map<String, dynamic> config = {};
      if (await configFile.exists()) {
        try {
          final content = await configFile.readAsString();
          config = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          print('解析 Gemini 配置失败: $e');
          config = {};
        }
      }

      // 确保 apiKey 字段存在（如果不存在则设置为空字符串）
      if (!config.containsKey('apiKey')) {
        config['apiKey'] = '';
      }

      // 获取现有的 mcpServers（如果不存在则创建）
      Map<String, dynamic> mcpServers = {};
      if (config['mcpServers'] != null) {
        mcpServers = Map<String, dynamic>.from(config['mcpServers'] as Map);
      }

      // 合并策略：完全覆盖同名（serverId）的 MCP 服务，保留其他 MCP 服务
      for (final server in serversToSync) {
        mcpServers[server.serverId] = server.toToolConfigFormat();
      }

      // 更新配置中的 mcpServers 字段，保留 apiKey
      config['mcpServers'] = mcpServers;

      // 写入配置文件
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      return true;
    } catch (e) {
      print('同步到 Gemini 失败: $e');
      return false;
    }
  }

  /// 同步 MCP 服务到 ClaudeCode 配置文件（~/.claude.json）
  Future<bool> _syncToClaudeCode(List<McpServer> serversToSync, {String? scope}) async {
    try {
      final homeDir = await SettingsService.getUserHomeDir();
      final configFilePath = path.join(homeDir, '.claude.json');
      final configFile = File(configFilePath);

      // 备份原文件
      if (await configFile.exists()) {
        final backupPath = '$configFilePath.backup';
        await configFile.copy(backupPath);
      }

      // 读取现有配置
      Map<String, dynamic> config = {};
      if (await configFile.exists()) {
        try {
          final content = await configFile.readAsString();
          config = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          print('解析 ClaudeCode 配置失败: $e');
          config = {};
        }
      }

      // 准备要写入的 mcpServers 配置
      final mcpServersToWrite = <String, dynamic>{};
      for (final server in serversToSync) {
        mcpServersToWrite[server.serverId] = server.toToolConfigFormat();
      }

      if (scope != null && scope != 'global') {
        // 写入项目配置
        if (config['projects'] == null) {
          config['projects'] = <String, dynamic>{};
        }
        final projects = config['projects'] as Map<String, dynamic>;
        if (projects[scope] == null) {
          projects[scope] = <String, dynamic>{};
        }
        final projectConfig = projects[scope] as Map<String, dynamic>;
        
        // 获取项目现有的 mcpServers
        Map<String, dynamic> projectMcpServers = {};
        if (projectConfig['mcpServers'] != null) {
          projectMcpServers = Map<String, dynamic>.from(projectConfig['mcpServers'] as Map);
        }
        
        // 合并新的配置
        projectMcpServers.addAll(mcpServersToWrite);
        projectConfig['mcpServers'] = projectMcpServers;
        
        print('写入 ClaudeCode 项目配置: $scope');
      } else {
        // 写入全局配置
        Map<String, dynamic> globalMcpServers = {};
        if (config['mcpServers'] != null) {
          globalMcpServers = Map<String, dynamic>.from(config['mcpServers'] as Map);
        }
        
        // 合并新的配置
        globalMcpServers.addAll(mcpServersToWrite);
        config['mcpServers'] = globalMcpServers;
        
        print('写入 ClaudeCode 全局配置');
      }

      // 写入配置文件
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      return true;
    } catch (e) {
      print('同步到 ClaudeCode 失败: $e');
      return false;
    }
  }

  /// 同步 MCP 服务到 Codex 的 TOML 配置文件
  Future<bool> _syncToCodexToml(File configFile, List<McpServer> serversToSync) async {
    try {
      String existingContent = '';
      if (await configFile.exists()) {
        existingContent = await configFile.readAsString();
      }

      // 解析现有的 TOML 内容，提取非 MCP 配置部分
      final lines = existingContent.split('\n');
      final nonMcpLines = <String>[];
      final mcpServerSections = <String, Map<String, dynamic>>{};
      
      String? currentServerId;
      Map<String, dynamic>? currentServerConfig;
      bool inMcpServerSection = false;

      for (final line in lines) {
        final trimmed = line.trim();
        
        // 检查是否是 MCP 服务器配置节
        if (trimmed.startsWith('[mcp_servers.') && trimmed.endsWith(']')) {
          // 保存之前的服务器配置
          if (currentServerId != null && currentServerConfig != null) {
            mcpServerSections[currentServerId] = currentServerConfig!;
          }
          
          // 开始新的服务器配置，使用统一的解析方法处理带引号的表名
          currentServerId = _parseTomlTableName(trimmed);
          currentServerConfig = {};
          inMcpServerSection = true;
          continue;
        }
        
        // 检查是否是其他配置节（非 MCP）
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          // 保存之前的服务器配置
          if (currentServerId != null && currentServerConfig != null) {
            mcpServerSections[currentServerId] = currentServerConfig!;
          }
          
          currentServerId = null;
          currentServerConfig = null;
          inMcpServerSection = false;
          nonMcpLines.add(line);
          continue;
        }
        
        // 如果在 MCP 服务器配置节中，解析配置项
        if (inMcpServerSection && currentServerConfig != null && trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          // 检查是否是 MCP 服务器配置的有效字段
          // MCP 服务器配置的有效字段：command, args, env, cwd, url, headers, type
          final validMcpFields = {'command', 'args', 'env', 'cwd', 'url', 'headers', 'type'};
          
          // 找到第一个 = 的位置（key和value之间的等号）
          // 注意：不能直接用split('=')，因为对象内部也有等号
          final equalIndex = trimmed.indexOf('=');
          if (equalIndex > 0) {
            final key = trimmed.substring(0, equalIndex).trim();
            
            // 如果不是 MCP 服务器的有效字段，说明已经离开了 MCP 服务器节，应该保存当前配置并结束
            if (!validMcpFields.contains(key)) {
              // 保存当前的服务器配置
              if (currentServerId != null && currentServerConfig != null) {
                mcpServerSections[currentServerId] = currentServerConfig!;
              }
              // 结束 MCP 服务器节，将当前行作为非 MCP 配置行处理
              currentServerId = null;
              currentServerConfig = null;
              inMcpServerSection = false;
              nonMcpLines.add(line);
              continue;
            }
            
            var value = trimmed.substring(equalIndex + 1).trim();
            
            // 处理数组（使用改进的解析逻辑，支持嵌套引号和自动提取环境变量）
            if (value.startsWith('[') && value.endsWith(']')) {
              final arrayContent = value.substring(1, value.length - 1);
              final result = _parseTomlArrayWithEnvExtraction(arrayContent);
              
              // 保存 args
              if (result.$1.isNotEmpty) {
                currentServerConfig![key] = result.$1;
              }
              
              // 如果有环境变量，保存到 env
              if (result.$2.isNotEmpty) {
                Map<String, String>? existingEnv = currentServerConfig!['env'] as Map<String, String>?;
                if (existingEnv == null) {
                  existingEnv = <String, String>{};
                }
                existingEnv.addAll(result.$2);
                currentServerConfig!['env'] = existingEnv;
                print('修复服务器 ${currentServerId}：从 args 中提取环境变量: ${result.$2.keys.join(", ")}');
              }
            }
            // 处理对象（env）
            else if (value.startsWith('{') && value.endsWith('}')) {
              final envMap = <String, String>{};
              final envContent = value.substring(1, value.length - 1);
              
              // 解析TOML对象格式： "key" = "value", "key2" = "value2"
              // 使用正则表达式匹配 "key" = "value" 格式
              final regex = RegExp(r'"([^"]+)"\s*=\s*"([^"]+)"');
              final matches = regex.allMatches(envContent);
              for (final match in matches) {
                if (match.groupCount >= 2) {
                  final k = match.group(1)!;
                  final v = match.group(2)!;
                  envMap[k] = v;
                }
              }
              
              // 如果没有匹配到（可能是单引号或其他格式），使用原来的方法作为后备
              if (envMap.isEmpty) {
                final envPairs = envContent.split(',');
                for (final pair in envPairs) {
                  // 找到第一个 = 的位置
                  final pairEqualIndex = pair.indexOf('=');
                  if (pairEqualIndex > 0) {
                    var k = pair.substring(0, pairEqualIndex).trim();
                    var v = pair.substring(pairEqualIndex + 1).trim();
                    if ((k.startsWith('"') && k.endsWith('"')) ||
                        (k.startsWith("'") && k.endsWith("'"))) {
                      k = k.substring(1, k.length - 1);
                    }
                    if ((v.startsWith('"') && v.endsWith('"')) ||
                        (v.startsWith("'") && v.endsWith("'"))) {
                      v = v.substring(1, v.length - 1);
                    }
                    if (k.isNotEmpty && v.isNotEmpty) {
                      envMap[k] = v;
                    }
                  }
                }
              }
              
              if (envMap.isNotEmpty) {
                currentServerConfig![key] = envMap;
              }
            }
            // 处理字符串（包括url字段）
            else {
              // 移除引号
              if ((value.startsWith('"') && value.endsWith('"')) ||
                  (value.startsWith("'") && value.endsWith("'"))) {
                value = value.substring(1, value.length - 1);
              }
              currentServerConfig![key] = value;
            }
          }
        } else if (!inMcpServerSection) {
          // 非 MCP 配置行，保留
          nonMcpLines.add(line);
        }
      }
      
      // 保存最后一个服务器配置
      if (currentServerId != null && currentServerConfig != null) {
        mcpServerSections[currentServerId] = currentServerConfig!;
      }

      // 更新或添加新的 MCP 服务器配置
      // 注意：合并配置而不是完全覆盖，保留原始配置中的其他字段
      // 创建规范化名称到原始名称的映射，用于容错比对
      final normalizedToOriginal = <String, String>{};
      for (final key in mcpServerSections.keys) {
        final normalized = _normalizeServerNameForComparison(key);
        normalizedToOriginal[normalized] = key;
      }

      for (final server in serversToSync) {
        var serverConfig = server.toToolConfigFormat();
        
        // 对于 codex，需要从 args 中提取环境变量到 env
        if (serverConfig.containsKey('args') && serverConfig['args'] is List) {
          final args = serverConfig['args'] as List<String>;
          final result = _extractEnvFromArgs(args);
          
          // 更新 args（移除环境变量）
          if (result.$1.isNotEmpty) {
            serverConfig['args'] = result.$1;
          } else {
            serverConfig.remove('args');
          }
          
          // 合并 env（提取的环境变量 + 原有的 env）
          if (result.$2.isNotEmpty) {
            Map<String, String>? existingEnv = serverConfig['env'] as Map<String, String>?;
            if (existingEnv == null) {
              existingEnv = <String, String>{};
            }
            existingEnv.addAll(result.$2);
            serverConfig['env'] = existingEnv;
          }
        }
        
        final normalizedServerId = _normalizeServerNameForComparison(server.serverId);
        
        // 使用规范化名称进行容错比对（空格和连字符视为相同）
        String? existingKey;
        if (normalizedToOriginal.containsKey(normalizedServerId)) {
          existingKey = normalizedToOriginal[normalizedServerId];
        } else if (mcpServerSections.containsKey(server.serverId)) {
          existingKey = server.serverId;
        }
        
        if (existingKey != null) {
          // 服务器已存在，合并配置（保留原始字段）
          final existingConfig = mcpServerSections[existingKey]!;
          // 合并配置：先保留原始配置，然后更新需要更新的字段
          // 只合并 MCP 服务器的有效字段，过滤掉其他字段（如 model_provider, model 等）
          final mergedConfig = Map<String, dynamic>.from(existingConfig);
          final validMcpFields = {'command', 'args', 'env', 'cwd', 'url', 'headers', 'type'};
          for (final entry in serverConfig.entries) {
            if (validMcpFields.contains(entry.key)) {
              mergedConfig[entry.key] = entry.value;
            }
          }
          // 使用规范化后的名称作为新键（符合 codex 格式要求）
          final normalizedName = _normalizeCodexServerName(server.serverId);
          mcpServerSections.remove(existingKey);
          mcpServerSections[normalizedName] = mergedConfig;
        } else {
          // 新服务器，使用规范化后的名称
          // 过滤掉无效字段
          final validMcpFields = {'command', 'args', 'env', 'cwd', 'url', 'headers', 'type'};
          final filteredConfig = <String, dynamic>{};
          for (final entry in serverConfig.entries) {
            if (validMcpFields.contains(entry.key)) {
              filteredConfig[entry.key] = entry.value;
            }
          }
          final normalizedName = _normalizeCodexServerName(server.serverId);
          mcpServerSections[normalizedName] = filteredConfig;
        }
      }

      // 生成 TOML 内容
      final buffer = StringBuffer();
      
      // 写入非 MCP 配置部分
      for (final line in nonMcpLines) {
        buffer.writeln(line);
      }
      
      // 写入 MCP 服务器配置
      if (mcpServerSections.isNotEmpty) {
        if (nonMcpLines.isNotEmpty && !nonMcpLines.last.trim().isEmpty) {
          buffer.writeln('');
        }
        for (final entry in mcpServerSections.entries) {
          // 使用规范化方法处理表名，将空格替换为连字符（符合 codex 格式要求）
          final normalizedName = _normalizeTomlTableName(entry.key);
          buffer.writeln('[mcp_servers.$normalizedName]');
          final config = entry.value;
          
          // 判断服务器类型：如果有url字段，是http/sse类型；否则是stdio类型
          final hasUrl = config.containsKey('url') && config['url'] != null;
          
          if (hasUrl) {
            // http/sse 类型：写入 url 和 headers
            if (config['url'] != null) {
              buffer.writeln('url = "${config['url']}"');
            }
            
            if (config['headers'] != null && config['headers'] is Map) {
              final headers = config['headers'] as Map<String, dynamic>;
              if (headers.isNotEmpty) {
                final headerPairs = headers.entries.map((e) => '"${e.key}" = "${e.value}"').join(', ');
                buffer.writeln('headers = { $headerPairs }');
              }
            }
          } else {
            // stdio 类型：写入 command, args, env, cwd
            // 只写入 MCP 服务器的有效字段，过滤掉其他字段（如 model_provider, model 等）
            final commandValue = config['command'] as String?;
            if (commandValue != null) {
              // 检查 command 是否包含空格，如果包含则拆分
              if (commandValue.contains(' ')) {
                final splitResult = _splitCommand(commandValue);
                buffer.writeln('command = "${splitResult.$1}"');
                // 将拆分出的 args 合并到现有的 args 中
                List<String> allArgs = List<String>.from(splitResult.$2);
                if (config['args'] != null && config['args'] is List) {
                  allArgs.addAll(List<String>.from(config['args'] as List));
                }
                if (allArgs.isNotEmpty) {
                  final argsStr = allArgs.map((e) => '"$e"').join(', ');
                  buffer.writeln('args = [$argsStr]');
                }
              } else {
                buffer.writeln('command = "$commandValue"');
                
                if (config['args'] != null && config['args'] is List) {
                  final args = config['args'] as List;
                  final argsStr = args.map((e) => '"$e"').join(', ');
                  buffer.writeln('args = [$argsStr]');
                }
              }
            }
            
            if (config['env'] != null && config['env'] is Map) {
              final env = config['env'] as Map<String, dynamic>;
              if (env.isNotEmpty) {
                final envPairs = env.entries.map((e) => '"${e.key}" = "${e.value}"').join(', ');
                buffer.writeln('env = { $envPairs }');
              }
            }
            
            if (config['cwd'] != null) {
              buffer.writeln('cwd = "${config['cwd']}"');
            }
          }
          
          buffer.writeln('');
        }
      }

      // 写入文件
      await configFile.writeAsString(buffer.toString());
      return true;
    } catch (e) {
      print('同步到 Codex TOML 配置失败: $e');
      return false;
    }
  }

  /// 读取工具配置文件
  Future<Map<String, dynamic>?> readToolConfig(AiToolType tool) async {
    try {
      // ClaudeCode 使用特殊的配置文件位置：~/.claude.json（不在配置目录下）
      if (tool == AiToolType.claudecode) {
        final homeDir = await SettingsService.getUserHomeDir();
        final configFilePath = path.join(homeDir, '.claude.json');
        print('工具 ${tool.displayName} 配置文件路径: $configFilePath');
        
        final configFile = File(configFilePath);
        if (!await configFile.exists()) {
          print('配置文件不存在: $configFilePath');
          return null;
        }

        final content = await configFile.readAsString();
        final config = jsonDecode(content) as Map<String, dynamic>;
        print('成功读取 ClaudeCode 配置');
        return config;
      }

      final configDir = await _configService.getConfigDir(tool);
      print('工具 ${tool.displayName} 配置目录: $configDir');
      
      final configFilePath = AiToolConfigService.getConfigFilePath(tool, customConfigDir: configDir);
      print('工具 ${tool.displayName} 配置文件路径（未展开）: $configFilePath');
      
      final expandedPath = AiToolConfigService.expandPath(configFilePath);
      print('读取工具 ${tool.displayName} 配置（已展开）: $expandedPath');
      
      final configFile = File(expandedPath);
      if (!await configFile.exists()) {
        print('配置文件不存在: $expandedPath');
        return null;
      }

      final content = await configFile.readAsString();
      
      // Codex 使用 TOML 格式，需要特殊处理
      if (tool == AiToolType.codex) {
        return await _readCodexTomlConfig(content);
      }

      // Gemini 和其他工具使用 JSON 格式
      final config = jsonDecode(content) as Map<String, dynamic>;
      
      // Gemini 的配置格式是 { "apiKey": "", "mcpServers": {} }
      // 需要确保返回的格式包含 mcpServers 字段
      if (tool == AiToolType.gemini) {
        // 如果配置中没有 mcpServers 字段，添加空对象
        if (!config.containsKey('mcpServers')) {
          config['mcpServers'] = <String, dynamic>{};
        }
        print('成功读取 Gemini 配置，mcpServers: ${config['mcpServers']}');
        return config;
      }

      // 其他工具使用 JSON 格式
      print('成功读取配置，mcpServers: ${config['mcpServers']}');
      return config;
    } catch (e, stackTrace) {
      print('读取工具 ${tool.displayName} 配置失败: $e');
      print('堆栈跟踪: $stackTrace');
      return null;
    }
  }

  /// 读取 Codex 的 TOML 配置文件，转换为统一的 JSON 格式
  Future<Map<String, dynamic>?> _readCodexTomlConfig(String content) async {
    try {
      final lines = content.split('\n');
      final mcpServers = <String, Map<String, dynamic>>{};
      
      String? currentServerId;
      Map<String, dynamic>? currentServerConfig;
      bool inMcpServerSection = false;

      for (final line in lines) {
        final trimmed = line.trim();
        
        // 检查是否是 MCP 服务器配置节
        if (trimmed.startsWith('[mcp_servers.') && trimmed.endsWith(']')) {
          // 保存之前的服务器配置
          if (currentServerId != null && currentServerConfig != null) {
            mcpServers[currentServerId] = currentServerConfig!;
          }
          
          // 开始新的服务器配置，使用统一的解析方法处理带引号的表名
          currentServerId = _parseTomlTableName(trimmed);
          currentServerConfig = {};
          inMcpServerSection = true;
          continue;
        }
        
        // 检查是否是其他配置节（非 MCP）
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          // 保存之前的服务器配置
          if (currentServerId != null && currentServerConfig != null) {
            mcpServers[currentServerId] = currentServerConfig!;
          }
          
          currentServerId = null;
          currentServerConfig = null;
          inMcpServerSection = false;
          continue;
        }
        
        // 如果在 MCP 服务器配置节中，解析配置项
        if (inMcpServerSection && currentServerConfig != null && trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          // 找到第一个 = 的位置（key和value之间的等号）
          // 注意：不能直接用split('=')，因为对象内部也有等号
          final equalIndex = trimmed.indexOf('=');
          if (equalIndex > 0) {
            final key = trimmed.substring(0, equalIndex).trim();
            var value = trimmed.substring(equalIndex + 1).trim();
            
            // 处理数组（使用改进的解析逻辑，支持嵌套引号和自动提取环境变量）
            if (value.startsWith('[') && value.endsWith(']')) {
              final arrayContent = value.substring(1, value.length - 1);
              final result = _parseTomlArrayWithEnvExtraction(arrayContent);
              
              // 保存 args
              if (result.$1.isNotEmpty) {
                currentServerConfig![key] = result.$1;
              }
              
              // 如果有环境变量，保存到 env
              if (result.$2.isNotEmpty) {
                Map<String, String>? existingEnv = currentServerConfig!['env'] as Map<String, String>?;
                if (existingEnv == null) {
                  existingEnv = <String, String>{};
                }
                existingEnv.addAll(result.$2);
                currentServerConfig!['env'] = existingEnv;
                print('修复服务器 ${currentServerId}：从 args 中提取环境变量: ${result.$2.keys.join(", ")}');
              }
            }
            // 处理对象（env）
            else if (value.startsWith('{') && value.endsWith('}')) {
              final envMap = <String, String>{};
              final envContent = value.substring(1, value.length - 1);
              
              // 解析TOML对象格式： "key" = "value", "key2" = "value2"
              // 使用正则表达式匹配 "key" = "value" 格式
              final regex = RegExp(r'"([^"]+)"\s*=\s*"([^"]+)"');
              final matches = regex.allMatches(envContent);
              for (final match in matches) {
                if (match.groupCount >= 2) {
                  final k = match.group(1)!;
                  final v = match.group(2)!;
                  envMap[k] = v;
                }
              }
              
              // 如果没有匹配到（可能是单引号或其他格式），使用原来的方法作为后备
              if (envMap.isEmpty) {
                final envPairs = envContent.split(',');
                for (final pair in envPairs) {
                  // 找到第一个 = 的位置
                  final pairEqualIndex = pair.indexOf('=');
                  if (pairEqualIndex > 0) {
                    var k = pair.substring(0, pairEqualIndex).trim();
                    var v = pair.substring(pairEqualIndex + 1).trim();
                    if ((k.startsWith('"') && k.endsWith('"')) ||
                        (k.startsWith("'") && k.endsWith("'"))) {
                      k = k.substring(1, k.length - 1);
                    }
                    if ((v.startsWith('"') && v.endsWith('"')) ||
                        (v.startsWith("'") && v.endsWith("'"))) {
                      v = v.substring(1, v.length - 1);
                    }
                    if (k.isNotEmpty && v.isNotEmpty) {
                      envMap[k] = v;
                    }
                  }
                }
              }
              
              if (envMap.isNotEmpty) {
                currentServerConfig![key] = envMap;
              }
            }
            // 处理字符串
            else {
              // 移除引号
              if ((value.startsWith('"') && value.endsWith('"')) ||
                  (value.startsWith("'") && value.endsWith("'"))) {
                value = value.substring(1, value.length - 1);
              }
              currentServerConfig![key] = value;
            }
          }
        }
      }
      
      // 保存最后一个服务器配置
      if (currentServerId != null && currentServerConfig != null) {
        mcpServers[currentServerId] = currentServerConfig!;
      }

      // 修复错误格式：
      // 1. 检查 command 是否包含空格，如果是则拆分
      // 2. 检查 args 数组中是否有环境变量格式的元素（如 "API_KEY=xxx"），如果有则提取到 env 中
      for (final entry in mcpServers.entries) {
        final config = entry.value;
        
        // 修复 command 包含空格的情况
        if (config.containsKey('command') && config['command'] is String) {
          final commandStr = config['command'] as String;
          if (commandStr.contains(' ')) {
            final splitResult = _splitCommand(commandStr);
            config['command'] = splitResult.$1;
            if (splitResult.$2.isNotEmpty) {
              // 合并到现有的 args（如果有）
              List<String>? existingArgs = config['args'] as List<String>?;
              if (existingArgs == null) {
                existingArgs = [];
              }
              // 将拆分出的 args 添加到前面
              existingArgs = [...splitResult.$2, ...existingArgs];
              config['args'] = existingArgs;
              print('修复服务器 ${entry.key}：拆分 command "${commandStr}" 为 command="${splitResult.$1}" 和 args=${splitResult.$2}');
            }
          }
        }
        
        // 修复 args 中的环境变量
        if (config.containsKey('args') && config['args'] is List) {
          final args = config['args'] as List;
          final fixedArgs = <String>[];
          Map<String, String>? env = config['env'] as Map<String, String>?;
          if (env == null) {
            env = <String, String>{};
          }
          
          bool hasChanges = false;
          for (final arg in args) {
            final argStr = arg.toString();
            // 检查是否是环境变量格式：KEY=VALUE（可能包含转义引号）
            // 匹配格式如：API_KEY=value 或 API_KEY="value" 或 "API_KEY=\"value\""
            final envMatch = RegExp(r'^"?([A-Z_][A-Z0-9_]*)\s*=\s*(.+)$').firstMatch(argStr);
            if (envMatch != null) {
              // 这是环境变量，提取到 env 中
              final key = envMatch.group(1)!;
              var value = envMatch.group(2)!;
              // 移除引号（处理转义引号和嵌套引号）
              // 先处理转义的引号 \" -> "
              value = value.replaceAll(r'\"', '"');
              // 然后移除外层引号
              while ((value.startsWith('"') && value.endsWith('"')) ||
                     (value.startsWith("'") && value.endsWith("'"))) {
                value = value.substring(1, value.length - 1);
              }
              env[key] = value;
              hasChanges = true;
            } else {
              // 不是环境变量，保留在 args 中
              fixedArgs.add(argStr);
            }
          }
          
          if (hasChanges) {
            config['args'] = fixedArgs;
            if (env.isNotEmpty) {
              config['env'] = env;
            } else {
              config.remove('env');
            }
            print('修复服务器 ${entry.key}：将环境变量从 args 移到 env');
          }
        }
      }

      print('成功读取 Codex TOML 配置，mcpServers: $mcpServers');
      return {'mcpServers': mcpServers};
    } catch (e, stackTrace) {
      print('读取 Codex TOML 配置失败: $e');
      print('堆栈跟踪: $stackTrace');
      return null;
    }
  }

  /// 写入工具配置文件
  Future<bool> writeToolConfig(AiToolType tool, Map<String, dynamic> config) async {
    try {
      final configDir = await _configService.getConfigDir(tool);
      await _configService.ensureConfigDirExists(tool, customConfigDir: configDir);
      final configFilePath = AiToolConfigService.getConfigFilePath(tool, customConfigDir: configDir);
      final expandedPath = AiToolConfigService.expandPath(configFilePath);

      // 备份原文件
      final configFile = File(expandedPath);
      if (await configFile.exists()) {
        final backupPath = '$expandedPath.backup';
        await configFile.copy(backupPath);
      }

      // Codex 使用 TOML 格式，需要特殊处理
      if (tool == AiToolType.codex) {
        // 将 JSON 格式的配置转换为 TOML
        final mcpServers = config['mcpServers'] as Map<String, dynamic>? ?? {};
        final buffer = StringBuffer();
        
        for (final entry in mcpServers.entries) {
          // 使用规范化方法处理表名，将空格替换为连字符（符合 codex 格式要求）
          final normalizedName = _normalizeTomlTableName(entry.key);
          buffer.writeln('[mcp_servers.$normalizedName]');
          var serverConfig = Map<String, dynamic>.from(entry.value as Map<String, dynamic>);
          
          // 对于 codex，需要从 args 中提取环境变量到 env
          if (serverConfig.containsKey('args') && serverConfig['args'] is List) {
            final args = List<String>.from(serverConfig['args'] as List);
            final result = _extractEnvFromArgs(args);
            
            // 更新 args（移除环境变量）
            if (result.$1.isNotEmpty) {
              serverConfig['args'] = result.$1;
            } else {
              serverConfig.remove('args');
            }
            
            // 合并 env（提取的环境变量 + 原有的 env）
            if (result.$2.isNotEmpty) {
              Map<String, String>? existingEnv = serverConfig['env'] as Map<String, String>?;
              if (existingEnv == null) {
                existingEnv = <String, String>{};
              }
              existingEnv.addAll(result.$2);
              serverConfig['env'] = existingEnv;
            }
          }
          
          // 处理 command：确保不包含空格（如果包含，应该已经在 args 中）
          final commandValue = serverConfig['command'] as String?;
          if (commandValue != null) {
            // 检查 command 是否包含空格，如果包含则拆分
            if (commandValue.contains(' ')) {
              final splitResult = _splitCommand(commandValue);
              buffer.writeln('command = "${splitResult.$1}"');
              // 将拆分出的 args 合并到现有的 args 中
              List<String> allArgs = List<String>.from(splitResult.$2);
              if (serverConfig['args'] != null && serverConfig['args'] is List) {
                allArgs.addAll(List<String>.from(serverConfig['args'] as List));
              }
              if (allArgs.isNotEmpty) {
                final argsStr = allArgs.map((e) => '"$e"').join(', ');
                buffer.writeln('args = [$argsStr]');
              }
            } else {
              buffer.writeln('command = "$commandValue"');
              
              if (serverConfig['args'] != null && serverConfig['args'] is List) {
                final args = serverConfig['args'] as List;
                final argsStr = args.map((e) => '"$e"').join(', ');
                buffer.writeln('args = [$argsStr]');
              }
            }
          }
          
          if (serverConfig['env'] != null && serverConfig['env'] is Map) {
            final env = serverConfig['env'] as Map<String, dynamic>;
            if (env.isNotEmpty) {
              final envPairs = env.entries.map((e) => '"${e.key}" = "${e.value}"').join(', ');
              buffer.writeln('env = { $envPairs }');
            }
          }
          
          if (serverConfig['cwd'] != null) {
            buffer.writeln('cwd = "${serverConfig['cwd']}"');
          }
          
          buffer.writeln('');
        }
        
        await configFile.writeAsString(buffer.toString());
        return true;
      }

      // 其他工具使用 JSON 格式
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      return true;
    } catch (e) {
      print('写入工具 ${tool.displayName} 配置失败: $e');
      return false;
    }
  }

  /// 获取工具配置中的 mcpServers
  /// [scope] 对于 claudecode，可以是 'global' 或项目路径（如 '/Users/liuhuayao/dev'）
  /// 返回 mcpServers 和是否有项目配置的标志
  Future<({Map<String, dynamic>? mcpServers, bool hasProjectConfig})> getToolMcpServers(AiToolType tool, {String? scope}) async {
    final config = await readToolConfig(tool);
    if (config == null) {
      return (mcpServers: null, hasProjectConfig: false);
    }
    
    // ClaudeCode 支持全局和项目配置
    if (tool == AiToolType.claudecode) {
      if (scope != null && scope != 'global') {
        // 项目配置：从 projects 对象中获取指定项目的 mcpServers
        final projects = config['projects'] as Map<String, dynamic>?;
        if (projects != null && projects.containsKey(scope)) {
          final projectConfig = projects[scope] as Map<String, dynamic>?;
          final projectMcpServers = projectConfig?['mcpServers'] as Map<String, dynamic>?;
          if (projectMcpServers != null && projectMcpServers.isNotEmpty) {
            print('使用 ClaudeCode 项目配置: $scope');
            return (mcpServers: projectMcpServers, hasProjectConfig: true);
          } else {
            // 项目存在但没有 MCP 配置，返回空列表（不返回全局配置）
            print('项目 $scope 没有 MCP 配置，返回空列表');
            return (mcpServers: <String, dynamic>{}, hasProjectConfig: false);
          }
        } else {
          // 项目不存在，返回空列表（不返回全局配置）
          print('项目 $scope 不存在，返回空列表');
          return (mcpServers: <String, dynamic>{}, hasProjectConfig: false);
        }
      }
      // 全局配置：从根级别的 mcpServers 获取
      final globalMcpServers = config['mcpServers'] as Map<String, dynamic>?;
      print('使用 ClaudeCode 全局配置');
      return (mcpServers: globalMcpServers, hasProjectConfig: false);
    }
    
    // 其他工具直接从根级别获取
    return (mcpServers: config['mcpServers'] as Map<String, dynamic>?, hasProjectConfig: false);
  }

  /// 获取 ClaudeCode 可用的配置范围（全局 + 所有项目路径）
  /// 返回所有项目路径，无论是否有 MCP 配置
  Future<List<String>> getClaudeCodeScopes() async {
    final config = await readToolConfig(AiToolType.claudecode);
    if (config == null) {
      return ['global'];
    }
    
    final scopes = <String>['global'];
    final projects = config['projects'] as Map<String, dynamic>?;
    if (projects != null) {
      // 列出所有项目路径，无论是否有 MCP 配置
      for (final projectPath in projects.keys) {
        scopes.add(projectPath);
      }
    }
    return scopes;
  }

  /// 检查指定项目是否有 MCP 配置
  Future<bool> hasProjectMcpConfig(String projectPath) async {
    final config = await readToolConfig(AiToolType.claudecode);
    if (config == null) {
      return false;
    }
    
    final projects = config['projects'] as Map<String, dynamic>?;
    if (projects != null && projects.containsKey(projectPath)) {
      final projectConfig = projects[projectPath] as Map<String, dynamic>?;
      final projectMcpServers = projectConfig?['mcpServers'] as Map<String, dynamic>?;
      return projectMcpServers != null && projectMcpServers.isNotEmpty;
    }
    return false;
  }

  /// 从工具配置文件读取所有 MCP 服务器配置
  /// 返回 Map，key 为 serverId（MCP 服务名称），value 为 McpServer 对象
  /// [scope] 对于 claudecode，可以是 'global' 或项目路径
  /// 返回结果和是否有项目配置的标志
  Future<({Map<String, McpServer> servers, bool hasProjectConfig})> readMcpServersFromTool(AiToolType tool, {String? scope}) async {
    final result = <String, McpServer>{};
    
    try {
      final resultData = await getToolMcpServers(tool, scope: scope);
      final mcpServers = resultData.mcpServers;
      final hasProjectConfig = resultData.hasProjectConfig;
      
      print('从工具 ${tool.displayName}${scope != null ? ' ($scope)' : ''} 读取到的 mcpServers: $mcpServers, hasProjectConfig: $hasProjectConfig');
      
      if (mcpServers == null || mcpServers.isEmpty) {
        print('mcpServers 为空或 null');
        return (servers: result, hasProjectConfig: hasProjectConfig);
      }

      // 遍历工具配置中的每个 MCP 服务器
      mcpServers.forEach((serverId, config) {
        try {
          print('解析 MCP 服务器: $serverId, 配置: $config');
          final server = _parseToolConfigToMcpServer(serverId, config as Map<String, dynamic>);
          result[serverId] = server;
          print('成功解析 MCP 服务器: $serverId');
        } catch (e, stackTrace) {
          print('解析 MCP 服务器 "$serverId" 失败: $e');
          print('堆栈跟踪: $stackTrace');
        }
      });
      
      print('最终解析结果数量: ${result.length}');
      return (servers: result, hasProjectConfig: hasProjectConfig);
    } catch (e, stackTrace) {
      print('从工具 ${tool.displayName} 读取 MCP 配置失败: $e');
      print('堆栈跟踪: $stackTrace');
      return (servers: <String, McpServer>{}, hasProjectConfig: false);
    }
  }

  /// 解析工具配置中的单个 MCP 服务器配置为 McpServer 对象
  McpServer _parseToolConfigToMcpServer(String serverId, Map<String, dynamic> config) {
    // 判断服务器类型
    McpServerType serverType;
    if (config.containsKey('url')) {
      // 有 url 字段，判断是 http 还是 sse
      final typeStr = config['type'] as String?;
      if (typeStr == 'sse') {
        serverType = McpServerType.sse;
      } else {
        serverType = McpServerType.http;
      }
    } else {
      // 没有 url，默认为 stdio
      serverType = McpServerType.stdio;
    }

    // 解析 stdio 类型字段
    String? command;
    List<String>? args;
    Map<String, String>? env;
    String? cwd;

    if (serverType == McpServerType.stdio) {
      // 处理 command：如果包含空格，需要拆分
      final commandStr = config['command'] as String?;
      if (commandStr != null && commandStr.contains(' ')) {
        final splitResult = _splitCommand(commandStr);
        command = splitResult.$1;
        // 将拆分出的 args 合并到 args 中
        if (splitResult.$2.isNotEmpty) {
          final existingArgs = config['args'] as List?;
          if (existingArgs != null) {
            args = [...splitResult.$2, ...List<String>.from(existingArgs)];
          } else {
            args = splitResult.$2;
          }
        } else {
          if (config['args'] != null) {
            if (config['args'] is List) {
              args = List<String>.from(config['args']);
            } else if (config['args'] is String) {
              args = [config['args'] as String];
            }
          }
        }
      } else {
        command = commandStr;
        
        if (config['args'] != null) {
          if (config['args'] is List) {
            args = List<String>.from(config['args']);
          } else if (config['args'] is String) {
            args = [config['args'] as String];
          }
        }
      }

      if (config['env'] != null) {
        if (config['env'] is Map) {
          env = Map<String, String>.from(config['env'] as Map);
        }
      }

      cwd = config['cwd'] as String?;
    }

    // 解析 http/sse 类型字段
    String? url;
    Map<String, String>? headers;

    if (serverType == McpServerType.http || serverType == McpServerType.sse) {
      url = config['url'] as String?;
      
      if (config['headers'] != null) {
        if (config['headers'] is Map) {
          headers = Map<String, String>.from(config['headers'] as Map);
        }
      }
    }

    // 创建 McpServer 对象
    // serverId 使用传入的 key，name 默认使用 serverId
    final now = DateTime.now();
    return McpServer(
      serverId: serverId,
      name: serverId, // 默认名称使用 serverId
      serverType: serverType,
      command: command,
      args: args,
      env: env,
      cwd: cwd,
      url: url,
      headers: headers,
      isActive: true, // 从工具读取的默认激活
      createdAt: now,
      updatedAt: now,
    );
  }

  /// 从工具配置文件中删除指定的 MCP 服务
  /// [tool] 目标工具
  /// [serverIds] 要删除的 MCP 服务 ID 列表
  /// [scope] 对于 claudecode，可以是 'global' 或项目路径
  Future<bool> deleteFromTool(AiToolType tool, Set<String> serverIds, {String? scope}) async {
    try {
      if (serverIds.isEmpty) {
        return false;
      }

      // ClaudeCode 使用特殊的配置文件位置：~/.claude.json
      if (tool == AiToolType.claudecode) {
        return await _deleteFromClaudeCode(serverIds, scope: scope);
      }

      // 获取配置文件路径
      final configDir = await _configService.getConfigDir(tool);
      final configFilePath = AiToolConfigService.getConfigFilePath(tool, customConfigDir: configDir);
      final expandedPath = AiToolConfigService.expandPath(configFilePath);

      final configFile = File(expandedPath);
      if (!await configFile.exists()) {
        return false;
      }

      // 备份原文件
      final backupPath = '$expandedPath.backup';
      await configFile.copy(backupPath);

      // Codex 使用 TOML 格式，需要特殊处理
      if (tool == AiToolType.codex) {
        return await _deleteFromCodexToml(configFile, serverIds);
      }

      // Gemini 和其他工具使用 JSON 格式
      final content = await configFile.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;

      // 获取现有的 mcpServers
      if (config['mcpServers'] == null) {
        return false;
      }

      final mcpServers = Map<String, dynamic>.from(config['mcpServers'] as Map);

      // 删除指定的服务
      for (final serverId in serverIds) {
        mcpServers.remove(serverId);
      }

      // 更新配置中的 mcpServers 字段
      config['mcpServers'] = mcpServers;

      // Gemini 需要保留 apiKey 字段
      if (tool == AiToolType.gemini && !config.containsKey('apiKey')) {
        config['apiKey'] = '';
      }

      // 写入配置文件
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      return true;
    } catch (e) {
      print('从工具 ${tool.displayName} 删除 MCP 服务失败: $e');
      return false;
    }
  }

  /// 从 ClaudeCode 配置文件中删除 MCP 服务
  Future<bool> _deleteFromClaudeCode(Set<String> serverIds, {String? scope}) async {
    try {
      final homeDir = await SettingsService.getUserHomeDir();
      final configFilePath = path.join(homeDir, '.claude.json');
      final configFile = File(configFilePath);
      
      if (!await configFile.exists()) {
        return false;
      }

      // 备份原文件
      final backupPath = '$configFilePath.backup';
      await configFile.copy(backupPath);

      // 读取现有配置
      final content = await configFile.readAsString();
      final config = jsonDecode(content) as Map<String, dynamic>;

      if (scope != null && scope != 'global') {
        // 从项目配置中删除
        final projects = config['projects'] as Map<String, dynamic>?;
        if (projects != null && projects.containsKey(scope)) {
          final projectConfig = projects[scope] as Map<String, dynamic>?;
          final projectMcpServers = projectConfig?['mcpServers'] as Map<String, dynamic>?;
          if (projectMcpServers != null) {
            for (final serverId in serverIds) {
              projectMcpServers.remove(serverId);
            }
            projectConfig!['mcpServers'] = projectMcpServers;
            print('从 ClaudeCode 项目配置删除: $scope');
          }
        }
      } else {
        // 从全局配置中删除
        final globalMcpServers = config['mcpServers'] as Map<String, dynamic>?;
        if (globalMcpServers != null) {
          for (final serverId in serverIds) {
            globalMcpServers.remove(serverId);
          }
          config['mcpServers'] = globalMcpServers;
          print('从 ClaudeCode 全局配置删除');
        }
      }

      // 写入配置文件
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      return true;
    } catch (e) {
      print('从 ClaudeCode 删除 MCP 服务失败: $e');
      return false;
    }
  }

  /// 从 Codex 的 TOML 配置文件中删除 MCP 服务
  Future<bool> _deleteFromCodexToml(File configFile, Set<String> serverIds) async {
    try {
      final content = await configFile.readAsString();
      final lines = content.split('\n');
      final nonMcpLines = <String>[];
      final mcpServerSections = <String, Map<String, dynamic>>{};
      
      String? currentServerId;
      Map<String, dynamic>? currentServerConfig;
      bool inMcpServerSection = false;

      // 解析 TOML 内容
      for (final line in lines) {
        final trimmed = line.trim();
        
        // 检查是否是 MCP 服务器配置节
        if (trimmed.startsWith('[mcp_servers.') || trimmed.startsWith('[mcp.servers.')) {
          // 保存上一个服务器配置
          if (currentServerId != null && currentServerConfig != null) {
            mcpServerSections[currentServerId] = currentServerConfig!;
          }
          
          // 提取服务器ID，使用统一的解析方法处理带引号的表名
          if (trimmed.startsWith('[mcp_servers.')) {
            currentServerId = _parseTomlTableName(trimmed);
          } else {
            // 处理 [mcp.servers.xxx] 格式
            final match = RegExp(r'\[mcp\.servers\.(.+)\]').firstMatch(trimmed);
            if (match != null) {
              var name = match.group(1)!;
              // 移除可能的引号
              if ((name.startsWith('"') && name.endsWith('"')) ||
                  (name.startsWith("'") && name.endsWith("'"))) {
                name = name.substring(1, name.length - 1);
              }
              currentServerId = name;
            } else {
              continue;
            }
          }
          currentServerConfig = <String, dynamic>{};
          inMcpServerSection = true;
          continue;
        }
        
        // 如果不在 MCP 服务器配置节中，保留原行
        if (!inMcpServerSection) {
          nonMcpLines.add(line);
          continue;
        }
        
        // 检查是否结束当前节
        if (trimmed.startsWith('[') && !trimmed.startsWith('[mcp')) {
          if (currentServerId != null && currentServerConfig != null) {
            mcpServerSections[currentServerId] = currentServerConfig!;
          }
          currentServerId = null;
          currentServerConfig = null;
          inMcpServerSection = false;
          nonMcpLines.add(line);
          continue;
        }
        
        // 解析配置项（使用与_readCodexTomlConfig相同的逻辑）
        if (inMcpServerSection && currentServerConfig != null && trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          // 找到第一个 = 的位置（key和value之间的等号）
          // 注意：不能直接用split('=')，因为对象内部也有等号
          final equalIndex = trimmed.indexOf('=');
          if (equalIndex > 0) {
            final key = trimmed.substring(0, equalIndex).trim();
            var value = trimmed.substring(equalIndex + 1).trim();
            
            // 处理数组（使用改进的解析逻辑，支持嵌套引号和自动提取环境变量）
            if (value.startsWith('[') && value.endsWith(']')) {
              final arrayContent = value.substring(1, value.length - 1);
              final result = _parseTomlArrayWithEnvExtraction(arrayContent);
              
              // 保存 args
              if (result.$1.isNotEmpty) {
                currentServerConfig![key] = result.$1;
              }
              
              // 如果有环境变量，保存到 env
              if (result.$2.isNotEmpty) {
                Map<String, String>? existingEnv = currentServerConfig!['env'] as Map<String, String>?;
                if (existingEnv == null) {
                  existingEnv = <String, String>{};
                }
                existingEnv.addAll(result.$2);
                currentServerConfig!['env'] = existingEnv;
                print('修复服务器 ${currentServerId}：从 args 中提取环境变量: ${result.$2.keys.join(", ")}');
              }
            }
            // 处理对象（env）
            else if (value.startsWith('{') && value.endsWith('}')) {
              final envMap = <String, String>{};
              final envContent = value.substring(1, value.length - 1);
              
              // 解析TOML对象格式： "key" = "value", "key2" = "value2"
              // 使用正则表达式匹配 "key" = "value" 格式
              final regex = RegExp(r'"([^"]+)"\s*=\s*"([^"]+)"');
              final matches = regex.allMatches(envContent);
              for (final match in matches) {
                if (match.groupCount >= 2) {
                  final k = match.group(1)!;
                  final v = match.group(2)!;
                  envMap[k] = v;
                }
              }
              
              // 如果没有匹配到（可能是单引号或其他格式），使用原来的方法作为后备
              if (envMap.isEmpty) {
                final envPairs = envContent.split(',');
                for (final pair in envPairs) {
                  // 找到第一个 = 的位置
                  final pairEqualIndex = pair.indexOf('=');
                  if (pairEqualIndex > 0) {
                    var k = pair.substring(0, pairEqualIndex).trim();
                    var v = pair.substring(pairEqualIndex + 1).trim();
                    if ((k.startsWith('"') && k.endsWith('"')) ||
                        (k.startsWith("'") && k.endsWith("'"))) {
                      k = k.substring(1, k.length - 1);
                    }
                    if ((v.startsWith('"') && v.endsWith('"')) ||
                        (v.startsWith("'") && v.endsWith("'"))) {
                      v = v.substring(1, v.length - 1);
                    }
                    if (k.isNotEmpty && v.isNotEmpty) {
                      envMap[k] = v;
                    }
                  }
                }
              }
              
              if (envMap.isNotEmpty) {
                currentServerConfig![key] = envMap;
              }
            }
            // 处理字符串
            else {
              // 移除引号
              if ((value.startsWith('"') && value.endsWith('"')) ||
                  (value.startsWith("'") && value.endsWith("'"))) {
                value = value.substring(1, value.length - 1);
              }
              currentServerConfig![key] = value;
            }
          }
        }
      }
      
      // 保存最后一个服务器配置
      if (currentServerId != null && currentServerConfig != null) {
        mcpServerSections[currentServerId] = currentServerConfig!;
      }

      // 删除指定的服务（使用容错比对）
      // 创建规范化名称到原始名称的映射
      final normalizedToOriginal = <String, String>{};
      for (final key in mcpServerSections.keys) {
        final normalized = _normalizeServerNameForComparison(key);
        normalizedToOriginal[normalized] = key;
      }

      for (final serverId in serverIds) {
        final normalizedServerId = _normalizeServerNameForComparison(serverId);
        
        // 使用规范化名称进行容错比对
        String? keyToRemove;
        if (normalizedToOriginal.containsKey(normalizedServerId)) {
          keyToRemove = normalizedToOriginal[normalizedServerId];
        } else if (mcpServerSections.containsKey(serverId)) {
          keyToRemove = serverId;
        }
        
        if (keyToRemove != null) {
          mcpServerSections.remove(keyToRemove);
        }
      }

      // 生成新的 TOML 内容
      final buffer = StringBuffer();
      
      // 写入非 MCP 配置部分
      for (final line in nonMcpLines) {
        buffer.writeln(line);
      }
      
      // 写入剩余的 MCP 服务器配置
      if (mcpServerSections.isNotEmpty) {
        if (nonMcpLines.isNotEmpty && !nonMcpLines.last.trim().isEmpty) {
          buffer.writeln('');
        }
        for (final entry in mcpServerSections.entries) {
          // 使用规范化方法处理表名，将空格替换为连字符（符合 codex 格式要求）
          final normalizedName = _normalizeTomlTableName(entry.key);
          buffer.writeln('[mcp_servers.$normalizedName]');
          final config = entry.value;
          
          // 判断服务器类型：如果有url字段，是http/sse类型；否则是stdio类型
          final hasUrl = config.containsKey('url') && config['url'] != null;
          
          if (hasUrl) {
            // http/sse 类型：写入 url 和 headers
            if (config['url'] != null) {
              buffer.writeln('url = "${config['url']}"');
            }
            
            if (config['headers'] != null && config['headers'] is Map) {
              final headers = config['headers'] as Map<String, dynamic>;
              if (headers.isNotEmpty) {
                final headerPairs = headers.entries.map((e) => '"${e.key}" = "${e.value}"').join(', ');
                buffer.writeln('headers = { $headerPairs }');
              }
            }
          } else {
            // stdio 类型：写入 command, args, env, cwd
            if (config['command'] != null) {
              buffer.writeln('command = "${config['command']}"');
            }
            
            if (config['args'] != null && config['args'] is List) {
              final args = config['args'] as List;
              final argsStr = args.map((e) => '"$e"').join(', ');
              buffer.writeln('args = [$argsStr]');
            }
            
            if (config['env'] != null && config['env'] is Map) {
              final env = config['env'] as Map<String, dynamic>;
              if (env.isNotEmpty) {
                final envPairs = env.entries.map((e) => '"${e.key}" = "${e.value}"').join(', ');
                buffer.writeln('env = { $envPairs }');
              }
            }
            
            if (config['cwd'] != null) {
              buffer.writeln('cwd = "${config['cwd']}"');
            }
          }
          
          // 写入其他可能存在的字段（保留原始配置中的其他字段，但排除已处理的字段和type字段）
          for (final kv in config.entries) {
            final key = kv.key;
            if (key != 'command' && key != 'args' && key != 'env' && key != 'cwd' && 
                key != 'url' && key != 'headers' && key != 'type') {
              final value = kv.value;
              if (value is String) {
                buffer.writeln('$key = "$value"');
              } else if (value is List) {
                final listStr = value.map((e) => '"$e"').join(', ');
                buffer.writeln('$key = [$listStr]');
              } else if (value is Map) {
                final mapPairs = (value as Map<String, dynamic>).entries.map((e) => '"${e.key}" = "${e.value}"').join(', ');
                buffer.writeln('$key = { $mapPairs }');
              }
            }
          }
          
          buffer.writeln('');
        }
      }

      // 写入文件
      await configFile.writeAsString(buffer.toString());

      return true;
    } catch (e) {
      print('从 Codex TOML 配置删除 MCP 服务失败: $e');
      return false;
    }
  }
}

