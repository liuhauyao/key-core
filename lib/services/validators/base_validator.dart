import '../../models/ai_key.dart';
import '../../models/validation_config.dart';
import '../../models/validation_result.dart';
import '../../models/unified_provider_config.dart';
import 'validation_helper.dart';

/// 校验器基类
abstract class BaseValidator {
  /// 校验密钥
  Future<KeyValidationResult> validate({
    required AIKey key,
    required ValidationConfig config,
    UnifiedProviderConfig? providerConfig,
    Duration? timeout,
  });

  /// 获取 baseUrl（委托给 ValidationHelper）
  String? getBaseUrl(AIKey key, ValidationConfig config, [UnifiedProviderConfig? providerConfig]) {
    return ValidationHelper.getBaseUrl(key, config, providerConfig);
  }

  /// 获取所有需要尝试的 baseUrl 列表（包括默认和备用地址）
  List<String> getBaseUrlsToTry(AIKey key, ValidationConfig config, [UnifiedProviderConfig? providerConfig]) {
    final baseUrls = <String>[];
    
    // 1. 优先使用默认 baseUrl
    final defaultBaseUrl = getBaseUrl(key, config, providerConfig);
    if (defaultBaseUrl != null && defaultBaseUrl.isNotEmpty) {
      baseUrls.add(defaultBaseUrl);
    }
    
    // 2. 添加备用 baseUrl 列表
    if (config.fallbackBaseUrls != null && config.fallbackBaseUrls!.isNotEmpty) {
      for (final fallbackUrl in config.fallbackBaseUrls!) {
        if (fallbackUrl.isNotEmpty && !baseUrls.contains(fallbackUrl)) {
          baseUrls.add(fallbackUrl);
        }
      }
    }
    
    // 3. 如果没有其他地址，使用单个 fallbackBaseUrl
    if (baseUrls.isEmpty && config.fallbackBaseUrl != null && config.fallbackBaseUrl!.isNotEmpty) {
      baseUrls.add(config.fallbackBaseUrl!);
    }
    
    return baseUrls;
  }

  /// 替换请求头中的 {apiKey} 占位符（委托给 ValidationHelper）
  Map<String, String> replaceApiKeyInHeaders(
    Map<String, String> headers,
    String apiKey,
  ) {
    return ValidationHelper.replaceApiKeyInHeaders(headers, apiKey);
  }

  /// 替换请求体中的 {apiKey} 占位符（委托给 ValidationHelper）
  Map<String, dynamic> replaceApiKeyInBody(
    Map<String, dynamic> body,
    String apiKey,
  ) {
    return ValidationHelper.replaceApiKeyInBody(body, apiKey);
  }

  /// 构建完整的 URL（委托给 ValidationHelper）
  Uri buildUrl(String? baseUrl, String endpoint) {
    return ValidationHelper.buildUrl(baseUrl, endpoint);
  }

  /// 处理 HTTP 响应错误
  KeyValidationResult handleHttpError(
    int statusCode,
    ValidationConfig config,
  ) {
    // 检查是否是成功状态码
    if (config.successStatus != null &&
        config.successStatus!.contains(statusCode)) {
      return KeyValidationResult.success(message: '密钥有效');
    }

    // 获取错误消息
    final errorMessage = ValidationHelper.getErrorMessage(statusCode, config);
    ValidationError error;

    if (statusCode == 401 || statusCode == 403) {
      error = ValidationError.invalidKey;
    } else if (statusCode == 429) {
      error = ValidationError.serverError;
    } else if (statusCode >= 500) {
      error = ValidationError.serverError;
    } else {
      error = ValidationError.unknown;
    }

    return KeyValidationResult.failure(
      error: error,
      message: errorMessage,
    );
  }
}
