import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/ai_key.dart';
import '../models/model_info.dart';
import '../models/validation_config.dart';
import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import 'validators/validation_helper.dart';

/// 模型列表查询结果
class ModelListResult {
  final bool success;
  final List<ModelInfo>? models;
  final String? error;

  ModelListResult.success(this.models)
      : success = true,
        error = null;

  ModelListResult.failure(this.error)
      : success = false,
        models = null;
}

/// 模型列表查询服务
class ModelListService {
  final CloudConfigService _cloudConfigService = CloudConfigService();

  /// 查询模型列表
  /// 使用密钥的 platform_type_id（即 key.platformType.id）从已加载的配置文件中匹配配置
  /// 配置文件在应用启动时已加载到缓存，这里从缓存中读取配置
  Future<ModelListResult> getModelList({
    required AIKey key,
    Duration? timeout,
  }) async {
    try {
      // 使用密钥的 platform_type_id（即 platformType.id）来匹配配置文件中的供应商配置
      final platformTypeId = key.platformType.id;
      // 从缓存中获取供应商配置（配置文件在应用启动时已加载到缓存）
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        return ModelListResult.failure('无法加载配置（缓存为空）');
      }

      // 根据 platform_type_id 查找对应的供应商配置
      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformTypeId,
        orElse: () => throw Exception('未找到供应商配置: $platformTypeId'),
      );

      // 获取校验配置
      final validationConfig = providerConfig.validation;
      if (validationConfig == null ||
          validationConfig.modelsEndpoint == null ||
          validationConfig.modelsEndpoint!.isEmpty) {
        return ModelListResult.failure('该平台不支持模型列表查询');
      }

      // 获取 baseUrl 列表（支持多个 fallback）
      List<String> baseUrls = [];
      
      if (validationConfig.modelsBaseUrlSource != null) {
        // 创建临时配置使用 modelsBaseUrlSource
        final tempConfig = ValidationConfig(
          type: validationConfig.type,
          baseUrlSource: validationConfig.modelsBaseUrlSource,
          fallbackBaseUrl: validationConfig.modelsFallbackBaseUrl ?? validationConfig.fallbackBaseUrl,
          fallbackBaseUrls: validationConfig.modelsFallbackBaseUrls,
        );
        // 使用改进后的getBaseUrl，传递providerConfig以支持自动检测
        final primaryUrl = ValidationHelper.getBaseUrl(key, tempConfig, providerConfig);
        if (primaryUrl != null && primaryUrl.isNotEmpty) {
          baseUrls.add(primaryUrl);
        }
      } else {
        // 如果没有modelsBaseUrlSource，使用默认的baseUrlSource或自动检测
        final primaryUrl = ValidationHelper.getBaseUrl(key, validationConfig, providerConfig);
        if (primaryUrl != null && primaryUrl.isNotEmpty) {
          baseUrls.add(primaryUrl);
        }
      }
      
      // 添加 fallback URLs
      if (validationConfig.modelsFallbackBaseUrls != null) {
        baseUrls.addAll(validationConfig.modelsFallbackBaseUrls!);
      } else if (validationConfig.modelsFallbackBaseUrl != null) {
        baseUrls.add(validationConfig.modelsFallbackBaseUrl!);
      } else if (validationConfig.fallbackBaseUrl != null) {
        baseUrls.add(validationConfig.fallbackBaseUrl!);
      }
      
      // 去重
      baseUrls = baseUrls.toSet().toList();
      
      if (baseUrls.isEmpty) {
        return ModelListResult.failure('缺少 API 端点配置');
      }

      // 构建请求
      final endpoint = validationConfig.modelsEndpoint!;
      final method = (validationConfig.modelsMethod ?? 'GET').toUpperCase();
      final apiKey = key.keyValue;

      // 构建请求头
      final headers = <String, String>{};

      // 如果使用了独立的 modelsBaseUrlSource，说明使用的是 OpenAI 兼容 API，使用 Bearer token
      // 否则根据校验器类型设置默认请求头
      if (validationConfig.modelsBaseUrlSource != null) {
        // 使用 OpenAI 兼容的请求头
        headers['Authorization'] = 'Bearer $apiKey';
      } else if (validationConfig.type == 'openai' ||
          validationConfig.type == 'openai-compatible') {
        headers['Authorization'] = 'Bearer $apiKey';
      } else if (validationConfig.type == 'anthropic' ||
          validationConfig.type == 'anthropic-compatible') {
        headers['x-api-key'] = apiKey;
        headers['anthropic-version'] = '2023-06-01';
      } else if (validationConfig.type == 'google') {
        headers['x-goog-api-key'] = apiKey;
      }

      // 添加默认请求头
      headers.putIfAbsent('User-Agent', () => 'KeyCore/1.0');
      headers.putIfAbsent('Accept', () => 'application/json');
      
      // 合并配置中的请求头（如果配置中有 modelsHeaders，优先使用）
      // 注意：目前配置中没有 modelsHeaders 字段，所以使用默认的 headers
      if (validationConfig.headers != null) {
        headers.addAll(
          ValidationHelper.replaceApiKeyInHeaders(validationConfig.headers!, apiKey),
        );
      }
      
      // 如果是 POST 请求，添加 Content-Type
      if (method == 'POST') {
        headers.putIfAbsent('Content-Type', () => 'application/json');
      }

      // 获取所有模型（支持多个 baseUrl，不分页）
      final client = http.Client();
      final requestTimeout = timeout ?? const Duration(seconds: 5);
      
      try {
        // 尝试每个 baseUrl
        Exception? lastError;
        for (int urlIndex = 0; urlIndex < baseUrls.length; urlIndex++) {
          final baseUrl = baseUrls[urlIndex];
          print('ModelListService: 尝试 baseUrl ${urlIndex + 1}/${baseUrls.length}: $baseUrl');
          
          try {
            // 直接获取所有模型（所有供应商的模型列表 API 都不需要分页）
            final url = ValidationHelper.buildUrl(baseUrl, endpoint);
            print('ModelListService: 请求 URL: $url');
            print('ModelListService: 请求方法: $method');
            print('ModelListService: 请求头: $headers');

            http.Response response;
            if (method == 'POST') {
              final body = validationConfig.body != null
                  ? jsonEncode(
                      ValidationHelper.replaceApiKeyInBody(validationConfig.body!, apiKey),
                    )
                  : null;
              response = await client
                  .post(url, headers: headers, body: body)
                  .timeout(requestTimeout);
            } else {
              response = await client.get(url, headers: headers).timeout(requestTimeout);
            }
            
            print('ModelListService: 响应状态码: ${response.statusCode}');

            if (response.statusCode == 200) {
              final jsonData = jsonDecode(utf8.decode(response.bodyBytes));
              final models = _parseModelList(jsonData, validationConfig);
              print('ModelListService: 获取模型数量: ${models.length}');
              if (models.isNotEmpty) {
                return ModelListResult.success(models);
              }
            } else if (response.statusCode >= 400 && response.statusCode < 500) {
              // 4xx 错误，不尝试下一个 URL
              return ModelListResult.failure('查询失败：HTTP ${response.statusCode}');
            }
          } catch (e) {
            print('ModelListService: baseUrl $baseUrl 请求失败: $e');
            lastError = e is Exception ? e : Exception(e.toString());
            // 继续尝试下一个 URL
          }
        }
        
        // 所有 URL 都失败了
        if (lastError != null) {
          return ModelListResult.failure('查询失败：${lastError.toString()}');
        }
        return ModelListResult.failure('所有 API 端点都无法获取模型列表');
      } finally {
        client.close();
      }
    } on http.ClientException catch (e) {
      return ModelListResult.failure('网络错误：${e.message}');
    } on FormatException catch (e) {
      return ModelListResult.failure('响应格式错误：${e.message}');
    } catch (e) {
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timeout')) {
        return ModelListResult.failure('请求超时，请检查网络连接');
      }
      return ModelListResult.failure('查询失败：${e.toString()}');
    }
  }

  /// 解析模型列表
  List<ModelInfo> _parseModelList(
    dynamic jsonData,
    ValidationConfig config,
  ) {
    // 获取模型列表路径
    final responsePath = config.modelsResponsePath;
    dynamic modelsData = jsonData;

    if (responsePath != null && responsePath.isNotEmpty) {
      final parts = responsePath.split('.');
      for (final part in parts) {
        if (modelsData is Map && modelsData.containsKey(part)) {
          modelsData = modelsData[part];
        } else {
          return [];
        }
      }
    }

    // 确保是列表
    if (modelsData is! List) {
      return [];
    }

    // 获取字段名
    final idField = config.modelIdField ?? 'id';
    final nameField = config.modelNameField ?? 'name';
    final descriptionField = config.modelDescriptionField;

    // 解析每个模型
    final models = <ModelInfo>[];
    for (final item in modelsData) {
      if (item is Map) {
        try {
          final model = ModelInfo.fromJson(
            Map<String, dynamic>.from(item),
            idField: idField,
            nameField: nameField,
            descriptionField: descriptionField,
          );
          if (model.id.isNotEmpty) {
            models.add(model);
          }
        } catch (e) {
          // 跳过无效的模型项
          continue;
        }
      }
    }

    return models;
  }
}

