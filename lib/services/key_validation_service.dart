import '../models/ai_key.dart';
import '../models/validation_config.dart';
import '../models/validation_result.dart';
import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import 'validators/base_validator.dart';
import 'validators/openai_validator.dart';
import 'validators/anthropic_validator.dart';
import 'validators/google_validator.dart';
import 'validators/configurable_validator.dart';

/// 密钥校验服务
class KeyValidationService {
  final CloudConfigService _cloudConfigService = CloudConfigService();

  /// 校验密钥
  Future<KeyValidationResult> validateKey({
    required AIKey key,
    Duration? timeout,
  }) async {
    try {
      print('KeyValidationService: 开始校验密钥，平台类型: ${key.platformType.id}');
      
      // 获取供应商配置
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        print('KeyValidationService: 无法加载配置');
        return KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '无法加载配置',
        );
      }

      // 查找对应的供应商配置
      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == key.platformType.id,
        orElse: () => throw Exception('未找到供应商配置'),
      );
      print('KeyValidationService: 找到供应商配置: ${providerConfig.name}');

      // 获取校验配置
      ValidationConfig? validationConfig = providerConfig.validation;
      print('KeyValidationService: 校验配置是否存在: ${validationConfig != null}');

      // 如果没有配置，尝试使用默认配置
      if (validationConfig == null) {
        print('KeyValidationService: 使用默认校验配置');
        validationConfig = _getDefaultValidationConfig(key.platformType);
      }

      // 如果还是没有配置，使用通用校验器
      if (validationConfig == null) {
        print('KeyValidationService: 使用通用校验器');
        return await _validateWithGenericValidator(key, timeout: timeout);
      }

      print('KeyValidationService: 校验器类型: ${validationConfig.type}, 端点: ${validationConfig.endpoint}, 方法: ${validationConfig.method}');
      print('KeyValidationService: baseUrlSource: ${validationConfig.baseUrlSource}, fallbackBaseUrl: ${validationConfig.fallbackBaseUrl}');

      // 根据类型选择合适的校验器
      final validator = _getValidator(validationConfig.type);
      print('KeyValidationService: 使用校验器: ${validator.runtimeType}');
      
      final result = await validator.validate(
        key: key,
        config: validationConfig,
        timeout: timeout,
      );
      
      print('KeyValidationService: 校验结果 - 有效: ${result.isValid}, 消息: ${result.message}, 错误: ${result.error}');
      return result;
    } catch (e, stackTrace) {
      print('KeyValidationService: 校验异常: $e');
      print('KeyValidationService: 堆栈跟踪: $stackTrace');
      return KeyValidationResult.failure(
        error: ValidationError.unknown,
        message: '校验失败：${e.toString()}',
      );
    }
  }

  /// 获取默认校验配置
  ValidationConfig? _getDefaultValidationConfig(PlatformType platformType) {
    // 根据平台类型返回默认配置
    if (platformType == PlatformType.openAI) {
      return ValidationConfig(
        type: 'openai',
        endpoint: '/models', // baseUrl 已经包含 /v1，所以 endpoint 只需要 /models
        method: 'GET',
        baseUrlSource: 'codex.baseUrl',
        fallbackBaseUrl: 'https://api.openai.com/v1',
        headers: {
          'Authorization': 'Bearer {apiKey}',
          'content-type': 'application/json',
        },
        successStatus: [200],
      );
    } else if (platformType == PlatformType.anthropic) {
      return ValidationConfig(
        type: 'anthropic',
        endpoint: '/v1/messages',
        method: 'POST',
        baseUrlSource: 'claudeCode.baseUrl',
        fallbackBaseUrl: 'https://api.anthropic.com',
        headers: {
          'x-api-key': '{apiKey}',
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: {
          'model': 'claude-3-haiku-20240307',
          'max_tokens': 1,
          'messages': [],
        },
        successStatus: [200],
      );
    } else if (platformType == PlatformType.google ||
        platformType == PlatformType.gemini) {
      return ValidationConfig(
        type: 'google',
        endpoint: '/models', // baseUrl 已经包含 /v1，所以 endpoint 只需要 /models
        method: 'GET',
        baseUrlSource: 'platform.apiEndpoint',
        fallbackBaseUrl: 'https://generativelanguage.googleapis.com/v1',
        headers: {
          'x-goog-api-key': '{apiKey}',
          'content-type': 'application/json',
        },
        successStatus: [200],
      );
    }

    return null;
  }

  /// 获取校验器实例
  BaseValidator _getValidator(String type) {
    switch (type) {
      case 'openai':
      case 'openai-compatible':
        return OpenAIValidator();
      case 'anthropic':
      case 'anthropic-compatible':
        return AnthropicValidator();
      case 'google':
        return GoogleValidator();
      case 'custom':
      default:
        return ConfigurableValidator();
    }
  }

  /// 使用通用校验器（尝试常见端点）
  Future<KeyValidationResult> _validateWithGenericValidator(
    AIKey key, {
    Duration? timeout,
  }) async {
    final validator = ConfigurableValidator();
    final commonEndpoints = ['/v1/models', '/health', '/api/health'];
    final apiKey = key.keyValue;

    for (final endpoint in commonEndpoints) {
      try {
        final baseUrl = key.apiEndpoint ??
            key.codexBaseUrl ??
            key.claudeCodeBaseUrl ??
            'https://api.example.com';

        final config = ValidationConfig(
          type: 'custom',
          endpoint: endpoint,
          method: 'GET',
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          baseUrlSource: null,
          fallbackBaseUrl: baseUrl,
        );

        final result = await validator.validate(
          key: key,
          config: config,
          timeout: timeout ?? const Duration(seconds: 5),
        );

        if (result.isValid) {
          return result;
        }
      } catch (e) {
        // 继续尝试下一个端点
        continue;
      }
    }

    return KeyValidationResult.failure(
      error: ValidationError.unknown,
      message: '无法找到有效的校验端点',
    );
  }

  /// 检查平台是否支持模型列表查询
  Future<bool> supportsModelList(PlatformType platformType) async {
    try {
      print('KeyValidationService: 检查模型列表支持，平台类型: ${platformType.id}');
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        print('KeyValidationService: 配置数据为空');
        return false;
      }

      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformType.id,
        orElse: () => throw Exception('未找到供应商配置'),
      );

      print('KeyValidationService: 找到供应商配置: ${providerConfig.name}');
      final hasModelsEndpoint = providerConfig.validation?.modelsEndpoint != null &&
          providerConfig.validation!.modelsEndpoint!.isNotEmpty;
      print('KeyValidationService: 模型列表端点: ${providerConfig.validation?.modelsEndpoint}, 支持: $hasModelsEndpoint');
      
      return hasModelsEndpoint;
    } catch (e) {
      print('KeyValidationService: 检查模型列表支持失败: $e');
      return false;
    }
  }

  /// 检查平台是否有校验配置
  Future<bool> hasValidationConfig(PlatformType platformType) async {
    try {
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) return false;

      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformType.id,
        orElse: () => throw Exception('未找到供应商配置'),
      );

      return providerConfig.validation != null;
    } catch (e) {
      return false;
    }
  }
}

