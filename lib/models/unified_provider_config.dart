import 'platform_type.dart';
import 'cloud_config.dart' as cloud;
import 'validation_config.dart';

/// 供应商能力类型
enum ProviderCapability {
  claudeCode, // 支持 ClaudeCode
  codex, // 支持 Codex
  platform, // 平台预设（密钥管理）
}

/// ClaudeCode 配置
class ClaudeCodeConfig {
  final String baseUrl;
  final cloud.ClaudeCodeModelConfig modelConfig;
  final List<String>? endpointCandidates;

  ClaudeCodeConfig({
    required this.baseUrl,
    required this.modelConfig,
    this.endpointCandidates,
  });

  factory ClaudeCodeConfig.fromJson(Map<String, dynamic> json) {
    return ClaudeCodeConfig(
      baseUrl: json['baseUrl'] as String,
      modelConfig: cloud.ClaudeCodeModelConfig.fromJson(
        json['modelConfig'] as Map<String, dynamic>,
      ),
      endpointCandidates: json['endpointCandidates'] != null
          ? List<String>.from(json['endpointCandidates'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'modelConfig': modelConfig.toJson(),
      if (endpointCandidates != null) 'endpointCandidates': endpointCandidates,
    };
  }
}

/// Codex 配置
class CodexConfig {
  final String baseUrl;
  final String model;
  final List<String>? endpointCandidates;

  CodexConfig({
    required this.baseUrl,
    required this.model,
    this.endpointCandidates,
  });

  factory CodexConfig.fromJson(Map<String, dynamic> json) {
    return CodexConfig(
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
      endpointCandidates: json['endpointCandidates'] != null
          ? List<String>.from(json['endpointCandidates'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'model': model,
      if (endpointCandidates != null) 'endpointCandidates': endpointCandidates,
    };
  }
}

/// 平台预设配置
class PlatformConfig {
  final String? managementUrl;
  final String? apiEndpoint;
  final String? defaultName;

  PlatformConfig({
    this.managementUrl,
    this.apiEndpoint,
    this.defaultName,
  });

  factory PlatformConfig.fromJson(Map<String, dynamic> json) {
    return PlatformConfig(
      managementUrl: json['managementUrl'] as String?,
      apiEndpoint: json['apiEndpoint'] as String?,
      defaultName: json['defaultName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (managementUrl != null) 'managementUrl': managementUrl,
      if (apiEndpoint != null) 'apiEndpoint': apiEndpoint,
      if (defaultName != null) 'defaultName': defaultName,
    };
  }
}

/// 统一供应商配置
class UnifiedProviderConfig {
  /// 供应商唯一标识（通常与 platformType 相同）
  final String id;
  
  /// 供应商名称
  final String name;
  
  /// 平台类型（PlatformType 的字符串值）
  final String platformType;
  
  /// 分组数组（如 ["claudeCode", "codex", "popular"]）
  final List<String> categories;
  
  /// 供应商分类（official, cnOfficial, thirdParty, aggregator）
  final cloud.ProviderCategory providerCategory;
  
  /// 网站地址
  final String websiteUrl;
  
  /// API Key 获取地址（可选）
  final String? apiKeyUrl;
  
  /// 是否为官方供应商
  final bool isOfficial;
  
  /// 是否为合作伙伴
  final bool isPartner;
  
  /// ClaudeCode 配置（如果支持 ClaudeCode）
  final ClaudeCodeConfig? claudeCode;
  
  /// Codex 配置（如果支持 Codex）
  final CodexConfig? codex;
  
  /// 平台预设配置（如果支持平台预设）
  final PlatformConfig? platform;
  
  /// 校验配置（可选）
  final ValidationConfig? validation;
  
  /// 图标文件名（相对于 assets/icons/platforms 目录）
  final String? icon;

  UnifiedProviderConfig({
    required this.id,
    required this.name,
    required this.platformType,
    required this.categories,
    required this.providerCategory,
    required this.websiteUrl,
    this.apiKeyUrl,
    this.isOfficial = false,
    this.isPartner = false,
    this.claudeCode,
    this.codex,
    this.platform,
    this.validation,
    this.icon,
  });

  factory UnifiedProviderConfig.fromJson(Map<String, dynamic> json) {
    return UnifiedProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      platformType: json['platformType'] as String,
      categories: List<String>.from(json['categories'] as List),
      providerCategory: cloud.ProviderCategory.values.firstWhere(
        (e) => e.toString().split('.').last == json['providerCategory'],
        orElse: () => cloud.ProviderCategory.thirdParty,
      ),
      websiteUrl: json['websiteUrl'] as String,
      apiKeyUrl: json['apiKeyUrl'] as String?,
      isOfficial: json['isOfficial'] as bool? ?? false,
      isPartner: json['isPartner'] as bool? ?? false,
      claudeCode: json['claudeCode'] != null
          ? ClaudeCodeConfig.fromJson(json['claudeCode'] as Map<String, dynamic>)
          : null,
      codex: json['codex'] != null
          ? CodexConfig.fromJson(json['codex'] as Map<String, dynamic>)
          : null,
      platform: json['platform'] != null
          ? PlatformConfig.fromJson(json['platform'] as Map<String, dynamic>)
          : null,
      validation: json['validation'] != null
          ? ValidationConfig.fromJson(json['validation'] as Map<String, dynamic>)
          : null,
      icon: json['icon'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'platformType': platformType,
      'categories': categories,
      'providerCategory': providerCategory.toString().split('.').last,
      'websiteUrl': websiteUrl,
      if (apiKeyUrl != null) 'apiKeyUrl': apiKeyUrl,
      'isOfficial': isOfficial,
      'isPartner': isPartner,
      if (claudeCode != null) 'claudeCode': claudeCode!.toJson(),
      if (codex != null) 'codex': codex!.toJson(),
      if (platform != null) 'platform': platform!.toJson(),
      if (validation != null) 'validation': validation!.toJson(),
      if (icon != null) 'icon': icon,
    };
  }

  /// 获取供应商支持的能力列表
  List<ProviderCapability> get capabilities {
    final List<ProviderCapability> caps = [];
    if (claudeCode != null) caps.add(ProviderCapability.claudeCode);
    if (codex != null) caps.add(ProviderCapability.codex);
    if (platform != null) caps.add(ProviderCapability.platform);
    return caps;
  }

  /// 检查是否支持指定能力
  bool supports(ProviderCapability capability) {
    switch (capability) {
      case ProviderCapability.claudeCode:
        return claudeCode != null;
      case ProviderCapability.codex:
        return codex != null;
      case ProviderCapability.platform:
        return platform != null;
    }
  }

  /// 检查是否属于指定分组
  bool belongsToCategory(String category) {
    return categories.contains(category);
  }
}

