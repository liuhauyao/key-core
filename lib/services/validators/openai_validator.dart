import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../models/ai_key.dart';
import '../../models/validation_config.dart';
import '../../models/validation_result.dart';
import '../../models/unified_provider_config.dart';
import 'base_validator.dart';
import 'validation_helper.dart';

/// OpenAI 校验器
class OpenAIValidator extends BaseValidator {
  @override
  Future<KeyValidationResult> validate({
    required AIKey key,
    required ValidationConfig config,
    UnifiedProviderConfig? providerConfig,
    Duration? timeout,
  }) async {
    print('OpenAIValidator: 开始校验');
    
    // 获取所有需要尝试的 baseUrl
    final baseUrls = getBaseUrlsToTry(key, config, providerConfig);
    
    if (baseUrls.isEmpty) {
      print('OpenAIValidator: 没有可用的 baseUrl');
      return KeyValidationResult.failure(
        error: ValidationError.unknown,
        message: '缺少 API 端点配置',
      );
    }

    print('OpenAIValidator: 将尝试 ${baseUrls.length} 个 baseUrl: $baseUrls');

    // 默认端点和方法
    final endpoint = config.endpoint ?? '/v1/models';
    final method = config.method ?? 'GET';
    final apiKey = key.keyValue;
    
    print('OpenAIValidator: endpoint: $endpoint, method: $method');
    print('OpenAIValidator: apiKey 长度: ${apiKey.length}');

    // 构建请求头：优先使用配置中的 headers，否则使用默认值
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    
    if (config.headers != null && config.headers!.isNotEmpty) {
      // 使用配置中的 headers
      headers.addAll(replaceApiKeyInHeaders(config.headers!, apiKey));
      print('OpenAIValidator: 使用配置中的请求头: ${headers.keys.toList()}');
    } else {
      // 使用默认 headers
      headers['Authorization'] = 'Bearer $apiKey';
      print('OpenAIValidator: 使用默认请求头');
    }

    // 尝试每个 baseUrl
    final requestTimeout = timeout ?? const Duration(seconds: 5);
    
    for (int i = 0; i < baseUrls.length; i++) {
      final baseUrl = baseUrls[i];
      print('OpenAIValidator: 尝试 baseUrl ${i + 1}/${baseUrls.length}: $baseUrl');
      
      try {
        // 构建 URL
        final url = buildUrl(baseUrl, endpoint);
        print('OpenAIValidator: 请求 URL: $url');

        // 发送请求
        http.Response response;

        if (method.toUpperCase() == 'POST') {
          final body = config.body != null
              ? jsonEncode(replaceApiKeyInBody(config.body!, apiKey))
              : null;
          print('OpenAIValidator: 发送 POST 请求，body: ${body != null ? "已设置" : "无"}');
          response = await http
              .post(url, headers: headers, body: body)
              .timeout(requestTimeout);
        } else {
          print('OpenAIValidator: 发送 GET 请求');
          response = await http.get(url, headers: headers).timeout(requestTimeout);
        }

        print('OpenAIValidator: 响应状态码: ${response.statusCode}');
        
        // 只打印响应体的前 500 个字符，避免日志过长
        final responseBody = utf8.decode(response.bodyBytes);
        final previewBody = responseBody.length > 500 
            ? '${responseBody.substring(0, 500)}...' 
            : responseBody;
        print('OpenAIValidator: 响应体预览: $previewBody');

        // 处理响应
        final successStatus = config.successStatus ?? [200];
        if (successStatus.contains(response.statusCode)) {
          print('OpenAIValidator: 校验成功（使用 baseUrl: $baseUrl）');
          return KeyValidationResult.success(message: '验证通过');
        }

        // 如果是 302 重定向，且是旧地址，继续尝试其他地址（可能是旧地址重定向到新地址）
        if (response.statusCode == 302 && baseUrl.contains('aip.baidubce.com')) {
          print('OpenAIValidator: 检测到旧地址 302 重定向，继续尝试其他地址');
          continue; // 继续尝试下一个 baseUrl
        }

        // 429 速率限制：API Key 有效，只是请求太频繁，视为校验成功
        if (response.statusCode == 429) {
          print('OpenAIValidator: 检测到 429 速率限制，API Key 有效，视为校验成功');
          return KeyValidationResult.success(message: '验证通过（速率限制）');
        }

        // 403 权限不足：检查是否是 API Key 有效但需要付费计划的情况
        if (response.statusCode == 403) {
          final responseBodyLower = responseBody.toLowerCase();
          // 检查是否是账户权限问题（如需要付费计划），而不是 API Key 无效
          if (responseBodyLower.contains('premium') || 
              responseBodyLower.contains('team plan') ||
              responseBodyLower.contains('subscription') ||
              responseBodyLower.contains('billing') ||
              responseBodyLower.contains('plan required')) {
            print('OpenAIValidator: 检测到 403 权限不足（需要付费计划），API Key 有效，视为校验成功');
            return KeyValidationResult.success(message: '验证通过（需要付费计划）');
          }
        }

        // 失败即自动取消，不再尝试其他地址
        final errorMessage = ValidationHelper.getErrorMessage(response.statusCode, config) ?? '验证失败';
        print('OpenAIValidator: baseUrl $baseUrl 校验失败，状态码: ${response.statusCode}');
        return KeyValidationResult.failure(
          error: response.statusCode == 401 || response.statusCode == 403
              ? ValidationError.invalidKey
              : response.statusCode >= 500
                  ? ValidationError.serverError
                  : ValidationError.unknown,
          message: errorMessage,
        );
      } on http.ClientException catch (e) {
        print('OpenAIValidator: baseUrl $baseUrl 网络异常: ${e.message}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络错误：${e.message}',
        );
      } on FormatException catch (e) {
        print('OpenAIValidator: baseUrl $baseUrl 格式异常: ${e.message}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '响应格式错误：${e.message}',
        );
      } catch (e, stackTrace) {
        print('OpenAIValidator: baseUrl $baseUrl 未知异常: $e');
        print('OpenAIValidator: 堆栈跟踪: $stackTrace');
        
        // 失败即自动取消
        if (e.toString().contains('TimeoutException') ||
            e.toString().contains('timeout')) {
          return KeyValidationResult.failure(
            error: ValidationError.timeout,
            message: '请求超时，请检查网络连接',
          );
        } else {
          return KeyValidationResult.failure(
            error: ValidationError.unknown,
            message: '校验失败：${e.toString()}',
          );
        }
      }
    }

    // 理论上不应该到达这里，因为失败时会立即返回
    print('OpenAIValidator: 所有 baseUrl 都尝试失败');
    return KeyValidationResult.failure(
      error: ValidationError.unknown,
      message: '所有校验地址都失败',
    );
  }
}

