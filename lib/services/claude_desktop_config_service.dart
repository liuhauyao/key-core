import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/ai_key.dart';
import '../services/auth_service.dart';
import '../services/crypt_service.dart';
import '../services/settings_service.dart';
import '../services/platform_config_path_service.dart';

/// Claude Desktop 配置服务
///
/// 使用 Claude Desktop 原生支持的 3-Profile 第三方配置档案机制。
/// 通过写入 ~/Library/Application Support/Claude-3p/configLibrary/ 下的
/// Profile 文件来注入 API Key/Base URL/Model，而非修改 claude_desktop_config.json
/// 的 MCP servers。
///
/// 修改的配置文件：
///   1. claude_desktop_config.json     — deploymentMode 改为 "3p"
///   2. configLibrary/{UUID}.json      — Profile（API Key / Base URL / Models）
///   3. configLibrary/meta.json        — 跟踪当前激活的 Profile
///
/// 参考：cc-switch (farion1231/cc-switch) 的 Claude Desktop 3-Profile 实现
class ClaudeDesktopConfigService {
  static const String _configFileName = 'claude_desktop_config.json';
  static const String _profileId = PlatformConfigPathService.claudeDesktopProfileId;

  final AuthService _authService = AuthService();
  final CryptService _cryptService = CryptService();
  final SettingsService _settingsService = SettingsService();

  // 缓存
  String? _cachedConfigDir;
  bool? _cachedIsOfficial;

  /// 获取 Claude Desktop 配置目录路径
  Future<String> _getConfigDir() async {
    if (_cachedConfigDir != null) return _cachedConfigDir!;
    final customDir = _settingsService.getClaudeDesktopConfigDir();
    final configDir = await PlatformConfigPathService.getClaudeDesktopConfigDir(
      customDir: customDir,
    );
    _cachedConfigDir = configDir;
    return configDir;
  }

  /// 获取 claude_desktop_config.json 路径
  Future<String> _getConfigFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _configFileName);
  }

  /// 获取 Profile 文件路径
  Future<String> _getProfilePath() async {
    final libraryDir = await PlatformConfigPathService.getClaudeDesktop3pConfigLibraryDir();
    return path.join(libraryDir, '$_profileId.json');
  }

  /// 获取 meta.json 路径
  Future<String> _getMetaPath() async {
    return await PlatformConfigPathService.getClaudeDesktopMetaPath();
  }

  // ==================== 公共方法 ====================

  /// 检测配置文件状态
  Future<Map<String, dynamic>> checkConfigExists() async {
    final configDir = await _getConfigDir();
    final configPath = await _getConfigFilePath();
    final profilePath = await _getProfilePath();
    final metaPath = await _getMetaPath();

    final configDirObj = Directory(configDir);
    final configFile = File(configPath);
    final profileFile = File(profilePath);
    final metaFile = File(metaPath);

    bool dirExists = false;
    bool configExists = false;
    bool profileExists = false;
    bool metaExists = false;

    try {
      dirExists = await configDirObj.exists();
      if (dirExists) {
        configExists = await configFile.exists();
      }
      profileExists = await profileFile.exists();
      metaExists = await metaFile.exists();
    } catch (e) {
      // 权限问题等
    }

    return {
      'configDir': configDir,
      'configPath': configPath,
      'dirExists': dirExists,
      'configExists': configExists,
      'profilePath': profilePath,
      'profileExists': profileExists,
      'metaPath': metaPath,
      'metaExists': metaExists,
    };
  }

  /// 读取 claude_desktop_config.json
  Future<Map<String, dynamic>?> readConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      print('ClaudeDesktopConfigService: 读取配置失败: $e');
      return null;
    }
  }

  /// 读取 Profile 文件
  Future<Map<String, dynamic>?> readProfile() async {
    try {
      final profilePath = await _getProfilePath();
      final file = File(profilePath);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      if (content.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (e) {
      print('ClaudeDesktopConfigService: 读取 Profile 失败: $e');
      return null;
    }
  }

  /// 备份当前配置
  Future<bool> backupConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      if (await configFile.exists()) {
        await configFile.copy('$configPath.bak');
      }
      final profilePath = await _getProfilePath();
      final profileFile = File(profilePath);
      if (await profileFile.exists()) {
        await profileFile.copy('$profilePath.bak');
      }
      return true;
    } catch (e) {
      print('ClaudeDesktopConfigService: 备份配置失败: $e');
      return false;
    }
  }

  /// 切换 Claude Desktop 使用的密钥
  ///
  /// 通过 3-Profile 机制注入 API Key：
  ///   1. 写入 claude_desktop_config.json → deploymentMode: "3p" + configLibraryReference
  ///   2. 写入 Profile → inferenceGatewayBaseUrl + inferenceGatewayApiKey + inferenceModels
  ///   3. 更新 meta.json → 标记当前激活的 Profile
  Future<bool> switchProvider(AIKey key) async {
    try {
      // 解密密钥值
      String apiKey = key.keyValue;
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword && apiKey.startsWith('{')) {
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey != null) {
          apiKey = await _cryptService.decrypt(apiKey, encryptionKey);
        }
      }

      // 1. 读取/创建 claude_desktop_config.json
      final config = await readConfig() ?? <String, dynamic>{};
      config['deploymentMode'] = '3p';
      config['configLibraryReference'] = {
        'id': _profileId,
        'name': 'Key Core',
      };

      // 清理旧的 key-core-env MCP 条目（如果有）
      if (config.containsKey('mcpServers')) {
        final mcpServers = config['mcpServers'] as Map<String, dynamic>;
        mcpServers.remove('key-core-env');
        if (mcpServers.isEmpty) {
          config.remove('mcpServers');
        }
      }

      // 2. 构建 Profile
      final baseUrl = key.claudeDesktopBaseUrl?.isNotEmpty == true
          ? key.claudeDesktopBaseUrl!
          : 'https://api.anthropic.com';

      // 使用用户为每个路由配置的模型映射做 labelOverride
      // 未配置时使用 claudeDesktopModel 作为 sonnet 的兜底
      final sonnetLabel = key.claudeDesktopSonnetModel?.isNotEmpty == true
          ? key.claudeDesktopSonnetModel
          : (key.claudeDesktopModel?.isNotEmpty == true ? key.claudeDesktopModel : null);
      final haikuLabel = key.claudeDesktopHaikuModel?.isNotEmpty == true
          ? key.claudeDesktopHaikuModel
          : null;
      final opusLabel = key.claudeDesktopOpusModel?.isNotEmpty == true
          ? key.claudeDesktopOpusModel
          : null;

      final models = <dynamic>[
        sonnetLabel != null
            ? {'name': 'claude-sonnet-4-6', 'labelOverride': sonnetLabel, 'supports1m': true}
            : 'claude-sonnet-4-6',
        opusLabel != null
            ? {'name': 'claude-opus-4-8', 'labelOverride': opusLabel, 'supports1m': true}
            : {'name': 'claude-opus-4-8', 'supports1m': true},
        haikuLabel != null
            ? {'name': 'claude-haiku-4-5', 'labelOverride': haikuLabel, 'supports1m': true}
            : {'name': 'claude-haiku-4-5', 'supports1m': true},
      ];

      final profile = <String, dynamic>{
        'coworkEgressAllowedHosts': ['*'],
        'disableDeploymentModeChooser': true,
        'inferenceGatewayApiKey': apiKey,
        'inferenceGatewayAuthScheme': 'bearer',
        'inferenceGatewayBaseUrl': baseUrl,
        'inferenceProvider': 'gateway',
        'inferenceModels': models,
      };

      // 3. 构建 meta.json
      final meta = <String, dynamic>{
        'appliedId': _profileId,
        'entries': [
          {
            'id': _profileId,
            'name': 'Key Core',
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      };

      // 4. 确保目录存在并原子写入
      final configDir = await _getConfigDir();
      await Directory(configDir).create(recursive: true);

      final libraryDir = await PlatformConfigPathService.getClaudeDesktop3pConfigLibraryDir();
      await Directory(libraryDir).create(recursive: true);

      // 写 claude_desktop_config.json（主配置文件）
      final configPath = await _getConfigFilePath();
      final tempConfigPath = '$configPath.tmp';
      await File(tempConfigPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );
      await File(tempConfigPath).rename(configPath);

      // 写 Claude-3p/configLibrary/claude_desktop_config.json（3p 专用配置文件）
      final threepConfigPath = path.join(libraryDir, 'claude_desktop_config.json');
      final tempThreepPath = '$threepConfigPath.tmp';
      await File(tempThreepPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );
      await File(tempThreepPath).rename(threepConfigPath);

      // 写 Profile
      final profilePath = await _getProfilePath();
      final tempProfilePath = '$profilePath.tmp';
      await File(tempProfilePath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(profile),
      );
      await File(tempProfilePath).rename(profilePath);

      // 写 meta.json
      final metaPath = await _getMetaPath();
      final tempMetaPath = '$metaPath.tmp';
      await File(tempMetaPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(meta),
      );
      await File(tempMetaPath).rename(metaPath);

      // 覆盖其他工具残留的 _meta.json 和 profile（如存在），防止干扰
      final staleMetaPath = path.join(libraryDir, '_meta.json');
      final staleMetaFile = File(staleMetaPath);
      if (await staleMetaFile.exists()) {
        try {
          await staleMetaFile.writeAsString(
            const JsonEncoder.withIndent('  ').convert({'appliedId': _profileId, 'entries': []}),
          );
        } catch (_) {}
      }
      final staleProfilePath = path.join(libraryDir, 'd808fcc1-9179-4599-aa44-003947430bdd.json');
      final staleProfileFile = File(staleProfilePath);
      if (await staleProfileFile.exists()) {
        try {
          await staleProfileFile.writeAsString('{}');
        } catch (_) {}
      }

      _cachedIsOfficial = null;
      print('ClaudeDesktopConfigService: 切换成功 - Profile=$_profileId, BaseUrl=$baseUrl');
      return true;
    } catch (e) {
      print('ClaudeDesktopConfigService: 切换配置失败: $e');
      return false;
    }
  }

  /// 获取当前使用的 API Key（从 Profile 中读取）
  Future<String?> getCurrentApiKey() async {
    try {
      final config = await readConfig();
      if (config == null) return null;

      // 检查是否是 3p 模式
      if (config['deploymentMode'] != '3p') return null;

      final profile = await readProfile();
      if (profile == null) return null;

      final apiKey = profile['inferenceGatewayApiKey'] as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        return apiKey.trim();
      }
      return null;
    } catch (e) {
      print('ClaudeDesktopConfigService: 获取 API Key 失败: $e');
      return null;
    }
  }

  /// 判断当前是否是官方配置（1p 模式或无配置）
  Future<bool> isOfficialConfig() async {
    if (_cachedIsOfficial != null) return _cachedIsOfficial!;
    try {
      final config = await readConfig();
      if (config == null) {
        _cachedIsOfficial = true;
        return true;
      }
      final isOfficial = config['deploymentMode'] != '3p';
      _cachedIsOfficial = isOfficial;
      return isOfficial;
    } catch (e) {
      return true;
    }
  }

  /// 切换回官方配置
  ///
  ///   1. claude_desktop_config.json → deploymentMode: "1p"
  ///   2. 删除 Profile 文件
  ///   3. 更新 meta.json 移除 Profile 条目
  Future<bool> switchToOfficial() async {
    try {
      await backupConfig();

      // 1. 读取/创建 claude_desktop_config.json
      final config = await readConfig() ?? <String, dynamic>{};
      config['deploymentMode'] = '1p';
      config.remove('configLibraryReference');

      // 清理旧的 key-core-env MCP 条目
      if (config.containsKey('mcpServers')) {
        final mcpServers = config['mcpServers'] as Map<String, dynamic>;
        mcpServers.remove('key-core-env');
      }

      // 2. 删除 Profile 文件
      final profilePath = await _getProfilePath();
      final profileFile = File(profilePath);
      if (await profileFile.exists()) {
        await profileFile.delete();
      }

      // 删除 3p configLibrary/claude_desktop_config.json
      final libraryDir = await PlatformConfigPathService.getClaudeDesktop3pConfigLibraryDir();
      final threepConfigPath = path.join(libraryDir, 'claude_desktop_config.json');
      final threepConfigFile = File(threepConfigPath);
      if (await threepConfigFile.exists()) {
        await threepConfigFile.delete();
      }

      // 覆盖其他工具残留的 _meta.json 和 profile，防止干扰官方配置
      final staleMetaPath = path.join(libraryDir, '_meta.json');
      final staleMetaFile = File(staleMetaPath);
      if (await staleMetaFile.exists()) {
        try {
          await staleMetaFile.writeAsString('{}');
        } catch (_) {}
      }
      final staleProfilePath = path.join(libraryDir, 'd808fcc1-9179-4599-aa44-003947430bdd.json');
      final staleProfileFile = File(staleProfilePath);
      if (await staleProfileFile.exists()) {
        try {
          await staleProfileFile.writeAsString('{}');
        } catch (_) {}
      }

      // 3. 更新 meta.json 移除条目
      final metaPath = await _getMetaPath();
      final metaFile = File(metaPath);
      if (await metaFile.exists()) {
        try {
          final content = await metaFile.readAsString();
          final meta = jsonDecode(content);
          if (meta is Map) {
            meta.remove('appliedId');
            final entries = meta['entries'];
            if (entries is List) {
              entries.removeWhere((e) =>
                  (e is Map && e['id'] == _profileId));
              if (entries.isEmpty) {
                meta.remove('entries');
              }
            }
            await metaFile.writeAsString(
              const JsonEncoder.withIndent('  ').convert(meta),
            );
          }
        } catch (e) {
          // meta.json 损坏或不存在的处理 — 可以忽略
        }
      }

      final configPath = await _getConfigFilePath();
      final configFile = File(configPath);
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(config),
      );

      _cachedIsOfficial = null;
      print('ClaudeDesktopConfigService: 已切换回官方配置');
      return true;
    } catch (e) {
      print('ClaudeDesktopConfigService: 切换官方配置失败: $e');
      return false;
    }
  }
}
