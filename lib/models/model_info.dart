/// 模型定价信息
class ModelPricing {
  final String? prompt; // 输入 token 成本
  final String? completion; // 输出 token 成本
  final String? request; // 每次请求固定成本
  final String? image; // 每个图片输入成本
  final String? webSearch; // 每次网络搜索成本
  final String? internalReasoning; // 内部推理 token 成本
  final String? inputCacheRead; // 缓存输入 token 读取成本
  final String? inputCacheWrite; // 缓存输入 token 写入成本

  ModelPricing({
    this.prompt,
    this.completion,
    this.request,
    this.image,
    this.webSearch,
    this.internalReasoning,
    this.inputCacheRead,
    this.inputCacheWrite,
  });

  factory ModelPricing.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ModelPricing();
    return ModelPricing(
      prompt: json['prompt']?.toString(),
      completion: json['completion']?.toString(),
      request: json['request']?.toString(),
      image: json['image']?.toString(),
      webSearch: json['web_search']?.toString(),
      internalReasoning: json['internal_reasoning']?.toString(),
      inputCacheRead: json['input_cache_read']?.toString(),
      inputCacheWrite: json['input_cache_write']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (prompt != null) 'prompt': prompt,
      if (completion != null) 'completion': completion,
      if (request != null) 'request': request,
      if (image != null) 'image': image,
      if (webSearch != null) 'web_search': webSearch,
      if (internalReasoning != null) 'internal_reasoning': internalReasoning,
      if (inputCacheRead != null) 'input_cache_read': inputCacheRead,
      if (inputCacheWrite != null) 'input_cache_write': inputCacheWrite,
    };
  }
}

/// 模型架构信息
class ModelArchitecture {
  final List<String>? inputModalities; // 支持的输入类型
  final List<String>? outputModalities; // 支持的输出类型
  final String? tokenizer; // 分词方法
  final String? instructType; // 指令格式类型

  ModelArchitecture({
    this.inputModalities,
    this.outputModalities,
    this.tokenizer,
    this.instructType,
  });

  factory ModelArchitecture.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ModelArchitecture();
    return ModelArchitecture(
      inputModalities: json['input_modalities'] != null
          ? List<String>.from(json['input_modalities'])
          : null,
      outputModalities: json['output_modalities'] != null
          ? List<String>.from(json['output_modalities'])
          : null,
      tokenizer: json['tokenizer']?.toString(),
      instructType: json['instruct_type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (inputModalities != null) 'input_modalities': inputModalities,
      if (outputModalities != null) 'output_modalities': outputModalities,
      if (tokenizer != null) 'tokenizer': tokenizer,
      if (instructType != null) 'instruct_type': instructType,
    };
  }
}

/// 模型提供商信息
class ModelTopProvider {
  final int? contextLength; // 提供商特定的上下文限制
  final int? maxCompletionTokens; // 响应最大 token 数
  final bool? isModerated; // 是否应用内容审核

  ModelTopProvider({
    this.contextLength,
    this.maxCompletionTokens,
    this.isModerated,
  });

  factory ModelTopProvider.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ModelTopProvider();
    return ModelTopProvider(
      contextLength: json['context_length'] as int?,
      maxCompletionTokens: json['max_completion_tokens'] as int?,
      isModerated: json['is_moderated'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (contextLength != null) 'context_length': contextLength,
      if (maxCompletionTokens != null) 'max_completion_tokens': maxCompletionTokens,
      if (isModerated != null) 'is_moderated': isModerated,
    };
  }
}

/// 模型信息数据模型
class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final String? canonicalSlug; // 永久不变的 slug
  final int? created; // Unix 时间戳
  final int? contextLength; // 最大上下文窗口大小
  final ModelArchitecture? architecture; // 架构信息
  final ModelPricing? pricing; // 定价信息
  final ModelTopProvider? topProvider; // 提供商信息
  final List<String>? supportedParameters; // 支持的 API 参数
  final Map<String, dynamic>? perRequestLimits; // 速率限制信息
  final Map<String, dynamic>? rawData; // 原始数据（用于存储其他未解析的字段）

  ModelInfo({
    required this.id,
    required this.name,
    this.description,
    this.canonicalSlug,
    this.created,
    this.contextLength,
    this.architecture,
    this.pricing,
    this.topProvider,
    this.supportedParameters,
    this.perRequestLimits,
    this.rawData,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json, {
    String idField = 'id',
    String nameField = 'name',
    String? descriptionField,
  }) {
    // 提取基础字段
    final id = json[idField]?.toString() ?? '';
    final name = json[nameField]?.toString() ?? json[idField]?.toString() ?? '';
    final description = descriptionField != null ? json[descriptionField]?.toString() : json['description']?.toString();
    
    // 提取扩展字段
    final canonicalSlug = json['canonical_slug']?.toString();
    final created = json['created'] as int?;
    final contextLength = json['context_length'] as int?;
    
    // 提取架构信息
    final architecture = json['architecture'] != null
        ? ModelArchitecture.fromJson(json['architecture'] as Map<String, dynamic>?)
        : null;
    
    // 提取定价信息
    final pricing = json['pricing'] != null
        ? ModelPricing.fromJson(json['pricing'] as Map<String, dynamic>?)
        : null;
    
    // 提取提供商信息
    final topProvider = json['top_provider'] != null
        ? ModelTopProvider.fromJson(json['top_provider'] as Map<String, dynamic>?)
        : null;
    
    // 提取支持的参数
    final supportedParameters = json['supported_parameters'] != null
        ? List<String>.from(json['supported_parameters'])
        : null;
    
    // 提取速率限制
    final perRequestLimits = json['per_request_limits'] as Map<String, dynamic>?;
    
    // 保存原始数据（用于存储其他未解析的字段）
    final rawData = Map<String, dynamic>.from(json);

    return ModelInfo(
      id: id,
      name: name,
      description: description,
      canonicalSlug: canonicalSlug,
      created: created,
      contextLength: contextLength,
      architecture: architecture,
      pricing: pricing,
      topProvider: topProvider,
      supportedParameters: supportedParameters,
      perRequestLimits: perRequestLimits,
      rawData: rawData,
    );
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'id': id,
      'name': name,
    };
    
    if (description != null) result['description'] = description;
    if (canonicalSlug != null) result['canonical_slug'] = canonicalSlug;
    if (created != null) result['created'] = created;
    if (contextLength != null) result['context_length'] = contextLength;
    if (architecture != null) result['architecture'] = architecture!.toJson();
    if (pricing != null) result['pricing'] = pricing!.toJson();
    if (topProvider != null) result['top_provider'] = topProvider!.toJson();
    if (supportedParameters != null) result['supported_parameters'] = supportedParameters;
    if (perRequestLimits != null) result['per_request_limits'] = perRequestLimits;
    
    // 添加原始数据中的其他字段（不覆盖已解析的字段）
    if (rawData != null) {
      final knownFields = {
        'id', 'name', 'description', 'canonical_slug', 'created', 'context_length',
        'architecture', 'pricing', 'top_provider', 'supported_parameters', 'per_request_limits'
      };
      rawData!.forEach((key, value) {
        if (!knownFields.contains(key)) {
          result[key] = value;
        }
      });
    }
    
    return result;
  }
}



