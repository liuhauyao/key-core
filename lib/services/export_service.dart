import 'dart:convert';
import 'dart:io';
import '../models/ai_key.dart';
import '../models/mcp_server.dart';
import '../services/database_service.dart';
import '../services/crypt_service.dart';
import '../services/auth_service.dart';
import '../services/mcp_database_service.dart';
import '../services/settings_service.dart';
import '../constants/app_constants.dart';

/// 导出服务
class ExportService {
  final DatabaseService _databaseService = DatabaseService.instance;
  final McpDatabaseService _mcpDatabaseService = McpDatabaseService();
  final CryptService _cryptService = CryptService();
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();

  /// 导出所有密钥到JSON文件
  /// 如果用户设置了主密码，用主密码解密后明文导出
  /// 如果用户没有设置主密码，直接明文导出
  Future<String?> exportKeys(String filePath) async {
    try {
      // 获取所有密钥
      final keys = await _databaseService.getAllKeys();

      // 检查是否设置了主密码
      final hasPassword = await _authService.hasMasterPassword();
      final encryptionKey = hasPassword ? await _authService.getEncryptionKey() : null;

      // 解密所有密钥值（如果有主密码）或直接使用明文
      final exportKeys = <Map<String, dynamic>>[];
      for (final key in keys) {
        try {
          String decryptedValue;
          
          if (hasPassword && encryptionKey != null) {
            // 如果设置了主密码，需要解密
            if (key.keyValue.startsWith('{')) {
              // 加密格式，需要解密
              decryptedValue = await _cryptService.decrypt(
                key.keyValue,
                encryptionKey,
              );
            } else {
              // 明文格式，直接使用
              decryptedValue = key.keyValue;
            }
          } else {
            // 没有设置主密码，直接使用明文
            decryptedValue = key.keyValue;
          }

          exportKeys.add({
            'name': key.name,
            'platform': key.platform,
            'platform_type': key.platformType.index,
            'management_url': key.managementUrl,
            'api_endpoint': key.apiEndpoint,
            'key_value': decryptedValue,
            'expiry_date': key.expiryDate?.toIso8601String(),
            'tags': key.tags,
            'notes': key.notes,
            'is_active': key.isActive,
            'is_favorite': key.isFavorite,
            'created_at': key.createdAt.toIso8601String(),
            'updated_at': key.updatedAt.toIso8601String(),
            'icon': key.icon,
            // ClaudeCode 配置
            'enable_claude_code': key.enableClaudeCode,
            'claude_code_api_endpoint': key.claudeCodeApiEndpoint,
            'claude_code_model': key.claudeCodeModel,
            'claude_code_haiku_model': key.claudeCodeHaikuModel,
            'claude_code_sonnet_model': key.claudeCodeSonnetModel,
            'claude_code_opus_model': key.claudeCodeOpusModel,
            'claude_code_base_url': key.claudeCodeBaseUrl,
            // Codex 配置
            'enable_codex': key.enableCodex,
            'codex_api_endpoint': key.codexApiEndpoint,
            'codex_model': key.codexModel,
            'codex_base_url': key.codexBaseUrl,
            'codex_config': key.codexConfig != null ? jsonEncode(key.codexConfig) : null,
            // Gemini 配置
            'enable_gemini': key.enableGemini,
            'gemini_api_endpoint': key.geminiApiEndpoint,
            'gemini_model': key.geminiModel,
            'gemini_base_url': key.geminiBaseUrl,
          });
        } catch (e) {
          // 跳过无法处理的密钥
          continue;
        }
      }

      // 获取所有MCP服务
      final mcpServers = await _mcpDatabaseService.getAllMcpServers();
      final exportMcpServers = mcpServers.map((server) => {
        'server_id': server.serverId,
        'name': server.name,
        'description': server.description,
        'icon': server.icon,
        'server_type': server.serverType.value,
        'command': server.command,
        'args': server.args,
        'env': server.env,
        'cwd': server.cwd,
        'url': server.url,
        'headers': server.headers,
        'tags': server.tags,
        'homepage': server.homepage,
        'docs': server.docs,
        'is_active': server.isActive,
        'created_at': server.createdAt.toIso8601String(),
        'updated_at': server.updatedAt.toIso8601String(),
      }).toList();

      // 获取官方 API Key 配置
      await _settingsService.init();
      final officialClaudeApiKey = _settingsService.getOfficialClaudeApiKey();
      final officialCodexApiKey = _settingsService.getOfficialCodexApiKey();
      final officialGeminiApiKey = _settingsService.getOfficialGeminiApiKey();

      // 明文导出JSON（不再加密文件），包含密钥、MCP服务和官方 API Key 配置
      final jsonData = jsonEncode({
        'version': AppConstants.appVersion,
        'export_date': DateTime.now().toIso8601String(),
        'key_count': exportKeys.length,
        'mcp_server_count': exportMcpServers.length,
        'keys': exportKeys,
        'mcp_servers': exportMcpServers,
        // 官方 API Key 配置
        'official_api_keys': {
          'claude': officialClaudeApiKey,
          'codex': officialCodexApiKey,
          'gemini': officialGeminiApiKey,
        },
      });

      // 写入文件
      try {
        final file = File(filePath);
        // 确保父目录存在
        final parentDir = file.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        await file.writeAsString(jsonData);
        return filePath;
      } catch (e) {
        // 文件写入错误，提供更详细的错误信息
        if (e.toString().contains('Permission denied') || 
            e.toString().contains('权限') ||
            e.toString().contains('denied')) {
          throw Exception('没有写入文件的权限，请检查文件路径或选择其他位置');
        } else if (e.toString().contains('No such file') || 
                   e.toString().contains('文件不存在')) {
          throw Exception('文件路径无效: $filePath');
        } else {
          throw Exception('写入文件失败: ${e.toString()}');
        }
      }
    } catch (e) {
      // 重新抛出异常，让上层处理
      if (e is Exception) {
        rethrow;
      }
      throw Exception('导出失败: ${e.toString()}');
    }
  }

  /// 导出为未加密的JSON（用于调试，不推荐）
  Future<String?> exportKeysPlain(String filePath) async {
    try {
      final keys = await _databaseService.getAllKeys();
      final encryptionKey = await _authService.getEncryptionKey();
      if (encryptionKey == null) {
        throw Exception('未找到加密密钥');
      }

      final exportKeys = <Map<String, dynamic>>[];
      for (final key in keys) {
        try {
          final decryptedValue = await _cryptService.decrypt(
            key.keyValue,
            encryptionKey,
          );

          exportKeys.add({
            'name': key.name,
            'platform': key.platform,
            'platform_type': key.platformType.index,
            'management_url': key.managementUrl,
            'api_endpoint': key.apiEndpoint,
            'key_value': decryptedValue,
            'expiry_date': key.expiryDate?.toIso8601String(),
            'tags': key.tags,
            'notes': key.notes,
            'is_active': key.isActive,
            'is_favorite': key.isFavorite,
            'created_at': key.createdAt.toIso8601String(),
            'updated_at': key.updatedAt.toIso8601String(),
            'icon': key.icon,
            // ClaudeCode 配置
            'enable_claude_code': key.enableClaudeCode,
            'claude_code_api_endpoint': key.claudeCodeApiEndpoint,
            'claude_code_model': key.claudeCodeModel,
            'claude_code_haiku_model': key.claudeCodeHaikuModel,
            'claude_code_sonnet_model': key.claudeCodeSonnetModel,
            'claude_code_opus_model': key.claudeCodeOpusModel,
            'claude_code_base_url': key.claudeCodeBaseUrl,
            // Codex 配置
            'enable_codex': key.enableCodex,
            'codex_api_endpoint': key.codexApiEndpoint,
            'codex_model': key.codexModel,
            'codex_base_url': key.codexBaseUrl,
            'codex_config': key.codexConfig != null ? jsonEncode(key.codexConfig) : null,
            // Gemini 配置
            'enable_gemini': key.enableGemini,
            'gemini_api_endpoint': key.geminiApiEndpoint,
            'gemini_model': key.geminiModel,
            'gemini_base_url': key.geminiBaseUrl,
          });
        } catch (e) {
          continue;
        }
      }

      // 获取官方 API Key 配置
      await _settingsService.init();
      final officialClaudeApiKey = _settingsService.getOfficialClaudeApiKey();
      final officialCodexApiKey = _settingsService.getOfficialCodexApiKey();
      final officialGeminiApiKey = _settingsService.getOfficialGeminiApiKey();

      final file = File(filePath);
      await file.writeAsString(jsonEncode({
        'version': AppConstants.appVersion,
        'export_date': DateTime.now().toIso8601String(),
        'key_count': exportKeys.length,
        'keys': exportKeys,
        // 官方 API Key 配置
        'official_api_keys': {
          'claude': officialClaudeApiKey,
          'codex': officialCodexApiKey,
          'gemini': officialGeminiApiKey,
        },
      }));

      return filePath;
    } catch (e) {
      throw Exception('导出失败: ${e.toString()}');
    }
  }
}

