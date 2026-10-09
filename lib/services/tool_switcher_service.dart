import 'dart:async';
import '../models/provider.dart';
import '../services/config_file_service.dart';

/// 工具配置切换服务
/// 负责将供应商配置应用到各个 AI 工具的配置文件
class ToolSwitcherService {
  static ToolSwitcherService? _instance;

  final ConfigFileService _configService = ConfigFileService.instance;

  ToolSwitcherService._();

  static ToolSwitcherService get instance {
    _instance ??= ToolSwitcherService._();
    return _instance!;
  }

  /// 切换 Claude Code 配置
  Future<void> switchClaudeCode(Provider provider) async {
    if (!provider.supportedTools.contains('claude_code')) {
      throw Exception('该供应商不支持 Claude Code');
    }

    if (provider.apiKey == null || provider.apiKey!.isEmpty) {
      throw Exception('供应商 API Key 未设置');
    }

    final configPath = _configService.getConfigPath('claude_code');

    try {
      // 准备配置更新
      final updates = <String, dynamic>{
        'apiKey': provider.apiKey,
      };

      // 如果有自定义 API Endpoint
      if (provider.apiEndpoint != null) {
        updates['apiEndpoint'] = provider.apiEndpoint;
      }

      // 如果有模型配置
      if (provider.models.isNotEmpty) {
        // 设置默认模型（第一个模型）
        final defaultModel = provider.models.first;
        updates['model'] = defaultModel.id;
        
        // 如果有多个模型，设置模型列表
        if (provider.models.length > 1) {
          updates['availableModels'] = provider.models
              .map((m) => {
                    'id': m.id,
                    'name': m.displayName,
                    'contextWindow': m.contextWindow,
                  })
              .toList();
        }
      }

      // 写入配置（包含备份）
      await _configService.updateJsonFields(configPath, updates);
      
      print('Claude Code 配置已切换到供应商: ${provider.name}');
    } catch (e) {
      throw Exception('切换 Claude Code 配置失败: $e');
    }
  }

  /// 切换 Codex 配置（暂时简化处理，实际需要 TOML 解析）
  Future<void> switchCodex(Provider provider) async {
    if (!provider.supportedTools.contains('codex')) {
      throw Exception('该供应商不支持 Codex');
    }

    if (provider.apiKey == null || provider.apiKey!.isEmpty) {
      throw Exception('供应商 API Key 未设置');
    }

    // TODO: 实现 Codex TOML 配置文件的读写
    // Codex 使用 TOML 格式，需要 TOML 解析库
    print('Codex 配置切换功能待实现（需要 TOML 支持）');
    
    throw Exception('Codex 配置切换功能待实现');
  }

  /// 切换 Gemini CLI 配置
  Future<void> switchGeminiCli(Provider provider) async {
    if (!provider.supportedTools.contains('gemini_cli')) {
      throw Exception('该供应商不支持 Gemini CLI');
    }

    if (provider.apiKey == null || provider.apiKey!.isEmpty) {
      throw Exception('供应商 API Key 未设置');
    }

    final configPath = _configService.getConfigPath('gemini_cli');

    try {
      final updates = <String, dynamic>{
        'apiKey': provider.apiKey,
      };

      if (provider.apiEndpoint != null) {
        updates['apiEndpoint'] = provider.apiEndpoint;
      }

      if (provider.models.isNotEmpty) {
        updates['model'] = provider.models.first.id;
      }

      await _configService.updateJsonFields(configPath, updates);
      
      print('Gemini CLI 配置已切换到供应商: ${provider.name}');
    } catch (e) {
      throw Exception('切换 Gemini CLI 配置失败: $e');
    }
  }

  /// 切换 OpenClaw 配置
  Future<void> switchOpenClaw(Provider provider) async {
    if (!provider.supportedTools.contains('openclaw')) {
      throw Exception('该供应商不支持 OpenClaw');
    }

    if (provider.apiKey == null || provider.apiKey!.isEmpty) {
      throw Exception('供应商 API Key 未设置');
    }

    final configPath = _configService.getConfigPath('openclaw');

    try {
      final updates = <String, dynamic>{
        'apiKey': provider.apiKey,
      };

      if (provider.apiEndpoint != null) {
        updates['baseUrl'] = provider.apiEndpoint;
      }

      if (provider.models.isNotEmpty) {
        updates['model'] = provider.models.first.id;
      }

      await _configService.updateJsonFields(configPath, updates);
      
      print('OpenClaw 配置已切换到供应商: ${provider.name}');
    } catch (e) {
      throw Exception('切换 OpenClaw 配置失败: $e');
    }
  }

  /// 切换 Grok Build 配置
  Future<void> switchGrokBuild(Provider provider) async {
    if (!provider.supportedTools.contains('grok_build')) {
      throw Exception('该供应商不支持 Grok Build');
    }

    if (provider.apiKey == null || provider.apiKey!.isEmpty) {
      throw Exception('供应商 API Key 未设置');
    }

    final configPath = _configService.getConfigPath('grok_build');

    try {
      final updates = <String, dynamic>{
        'apiKey': provider.apiKey,
      };

      if (provider.apiEndpoint != null) {
        updates['apiEndpoint'] = provider.apiEndpoint;
      }

      if (provider.models.isNotEmpty) {
        updates['model'] = provider.models.first.id;
      }

      await _configService.updateJsonFields(configPath, updates);
      
      print('Grok Build 配置已切换到供应商: ${provider.name}');
    } catch (e) {
      throw Exception('切换 Grok Build 配置失败: $e');
    }
  }

  /// 批量切换多个工具的配置
  Future<Map<String, bool>> switchMultipleTools(
    Provider provider,
    List<String> tools,
  ) async {
    final results = <String, bool>{};

    for (final tool in tools) {
      try {
        await switchTool(provider, tool);
        results[tool] = true;
      } catch (e) {
        print('切换 $tool 失败: $e');
        results[tool] = false;
      }
    }

    return results;
  }

  /// 切换指定工具的配置
  Future<void> switchTool(Provider provider, String tool) async {
    switch (tool.toLowerCase()) {
      case 'claude_code':
        await switchClaudeCode(provider);
        break;
      
      case 'codex':
        await switchCodex(provider);
        break;
      
      case 'gemini_cli':
        await switchGeminiCli(provider);
        break;
      
      case 'openclaw':
        await switchOpenClaw(provider);
        break;
      
      case 'grok_build':
        await switchGrokBuild(provider);
        break;
      
      default:
        throw Exception('不支持的工具: $tool');
    }
  }

  /// 获取当前工具的配置信息
  Future<Map<String, dynamic>?> getCurrentConfig(String tool) async {
    try {
      final configPath = _configService.getConfigPath(tool);
      if (!await _configService.exists(configPath)) {
        return null;
      }
      return await _configService.readJsonConfig(configPath);
    } catch (e) {
      print('获取 $tool 配置失败: $e');
      return null;
    }
  }

  /// 验证工具配置是否正确
  Future<bool> validateConfig(String tool) async {
    try {
      final config = await getCurrentConfig(tool);
      if (config == null) return false;

      // 检查必要字段
      return config.containsKey('apiKey') && 
             config['apiKey'] != null && 
             config['apiKey'].toString().isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// 列出配置文件的备份
  Future<List<String>> listBackups(String tool) async {
    try {
      final configPath = _configService.getConfigPath(tool);
      return await _configService.listBackups(configPath);
    } catch (e) {
      print('列出备份失败: $e');
      return [];
    }
  }

  /// 恢复配置备份
  Future<void> restoreBackup(String tool, String backupPath) async {
    try {
      final configPath = _configService.getConfigPath(tool);
      await _configService.restoreBackup(backupPath, configPath);
      print('$tool 配置已从备份恢复');
    } catch (e) {
      throw Exception('恢复备份失败: $e');
    }
  }

  /// 清理旧备份
  Future<void> cleanupBackups(String tool, {int keep = 5}) async {
    try {
      final configPath = _configService.getConfigPath(tool);
      await _configService.cleanupOldBackups(configPath, keep: keep);
    } catch (e) {
      print('清理备份失败: $e');
    }
  }
}
