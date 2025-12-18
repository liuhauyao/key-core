import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../../models/ai_key.dart';
import '../../models/validation_config.dart';
import '../../models/validation_result.dart';
import 'base_validator.dart';

/// 配置驱动的通用校验器（处理 custom 类型）
class ConfigurableValidator extends BaseValidator {
  @override
  Future<KeyValidationResult> validate({
    required AIKey key,
    required ValidationConfig config,
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
    final baseUrls = getBaseUrlsToTry(key, config);
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
    // 如果 endpoint 包含 client_secret 参数，且 apiKey 包含冒号分隔符，则解析它
    if (endpoint.contains('client_secret') && apiKey.contains(':')) {
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
    KeyValidationResult? lastError;
    // Hugging Face API 可能需要更长的超时时间，增加到 60 秒
    final requestTimeout = timeout ?? const Duration(seconds: 60);
    
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
        print('ConfigurableValidator: ClientException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络错误：${e.message}',
        );
        // 网络错误继续尝试下一个地址
        continue;
      } on FormatException catch (e) {
        print('ConfigurableValidator: FormatException: ${e.message}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '响应格式错误：${e.message}',
        );
        // 格式错误继续尝试下一个地址
        continue;
      } on SocketException catch (e) {
        print('ConfigurableValidator: SocketException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: '网络连接错误：${e.message}',
        );
        // 网络错误继续尝试下一个地址
        continue;
      } on TlsException catch (e) {
        print('ConfigurableValidator: TlsException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: 'SSL/TLS 连接错误：${e.message}',
        );
        // SSL 错误继续尝试下一个地址
        continue;
      } on HandshakeException catch (e) {
        print('ConfigurableValidator: HandshakeException: ${e.message}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        lastError = KeyValidationResult.failure(
          error: ValidationError.networkError,
          message: 'SSL/TLS 握手失败，请检查网络连接和系统证书',
        );
        // SSL 握手错误继续尝试下一个地址
        continue;
      } catch (e, stackTrace) {
        print('ConfigurableValidator: 捕获异常: ${e.toString()}');
        print('ConfigurableValidator: 异常类型: ${e.runtimeType}');
        print('ConfigurableValidator: 堆栈跟踪: $stackTrace');
        if (e.toString().contains('TimeoutException') ||
            e.toString().contains('timeout') ||
            e.toString().contains('Timeout')) {
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

