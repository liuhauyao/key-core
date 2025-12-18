import '../../models/ai_key.dart';
import '../../models/validation_config.dart';

/// 校验辅助工具类
class ValidationHelper {
  /// 获取 baseUrl
  static String? getBaseUrl(AIKey key, ValidationConfig config) {
    print('ValidationHelper: 获取 baseUrl，baseUrlSource: ${config.baseUrlSource}');
    
    if (config.baseUrlSource == null) {
      print('ValidationHelper: baseUrlSource 为空，使用 fallbackBaseUrl: ${config.fallbackBaseUrl}');
      return config.fallbackBaseUrl;
    }

    // 解析 baseUrlSource，支持嵌套路径如 "claudeCode.baseUrl"
    final parts = config.baseUrlSource!.split('.');
    if (parts.isEmpty) {
      print('ValidationHelper: baseUrlSource 解析为空，使用 fallbackBaseUrl: ${config.fallbackBaseUrl}');
      return config.fallbackBaseUrl;
    }

    // 直接处理常见的路径模式
    if (parts.length == 2) {
      if (parts[0] == 'claudeCode' && parts[1] == 'baseUrl') {
        final url = key.claudeCodeBaseUrl;
        print('ValidationHelper: 从 claudeCodeBaseUrl 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      } else if (parts[0] == 'codex' && parts[1] == 'baseUrl') {
        final url = key.codexBaseUrl;
        print('ValidationHelper: 从 codexBaseUrl 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      } else if (parts[0] == 'platform' && parts[1] == 'apiEndpoint') {
        final url = key.apiEndpoint;
        print('ValidationHelper: 从 apiEndpoint 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      }
    } else if (parts.length == 1) {
      if (parts[0] == 'claudeCode') {
        final url = key.claudeCodeBaseUrl;
        print('ValidationHelper: 从 claudeCodeBaseUrl 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      } else if (parts[0] == 'codex') {
        final url = key.codexBaseUrl;
        print('ValidationHelper: 从 codexBaseUrl 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      } else if (parts[0] == 'platform') {
        final url = key.apiEndpoint;
        print('ValidationHelper: 从 apiEndpoint 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      } else if (parts[0] == 'apiEndpoint') {
        final url = key.apiEndpoint;
        print('ValidationHelper: 从 apiEndpoint 获取: $url');
        if (url != null && url.isNotEmpty) {
          return url;
        }
      }
    }

    print('ValidationHelper: 未找到匹配的 URL，使用 fallbackBaseUrl: ${config.fallbackBaseUrl}');
    return config.fallbackBaseUrl;
  }

  /// 替换请求头中的 {apiKey} 占位符
  static Map<String, String> replaceApiKeyInHeaders(
    Map<String, String> headers,
    String apiKey,
  ) {
    return headers.map((key, value) => MapEntry(
          key,
          value.replaceAll('{apiKey}', apiKey),
        ));
  }

  /// 替换请求体中的 {apiKey} 占位符
  static Map<String, dynamic> replaceApiKeyInBody(
    Map<String, dynamic> body,
    String apiKey,
  ) {
    final result = <String, dynamic>{};
    body.forEach((key, value) {
      if (value is String) {
        result[key] = value.replaceAll('{apiKey}', apiKey);
      } else if (value is Map) {
        result[key] = replaceApiKeyInBody(
          Map<String, dynamic>.from(value),
          apiKey,
        );
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is String) {
            return item.replaceAll('{apiKey}', apiKey);
          } else if (item is Map) {
            return replaceApiKeyInBody(
              Map<String, dynamic>.from(item),
              apiKey,
            );
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  /// 构建完整的 URL
  static Uri buildUrl(String? baseUrl, String endpoint) {
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('Base URL 不能为空');
    }

    // 确保 baseUrl 不以 / 结尾
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // 确保 endpoint 以 / 开头
    final cleanEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';

    // 解析 baseUrl 以提取协议、主机和端口
    final baseUri = Uri.parse(cleanBaseUrl);
    
    // 解析 endpoint，分离路径和查询参数
    final endpointUri = Uri.parse(cleanEndpoint);
    final endpointPath = endpointUri.path;
    final endpointQueryParams = endpointUri.queryParameters;
    
    // 构建完整的路径：baseUrl 的路径 + endpoint 的路径
    String fullPath;
    if (baseUri.path.isNotEmpty && baseUri.path != '/') {
      // baseUrl 有路径，需要合并
      final basePath = baseUri.path.endsWith('/')
          ? baseUri.path.substring(0, baseUri.path.length - 1)
          : baseUri.path;
      fullPath = '$basePath$endpointPath';
    } else {
      // baseUrl 没有路径，直接使用 endpoint 的路径
      fullPath = endpointPath;
    }
    
    // 构建 host，如果端口不是默认端口则包含端口号
    String host;
    if (baseUri.hasPort) {
      // 对于 https，默认端口是 443；对于 http，默认端口是 80
      final defaultPort = baseUri.scheme == 'https' ? 443 : 80;
      if (baseUri.port != defaultPort) {
        host = '${baseUri.host}:${baseUri.port}';
      } else {
        host = baseUri.host;
      }
    } else {
      host = baseUri.host;
    }
    
    // 合并查询参数（baseUrl 的查询参数 + endpoint 的查询参数）
    Map<String, dynamic>? queryParameters;
    if (baseUri.queryParameters.isNotEmpty || endpointQueryParams.isNotEmpty) {
      queryParameters = {
        ...baseUri.queryParameters,
        ...endpointQueryParams,
      };
    }
    
    // 使用 Uri.https 或 Uri.http 显式构建 URL，确保正确的格式
    if (baseUri.scheme == 'https') {
      return Uri.https(
        host,
        fullPath,
        queryParameters?.isEmpty ?? true ? null : queryParameters,
      );
    } else if (baseUri.scheme == 'http') {
      return Uri.http(
        host,
        fullPath,
        queryParameters?.isEmpty ?? true ? null : queryParameters,
      );
    } else {
      // 回退到原来的方式
      return Uri.parse('$cleanBaseUrl$cleanEndpoint');
    }
  }

  /// 处理 HTTP 响应错误
  static String? getErrorMessage(int statusCode, ValidationConfig config) {
    // 检查错误状态码映射
    if (config.errorStatus != null &&
        config.errorStatus!.containsKey(statusCode.toString())) {
      return config.errorStatus![statusCode.toString()];
    }

    // 根据状态码返回默认错误
    if (statusCode == 401) {
      return '密钥无效或已过期';
    } else if (statusCode == 403) {
      return '密钥权限不足';
    } else if (statusCode == 429) {
      return '请求过于频繁，请稍后重试';
    } else if (statusCode >= 500) {
      return '服务器错误';
    }

    return '校验失败：HTTP $statusCode';
  }
}

