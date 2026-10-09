import 'package:equatable/equatable.dart';

/// 供应商模型
class Provider extends Equatable {
  final String id;
  final String name;
  final String? nameZh;
  final String providerType; // 'official', 'relay', 'custom'
  final String? apiEndpoint;
  final String? apiKey;
  final List<ProviderModel> models;
  final List<String> supportedTools;
  final String? region;
  final String? planType;
  final String? iconUrl;
  final String? websiteUrl;
  final String? apiKeyUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final bool isSponsored;
  final String? family;

  const Provider({
    required this.id,
    required this.name,
    this.nameZh,
    required this.providerType,
    this.apiEndpoint,
    this.apiKey,
    this.models = const [],
    this.supportedTools = const [],
    this.region,
    this.planType,
    this.iconUrl,
    this.websiteUrl,
    this.apiKeyUrl,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.isSponsored = false,
    this.family,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        nameZh,
        providerType,
        apiEndpoint,
        apiKey,
        models,
        supportedTools,
        region,
        planType,
        iconUrl,
        websiteUrl,
        apiKeyUrl,
        isActive,
        createdAt,
        updatedAt,
        description,
        isSponsored,
        family,
      ];

  Provider copyWith({
    String? id,
    String? name,
    String? nameZh,
    String? providerType,
    String? apiEndpoint,
    String? apiKey,
    List<ProviderModel>? models,
    List<String>? supportedTools,
    String? region,
    String? planType,
    String? iconUrl,
    String? websiteUrl,
    String? apiKeyUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
    bool? isSponsored,
    String? family,
  }) {
    return Provider(
      id: id ?? this.id,
      name: name ?? this.name,
      nameZh: nameZh ?? this.nameZh,
      providerType: providerType ?? this.providerType,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      supportedTools: supportedTools ?? this.supportedTools,
      region: region ?? this.region,
      planType: planType ?? this.planType,
      iconUrl: iconUrl ?? this.iconUrl,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      apiKeyUrl: apiKeyUrl ?? this.apiKeyUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
      isSponsored: isSponsored ?? this.isSponsored,
      family: family ?? this.family,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'name_zh': nameZh,
      'provider_type': providerType,
      'api_endpoint': apiEndpoint,
      'api_key': apiKey,
      'models': models.map((m) => m.toMap()).toList(),
      'supported_tools': supportedTools,
      'region': region,
      'plan_type': planType,
      'icon_url': iconUrl,
      'website_url': websiteUrl,
      'api_key_url': apiKeyUrl,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'description': description,
      'is_sponsored': isSponsored ? 1 : 0,
      'family': family,
    };
  }

  factory Provider.fromMap(Map<String, dynamic> map) {
    return Provider(
      id: map['id'] as String,
      name: map['name'] as String,
      nameZh: map['name_zh'] as String?,
      providerType: map['provider_type'] as String,
      apiEndpoint: map['api_endpoint'] as String?,
      apiKey: map['api_key'] as String?,
      models: (map['models'] as List<dynamic>?)
              ?.map((m) => ProviderModel.fromMap(m as Map<String, dynamic>))
              .toList() ??
          [],
      supportedTools: (map['supported_tools'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      region: map['region'] as String?,
      planType: map['plan_type'] as String?,
      iconUrl: map['icon_url'] as String?,
      websiteUrl: map['website_url'] as String?,
      apiKeyUrl: map['api_key_url'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          map['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          map['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      description: map['description'] as String?,
      isSponsored: (map['is_sponsored'] as int?) == 1,
      family: map['family'] as String?,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory Provider.fromJson(Map<String, dynamic> json) {
    return Provider(
      id: json['id'] as String,
      name: json['name'] as String,
      nameZh: json['nameZh'] as String?,
      providerType: json['providerType'] as String,
      apiEndpoint: json['apiEndpoint'] as String?,
      apiKey: null, // API key 不从 JSON 加载
      models: (json['models'] as List<dynamic>?)
              ?.map((m) => ProviderModel.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      supportedTools: (json['supportedTools'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      region: json['region'] as String?,
      planType: json['planKey'] as String?,
      iconUrl: json['iconUrl'] as String?,
      websiteUrl: json['websiteUrl'] as String?,
      apiKeyUrl: json['apiKeyUrl'] as String?,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      description: json['description'] as String?,
      isSponsored: json['isSponsored'] as bool? ?? false,
      family: json['family'] as String?,
    );
  }
}

/// 供应商模型
class ProviderModel extends Equatable {
  final String id;
  final String displayName;
  final int? contextWindow;
  final int? maxOutputTokens;
  final List<String>? reasoningLevels;
  final bool supportsImages;
  final bool supportsThinking;
  final double? inputPricePerMToken;
  final double? outputPricePerMToken;

  const ProviderModel({
    required this.id,
    required this.displayName,
    this.contextWindow,
    this.maxOutputTokens,
    this.reasoningLevels,
    this.supportsImages = false,
    this.supportsThinking = false,
    this.inputPricePerMToken,
    this.outputPricePerMToken,
  });

  @override
  List<Object?> get props => [
        id,
        displayName,
        contextWindow,
        maxOutputTokens,
        reasoningLevels,
        supportsImages,
        supportsThinking,
        inputPricePerMToken,
        outputPricePerMToken,
      ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'display_name': displayName,
      'context_window': contextWindow,
      'max_output_tokens': maxOutputTokens,
      'reasoning_levels': reasoningLevels,
      'supports_images': supportsImages ? 1 : 0,
      'supports_thinking': supportsThinking ? 1 : 0,
      'input_price_per_m_token': inputPricePerMToken,
      'output_price_per_m_token': outputPricePerMToken,
    };
  }

  factory ProviderModel.fromMap(Map<String, dynamic> map) {
    return ProviderModel(
      id: map['id'] as String,
      displayName: map['display_name'] as String,
      contextWindow: map['context_window'] as int?,
      maxOutputTokens: map['max_output_tokens'] as int?,
      reasoningLevels: (map['reasoning_levels'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      supportsImages: (map['supports_images'] as int?) == 1,
      supportsThinking: (map['supports_thinking'] as int?) == 1,
      inputPricePerMToken: (map['input_price_per_m_token'] as num?)?.toDouble(),
      outputPricePerMToken:
          (map['output_price_per_m_token'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'contextWindow': contextWindow,
      'maxOutputTokens': maxOutputTokens,
      'reasoningLevels': reasoningLevels,
      'supportsImages': supportsImages,
      'supportsThinking': supportsThinking,
      'inputPricePerMToken': inputPricePerMToken,
      'outputPricePerMToken': outputPricePerMToken,
    };
  }

  factory ProviderModel.fromJson(Map<String, dynamic> json) {
    return ProviderModel(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      contextWindow: json['contextWindow'] as int?,
      maxOutputTokens: json['maxOutputTokens'] as int?,
      reasoningLevels: (json['reasoningLevels'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      supportsImages: json['supportsImages'] as bool? ?? false,
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      inputPricePerMToken: (json['inputPricePerMToken'] as num?)?.toDouble(),
      outputPricePerMToken: (json['outputPricePerMToken'] as num?)?.toDouble(),
    );
  }
}
