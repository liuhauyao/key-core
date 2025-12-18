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
  /// 使用密钥的 platform_type_id（即 key.platformType.id）从已加载的配置文件中匹配校验配置
  /// 配置文件在应用启动时已加载到缓存，这里从缓存中读取配置
  Future<KeyValidationResult> validateKey({
    required AIKey key,
    Duration? timeout,
  }) async {
    try {
      // 使用密钥的 platform_type_id（即 platformType.id）来匹配配置文件中的供应商配置
      // platformType 是从数据库恢复的，优先使用 platform_type_id 字段
      final platformTypeId = key.platformType.id;
      
      // 从缓存中获取供应商配置（配置文件在应用启动时已加载到缓存）
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        print('KeyValidationService: 无法加载配置（缓存为空）');
        return KeyValidationResult.failure(
          error: ValidationError.unknown,
          message: '无法加载配置',
        );
      }

      // 根据 platform_type_id 查找对应的供应商配置
      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformTypeId,
        orElse: () => throw Exception('未找到供应商配置: $platformTypeId'),
      );

      // 获取校验配置
      ValidationConfig? validationConfig = providerConfig.validation;

      // 如果没有配置，尝试使用默认配置
      if (validationConfig == null) {
        validationConfig = _getDefaultValidationConfig(key.platformType);
      }

      // 如果还是没有配置，使用通用校验器
      if (validationConfig == null) {
        final requestTimeout = timeout ?? const Duration(seconds: 5);
        return await _validateWithGenericValidator(key, timeout: requestTimeout);
      }


      // 根据类型选择合适的校验器
      final validator = _getValidator(validationConfig.type);
      
      // 如果没有指定超时，默认使用5秒
      final requestTimeout = timeout ?? const Duration(seconds: 5);
      
      final result = await validator.validate(
        key: key,
        config: validationConfig,
        providerConfig: providerConfig,
        timeout: requestTimeout,
      );
      
      return result;
    } catch (e, stackTrace) {
      print('KeyValidationService: 校验异常: $e');
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
  /// 使用 platform_type_id（即 platformType.id）从已加载的配置文件中匹配配置
  Future<bool> supportsModelList(PlatformType platformType) async {
    try {
      final platformTypeId = platformType.id;
      // 从缓存中获取配置（配置文件在应用启动时已加载到缓存）
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) {
        return false;
      }

      // 根据 platform_type_id 查找对应的供应商配置
      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformTypeId,
        orElse: () => throw Exception('未找到供应商配置: $platformTypeId'),
      );

      final hasModelsEndpoint = providerConfig.validation?.modelsEndpoint != null &&
          providerConfig.validation!.modelsEndpoint!.isNotEmpty;
      
      return hasModelsEndpoint;
    } catch (e) {
      return false;
    }
  }

  /// 检查平台是否有校验配置
  /// 使用 platform_type_id（即 platformType.id）从已加载的配置文件中匹配配置
  Future<bool> hasValidationConfig(PlatformType platformType) async {
    try {
      final platformTypeId = platformType.id;
      // 从缓存中获取配置（配置文件在应用启动时已加载到缓存）
      final configData = await _cloudConfigService.getConfigData();
      if (configData == null) return false;

      // 根据 platform_type_id 查找对应的供应商配置
      final providerConfig = configData.providers.firstWhere(
        (p) => p.platformType == platformTypeId,
        orElse: () => throw Exception('未找到供应商配置: $platformTypeId'),
      );

      return providerConfig.validation != null;
    } catch (e) {
      return false;
    }
  }
}

