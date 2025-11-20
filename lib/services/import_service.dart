import 'dart:convert';
import 'dart:io';
import '../models/ai_key.dart';
import '../models/platform_type.dart';
import '../services/platform_registry.dart';
import '../models/mcp_server.dart';
import '../services/database_service.dart';
import '../services/crypt_service.dart';
import '../services/auth_service.dart';
import '../services/mcp_database_service.dart';
import '../services/settings_service.dart';

/// 导入服务
class ImportService {
  final DatabaseService _databaseService = DatabaseService.instance;
  final McpDatabaseService _mcpDatabaseService = McpDatabaseService();
  final CryptService _cryptService = CryptService();
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();

  /// 检测文件是否加密
  /// 返回 true 如果文件是加密的，false 如果是明文
  Future<bool> _isFileEncrypted(String fileContent) async {
    try {
      // 尝试直接解析JSON
      jsonDecode(fileContent);
      return false; // 能解析说明是明文
    } catch (e) {
      // 不能解析，可能是加密的
      // 检查是否是加密格式（以 { 开头，包含 data 和 iv 字段）
      try {
        final json = jsonDecode(fileContent);
        if (json is Map && json.containsKey('data') && json.containsKey('iv')) {
          return true; // 是加密格式
        }
      } catch (_) {
        // 不是JSON格式，可能是加密的
      }
      return true; // 默认认为是加密的
    }
  }

  /// 从JSON文件导入密钥
  /// filePassword: 如果文件是加密的，需要提供解密密码（可能是导出时的主密码）
  Future<ImportResult> importKeys(
      String filePath, String? filePassword) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      final fileContent = await file.readAsString();

      // 检测文件是否加密
      final isEncrypted = await _isFileEncrypted(fileContent);
      
      String jsonContent;
      if (isEncrypted) {
        // 文件是加密的，需要密码解密
        if (filePassword == null || filePassword.isEmpty) {
          throw Exception('文件已加密，需要提供解密密码');
        }
        
        try {
          final encryptionKey = await _cryptService.generateEncryptionKey(filePassword);
          jsonContent = await _cryptService.decrypt(fileContent, encryptionKey);
        } catch (e) {
          throw Exception('解密失败，密码可能不正确');
        }
      } else {
        // 文件是明文的，直接使用
        jsonContent = fileContent;
      }

      final jsonData = jsonDecode(jsonContent) as Map<String, dynamic>;

      // 验证版本
      final version = jsonData['version'] as String?;
      if (version == null) {
        throw Exception('无效的导出文件格式');
      }

      final keysData = jsonData['keys'] as List<dynamic>?;
      final mcpServersData = jsonData['mcp_servers'] as List<dynamic>?;
      
      // 兼容旧版本导出文件（可能没有mcp_servers字段）
      if (keysData == null && (mcpServersData == null || mcpServersData.isEmpty)) {
        throw Exception('文件中没有密钥或MCP服务数据');
      }

      // 检查当前应用是否设置了主密码
      final hasPassword = await _authService.hasMasterPassword();
      final encryptionKey = hasPassword ? await _authService.getEncryptionKey() : null;

      final importedKeys = <AIKey>[];
      final updatedKeys = <AIKey>[];
      final importedMcpServers = <McpServer>[];
      final updatedMcpServers = <McpServer>[];
      final errors = <String>[];

      // 处理密钥（如果存在）
      if (keysData != null && keysData.isNotEmpty) {
        for (final keyData in keysData) {
        try {
          final keyMap = keyData as Map<String, dynamic>;

          // 验证必需字段
          if (keyMap['name'] == null || keyMap['key_value'] == null) {
            errors.add('密钥缺少必需字段: ${keyMap['name'] ?? '未知'}');
            continue;
          }

          // 根据当前应用的主密码设置决定如何存储
          String finalKeyValue;
          if (hasPassword && encryptionKey != null) {
            // 如果当前应用设置了主密码，加密存储
            finalKeyValue = await _cryptService.encrypt(
              keyMap['key_value'] as String,
              encryptionKey,
            );
          } else {
            // 如果当前应用没有设置主密码，明文存储
            finalKeyValue = keyMap['key_value'] as String;
          }

          // 解析平台类型
          PlatformType platformType;
          if (keyMap['platform_type'] != null) {
            final typeIndex = keyMap['platform_type'] as int;
            final allPlatforms = PlatformRegistry.values;
            if (typeIndex >= 0 && typeIndex < allPlatforms.length) {
              platformType = allPlatforms[typeIndex];
            } else {
              platformType = PlatformRegistry.fromString(
                  keyMap['platform'] as String? ?? 'Custom');
            }
          } else {
            platformType = PlatformRegistry.fromString(
                keyMap['platform'] as String? ?? 'Custom');
          }

          // 解析标签
          List<String> tags = [];
          if (keyMap['tags'] != null) {
            if (keyMap['tags'] is List) {
              tags = List<String>.from(keyMap['tags']);
            } else if (keyMap['tags'] is String) {
              tags = (keyMap['tags'] as String)
                  .split(',')
                  .map((tag) => tag.trim())
                  .where((tag) => tag.isNotEmpty)
                  .toList();
            }
          }

          // 解析日期
          DateTime? expiryDate;
          if (keyMap['expiry_date'] != null) {
            try {
              expiryDate = DateTime.parse(keyMap['expiry_date'] as String);
            } catch (e) {
              // 忽略日期解析错误
            }
          }

          DateTime createdAt;
          try {
            createdAt = DateTime.parse(keyMap['created_at'] as String? ??
                DateTime.now().toIso8601String());
          } catch (e) {
            createdAt = DateTime.now();
          }

          DateTime updatedAt;
          try {
            updatedAt = DateTime.parse(keyMap['updated_at'] as String? ??
                DateTime.now().toIso8601String());
          } catch (e) {
            updatedAt = DateTime.now();
          }

          final keyName = keyMap['name'] as String;
          final keyPlatform = keyMap['platform'] as String? ?? platformType.value;

          // 检查是否已存在（根据 name + platform）
          final existingKey = await _databaseService.getKeyByNameAndPlatform(keyName, keyPlatform);

          final key = AIKey(
            id: existingKey?.id, // 如果存在，保留原有ID
            name: keyName,
            platform: keyPlatform,
            platformType: platformType,
            managementUrl: keyMap['management_url'] as String?,
            apiEndpoint: keyMap['api_endpoint'] as String?,
            keyValue: finalKeyValue,
            expiryDate: expiryDate,
            tags: tags,
            notes: keyMap['notes'] as String?,
            isActive: keyMap['is_active'] as bool? ?? true,
            createdAt: existingKey != null ? existingKey.createdAt : createdAt, // 保留原始创建时间
            updatedAt: DateTime.now(), // 更新时间为当前时间
            isFavorite: keyMap['is_favorite'] as bool? ?? false,
            icon: keyMap['icon'] as String?,
            enableClaudeCode: keyMap['enable_claude_code'] as bool? ?? false,
            claudeCodeApiEndpoint: keyMap['claude_code_api_endpoint'] as String?,
            claudeCodeModel: keyMap['claude_code_model'] as String?,
            claudeCodeHaikuModel: keyMap['claude_code_haiku_model'] as String?,
            claudeCodeSonnetModel: keyMap['claude_code_sonnet_model'] as String?,
            claudeCodeOpusModel: keyMap['claude_code_opus_model'] as String?,
            claudeCodeBaseUrl: keyMap['claude_code_base_url'] as String?,
            enableCodex: keyMap['enable_codex'] as bool? ?? false,
            codexApiEndpoint: keyMap['codex_api_endpoint'] as String?,
            codexModel: keyMap['codex_model'] as String?,
            codexBaseUrl: keyMap['codex_base_url'] as String?,
            codexConfig: keyMap['codex_config'] != null
                ? (keyMap['codex_config'] is Map
                    ? (keyMap['codex_config'] as Map<String, dynamic>?)
                    : (keyMap['codex_config'] is String
                        ? (jsonDecode(keyMap['codex_config'] as String) as Map<String, dynamic>?)
                        : null))
                : null,
            enableGemini: keyMap['enable_gemini'] as bool? ?? false,
            geminiApiEndpoint: keyMap['gemini_api_endpoint'] as String?,
            geminiModel: keyMap['gemini_model'] as String?,
            geminiBaseUrl: keyMap['gemini_base_url'] as String?,
          );

          if (existingKey != null) {
            updatedKeys.add(key);
          } else {
            importedKeys.add(key);
          }
        } catch (e) {
          final keyName = keyData is Map ? (keyData['name'] ?? '未知') : '未知';
          errors.add('导入密钥失败: $keyName: ${e.toString()}');
        }
      }
      }

      // 处理密钥：新增和更新
      if (importedKeys.isNotEmpty) {
        await _databaseService.insertKeys(importedKeys);
      }
      for (final key in updatedKeys) {
        try {
          await _databaseService.updateKey(key);
        } catch (e) {
          errors.add('更新密钥失败: ${key.name}: ${e.toString()}');
        }
      }

      // 处理MCP服务
      if (mcpServersData != null && mcpServersData.isNotEmpty) {
        for (final serverData in mcpServersData) {
          try {
            final serverMap = serverData as Map<String, dynamic>;
            
            // 验证必需字段
            if (serverMap['server_id'] == null || serverMap['name'] == null) {
              errors.add('MCP服务缺少必需字段: ${serverMap['name'] ?? '未知'}');
              continue;
            }

            final serverId = serverMap['server_id'] as String;
            
            // 检查是否已存在（根据 serverId）
            final existingServer = await _mcpDatabaseService.getMcpServerByServerId(serverId);

            // 解析参数
            List<String>? args;
            if (serverMap['args'] != null) {
              if (serverMap['args'] is List) {
                args = List<String>.from(serverMap['args']);
              }
            }

            Map<String, String>? env;
            if (serverMap['env'] != null) {
              if (serverMap['env'] is Map) {
                env = Map<String, String>.from(serverMap['env']);
              }
            }

            Map<String, String>? headers;
            if (serverMap['headers'] != null) {
              if (serverMap['headers'] is Map) {
                headers = Map<String, String>.from(serverMap['headers']);
              }
            }

            List<String>? tags;
            if (serverMap['tags'] != null) {
              if (serverMap['tags'] is List) {
                tags = List<String>.from(serverMap['tags']);
              }
            }

            DateTime createdAt;
            try {
              createdAt = DateTime.parse(serverMap['created_at'] as String? ?? DateTime.now().toIso8601String());
            } catch (e) {
              createdAt = DateTime.now();
            }

            DateTime updatedAt;
            try {
              updatedAt = DateTime.parse(serverMap['updated_at'] as String? ?? DateTime.now().toIso8601String());
            } catch (e) {
              updatedAt = DateTime.now();
            }

            final server = McpServer(
              id: existingServer?.id, // 如果存在，保留原有ID
              serverId: serverId,
              name: serverMap['name'] as String,
              description: serverMap['description'] as String?,
              icon: serverMap['icon'] as String?,
              serverType: McpServerType.fromString(serverMap['server_type'] as String? ?? 'stdio'),
              command: serverMap['command'] as String?,
              args: args,
              env: env,
              cwd: serverMap['cwd'] as String?,
              url: serverMap['url'] as String?,
              headers: headers,
              tags: tags,
              homepage: serverMap['homepage'] as String?,
              docs: serverMap['docs'] as String?,
              isActive: serverMap['is_active'] as bool? ?? true,
              createdAt: existingServer != null ? existingServer.createdAt : createdAt, // 保留原始创建时间
              updatedAt: DateTime.now(), // 更新时间为当前时间
            );

            if (existingServer != null) {
              await _mcpDatabaseService.updateMcpServer(server);
              updatedMcpServers.add(server);
            } else {
              await _mcpDatabaseService.addMcpServer(server);
              importedMcpServers.add(server);
            }
          } catch (e) {
            final serverName = serverData is Map ? (serverData['name'] ?? '未知') : '未知';
            errors.add('导入MCP服务失败: $serverName: ${e.toString()}');
          }
        }
      }

      // 处理官方 API Key 配置（如果存在）
      final officialApiKeysData = jsonData['official_api_keys'] as Map<String, dynamic>?;
      if (officialApiKeysData != null) {
        try {
          await _settingsService.init();
          
          // 导入官方 Claude API Key
          if (officialApiKeysData['claude'] != null) {
            final claudeApiKey = officialApiKeysData['claude'] as String?;
            if (claudeApiKey != null && claudeApiKey.isNotEmpty) {
              await _settingsService.setOfficialClaudeApiKey(claudeApiKey);
            }
          }
          
          // 导入官方 Codex API Key
          if (officialApiKeysData['codex'] != null) {
            final codexApiKey = officialApiKeysData['codex'] as String?;
            if (codexApiKey != null && codexApiKey.isNotEmpty) {
              await _settingsService.setOfficialCodexApiKey(codexApiKey);
            }
          }
          
          // 导入官方 Gemini API Key
          if (officialApiKeysData['gemini'] != null) {
            final geminiApiKey = officialApiKeysData['gemini'] as String?;
            if (geminiApiKey != null && geminiApiKey.isNotEmpty) {
              await _settingsService.setOfficialGeminiApiKey(geminiApiKey);
            }
          }
        } catch (e) {
          errors.add('导入官方 API Key 配置失败: ${e.toString()}');
        }
      }

      return ImportResult(
        success: true,
        importedCount: importedKeys.length,
        updatedCount: updatedKeys.length,
        mcpImportedCount: importedMcpServers.length,
        mcpUpdatedCount: updatedMcpServers.length,
        errorCount: errors.length,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        importedCount: 0,
        errorCount: 0,
        errors: [e.toString()],
      );
    }
  }
}

/// 导入结果
class ImportResult {
  final bool success;
  final int importedCount; // 新增的密钥数量
  final int updatedCount; // 更新的密钥数量
  final int mcpImportedCount; // 新增的MCP服务数量
  final int mcpUpdatedCount; // 更新的MCP服务数量
  final int errorCount;
  final List<String> errors;

  ImportResult({
    required this.success,
    required this.importedCount,
    this.updatedCount = 0,
    this.mcpImportedCount = 0,
    this.mcpUpdatedCount = 0,
    required this.errorCount,
    required this.errors,
  });

  String get message {
    if (success) {
      final parts = <String>[];
      if (importedCount > 0 || updatedCount > 0) {
        final keyParts = <String>[];
        if (importedCount > 0) keyParts.add('新增 $importedCount 个密钥');
        if (updatedCount > 0) keyParts.add('更新 $updatedCount 个密钥');
        parts.add(keyParts.join('，'));
      }
      if (mcpImportedCount > 0 || mcpUpdatedCount > 0) {
        final mcpParts = <String>[];
        if (mcpImportedCount > 0) mcpParts.add('新增 $mcpImportedCount 个MCP服务');
        if (mcpUpdatedCount > 0) mcpParts.add('更新 $mcpUpdatedCount 个MCP服务');
        parts.add(mcpParts.join('，'));
      }
      if (errorCount > 0) {
        parts.add('$errorCount 个失败');
      }
      return parts.isNotEmpty ? parts.join('；') : '导入完成';
    }
    return '导入失败: ${errors.join(', ')}';
  }
}

