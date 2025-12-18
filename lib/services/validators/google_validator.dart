import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/ai_key.dart';
import '../../models/validation_config.dart';
import '../../models/validation_result.dart';
import 'base_validator.dart';

/// Google AI/Gemini 校验器
class GoogleValidator extends BaseValidator {
  @override
  Future<KeyValidationResult> validate({
    required AIKey key,
    required ValidationConfig config,
    Duration? timeout,
  }) async {
    // 获取所有需要尝试的 baseUrl
    final baseUrls = getBaseUrlsToTry(key, config);
    
    if (baseUrls.isEmpty) {
      return KeyValidationResult.failure(
        error: ValidationError.unknown,
        message: '缺少 API 端点配置',
      );
    }

    // 默认端点和方法
    final endpoint = config.endpoint ?? '/v1/models';
    final method = config.method ?? 'GET';
    final apiKey = key.keyValue;

    // 构建请求头：优先使用配置中的 headers，否则使用默认值
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (config.headers != null && config.headers!.isNotEmpty) {
      // 使用配置中的 headers
      headers.addAll(replaceApiKeyInHeaders(config.headers!, apiKey));
    } else {
      // 使用默认 headers
      headers['x-goog-api-key'] = apiKey;
    }

    // 尝试每个 baseUrl
    KeyValidationResult? lastError;
    final requestTimeout = timeout ?? const Duration(seconds: 10);
    
    for (int i = 0; i < baseUrls.length; i++) {
      final baseUrl = baseUrls[i];
      
      try {
        // 构建 URL（Google API 使用查询参数传递 API key）
        final baseUri = buildUrl(baseUrl, endpoint);
        final url = baseUri.replace(
          queryParameters: {
            ...baseUri.queryParameters,
            'key': apiKey,
          },
        );

        // 发送请求
        http.Response response;

        if (method.toUpperCase() == 'POST') {
          final body = config.body != null
              ? jsonEncode(replaceApiKeyInBody(config.body!, apiKey))
              : null;
          response = await http
              .post(url, headers: headers, body: body)
              .timeout(requestTimeout);
        } else {
          response = await http.get(url, headers: headers).timeout(requestTimeout);
        }

        // 处理响应
        final successStatus = config.successStatus ?? [200];
        if (successStatus.contains(response.statusCode)) {
          return KeyValidationResult.success(message: '验证通过');
        }

        // 如果是密钥错误（401/403），不再尝试其他地址
        if (response.statusCode == 401 || response.statusCode == 403) {
          return KeyValidationResult.failure(
            error: ValidationError.invalidKey,
            message: '验证失败',
          );
        }

        // 记录错误，继续尝试下一个地址
        lastError = KeyValidationResult.failure(
          error: response.statusCode >= 500
              ? ValidationError.serverError
              : ValidationError.unknown,
          message: '验证失败',
        );
      } on http.ClientException catch (e) {
        lastError = KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络错误：${e.message}',
        );
        // 网络错误继续尝试下一个地址
        continue;
      } on FormatException catch (e) {
        lastError = KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '响应格式错误：${e.message}',
        );
        // 格式错误继续尝试下一个地址
        continue;
      } catch (e) {
        if (e.toString().contains('TimeoutException') ||
            e.toString().contains('timeout')) {
          lastError = KeyValidationResult.failure(
            error: ValidationError.timeout,
            message: '请求超时，请检查网络连接',
          );
        } else {
          lastError = KeyValidationResult.failure(
            error: ValidationError.unknown,
            message: '校验失败：${e.toString()}',
          );
        }
        // 继续尝试下一个地址
        continue;
      }
    }

    // 所有地址都尝试失败
    return lastError ?? KeyValidationResult.failure(
      error: ValidationError.unknown,
      message: '所有校验地址都失败',
    );
  }
}

