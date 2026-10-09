import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/mcp_server.dart';
import 'mcp_database_service.dart';
import 'ai_tool_config_service.dart';
import 'settings_service.dart';
import 'live_config/live_config_writer.dart';
import 'mcp/mcp_tool_formats.dart';

/// MCP 配置同步服务
/// 负责将激活的 MCP 服务器同步到各 AI 工具的配置文件中
class McpSyncService {
  final McpDatabaseService _databaseService = McpDatabaseService();
  final AiToolConfigService _configService = AiToolConfigService();

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
  Future<bool> syncToTool(AiToolType tool, Set<String> serverIds, {String? scope, bool throwOnError = false}) async {
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

      // 备份由 LiveConfigWriter 在写入前自动完成（首写 + 滚动备份）

      // Codex 使用 TOML 格式，需要特殊处理
      if (tool == AiToolType.codex) {
        return await _syncToCodexToml(configFile, serversToSync);
      }

      if (tool.isSyncOnly) {
        return await _syncToNewTool(tool, expandedPath, serversToSync);
      }

      // Gemini 使用 JSON 格式（settings.json），但需要特殊处理以保留 apiKey 字段
      if (tool == AiToolType.gemini) {
        return await _syncToGeminiJson(configFile, serversToSync);
      }

      // 其他工具使用 JSON 格式。解析失败时中止，不会以空配置覆盖原文件
      await LiveConfigWriter.instance.updateJson(tool, expandedPath, (config) {
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
      });

      return true;
    } catch (e) {
      print('同步到工具 ${tool.displayName} 失败: $e');
      if (throwOnError) rethrow;
      return false;
    }
  }

  /// 同步 MCP 服务到 Gemini 配置文件（~/.gemini/settings.json）
  Future<bool> _syncToGeminiJson(File configFile, List<McpServer> serversToSync) async {
    try {
      // 解析失败时中止，不会以空配置覆盖原文件（其中可能有用户的 apiKey 等）
      await LiveConfigWriter.instance.updateJson(AiToolType.gemini, configFile.path, (config) {
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
      });

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

      // ~/.claude.json 还保存着 Claude Code 的全部全局状态：解析失败必须中止，
      // 绝不能以空对象覆盖（以往的实现会清空该文件）
      await LiveConfigWriter.instance.updateJson(AiToolType.claudecode, configFilePath, (config) {
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
      });

      return true;
    } catch (e) {
      print('同步到 ClaudeCode 失败: $e');
      return false;
    }
  }

  /// Codex 下发前的兼容处理：command 含空格时拆分，args 中的 `KEY=value` 提取到 env（沿用旧行为）
  McpServer _prepareForCodex(McpServer server) {
    if (server.serverType != McpServerType.stdio) return server;
    var command = server.command;
    var args = <String>[...?server.args];
    if (command != null && command.contains(' ')) {
      final split = _splitCommand(command);
      command = split.$1;
      args = [...split.$2, ...args];
    }
    final extracted = _extractEnvFromArgs(args);
    final env = <String, String>{...?server.env, ...extracted.$2};
    return server.copyWith(command: command, args: extracted.$1, env: env.isEmpty ? null : env);
  }

  /// 同步 / 删除 Codex、Grok Build 的 `[mcp_servers.*]`（按表解析，只改涉及的服务表）
  ///
  /// 旧实现按行扫描：服务表中出现不认识的键（如 `startup_timeout_sec`）时会把它挪到上一张表，
  /// 且写入值时不做转义、请求头字段写成了 Codex 不认识的 `headers`（应为 `http_headers`）。
  Future<bool> _applyTomlMcp(
    AiToolType tool,
    File configFile, {
    Map<String, McpServer> upserts = const {},
    Set<String> removals = const {},
  }) async {
    final grok = tool == AiToolType.grokBuild;
    final prepared = grok ? upserts : upserts.map((k, v) => MapEntry(k, _prepareForCodex(v)));
    await LiveConfigWriter.instance.updateText(
      tool,
      configFile.path,
      (current) => McpToolFormats.applyToml(current, upserts: prepared, removals: removals, grok: grok),
    );
    return true;
  }

  /// 同步 MCP 服务到 Codex 的 TOML 配置文件
  Future<bool> _syncToCodexToml(File configFile, List<McpServer> serversToSync) async {
    try {
      return await _applyTomlMcp(AiToolType.codex, configFile,
          upserts: {for (final s in serversToSync) s.serverId: s});
    } catch (e) {
      print('同步到 Codex TOML 配置失败: $e');
      return false;
    }
  }

  /// 同步到新增的工具（OpenCode / Grok Build / Hermes / Pi / MiniMax Code）
  Future<bool> _syncToNewTool(AiToolType tool, String filePath, List<McpServer> servers) async {
    final supported = <McpServer>[];
    for (final s in servers) {
      final reason = McpToolFormats.unsupportedReason(tool, s);
      if (reason != null) {
        print('跳过 ${s.serverId} → ${tool.displayName}: $reason');
      } else {
        supported.add(s);
      }
    }
    if (supported.isEmpty) return false;
    switch (tool) {
      case AiToolType.grokBuild:
        return _applyTomlMcp(tool, File(filePath), upserts: {for (final s in supported) s.serverId: s});
      case AiToolType.hermes:
        await LiveConfigWriter.instance.updateText(
          tool,
          filePath,
          (current) => McpToolFormats.applyHermes(current, upserts: {for (final s in supported) s.serverId: s}),
        );
        return true;
      case AiToolType.opencode:
        await LiveConfigWriter.instance.updateJson(tool, filePath, (config) {
          final mcp = config['mcp'] is Map ? Map<String, dynamic>.from(config['mcp'] as Map) : <String, dynamic>{};
          for (final s in supported) {
            mcp[s.serverId] = McpToolFormats.toOpenCode(s);
          }
          config['mcp'] = mcp;
        });
        return true;
      default:
        await LiveConfigWriter.instance.updateJson(tool, filePath, (config) {
          final servers = config['mcpServers'] is Map
              ? Map<String, dynamic>.from(config['mcpServers'] as Map)
              : <String, dynamic>{};
          for (final s in supported) {
            servers[s.serverId] = tool == AiToolType.mcode ? McpToolFormats.toMCode(s) : McpToolFormats.toPi(s);
          }
          config['mcpServers'] = servers;
        });
        return true;
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

      // 新增工具：转换为统一的 {mcpServers: {...}}
      switch (tool) {
        case AiToolType.grokBuild:
          return {'mcpServers': McpToolFormats.readToml(content)};
        case AiToolType.hermes:
          return {'mcpServers': McpToolFormats.readHermes(content)};
        case AiToolType.opencode:
          final doc = jsonDecode(content) as Map<String, dynamic>;
          final mcp = doc['mcp'] is Map ? doc['mcp'] as Map : const {};
          return {
            'mcpServers': {
              for (final e in mcp.entries)
                if (e.value is Map) '${e.key}': McpToolFormats.fromOpenCode(e.value as Map),
            },
          };
        default:
          break;
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
      
      final rawHeaders = config['headers'] ?? config['http_headers'];
      if (rawHeaders is Map) {
        headers = rawHeaders.map((k, v) => MapEntry('$k', '$v'));
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
  Future<bool> deleteFromTool(AiToolType tool, Set<String> serverIds, {String? scope, bool throwOnError = false}) async {
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

      // 备份由 LiveConfigWriter 在写入前自动完成（首写 + 滚动备份）

      // Codex / Grok Build 使用 TOML 格式
      if (tool == AiToolType.codex || tool == AiToolType.grokBuild) {
        return await _applyTomlMcp(tool, configFile, removals: serverIds);
      }

      if (tool == AiToolType.hermes) {
        await LiveConfigWriter.instance.updateText(
          tool,
          expandedPath,
          (current) => McpToolFormats.applyHermes(current, removals: serverIds),
        );
        return true;
      }

      if (tool == AiToolType.opencode) {
        var had = false;
        await LiveConfigWriter.instance.updateJson(tool, expandedPath, (config) {
          final mcp = config['mcp'];
          if (mcp is! Map) return;
          final next = Map<String, dynamic>.from(mcp);
          for (final id in serverIds) {
            had = next.remove(id) != null || had;
          }
          config['mcp'] = next;
        }, createIfMissing: false);
        return had;
      }

      // Gemini 和其他工具使用 JSON 格式
      var hadMcpServers = false;
      await LiveConfigWriter.instance.updateJson(tool, expandedPath, (config) {
        // 获取现有的 mcpServers
        if (config['mcpServers'] == null) {
          return;
        }
        hadMcpServers = true;

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
      }, createIfMissing: false);

      return hadMcpServers;
    } catch (e) {
      print('从工具 ${tool.displayName} 删除 MCP 服务失败: $e');
      if (throwOnError) rethrow;
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

      await LiveConfigWriter.instance.updateJson(AiToolType.claudecode, configFilePath, (config) {
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
      }, createIfMissing: false);

      return true;
    } catch (e) {
      print('从 ClaudeCode 删除 MCP 服务失败: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 按工具启用（对齐 CC Switch：enabled_<app> + 切换即写入 + sync_all_enabled + import_from_apps）
  // ---------------------------------------------------------------------------

  /// 可作为 MCP 同步目标的工具（OpenClaw 的 MCP 由其自身管理，不在此列）
  static List<AiToolType> get mcpTargetTools =>
      AiToolType.values.where((t) => t != AiToolType.openclaw).toList();

  /// 启用 / 停用某个服务在某个工具上，并立即写入（或移除）该工具的配置。
  /// 写入失败时数据库保持原状并抛出异常。
  Future<void> setServerEnabledForTool(McpServer server, AiToolType tool, bool enabled) async {
    if (enabled) {
      final reason = McpToolFormats.unsupportedReason(tool, server);
      if (reason != null) throw StateError(reason);
      final ok = await syncToTool(tool, {server.serverId}, throwOnError: true);
      if (!ok) throw StateError('写入 ${tool.displayName} 配置失败');
    } else {
      await deleteFromTool(tool, {server.serverId}, throwOnError: true);
    }
    await _databaseService.setServerApp(server.serverId, tool, enabled);
  }

  /// 把所有“已启用”关系重新写入各工具（如手动改坏了工具配置后一键恢复）
  /// 返回每个工具的写入结果
  Future<Map<AiToolType, bool>> syncAllEnabled() async {
    final apps = await _databaseService.getAllServerApps();
    final byTool = <AiToolType, Set<String>>{};
    apps.forEach((id, tools) {
      for (final t in tools) {
        (byTool[t] ??= <String>{}).add(id);
      }
    });
    final result = <AiToolType, bool>{};
    for (final e in byTool.entries) {
      result[e.key] = await syncToTool(e.key, e.value);
    }
    return result;
  }

  /// 服务内容修改后，重新写入它已启用的工具
  Future<void> resyncServer(McpServer server, {String? previousServerId}) async {
    if (previousServerId != null && previousServerId != server.serverId) {
      final tools = await _databaseService.getServerApps(previousServerId);
      for (final t in tools) {
        await deleteFromTool(t, {previousServerId});
      }
      await _databaseService.renameServerApps(previousServerId, server.serverId);
    }
    for (final t in await _databaseService.getServerApps(server.serverId)) {
      await syncToTool(t, {server.serverId});
    }
  }

  /// 删除服务前，从它已启用的工具中移除
  Future<void> removeServerFromEnabledTools(String serverId) async {
    for (final t in await _databaseService.getServerApps(serverId)) {
      await deleteFromTool(t, {serverId});
    }
  }

  /// 从多个工具导入 MCP 服务（对齐 CC Switch `import_from_all_apps`）：
  /// 库中没有的服务新增；已有的保持不变；并记录“该服务在该工具上已启用”。
  Future<McpImportAllResult> importFromTools(Iterable<AiToolType> tools) async {
    final result = McpImportAllResult();
    for (final tool in tools) {
      if (tool == AiToolType.openclaw) continue;
      final read = await readMcpServersFromTool(tool);
      for (final entry in read.servers.entries) {
        try {
          final existing = await _databaseService.getMcpServerByServerId(entry.key);
          if (existing == null) {
            await _databaseService.addMcpServer(entry.value);
            result.added.add(entry.key);
          }
          await _databaseService.setServerApp(entry.key, tool, true);
          (result.linked[tool] ??= <String>{}).add(entry.key);
        } catch (e) {
          result.failed.add('${tool.displayName}/${entry.key}');
        }
      }
    }
    return result;
  }
}

/// 从所有工具导入的结果
class McpImportAllResult {
  final List<String> added = [];
  final Map<AiToolType, Set<String>> linked = {};
  final List<String> failed = [];
}
