import 'unified_provider_config.dart';

/// 供应商分类枚举（与provider_config.dart保持一致）
enum ProviderCategory {
  official, // 官方
  cnOfficial, // 国内官方
  thirdParty, // 第三方
  aggregator, // 聚合平台
}

/// ClaudeCode 模型配置
class ClaudeCodeModelConfig {
  final String mainModel;
  final String? haikuModel;
  final String? sonnetModel;
  final String? opusModel;

  ClaudeCodeModelConfig({
    required this.mainModel,
    this.haikuModel,
    this.sonnetModel,
    this.opusModel,
  });

  factory ClaudeCodeModelConfig.fromJson(Map<String, dynamic> json) {
    return ClaudeCodeModelConfig(
      mainModel: json['mainModel'] as String? ?? '',
      haikuModel: json['haikuModel'] as String?,
      sonnetModel: json['sonnetModel'] as String?,
      opusModel: json['opusModel'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mainModel': mainModel,
      if (haikuModel != null) 'haikuModel': haikuModel,
      if (sonnetModel != null) 'sonnetModel': sonnetModel,
      if (opusModel != null) 'opusModel': opusModel,
    };
  }
}

/// ClaudeCode 供应商配置
class ClaudeCodeProviderConfig {
  final String name;
  final String websiteUrl;
  final String? apiKeyUrl;
  final String baseUrl;
  final ClaudeCodeModelConfig modelConfig;
  final ProviderCategory category;
  final bool isOfficial;
  final bool isPartner;
  final List<String>? endpointCandidates;
  final String? platformType; // PlatformType的字符串值

  ClaudeCodeProviderConfig({
    required this.name,
    required this.websiteUrl,
    this.apiKeyUrl,
    required this.baseUrl,
    required this.modelConfig,
    required this.category,
    this.isOfficial = false,
    this.isPartner = false,
    this.endpointCandidates,
    this.platformType,
  });

  factory ClaudeCodeProviderConfig.fromJson(Map<String, dynamic> json) {
    return ClaudeCodeProviderConfig(
      name: json['name'] as String,
      websiteUrl: json['websiteUrl'] as String,
      apiKeyUrl: json['apiKeyUrl'] as String?,
      baseUrl: json['baseUrl'] as String,
      modelConfig: ClaudeCodeModelConfig.fromJson(
        json['modelConfig'] as Map<String, dynamic>,
      ),
      category: ProviderCategory.values.firstWhere(
        (e) => e.toString().split('.').last == json['category'],
        orElse: () => ProviderCategory.thirdParty,
      ),
      isOfficial: json['isOfficial'] as bool? ?? false,
      isPartner: json['isPartner'] as bool? ?? false,
      endpointCandidates: json['endpointCandidates'] != null
          ? List<String>.from(json['endpointCandidates'] as List)
          : null,
      platformType: json['platformType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'websiteUrl': websiteUrl,
      if (apiKeyUrl != null) 'apiKeyUrl': apiKeyUrl,
      'baseUrl': baseUrl,
      'modelConfig': modelConfig.toJson(),
      'category': category.toString().split('.').last,
      'isOfficial': isOfficial,
      'isPartner': isPartner,
      if (endpointCandidates != null) 'endpointCandidates': endpointCandidates,
      if (platformType != null) 'platformType': platformType,
    };
  }
}

/// Codex 供应商配置
class CodexProviderConfig {
  final String name;
  final String websiteUrl;
  final String? apiKeyUrl;
  final String baseUrl;
  final String model;
  final ProviderCategory category;
  final bool isOfficial;
  final bool isPartner;
  final List<String>? endpointCandidates;
  final String? platformType; // PlatformType的字符串值

  CodexProviderConfig({
    required this.name,
    required this.websiteUrl,
    this.apiKeyUrl,
    required this.baseUrl,
    required this.model,
    required this.category,
    this.isOfficial = false,
    this.isPartner = false,
    this.endpointCandidates,
    this.platformType,
  });

  factory CodexProviderConfig.fromJson(Map<String, dynamic> json) {
    return CodexProviderConfig(
      name: json['name'] as String,
      websiteUrl: json['websiteUrl'] as String,
      apiKeyUrl: json['apiKeyUrl'] as String?,
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
      category: ProviderCategory.values.firstWhere(
        (e) => e.toString().split('.').last == json['category'],
        orElse: () => ProviderCategory.thirdParty,
      ),
      isOfficial: json['isOfficial'] as bool? ?? false,
      isPartner: json['isPartner'] as bool? ?? false,
      endpointCandidates: json['endpointCandidates'] != null
          ? List<String>.from(json['endpointCandidates'] as List)
          : null,
      platformType: json['platformType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'websiteUrl': websiteUrl,
      if (apiKeyUrl != null) 'apiKeyUrl': apiKeyUrl,
      'baseUrl': baseUrl,
      'model': model,
      'category': category.toString().split('.').last,
      'isOfficial': isOfficial,
      'isPartner': isPartner,
      if (endpointCandidates != null) 'endpointCandidates': endpointCandidates,
      if (platformType != null) 'platformType': platformType,
    };
  }
}

/// 平台预设配置
class PlatformPresetConfig {
  final String platformType; // PlatformType的字符串值
  final String? managementUrl;
  final String? apiEndpoint;
  final String? defaultName;

  PlatformPresetConfig({
    required this.platformType,
    this.managementUrl,
    this.apiEndpoint,
    this.defaultName,
  });

  factory PlatformPresetConfig.fromJson(Map<String, dynamic> json) {
    return PlatformPresetConfig(
      platformType: json['platformType'] as String,
      managementUrl: json['managementUrl'] as String?,
      apiEndpoint: json['apiEndpoint'] as String?,
      defaultName: json['defaultName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'platformType': platformType,
      if (managementUrl != null) 'managementUrl': managementUrl,
      if (apiEndpoint != null) 'apiEndpoint': apiEndpoint,
      if (defaultName != null) 'defaultName': defaultName,
    };
  }
}

/// MCP 服务器模板配置
class McpServerTemplateConfig {
  final String serverId;
  final String name;
  final String? description;
  final String? icon;
  final String category; // McpServerCategory的字符串值
  final String serverType; // McpServerType的字符串值
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? cwd;
  final String? url;
  final Map<String, String>? headers;
  final List<String>? tags;
  final String? homepage;
  final String? docs;

  McpServerTemplateConfig({
    required this.serverId,
    required this.name,
    this.description,
    this.icon,
    required this.category,
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
  });

  factory McpServerTemplateConfig.fromJson(Map<String, dynamic> json) {
    return McpServerTemplateConfig(
      serverId: json['serverId'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      category: json['category'] as String,
      serverType: json['serverType'] as String,
      command: json['command'] as String?,
      args: json['args'] != null ? List<String>.from(json['args'] as List) : null,
      env: json['env'] != null
          ? Map<String, String>.from(json['env'] as Map)
          : null,
      cwd: json['cwd'] as String?,
      url: json['url'] as String?,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'] as Map)
          : null,
      tags: json['tags'] != null ? List<String>.from(json['tags'] as List) : null,
      homepage: json['homepage'] as String?,
      docs: json['docs'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'name': name,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      'category': category,
      'serverType': serverType,
      if (command != null) 'command': command,
      if (args != null) 'args': args,
      if (env != null) 'env': env,
      if (cwd != null) 'cwd': cwd,
      if (url != null) 'url': url,
      if (headers != null) 'headers': headers,
      if (tags != null) 'tags': tags,
      if (homepage != null) 'homepage': homepage,
      if (docs != null) 'docs': docs,
    };
  }
}

/// Codex 认证配置规则
class CodexAuthRule {
  final String? platformType; // PlatformType的字符串值，null表示匹配所有
  final List<String>? baseUrlPatterns; // baseUrl匹配模式
  final bool supportsAuthJson;
  final String? envKeyName;
  final bool requiresOpenaiAuth;
  final String? authJsonKey;
  final String wireApi;

  CodexAuthRule({
    this.platformType,
    this.baseUrlPatterns,
    required this.supportsAuthJson,
    this.envKeyName,
    required this.requiresOpenaiAuth,
    this.authJsonKey,
    this.wireApi = 'chat',
  });

  factory CodexAuthRule.fromJson(Map<String, dynamic> json) {
    return CodexAuthRule(
      platformType: json['platformType'] as String?,
      baseUrlPatterns: json['baseUrlPatterns'] != null
          ? List<String>.from(json['baseUrlPatterns'] as List)
          : null,
      supportsAuthJson: json['supportsAuthJson'] as bool? ?? false,
      envKeyName: json['envKeyName'] as String?,
      requiresOpenaiAuth: json['requiresOpenaiAuth'] as bool? ?? false,
      authJsonKey: json['authJsonKey'] as String?,
      wireApi: json['wireApi'] as String? ?? 'chat',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (platformType != null) 'platformType': platformType,
      if (baseUrlPatterns != null) 'baseUrlPatterns': baseUrlPatterns,
      'supportsAuthJson': supportsAuthJson,
      if (envKeyName != null) 'envKeyName': envKeyName,
      'requiresOpenaiAuth': requiresOpenaiAuth,
      if (authJsonKey != null) 'authJsonKey': authJsonKey,
      'wireApi': wireApi,
    };
  }
}

/// Codex 认证配置
class CodexAuthConfig {
  final List<CodexAuthRule> rules;
  final CodexAuthRule defaultRule; // 默认规则

  CodexAuthConfig({
    required this.rules,
    required this.defaultRule,
  });

  factory CodexAuthConfig.fromJson(Map<String, dynamic> json) {
    return CodexAuthConfig(
      rules: (json['rules'] as List? ?? [])
          .map((e) => CodexAuthRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultRule: CodexAuthRule.fromJson(
        json['defaultRule'] as Map<String, dynamic>,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rules': rules.map((e) => e.toJson()).toList(),
      'defaultRule': defaultRule.toJson(),
    };
  }
}

/// 平台图标映射配置
class PlatformIconMapping {
  final Map<String, String> mapping; // platformType -> iconPath

  PlatformIconMapping({required this.mapping});

  factory PlatformIconMapping.fromJson(Map<String, dynamic> json) {
    return PlatformIconMapping(
      mapping: Map<String, String>.from(json as Map),
    );
  }

  Map<String, dynamic> toJson() {
    return mapping;
  }
}

/// 供应商分类显示信息
class ProviderCategoryInfo {
  final String key; // category key
  final Map<String, String> displayNames; // locale -> displayName
  final Map<String, String>? descriptions; // locale -> description

  ProviderCategoryInfo({
    required this.key,
    required this.displayNames,
    this.descriptions,
  });

  factory ProviderCategoryInfo.fromJson(Map<String, dynamic> json) {
    return ProviderCategoryInfo(
      key: json['key'] as String,
      displayNames: Map<String, String>.from(json['displayNames'] as Map),
      descriptions: json['descriptions'] != null
          ? Map<String, String>.from(json['descriptions'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'displayNames': displayNames,
      if (descriptions != null) 'descriptions': descriptions,
    };
  }
}

/// 云端配置根对象
class CloudConfig {
  final String version;
  final int schemaVersion;
  final String lastUpdated;
  final CloudConfigData config;

  CloudConfig({
    required this.version,
    required this.schemaVersion,
    required this.lastUpdated,
    required this.config,
  });

  factory CloudConfig.fromJson(Map<String, dynamic> json) {
    return CloudConfig(
      version: json['version'] as String,
      schemaVersion: json['schemaVersion'] as int,
      lastUpdated: json['lastUpdated'] as String,
      config: CloudConfigData.fromJson(json['config'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'schemaVersion': schemaVersion,
      'lastUpdated': lastUpdated,
      'config': config.toJson(),
    };
  }
}

/// 云端配置数据
class CloudConfigData {
  /// 统一的供应商配置列表
  final List<UnifiedProviderConfig> providers;
  
  final List<McpServerTemplateConfig> mcpServerTemplates;
  final CodexAuthConfig codexAuthConfig;
  final PlatformIconMapping? platformIconMapping;
  final List<ProviderCategoryInfo>? providerCategories;

  CloudConfigData({
    required this.providers,
    required this.mcpServerTemplates,
    required this.codexAuthConfig,
    this.platformIconMapping,
    this.providerCategories,
  });

  factory CloudConfigData.fromJson(Map<String, dynamic> json) {
    return CloudConfigData(
      providers: (json['providers'] as List)
          .map((e) => UnifiedProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      mcpServerTemplates: (json['mcpServerTemplates'] as List? ?? [])
          .map((e) => McpServerTemplateConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      codexAuthConfig: CodexAuthConfig.fromJson(
        json['codexAuthConfig'] as Map<String, dynamic>,
      ),
      platformIconMapping: json['platformIconMapping'] != null
          ? PlatformIconMapping.fromJson(
              json['platformIconMapping'] as Map<String, dynamic>,
            )
          : null,
      providerCategories: json['providerCategories'] != null
          ? (json['providerCategories'] as List)
              .map((e) => ProviderCategoryInfo.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providers': providers.map((e) => e.toJson()).toList(),
      'mcpServerTemplates':
          mcpServerTemplates.map((e) => e.toJson()).toList(),
      'codexAuthConfig': codexAuthConfig.toJson(),
      if (platformIconMapping != null)
        'platformIconMapping': platformIconMapping!.toJson(),
      if (providerCategories != null)
        'providerCategories':
            providerCategories!.map((e) => e.toJson()).toList(),
    };
  }
}

