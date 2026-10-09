import 'platform_type.dart';
import 'cloud_config.dart' as cloud;
import 'validation_config.dart';

/// 供应商能力类型
enum ProviderCapability {
  claudeCode, // 支持 ClaudeCode
  codex, // 支持 Codex
  openclaw, // 支持 OpenClaw
  gemini, // 支持 Gemini CLI（第三方端点）
  claudeDesktop, // 支持 Claude Desktop 直连（3P）
  platform, // 平台预设（密钥管理）
}

/// ClaudeCode 配置
class ClaudeCodeConfig {
  final String baseUrl;
  final cloud.ClaudeCodeModelConfig modelConfig;
  final List<String>? endpointCandidates;

  /// 密钥写入的 env 变量名，缺省为 `ANTHROPIC_AUTH_TOKEN`
  /// （部分供应商要求 `ANTHROPIC_API_KEY`，AWS Bedrock 为 `AWS_BEARER_TOKEN_BEDROCK`）
  final String? apiKeyField;

  /// 该供应商额外需要的 env（如 `CLAUDE_CODE_MAX_CONTEXT_TOKENS`），切入时写入、切走时清除
  final Map<String, String>? env;

  ClaudeCodeConfig({
    required this.baseUrl,
    required this.modelConfig,
    this.endpointCandidates,
    this.apiKeyField,
    this.env,
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
      apiKeyField: json['apiKeyField'] as String?,
      env: json['env'] is Map
          ? (json['env'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'modelConfig': modelConfig.toJson(),
      if (endpointCandidates != null) 'endpointCandidates': endpointCandidates,
      if (apiKeyField != null) 'apiKeyField': apiKeyField,
      if (env != null) 'env': env,
    };
  }
}

/// Codex 配置
class CodexConfig {
  final String baseUrl;
  final String model;
  final List<String>? endpointCandidates;

  /// wire_api（Codex 新版本只支持 `responses`）
  final String? wireApi;

  /// model_reasoning_effort
  final String? reasoningEffort;

  CodexConfig({
    required this.baseUrl,
    required this.model,
    this.endpointCandidates,
    this.wireApi,
    this.reasoningEffort,
  });

  factory CodexConfig.fromJson(Map<String, dynamic> json) {
    return CodexConfig(
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String,
      endpointCandidates: json['endpointCandidates'] != null
          ? List<String>.from(json['endpointCandidates'] as List)
          : null,
      wireApi: json['wireApi'] as String?,
      reasoningEffort: json['reasoningEffort'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'model': model,
      if (endpointCandidates != null) 'endpointCandidates': endpointCandidates,
      if (wireApi != null) 'wireApi': wireApi,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    };
  }
}

/// Gemini CLI 第三方端点配置（写入 `GOOGLE_GEMINI_BASE_URL` / `GEMINI_MODEL`）
class GeminiPresetConfig {
  final String baseUrl;
  final String model;

  GeminiPresetConfig({required this.baseUrl, required this.model});

  factory GeminiPresetConfig.fromJson(Map<String, dynamic> json) => GeminiPresetConfig(
        baseUrl: json['baseUrl'] as String,
        model: json['model'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'model': model};
}

/// Claude Desktop 直连（3P）配置：仅在供应商的 Anthropic 兼容端点接受 `claude-*` 模型名时提供
class ClaudeDesktopPresetConfig {
  final String baseUrl;
  final cloud.ClaudeCodeModelConfig modelConfig;

  ClaudeDesktopPresetConfig({required this.baseUrl, required this.modelConfig});

  factory ClaudeDesktopPresetConfig.fromJson(Map<String, dynamic> json) => ClaudeDesktopPresetConfig(
        baseUrl: json['baseUrl'] as String,
        modelConfig: cloud.ClaudeCodeModelConfig.fromJson(
          (json['modelConfig'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
      );

  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'modelConfig': modelConfig.toJson()};
}

/// OpenClaw 预设中的模型定义
class OpenClawPresetModel {
  final String id;
  final String name;
  final bool? reasoning;
  final List<String>? input;
  final int? contextWindow;
  final int? maxTokens;

  const OpenClawPresetModel({
    required this.id,
    required this.name,
    this.reasoning,
    this.input,
    this.contextWindow,
    this.maxTokens,
  });

  factory OpenClawPresetModel.fromJson(Map<String, dynamic> json) => OpenClawPresetModel(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        reasoning: json['reasoning'] as bool?,
        input: json['input'] is List ? List<String>.from(json['input'] as List) : null,
        contextWindow: (json['contextWindow'] as num?)?.toInt(),
        maxTokens: (json['maxTokens'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (reasoning != null) 'reasoning': reasoning,
        if (input != null) 'input': input,
        if (contextWindow != null) 'contextWindow': contextWindow,
        if (maxTokens != null) 'maxTokens': maxTokens,
      };
}

/// OpenClaw 配置
class OpenClawConfig {
  final String baseUrl;
  final String model;

  /// OpenClaw 的 API 协议（`openai-completions` / `anthropic-messages` …）
  final String? api;

  /// 预设模型列表（写入 `models.providers[<id>].models`）
  final List<OpenClawPresetModel>? models;

  OpenClawConfig({required this.baseUrl, required this.model, this.api, this.models});

  factory OpenClawConfig.fromJson(Map<String, dynamic> json) {
    return OpenClawConfig(
      baseUrl: json['baseUrl'] as String,
      model: json['model'] as String? ?? '',
      api: json['api'] as String?,
      models: json['models'] is List
          ? (json['models'] as List)
              .whereType<Map>()
              .map((m) => OpenClawPresetModel.fromJson(m.cast<String, dynamic>()))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'model': model,
        if (api != null) 'api': api,
        if (models != null) 'models': models!.map((m) => m.toJson()).toList(),
      };
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

  /// OpenClaw 配置（如果支持 OpenClaw）
  final OpenClawConfig? openclaw;

  /// Gemini CLI 第三方端点配置
  final GeminiPresetConfig? gemini;

  /// Claude Desktop 直连配置
  final ClaudeDesktopPresetConfig? claudeDesktop;

  /// 同一厂商的不同站点/套餐归为一个家族（如 kimi），用于搜索与分组
  final String? family;

  /// 套餐标识（payg / coding / token …）
  final String? planKey;

  /// 地区标识（cn / intl）
  final String? regionKey;

  /// 搜索别名（中文名、域名、俗称，空格分隔）
  final String? searchAliases;
  
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
    this.openclaw,
    this.gemini,
    this.claudeDesktop,
    this.family,
    this.planKey,
    this.regionKey,
    this.searchAliases,
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
      openclaw: json['openclaw'] != null
          ? OpenClawConfig.fromJson(json['openclaw'] as Map<String, dynamic>)
          : null,
      gemini: json['gemini'] != null
          ? GeminiPresetConfig.fromJson(json['gemini'] as Map<String, dynamic>)
          : null,
      claudeDesktop: json['claudeDesktop'] != null
          ? ClaudeDesktopPresetConfig.fromJson(json['claudeDesktop'] as Map<String, dynamic>)
          : null,
      family: json['family'] as String?,
      planKey: json['planKey'] as String?,
      regionKey: json['regionKey'] as String?,
      searchAliases: json['searchAliases'] as String?,
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
      if (openclaw != null) 'openclaw': openclaw!.toJson(),
      if (gemini != null) 'gemini': gemini!.toJson(),
      if (claudeDesktop != null) 'claudeDesktop': claudeDesktop!.toJson(),
      if (family != null) 'family': family,
      if (planKey != null) 'planKey': planKey,
      if (regionKey != null) 'regionKey': regionKey,
      if (searchAliases != null) 'searchAliases': searchAliases,
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
    if (openclaw != null) caps.add(ProviderCapability.openclaw);
    if (gemini != null) caps.add(ProviderCapability.gemini);
    if (claudeDesktop != null) caps.add(ProviderCapability.claudeDesktop);
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
      case ProviderCapability.openclaw:
        return openclaw != null;
      case ProviderCapability.gemini:
        return gemini != null;
      case ProviderCapability.claudeDesktop:
        return claudeDesktop != null;
      case ProviderCapability.platform:
        return platform != null;
    }
  }

  /// 检查是否属于指定分组
  bool belongsToCategory(String category) {
    return categories.contains(category);
  }
}

