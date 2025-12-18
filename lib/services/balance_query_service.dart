import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/ai_key.dart';
import '../models/validation_config.dart';
import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import 'validators/validation_helper.dart';

/// 余额查询结果
class BalanceQueryResult {
  final bool success;
  final Map<String, dynamic>? balanceData;
  final String? error;

  BalanceQueryResult.success(this.balanceData)
      : success = true,
        error = null;

  BalanceQueryResult.failure(this.error)
      : success = false,
        balanceData = null;
}

/// 余额查询服务
class BalanceQueryService {
  final CloudConfigService _cloudConfigService = CloudConfigService();

  /// 查询余额
  Future<BalanceQueryResult> queryBalance({
    required AIKey key,
    Duration? timeout,
  }) async {
    try {
      print('BalanceQueryService: 开始查询余额，平台类型: ${key.platformType.id}');
      
      // 获取供应商配置
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        print('BalanceQueryService: 无法加载配置');
        return BalanceQueryResult.failure('无法加载配置');
      }

      // 查找对应的供应商配置
      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == key.platformType.id,
        orElse: () => throw Exception('未找到供应商配置'),
      );

      print('BalanceQueryService: 找到供应商配置: ${providerConfig.name}');

      // 获取校验配置
      final validationConfig = providerConfig.validation;
      if (validationConfig == null ||
          validationConfig.balanceEndpoint == null ||
          validationConfig.balanceEndpoint!.isEmpty) {
        print('BalanceQueryService: 该平台不支持余额查询');
        return BalanceQueryResult.failure('该平台不支持余额查询');
      }

      // 获取 baseUrl（优先使用 balanceBaseUrlSource，否则使用 baseUrlSource）
      String? baseUrl;
      if (validationConfig.balanceBaseUrlSource != null) {
        // 创建临时配置使用 balanceBaseUrlSource
        final tempConfig = ValidationConfig(
          type: validationConfig.type,
          baseUrlSource: validationConfig.balanceBaseUrlSource,
          fallbackBaseUrl: validationConfig.balanceFallbackBaseUrl ?? validationConfig.fallbackBaseUrl,
        );
        baseUrl = ValidationHelper.getBaseUrl(key, tempConfig);
      } else {
        baseUrl = ValidationHelper.getBaseUrl(key, validationConfig);
      }
      
      if (baseUrl == null || baseUrl.isEmpty) {
        print('BalanceQueryService: 缺少 API 端点配置');
        return BalanceQueryResult.failure('缺少 API 端点配置');
      }

      // 构建请求
      final endpoint = validationConfig.balanceEndpoint!;
      final method = (validationConfig.balanceMethod ?? 'GET').toUpperCase();
      final apiKey = key.keyValue;

      print('BalanceQueryService: endpoint: $endpoint, method: $method');
      print('BalanceQueryService: baseUrl: $baseUrl');

      // 构建请求头
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // 如果使用了独立的 balanceBaseUrlSource，说明使用的是 OpenAI 兼容 API，使用 Bearer token
      // 否则根据校验器类型设置默认请求头
      if (validationConfig.balanceBaseUrlSource != null) {
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

      // 合并配置中的请求头（如果配置中有 balanceHeaders，优先使用）
      // 注意：目前配置中没有 balanceHeaders 字段，所以使用默认的 headers
      if (validationConfig.headers != null) {
        headers.addAll(
          ValidationHelper.replaceApiKeyInHeaders(validationConfig.headers!, apiKey),
        );
      }

      // 构建 URL
      final url = ValidationHelper.buildUrl(baseUrl, endpoint);
      print('BalanceQueryService: 请求 URL: $url');

      // 发送请求
      final requestTimeout = timeout ?? const Duration(seconds: 10);
      http.Response response;

      if (method == 'POST') {
        final body = validationConfig.balanceBody != null
            ? jsonEncode(
                ValidationHelper.replaceApiKeyInBody(validationConfig.balanceBody!, apiKey),
              )
            : null;
        print('BalanceQueryService: 发送 POST 请求');
        response = await http
            .post(url, headers: headers, body: body)
            .timeout(requestTimeout);
      } else {
        print('BalanceQueryService: 发送 GET 请求');
        response = await http.get(url, headers: headers).timeout(requestTimeout);
      }

      print('BalanceQueryService: 响应状态码: ${response.statusCode}');

      // 解析响应
      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final jsonData = jsonDecode(responseBody);
        
        // 打印响应内容（限制长度）
        final previewBody = responseBody.length > 500 
            ? '${responseBody.substring(0, 500)}...' 
            : responseBody;
        print('BalanceQueryService: 余额查询成功，响应: $previewBody');
        
        return BalanceQueryResult.success(jsonData as Map<String, dynamic>);
      } else {
        final errorBody = utf8.decode(response.bodyBytes);
        print('BalanceQueryService: 余额查询失败，状态码: ${response.statusCode}, 响应: $errorBody');
        return BalanceQueryResult.failure(
          '查询失败：HTTP ${response.statusCode}',
        );
      }
    } on http.ClientException catch (e) {
      print('BalanceQueryService: 网络错误: ${e.message}');
      return BalanceQueryResult.failure('网络错误：${e.message}');
    } on FormatException catch (e) {
      print('BalanceQueryService: 响应格式错误: ${e.message}');
      return BalanceQueryResult.failure('响应格式错误：${e.message}');
    } catch (e) {
      print('BalanceQueryService: 查询失败: $e');
      if (e.toString().contains('TimeoutException') ||
          e.toString().contains('timeout')) {
        return BalanceQueryResult.failure('请求超时，请检查网络连接');
      }
      return BalanceQueryResult.failure('查询失败：${e.toString()}');
    }
  }

  /// 检查平台是否支持余额查询
  Future<bool> supportsBalanceQuery(PlatformType platformType) async {
    try {
      print('BalanceQueryService: 检查余额查询支持，平台类型: ${platformType.id}');
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        print('BalanceQueryService: 配置数据为空');
        return false;
      }

      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformType.id,
        orElse: () => throw Exception('未找到供应商配置'),
      );

      print('BalanceQueryService: 找到供应商配置: ${providerConfig.name}');
      final hasBalanceEndpoint = providerConfig.validation?.balanceEndpoint != null &&
          providerConfig.validation!.balanceEndpoint!.isNotEmpty;
      print('BalanceQueryService: 余额查询端点: ${providerConfig.validation?.balanceEndpoint}, 支持: $hasBalanceEndpoint');
      
      return hasBalanceEndpoint;
    } catch (e) {
      print('BalanceQueryService: 检查余额查询支持失败: $e');
      return false;
    }
  }
}

