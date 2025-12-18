import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/ai_key.dart';
import '../../models/validation_config.dart';
import '../../models/validation_result.dart';
import 'base_validator.dart';
import 'validation_helper.dart';

/// Anthropic 校验器
class AnthropicValidator extends BaseValidator {
  @override
  Future<KeyValidationResult> validate({
    required AIKey key,
    required ValidationConfig config,
    Duration? timeout,
  }) async {
    print('AnthropicValidator: 开始校验');
    
    // 获取所有需要尝试的 baseUrl
    final baseUrls = getBaseUrlsToTry(key, config);
    
    if (baseUrls.isEmpty) {
      print('AnthropicValidator: 没有可用的 baseUrl');
      return KeyValidationResult.failure(
        error: ValidationError.unknown,
        message: '缺少 API 端点配置',
      );
    }

    print('AnthropicValidator: 将尝试 ${baseUrls.length} 个 baseUrl: $baseUrls');

    // 默认端点和方法
    final endpoint = config.endpoint ?? '/v1/messages';
    final method = config.method ?? 'POST';
    final apiKey = key.keyValue;
    
    print('AnthropicValidator: endpoint: $endpoint, method: $method');
    print('AnthropicValidator: apiKey 长度: ${apiKey.length}');

    // 构建请求头：优先使用配置中的 headers，否则使用默认值
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (config.headers != null && config.headers!.isNotEmpty) {
      // 使用配置中的 headers
      headers.addAll(replaceApiKeyInHeaders(config.headers!, apiKey));
      print('AnthropicValidator: 使用配置中的请求头: ${headers.keys.toList()}');
    } else {
      // 使用默认 headers
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
      print('AnthropicValidator: 使用默认请求头');
    }

    // 构建请求体：优先使用配置中的 body，否则使用默认值
    final body = config.body ?? {
      'model': 'claude-3-haiku-20240307',
      'max_tokens': 1,
      'messages': [],
    };
    final requestBody = jsonEncode(replaceApiKeyInBody(body, apiKey));
    print('AnthropicValidator: 请求体: $requestBody');

    // 尝试每个 baseUrl
    KeyValidationResult? lastError;
    final requestTimeout = timeout ?? const Duration(seconds: 10);
    
    for (int i = 0; i < baseUrls.length; i++) {
      final baseUrl = baseUrls[i];
      print('AnthropicValidator: 尝试 baseUrl ${i + 1}/${baseUrls.length}: $baseUrl');
      
      try {
        // 构建 URL
        final url = buildUrl(baseUrl, endpoint);
        print('AnthropicValidator: 请求 URL: $url');

        // 发送请求
        print('AnthropicValidator: 发送 POST 请求');
        
        final response = await http
            .post(url, headers: headers, body: requestBody)
            .timeout(requestTimeout);

        print('AnthropicValidator: 响应状态码: ${response.statusCode}');
        
        // 只打印响应体的前 500 个字符，避免日志过长
        final responseBody = utf8.decode(response.bodyBytes);
        final previewBody = responseBody.length > 500 
            ? '${responseBody.substring(0, 500)}...' 
            : responseBody;
        print('AnthropicValidator: 响应体预览: $previewBody');

        // 处理响应
        final successStatus = config.successStatus ?? [200];
        if (successStatus.contains(response.statusCode)) {
          print('AnthropicValidator: 校验成功（使用 baseUrl: $baseUrl）');
          return KeyValidationResult.success(message: '验证通过');
        }

        // 如果是密钥错误（401/403），不再尝试其他地址
        if (response.statusCode == 401 || response.statusCode == 403) {
          final errorMessage = ValidationHelper.getErrorMessage(response.statusCode, config) ?? '验证失败';
          print('AnthropicValidator: 密钥错误，不再尝试其他地址');
          return KeyValidationResult.failure(
            error: ValidationError.invalidKey,
            message: errorMessage,
          );
        }

        // 记录错误，继续尝试下一个地址
        final errorMessage = ValidationHelper.getErrorMessage(response.statusCode, config) ?? '验证失败';
        print('AnthropicValidator: baseUrl $baseUrl 校验失败，状态码: ${response.statusCode}');
        lastError = KeyValidationResult.failure(
          error: response.statusCode >= 500
              ? ValidationError.serverError
              : ValidationError.unknown,
          message: errorMessage,
        );
      } on http.ClientException catch (e) {
        print('AnthropicValidator: baseUrl $baseUrl 网络异常: ${e.message}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络错误：${e.message}',
        );
        // 网络错误继续尝试下一个地址
        continue;
      } on FormatException catch (e) {
        print('AnthropicValidator: baseUrl $baseUrl 格式异常: ${e.message}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '响应格式错误：${e.message}',
        );
        // 格式错误继续尝试下一个地址
        continue;
      } catch (e) {
        print('AnthropicValidator: baseUrl $baseUrl 未知异常: $e');
        
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
    print('AnthropicValidator: 所有 baseUrl 都尝试失败');
    return lastError ?? KeyValidationResult.failure(
      error: ValidationError.unknown,
      message: '所有校验地址都失败',
    );
  }
}

