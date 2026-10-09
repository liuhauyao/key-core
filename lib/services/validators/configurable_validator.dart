import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../../models/ai_key.dart';
import '../../models/validation_config.dart';
import '../../models/validation_result.dart';
import '../../models/unified_provider_config.dart';
import 'base_validator.dart';

/// 配置驱动的通用校验器（处理 custom 类型）
class ConfigurableValidator extends BaseValidator {
  @override
  Future<KeyValidationResult> validate({
    required AIKey key,
    required ValidationConfig config,
    UnifiedProviderConfig? providerConfig,
    Duration? timeout,
  }) async {
    // 必须有 endpoint 配置
    if (config.endpoint == null || config.endpoint!.isEmpty) {
      return KeyValidationResult.failure(
        error: ValidationError.unknown,
        message: '缺少校验端点配置',
      );
    }

    // 获取所有需要尝试的 baseUrl
    final baseUrls = getBaseUrlsToTry(key, config, providerConfig);
    print('ConfigurableValidator: 获取到的 baseUrls: $baseUrls');
    
    if (baseUrls.isEmpty) {
      return KeyValidationResult.failure(
        error: ValidationError.unknown,
        message: '缺少 API 端点配置',
      );
    }

    var endpoint = config.endpoint!;
    final method = (config.method ?? 'GET').toUpperCase();
    final apiKey = key.keyValue;

    // 检查是否是百度千帆的双参数认证（需要 API Key 和 Secret Key）
    // 如果 endpoint 包含 client_secret 参数，需要特殊处理
    if (endpoint.contains('client_secret')) {
      // 如果 apiKey 包含冒号分隔符，则解析它
      if (apiKey.contains(':')) {
        final parts = apiKey.split(':');
        if (parts.length == 2) {
          final clientId = Uri.encodeComponent(parts[0].trim());
          final clientSecret = Uri.encodeComponent(parts[1].trim());
          // 替换 client_id 和 client_secret 参数
          endpoint = endpoint.replaceAll('client_id={apiKey}', 'client_id=$clientId');
          endpoint = endpoint.replaceAll('client_secret={apiKey}', 'client_secret=$clientSecret');
          // 替换其他可能的 {apiKey} 占位符
          endpoint = endpoint.replaceAll('{apiKey}', clientId);
        } else {
          // 格式错误，返回失败
          return KeyValidationResult.failure(
            error: ValidationError.invalidKey,
            message: 'API Key 格式错误，请使用格式：API_KEY:SECRET_KEY',
          );
        }
      } else {
        // endpoint 需要 client_secret，但 apiKey 不包含冒号，说明格式不正确
        return KeyValidationResult.failure(
          error: ValidationError.invalidKey,
          message: 'API Key 格式错误，请使用格式：API_KEY:SECRET_KEY（用冒号分隔）',
        );
      }
    } else {
      // 替换 endpoint 中的 {apiKey} 占位符（用于查询参数等情况）
      endpoint = endpoint.replaceAll('{apiKey}', apiKey);
    }

    // 构建请求头（只使用配置中的请求头，与 n8n 保持一致）
    final headers = <String, String>{};

    // 合并配置中的请求头
    if (config.headers != null) {
      headers.addAll(replaceApiKeyInHeaders(config.headers!, apiKey));
    }
    
    // 如果是 POST/PUT 请求，添加 Content-Type
    if (method == 'POST' || method == 'PUT') {
      headers.putIfAbsent('Content-Type', () => 'application/json');
    }

    // 尝试每个 baseUrl
    final requestTimeout = timeout ?? const Duration(seconds: 5);
    
    for (int i = 0; i < baseUrls.length; i++) {
      final baseUrl = baseUrls[i];
      
      try {
        // 构建 URL
        final url = buildUrl(baseUrl, endpoint);
        print('ConfigurableValidator: 请求 URL: $url');
        print('ConfigurableValidator: 请求方法: $method');
        print('ConfigurableValidator: 请求头: $headers');

        // 发送请求（使用 http.Client 以便更好地控制 SSL/TLS 连接）
        print('ConfigurableValidator: 准备发送请求，URL: $url');
        print('ConfigurableValidator: URL 类型: ${url.runtimeType}');
        print('ConfigurableValidator: URL 字符串: ${url.toString()}');
        
        // 创建 HTTP 客户端，使用系统默认的 SecurityContext
        final client = http.Client();
        http.Response response;
        
        try {
          if (method == 'POST' || method == 'PUT') {
            final body = config.body != null
                ? jsonEncode(replaceApiKeyInBody(config.body!, apiKey))
                : '{}';
            print('ConfigurableValidator: 发送 ${method} 请求');
            if (method == 'POST') {
              response = await client
                  .post(url, headers: headers, body: body)
                  .timeout(requestTimeout);
            } else {
              response = await client
                  .put(url, headers: headers, body: body)
                  .timeout(requestTimeout);
            }
          } else if (method == 'DELETE') {
            print('ConfigurableValidator: 发送 DELETE 请求');
            response = await client.delete(url, headers: headers).timeout(requestTimeout);
          } else {
            // GET
            print('ConfigurableValidator: 发送 GET 请求');
            response = await client.get(url, headers: headers).timeout(requestTimeout);
          }
        } finally {
          client.close();
        }

        print('ConfigurableValidator: 请求完成，响应状态码: ${response.statusCode}');
        print('ConfigurableValidator: 响应体长度: ${response.body.length}');
        if (response.body.length < 500) {
          print('ConfigurableValidator: 响应体: ${response.body}');
        }

        // 处理响应
        final successStatus = config.successStatus ?? [200];
        if (successStatus.contains(response.statusCode)) {
          return KeyValidationResult.success(message: '验证通过');
        }

        // 如果是 404 且还有更多 baseUrl 可以尝试，继续尝试下一个
        // 这适用于像 Pinecone 这样的情况：索引端点返回 404，但 controller 端点可能有效
        if (response.statusCode == 404 && i < baseUrls.length - 1) {
          print('ConfigurableValidator: 检测到 404，继续尝试下一个 baseUrl');
          continue; // 继续尝试下一个 baseUrl
        }

        // 401/403 表示认证失败，不需要继续尝试
        if (response.statusCode == 401 || response.statusCode == 403) {
          return KeyValidationResult.failure(
            error: ValidationError.invalidKey,
            message: '验证失败',
          );
        }

        // 其他错误状态码，如果还有更多 baseUrl，继续尝试
        if (i < baseUrls.length - 1) {
          print('ConfigurableValidator: 状态码 ${response.statusCode}，继续尝试下一个 baseUrl');
          continue;
        }

        // 所有 baseUrl 都尝试过了，返回失败
        return KeyValidationResult.failure(
          error: response.statusCode >= 500
              ? ValidationError.serverError
              : ValidationError.unknown,
          message: '验证失败',
        );
      } on http.ClientException catch (e) {
        print('ConfigurableValidator: ClientException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络错误：${e.message}',
        );
      } on FormatException catch (e) {
        print('ConfigurableValidator: FormatException: ${e.message}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '响应格式错误：${e.message}',
        );
      } on SocketException catch (e) {
        print('ConfigurableValidator: SocketException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络连接错误：${e.message}',
        );
      } on TlsException catch (e) {
        print('ConfigurableValidator: TlsException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: 'SSL/TLS 连接错误：${e.message}',
        );
      } on HandshakeException catch (e) {
        print('ConfigurableValidator: HandshakeException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        // 失败即自动取消
        return KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: 'SSL/TLS 握手失败，请检查网络连接和系统证书',
        );
      } catch (e, stackTrace) {
        print('ConfigurableValidator: 捕获异常: ${e.toString()}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        print('ConfigurableValidator: 堆栈跟踪: $stackTrace');
        // 失败即自动取消
        if (e.toString().contains('TimeoutException') ||
            e.toString().contains('timeout') ||
            e.toString().contains('Timeout')) {
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
    return KeyValidationResult.failure(
      error: ValidationError.unknown,
      message: '所有校验地址都失败',
    );
  }
}

