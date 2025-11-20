import 'dart:convert';
import '../models/cloud_config.dart';
import '../models/unified_provider_config.dart';

/// 配置解析器
/// 提供配置解析、验证和转换功能
class ConfigParser {
  /// 从JSON字符串解析配置
  static CloudConfig? parseFromJsonString(String jsonString) {
    try {
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      return CloudConfig.fromJson(jsonData);
    } catch (e) {
      print('ConfigParser: JSON解析失败: $e');
      return null;
    }
  }

  /// 从JSON Map解析配置
  static CloudConfig? parseFromJsonMap(Map<String, dynamic> jsonMap) {
    try {
      return CloudConfig.fromJson(jsonMap);
    } catch (e) {
      print('ConfigParser: 配置解析失败: $e');
      return null;
    }
  }

  /// 验证配置完整性
  static bool validateConfig(CloudConfig config) {
    try {
      // 检查版本号格式
      if (!_isValidVersion(config.version)) {
        print('ConfigParser: 版本号格式无效: ${config.version}');
        return false;
      }

      // 检查schema版本
      if (config.schemaVersion < 1) {
        print('ConfigParser: Schema版本无效: ${config.schemaVersion}');
        return false;
      }

      // 检查配置数据
      final data = config.config;
      
      // 检查必填字段
      if (data.providers.isEmpty) {
        print('ConfigParser: 配置数据为空');
        return false;
      }

      // 验证统一供应商配置
      for (final provider in data.providers) {
        if (provider.name.isEmpty || provider.platformType.isEmpty) {
          print('ConfigParser: 供应商配置无效: ${provider.name}');
          return false;
        }
        if (provider.claudeCode != null && provider.claudeCode!.baseUrl.isEmpty) {
          print('ConfigParser: ClaudeCode配置无效: ${provider.name}');
          return false;
        }
        if (provider.codex != null && (provider.codex!.baseUrl.isEmpty || provider.codex!.model.isEmpty)) {
          print('ConfigParser: Codex配置无效: ${provider.name}');
          return false;
        }
      }

      // 验证MCP服务器模板
      for (final template in data.mcpServerTemplates) {
        if (template.serverId.isEmpty || template.name.isEmpty) {
          print('ConfigParser: MCP服务器模板配置无效: ${template.serverId}');
          return false;
        }
      }

      // 验证Codex认证配置
      if (data.codexAuthConfig.rules.isEmpty) {
        print('ConfigParser: Codex认证配置规则为空');
        return false;
      }

      return true;
    } catch (e) {
      print('ConfigParser: 配置验证异常: $e');
      return false;
    }
  }

  /// 验证版本号格式（语义化版本号）
  static bool _isValidVersion(String version) {
    final regex = RegExp(r'^\d+\.\d+\.\d+$');
    return regex.hasMatch(version);
  }

  /// 将配置转换为JSON字符串
  static String? toJsonString(CloudConfig config) {
    try {
      return const JsonEncoder.withIndent('  ').convert(config.toJson());
    } catch (e) {
      print('ConfigParser: JSON序列化失败: $e');
      return null;
    }
  }

  /// 合并配置（用于多源配置合并）
  /// 优先级：config2 > config1
  static CloudConfig? mergeConfigs(CloudConfig config1, CloudConfig config2) {
    try {
      // 选择较新的版本
      final version1 = config1.version;
      final version2 = config2.version;
      final useConfig2 = _compareVersions(version1, version2) < 0;
      
      final baseConfig = useConfig2 ? config2 : config1;
      final mergeConfig = useConfig2 ? config1 : config2;
      
      // 合并统一供应商配置（去重，保留较新配置中的项）
      final mergedProviders = <UnifiedProviderConfig>[];
      final providerMap = <String, UnifiedProviderConfig>{};
      
      // 先添加基础配置
      for (final provider in baseConfig.config.providers) {
        providerMap[provider.id] = provider;
      }
      
      // 再添加合并配置（覆盖同名项）
      for (final provider in mergeConfig.config.providers) {
        providerMap[provider.id] = provider;
      }
      
      mergedProviders.addAll(providerMap.values);
      
      // 合并MCP服务器模板
      final mergedMcpTemplates = <McpServerTemplateConfig>[];
      final mcpTemplateMap = <String, McpServerTemplateConfig>{};
      
      for (final template in baseConfig.config.mcpServerTemplates) {
        mcpTemplateMap[template.serverId] = template;
      }
      
      for (final template in mergeConfig.config.mcpServerTemplates) {
        mcpTemplateMap[template.serverId] = template;
      }
      
      mergedMcpTemplates.addAll(mcpTemplateMap.values);
      
      // 创建合并后的配置
      final mergedConfigData = CloudConfigData(
        providers: mergedProviders,
        mcpServerTemplates: mergedMcpTemplates,
        codexAuthConfig: useConfig2 ? config2.config.codexAuthConfig : config1.config.codexAuthConfig,
        platformIconMapping: useConfig2 
            ? config2.config.platformIconMapping 
            : config1.config.platformIconMapping,
        providerCategories: useConfig2 
            ? config2.config.providerCategories 
            : config1.config.providerCategories,
      );
      
      return CloudConfig(
        version: useConfig2 ? version2 : version1,
        schemaVersion: baseConfig.schemaVersion,
        lastUpdated: DateTime.now().toIso8601String(),
        config: mergedConfigData,
      );
    } catch (e) {
      print('ConfigParser: 配置合并失败: $e');
      return null;
    }
  }

  /// 比较版本号
  static int _compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts = version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    while (v1Parts.length < v2Parts.length) {
      v1Parts.add(0);
    }
    while (v2Parts.length < v1Parts.length) {
      v2Parts.add(0);
    }
    
    for (int i = 0; i < v1Parts.length; i++) {
      if (v1Parts[i] < v2Parts[i]) return -1;
      if (v1Parts[i] > v2Parts[i]) return 1;
    }
    return 0;
  }
}

