import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mcp_server.dart';
import 'settings_service.dart';
import 'ai_tool_config_service.dart';

/// 工具启用状态管理服务
class ToolEnableService {
  static const String _keyPrefix = 'tool_enabled_';
  static const String _keyInitialized = 'tools_initialized';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // 首次安装时初始化默认状态
    if (!(_prefs?.getBool(_keyInitialized) ?? false)) {
      await _initializeDefaults();
    }
  }

  /// 初始化默认状态：所有工具默认关闭，等待用户首次授权后选择
  Future<void> _initializeDefaults() async {
    // 不再默认开启任何工具，由用户在首次授权时选择
    await _prefs?.setBool(_keyInitialized, true);
  }

  /// 检查工具是否启用
  Future<bool> isToolEnabled(AiToolType tool) async {
    await init();
    return _prefs?.getBool('$_keyPrefix${tool.value}') ?? false;
  }

  /// 设置工具启用状态
  Future<void> setToolEnabled(AiToolType tool, bool enabled) async {
    await init();
    await _prefs?.setBool('$_keyPrefix${tool.value}', enabled);
  }

  /// 获取所有已启用的工具
  Future<List<AiToolType>> getEnabledTools() async {
    await init();
    final enabledTools = <AiToolType>[];
    for (final tool in AiToolType.values) {
      if (await isToolEnabled(tool)) {
        enabledTools.add(tool);
      }
    }
    return enabledTools;
  }

  /// 验证工具配置文件是否存在且可读
  /// 如果目录存在但配置文件不存在，会自动创建默认配置文件
  Future<bool> validateToolConfig(AiToolType tool) async {
    try {
      final toolConfigService = AiToolConfigService();
      final configDir = await toolConfigService.getConfigDir(tool);
      final homeDir = await SettingsService.getUserHomeDir();
      final configFilePath = AiToolConfigService.getConfigFilePath(
        tool,
        customConfigDir: configDir,
        homeDir: homeDir,
      );
      
      final configDirObj = Directory(configDir);
      final file = File(configFilePath);
      
      // 检查目录是否存在
      final dirExists = await configDirObj.exists();
      if (!dirExists) {
        print('ToolEnableService: 工具 ${tool.displayName} 的配置目录不存在: $configDir');
        print('ToolEnableService: 可能该工具未安装');
        return false;
      }
      
      // 目录存在，检查配置文件
      final fileExists = await file.exists();
      if (!fileExists) {
        print('ToolEnableService: 工具 ${tool.displayName} 的目录存在但配置文件不存在');
        print('ToolEnableService: 尝试创建默认配置文件: $configFilePath');
        
        // 自动创建默认配置文件
        final success = await _createDefaultConfig(tool, file);
        if (!success) {
          print('ToolEnableService: 创建默认配置文件失败');
          return false;
        }
        
        print('ToolEnableService: 默认配置文件创建成功');
        return true;
      }
      
      // 配置文件存在，尝试读取内容
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        print('ToolEnableService: 配置文件为空，尝试写入默认配置');
        
        // 配置文件为空，写入默认配置
        final success = await _createDefaultConfig(tool, file);
        if (!success) {
          print('ToolEnableService: 写入默认配置失败');
          return false;
        }
        
        print('ToolEnableService: 默认配置写入成功');
        return true;
      }
      
      return true;
    } catch (e) {
      print('ToolEnableService: 验证工具配置失败: $e');
      return false;
    }
  }
  
  /// 为指定工具创建默认配置文件
  Future<bool> _createDefaultConfig(AiToolType tool, File configFile) async {
    try {
      final defaultConfig = _generateDefaultConfig(tool);
      await configFile.writeAsString(defaultConfig);
      
      // Codex 需要同时创建 auth.json 文件
      if (tool == AiToolType.codex) {
        await _createCodexAuthFile(configFile.parent.path);
      }
      
      return true;
    } catch (e) {
      print('ToolEnableService: 创建默认配置文件失败: $e');
      return false;
    }
  }
  
  /// 为 Codex 创建 auth.json 文件
  Future<void> _createCodexAuthFile(String configDir) async {
    try {
      final authFilePath = '$configDir/auth.json';
      final authFile = File(authFilePath);
      
      // 如果 auth.json 已存在，不覆盖
      if (await authFile.exists()) {
        print('ToolEnableService: auth.json 已存在，跳过创建');
        return;
      }
      
      // 创建默认的 auth.json
      final defaultAuth = <String, dynamic>{
        'OPENAI_API_KEY': '',
      };
      await authFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultAuth),
      );
      print('ToolEnableService: 创建默认 auth.json 成功: $authFilePath');
    } catch (e) {
      print('ToolEnableService: 创建 auth.json 失败: $e');
      // 不抛出异常，因为这不是关键错误
    }
  }
  
  /// 生成工具的默认配置内容
  String _generateDefaultConfig(AiToolType tool) {
    switch (tool) {
      case AiToolType.cursor:
        // Cursor 使用 mcp.json 格式
        return const JsonEncoder.withIndent('  ').convert({
          'mcpServers': <String, dynamic>{},
        });
        
      case AiToolType.claudecode:
        // ClaudeCode 使用 config.json 格式（~/.claude/config.json）
        return const JsonEncoder.withIndent('  ').convert({
          'mcpServers': <String, dynamic>{},
        });
        
      case AiToolType.codex:
        // Codex 使用 config.toml 格式
        // 创建一个空的 TOML 文件，用户后续可以通过 Codex 配置页面添加内容
        return '';
        
      case AiToolType.windsurf:
        // Windsurf 使用 mcp_config.json 格式
        return const JsonEncoder.withIndent('  ').convert({
          'mcpServers': <String, dynamic>{},
        });
        
      case AiToolType.gemini:
        // Gemini 使用 settings.json 格式，需要包含 apiKey 字段
        return const JsonEncoder.withIndent('  ').convert({
          'apiKey': '',
          'mcpServers': <String, dynamic>{},
        });
    }
  }
}

