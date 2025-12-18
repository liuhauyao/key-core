/// 校验配置数据模型
class ValidationConfig {
  /// 校验器类型（openai, anthropic, google, openai-compatible, anthropic-compatible, custom）
  final String type;
  
  /// 校验端点路径（相对于 baseUrl）
  final String? endpoint;
  
  /// HTTP 方法（GET/POST/PUT/DELETE）
  final String? method;
  
  /// 请求头（{apiKey} 会被替换为实际密钥值）
  final Map<String, String>? headers;
  
  /// 请求体（仅 POST/PUT 使用，{apiKey} 会被替换）
  final Map<String, dynamic>? body;
  
  /// 成功状态码列表（如 [200, 201]）
  final List<int>? successStatus;
  
  /// 错误状态码映射（状态码 -> 错误消息）
  final Map<String, String>? errorStatus;
  
  /// baseUrl 来源字段（如 "claudeCode.baseUrl", "codex.baseUrl", "platform.apiEndpoint"）
  final String? baseUrlSource;
  
  /// 备用 baseUrl（如果 baseUrlSource 为空）
  final String? fallbackBaseUrl;
  
  /// 备用 baseUrl 列表（用于国内/国外用户切换，按顺序尝试）
  final List<String>? fallbackBaseUrls;
  
  /// 模型列表查询端点（如 "/v1/models"），如果为空则不显示查看模型按钮
  final String? modelsEndpoint;
  
  /// 模型列表查询方法（GET/POST，默认 GET）
  final String? modelsMethod;
  
  /// JSON 响应中模型列表的路径（如 "data" 或 "models"，默认为根级别）
  final String? modelsResponsePath;
  
  /// 模型 ID 字段名（默认 "id"）
  final String? modelIdField;
  
  /// 模型名称字段名（默认 "name"）
  final String? modelNameField;
  
  /// 模型描述字段名（可选，默认 "description"）
  final String? modelDescriptionField;

  /// 余额查询端点（如 "/v1/account/balance"），如果为空则不显示查询余额按钮
  final String? balanceEndpoint;

  /// 余额查询方法（GET/POST，默认 GET）
  final String? balanceMethod;

  /// 余额查询请求体（仅 POST 使用）
  final Map<String, dynamic>? balanceBody;

  /// 模型列表查询的 baseUrl 来源（如果为空则使用 baseUrlSource）
  final String? modelsBaseUrlSource;

  /// 模型列表查询的备用 baseUrl（如果为空则使用 fallbackBaseUrl）
  final String? modelsFallbackBaseUrl;

  /// 模型列表查询的备用 baseUrl 列表（用于国内/国外用户切换，按顺序尝试）
  final List<String>? modelsFallbackBaseUrls;

  /// 余额查询的 baseUrl 来源（如果为空则使用 baseUrlSource）
  final String? balanceBaseUrlSource;

  /// 余额查询的备用 baseUrl（如果为空则使用 fallbackBaseUrl）
  final String? balanceFallbackBaseUrl;

  ValidationConfig({
    required this.type,
    this.endpoint,
    this.method,
    this.headers,
    this.body,
    this.successStatus,
    this.errorStatus,
    this.baseUrlSource,
    this.fallbackBaseUrl,
    this.fallbackBaseUrls,
    this.modelsEndpoint,
    this.modelsMethod,
    this.modelsResponsePath,
    this.modelIdField,
    this.modelNameField,
    this.modelDescriptionField,
    this.balanceEndpoint,
    this.balanceMethod,
    this.balanceBody,
    this.modelsBaseUrlSource,
    this.modelsFallbackBaseUrl,
    this.modelsFallbackBaseUrls,
    this.balanceBaseUrlSource,
    this.balanceFallbackBaseUrl,
  });

  factory ValidationConfig.fromJson(Map<String, dynamic> json) {
    return ValidationConfig(
      type: json['type'] as String,
      endpoint: json['endpoint'] as String?,
      method: json['method'] as String?,
      headers: json['headers'] != null
          ? Map<String, String>.from(json['headers'] as Map)
          : null,
      body: json['body'] as Map<String, dynamic>?,
      successStatus: json['successStatus'] != null
          ? List<int>.from(json['successStatus'] as List)
          : null,
      errorStatus: json['errorStatus'] != null
          ? Map<String, String>.from(json['errorStatus'] as Map)
          : null,
      baseUrlSource: json['baseUrlSource'] as String?,
      fallbackBaseUrl: json['fallbackBaseUrl'] as String?,
      fallbackBaseUrls: json['fallbackBaseUrls'] != null
          ? List<String>.from(json['fallbackBaseUrls'] as List)
          : null,
      modelsEndpoint: json['modelsEndpoint'] as String?,
      modelsMethod: json['modelsMethod'] as String?,
      modelsResponsePath: json['modelsResponsePath'] as String?,
      modelIdField: json['modelIdField'] as String?,
      modelNameField: json['modelNameField'] as String?,
      modelDescriptionField: json['modelDescriptionField'] as String?,
      balanceEndpoint: json['balanceEndpoint'] as String?,
      balanceMethod: json['balanceMethod'] as String?,
      balanceBody: json['balanceBody'] as Map<String, dynamic>?,
      modelsBaseUrlSource: json['modelsBaseUrlSource'] as String?,
      modelsFallbackBaseUrl: json['modelsFallbackBaseUrl'] as String?,
      modelsFallbackBaseUrls: json['modelsFallbackBaseUrls'] != null
          ? List<String>.from(json['modelsFallbackBaseUrls'] as List)
          : null,
      balanceBaseUrlSource: json['balanceBaseUrlSource'] as String?,
      balanceFallbackBaseUrl: json['balanceFallbackBaseUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (endpoint != null) 'endpoint': endpoint,
      if (method != null) 'method': method,
      if (headers != null) 'headers': headers,
      if (body != null) 'body': body,
      if (successStatus != null) 'successStatus': successStatus,
      if (errorStatus != null) 'errorStatus': errorStatus,
      if (baseUrlSource != null) 'baseUrlSource': baseUrlSource,
      if (fallbackBaseUrl != null) 'fallbackBaseUrl': fallbackBaseUrl,
      if (fallbackBaseUrls != null) 'fallbackBaseUrls': fallbackBaseUrls,
      if (modelsEndpoint != null) 'modelsEndpoint': modelsEndpoint,
      if (modelsMethod != null) 'modelsMethod': modelsMethod,
      if (modelsResponsePath != null) 'modelsResponsePath': modelsResponsePath,
      if (modelIdField != null) 'modelIdField': modelIdField,
      if (modelNameField != null) 'modelNameField': modelNameField,
      if (modelDescriptionField != null) 'modelDescriptionField': modelDescriptionField,
      if (balanceEndpoint != null) 'balanceEndpoint': balanceEndpoint,
      if (balanceMethod != null) 'balanceMethod': balanceMethod,
      if (balanceBody != null) 'balanceBody': balanceBody,
      if (modelsBaseUrlSource != null) 'modelsBaseUrlSource': modelsBaseUrlSource,
      if (modelsFallbackBaseUrl != null) 'modelsFallbackBaseUrl': modelsFallbackBaseUrl,
      if (modelsFallbackBaseUrls != null) 'modelsFallbackBaseUrls': modelsFallbackBaseUrls,
      if (balanceBaseUrlSource != null) 'balanceBaseUrlSource': balanceBaseUrlSource,
      if (balanceFallbackBaseUrl != null) 'balanceFallbackBaseUrl': balanceFallbackBaseUrl,
    };
  }
}

