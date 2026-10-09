import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/ai_key.dart';
import '../services/auth_service.dart';
import '../services/crypt_service.dart';
import '../services/settings_service.dart';
import '../services/platform_config_path_service.dart';
import '../models/mcp_server.dart' show AiToolType;
import 'live_config/key_field_floor.dart';
import 'live_config/live_state.dart';
import 'live_config/live_config_writer.dart';

/// Claude 配置服务
/// 管理 ~/.claude/config.json 的读写
class ClaudeConfigService {
  /// 最近一次 switchProvider / switchToOfficial 失败的原因（成功时清空），供 UI 显示失败原因。
  Object? lastSwitchError;

  static const String _configFileName = 'config.json';
  static const String _settingsFileName = 'settings.json';
  
  final AuthService _authService = AuthService();
  final CryptService _cryptService = CryptService();
  final SettingsService _settingsService = SettingsService();

  // 缓存配置目录，避免重复获取和打印日志
  String? _cachedConfigDir;

  /// 获取 Claude 配置目录路径
  /// 优先使用自定义路径，否则使用平台默认路径
  /// macOS/Linux: ~/.claude
  /// Windows: %APPDATA%\.claude
  Future<String> _getConfigDir() async {
    // 如果已缓存，直接返回
    if (_cachedConfigDir != null) {
      return _cachedConfigDir!;
    }

    // 检查是否有自定义路径
    final customDir = _settingsService.getClaudeConfigDir();
    
    // 使用统一的配置路径服务
    final configDir = await PlatformConfigPathService.getClaudeConfigDir(
      customDir: customDir,
    );
    
    // 缓存结果
    _cachedConfigDir = configDir;
    return configDir;
  }

  /// 获取配置文件路径
  Future<String> _getConfigFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _configFileName);
  }

  /// 获取 settings.json 路径
  Future<String> _getSettingsFilePath() async {
    final configDir = await _getConfigDir();
    return path.join(configDir, _settingsFileName);
  }

  /// 检测配置文件是否存在
  /// 返回配置文件路径和是否存在
  /// 如果目录存在但配置文件不存在，会自动创建默认配置文件
  /// 注意：在 App Store 沙盒环境中，如果无法访问目录，dirExists 会返回 false
  Future<Map<String, dynamic>> checkConfigExists() async {
    final configDir = await _getConfigDir();
    final configPath = await _getConfigFilePath();
    final settingsPath = await _getSettingsFilePath();
    
    final configDirObj = Directory(configDir);
    final configFile = File(configPath);
    final settingsFile = File(settingsPath);
    
    // 尝试检查目录和文件是否存在
    // 在沙盒环境中，如果没有权限访问，exists() 会返回 false（不会抛出异常）
    bool dirExists = false;
    bool configExists = false;
    bool settingsExists = false;
    
    try {
      dirExists = await configDirObj.exists();
      if (dirExists) {
        configExists = await configFile.exists();
        settingsExists = await settingsFile.exists();
      }
    } catch (e) {
      // 如果访问被拒绝（沙盒权限问题），dirExists 保持为 false
      // 这不会抛出异常，exists() 方法会返回 false
    }
    
    // 如果目录存在但配置文件不存在，自动创建默认配置文件
    if (dirExists && !configExists && !settingsExists) {
      print('ClaudeConfigService: 检测到目录存在但配置文件不存在，自动创建默认配置文件');
      await ensureConfigFilesIfDirExists();
      // 重新检查文件是否存在
      final configExistsAfter = await configFile.exists();
      final settingsExistsAfter = await settingsFile.exists();
      return {
        'configDir': configDir,
        'configPath': configPath,
        'settingsPath': settingsPath,
        'configExists': configExistsAfter,
        'settingsExists': settingsExistsAfter,
        'anyExists': configExistsAfter || settingsExistsAfter,
      };
    }
    
    return {
      'configDir': configDir,
      'configPath': configPath,
      'settingsPath': settingsPath,
      'configExists': configExists,
      'settingsExists': settingsExists,
      'anyExists': configExists || settingsExists,
    };
  }

  /// 如果目录存在但配置文件不存在，创建默认配置文件
  Future<bool> ensureConfigFilesIfDirExists() async {
    try {
      final configDir = await _getConfigDir();
      final configDirObj = Directory(configDir);
      
      // 检查目录是否存在
      if (!await configDirObj.exists()) {
        print('ClaudeConfigService: 配置目录不存在，跳过创建配置文件');
        return false;
      }
      
      final configPath = await _getConfigFilePath();
      final settingsPath = await _getSettingsFilePath();
      
      final configFile = File(configPath);
      final settingsFile = File(settingsPath);
      
      // 如果配置文件已存在，不创建
      if (await configFile.exists() || await settingsFile.exists()) {
        print('ClaudeConfigService: 配置文件已存在，跳过创建');
        return false;
      }
      
      // 创建默认的 config.json
      final defaultConfig = <String, dynamic>{};
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultConfig),
      );
      print('ClaudeConfigService: 创建默认 config.json: $configPath');
      
      // 创建默认的 settings.json
      final defaultSettings = <String, dynamic>{
        'env': <String, dynamic>{},
      };
      await settingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(defaultSettings),
      );
      print('ClaudeConfigService: 创建默认 settings.json: $settingsPath');
      
      return true;
    } catch (e) {
      print('ClaudeConfigService: 创建默认配置文件失败: $e');
      return false;
    }
  }

  /// 读取配置文件
  Future<Map<String, dynamic>?> readConfig() async {
    try {
      final configPath = await _getConfigFilePath();
      final file = File(configPath);
      
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 读取 settings.json
  Future<Map<String, dynamic>?> readSettings() async {
    try {
      final settingsPath = await _getSettingsFilePath();
      final file = File(settingsPath);
      
      if (!await file.exists()) {
        return null;
      }

      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      
      // 确保返回的是 Map 类型
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        // 处理 Map<dynamic, dynamic> 的情况
        return Map<String, dynamic>.from(decoded);
      }
      
      return null;
    } catch (e) {
      print('读取 settings.json 失败: $e');
      return null;
    }
  }

  /// 写入配置（切换使用的密钥）
  ///
  /// 经 [LiveConfigWriter] 一次性提交 settings.json 与 config.json：
  /// - 只改关键字段（[KeyFieldFloor.claudeKeysClearedOnSwitch]），其余键与顺序保持不变；
  /// - 任一文件解析失败则中止，不会以空对象覆盖用户配置；
  /// - 原子写入、自动备份，文件权限 0600。
  Future<bool> switchProvider(AIKey key) async {
    lastSwitchError = null;
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

      final settingsPath = await _getSettingsFilePath();
      final configPath = await _getConfigFilePath();
      final statePath = await LiveState.path();
      final previous = await _readLiveState(statePath);
      var written = <String, dynamic>{};

      await LiveConfigWriter.instance.apply(AiToolType.claudecode, [
        LiveEdit.json(
          settingsPath,
          (settings) => written = applyProviderToSettings(settings, key, apiKey, previous: previous),
          containsSecrets: true,
        ),
        LiveEdit(statePath, (current) => LiveState.edit(statePath, _liveStateTool, written).transform(current),
            containsSecrets: true),
        // primaryApiKey 用于 VS Code 插件联动
        LiveEdit.json(
          configPath,
          (config) {
            config['primaryApiKey'] = apiKey;
          },
          containsSecrets: true,
        ),
      ]);

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      lastSwitchError = e;
      print('ClaudeConfigService: 切换配置失败: $e');
      return false;
    }
  }

  static const String _liveStateTool = 'claudecode';

  Future<Map<String, dynamic>> _readLiveState(String statePath) async {
    try {
      final f = File(statePath);
      if (!await f.exists()) return {};
      return LiveState.readSection(await f.readAsString(), _liveStateTool);
    } catch (_) {
      return {};
    }
  }

  /// 移除上一把密钥写入、且值未被用户改动的供应商专属 env
  static void _removePreviousExtraEnv(Map<String, dynamic> env, Map<String, dynamic> previous) {
    final prevEnv = previous['extraEnv'];
    if (prevEnv is! Map) return;
    prevEnv.forEach((k, v) {
      if (env[k] == v) env.remove(k);
    });
  }

  /// 把密钥的关键字段写入 settings.json 文档（纯函数，便于测试）。
  ///
  /// 先清空 Key Core 拥有的关键字段，再写入该密钥的值；`env` 中的其他变量与
  /// 顶层其他键保持不变。
  ///
  /// - 密钥写入 [AIKey.claudeCodeApiKeyField]（缺省 `ANTHROPIC_AUTH_TOKEN`，部分供应商为
  ///   `ANTHROPIC_API_KEY` / `AWS_BEARER_TOKEN_BEDROCK`）；
  /// - [AIKey.claudeCodeExtraEnv] 为供应商专属 env：切入时写入；[previous] 记录上一把密钥
  ///   写入的值，切走时只删除值未被改动过的（借鉴 CC Switch `CLAUDE_EXCLUSIVE_ENV`）。
  ///
  /// 返回需要记入 live-state 的内容。
  static Map<String, dynamic> applyProviderToSettings(
    Map<String, dynamic> settings,
    AIKey key,
    String apiKey, {
    Map<String, dynamic> previous = const {},
  }) {
    final env = _ensureEnv(settings);

    final keyField = KeyFieldFloor.claudeApiKeyFields.contains(key.claudeCodeApiKeyField)
        ? key.claudeCodeApiKeyField
        : KeyFieldFloor.claudeAuthToken;

    _removePreviousExtraEnv(env, previous);
    for (final k in KeyFieldFloor.claudeKeysClearedOnSwitch) {
      // 本次要写入的密钥字段原地覆盖，保持用户文件中的键顺序
      if (k != keyField) env.remove(k);
    }
    env[keyField] = apiKey;

    final extra = <String, String>{};
    key.claudeCodeExtraEnv.forEach((k, v) {
      // 关键字段由上面的逻辑负责，不允许通过额外 env 覆盖
      if (KeyFieldFloor.claudeApiKeyFields.contains(k) || k == KeyFieldFloor.claudeBaseUrl) return;
      if (KeyFieldFloor.claudeModelKeys.contains(k) && (env[k] != null)) return;
      if (v.isEmpty) return;
      env[k] = v;
      extra[k] = v;
    });

    final values = <String, String?>{
      KeyFieldFloor.claudeBaseUrl: key.claudeCodeBaseUrl,
      'ANTHROPIC_MODEL': key.claudeCodeModel,
      'ANTHROPIC_DEFAULT_HAIKU_MODEL': key.claudeCodeHaikuModel,
      'ANTHROPIC_DEFAULT_SONNET_MODEL': key.claudeCodeSonnetModel,
      'ANTHROPIC_DEFAULT_OPUS_MODEL': key.claudeCodeOpusModel,
    };
    values.forEach((name, value) {
      if (value != null && value.isNotEmpty) env[name] = value;
    });

    return {
      if (keyField != KeyFieldFloor.claudeAuthToken) 'apiKeyField': keyField,
      if (extra.isNotEmpty) 'extraEnv': extra,
    };
  }

  /// 取得 settings.json 中的 env 对象（不存在或类型不对时新建）
  static Map<String, dynamic> _ensureEnv(Map<String, dynamic> settings) {
    final raw = settings['env'];
    if (raw is Map<String, dynamic>) return raw;
    final env = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    settings['env'] = env;
    return env;
  }

  /// 备份当前配置
  ///
  /// 保留该方法以兼容调用方。备份现在由 [LiveConfigWriter] 在每次写入前自动完成
  /// （首写备份 + 带时间戳的滚动备份，位于 `~/.keycore/backups/live`），
  /// 不再生成会被反复覆盖的单份 `.bak` 文件。
  Future<bool> backupConfig() async => true;

  /// 获取当前使用的 API Key
  /// 优先从 settings.json 的 env.ANTHROPIC_AUTH_TOKEN 读取
  /// 如果没有，则尝试从 config.json 的 primaryApiKey 读取
  Future<String?> getCurrentApiKey() async {
    try {
      // 首先尝试从 settings.json 读取
      final settings = await readSettings();
      if (settings != null) {
        final env = settings['env'];
        if (env != null && env is Map) {
          final envMap = env as Map<String, dynamic>;
          // 尝试 ANTHROPIC_AUTH_TOKEN
          var apiKey = envMap['ANTHROPIC_AUTH_TOKEN'] as String?;
          // 如果没有，尝试 ANTHROPIC_API_KEY（兼容性）
          if ((apiKey == null || apiKey.isEmpty) && envMap.containsKey('ANTHROPIC_API_KEY')) {
            apiKey = envMap['ANTHROPIC_API_KEY'] as String?;
          }
          if ((apiKey == null || apiKey.isEmpty) &&
              envMap.containsKey(KeyFieldFloor.claudeBedrockBearerToken)) {
            apiKey = envMap[KeyFieldFloor.claudeBedrockBearerToken] as String?;
          }
          
          if (apiKey != null && apiKey.isNotEmpty) {
            // 清理 API Key（去除首尾空白）
            apiKey = apiKey.trim();
            return apiKey;
          }
        }
      }
      
      // 如果 settings.json 中没有，尝试从 config.json 读取 primaryApiKey
      final config = await readConfig();
      if (config != null) {
        final primaryApiKey = config['primaryApiKey'] as String?;
        if (primaryApiKey != null && primaryApiKey.isNotEmpty && primaryApiKey != 'any') {
          final apiKey = primaryApiKey.trim();
          return apiKey;
        }
      }
      
      print('ClaudeConfigService: 未找到 API Key');
      return null;
    } catch (e) {
      print('ClaudeConfigService: 获取 API Key 失败: $e');
      return null;
    }
  }

  /// 判断当前是否是官方配置
  /// 官方配置的特征：没有 ANTHROPIC_BASE_URL 或 ANTHROPIC_BASE_URL 为空
  // 缓存官方配置检查结果，避免重复读取文件
  bool? _cachedIsOfficial;
  DateTime? _cachedIsOfficialTime;
  static const _cacheTimeout = Duration(seconds: 5); // 缓存5秒

  Future<bool> isOfficialConfig() async {
    // 检查缓存是否有效
    if (_cachedIsOfficial != null && 
        _cachedIsOfficialTime != null &&
        DateTime.now().difference(_cachedIsOfficialTime!) < _cacheTimeout) {
      return _cachedIsOfficial!;
    }

    try {
      final settings = await readSettings();
      if (settings == null) {
        _cachedIsOfficial = true; // 没有配置文件，视为官方配置
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }
      
      final env = settings['env'];
      if (env == null || env is! Map) {
        _cachedIsOfficial = true;
        _cachedIsOfficialTime = DateTime.now();
        return _cachedIsOfficial!;
      }
      
      final envMap = env as Map<String, dynamic>;
      
      // 如果没有设置 ANTHROPIC_BASE_URL，或者为空，则认为是官方配置
      final baseUrl = envMap['ANTHROPIC_BASE_URL'] as String?;
      final isOfficial = baseUrl == null || baseUrl.isEmpty;
      
      // 缓存结果
      _cachedIsOfficial = isOfficial;
      _cachedIsOfficialTime = DateTime.now();
      
      return isOfficial;
    } catch (e) {
      // 出错时返回 false，不缓存错误结果
      return false;
    }
  }

  /// 清除官方配置缓存（在配置更新后调用）
  void _clearOfficialConfigCache() {
    _cachedIsOfficial = null;
    _cachedIsOfficialTime = null;
  }

  /// 切换回官方配置
  /// 清除第三方密钥的模型配置、密钥配置、URL配置
  /// 如果本地存储有官方API Key，则写入；没有则清空
  Future<bool> switchToOfficial() async {
    lastSwitchError = null;
    try {
      // 确保 SettingsService 已初始化（官方 API Key 存于系统钥匙串）
      await _settingsService.init();
      final officialApiKey = _settingsService.getOfficialClaudeApiKey();

      final settingsPath = await _getSettingsFilePath();
      final configPath = await _getConfigFilePath();
      final statePath = await LiveState.path();
      final previous = await _readLiveState(statePath);

      await LiveConfigWriter.instance.apply(AiToolType.claudecode, [
        LiveEdit.json(
          settingsPath,
          (settings) => applyOfficialToSettings(settings, officialApiKey, previous: previous),
          containsSecrets: true,
        ),
        LiveState.edit(statePath, _liveStateTool, const {}),
        LiveEdit.json(
          configPath,
          (config) {
            if (officialApiKey != null && officialApiKey.isNotEmpty) {
              config['primaryApiKey'] = officialApiKey;
            } else {
              config.remove('primaryApiKey');
            }
          },
          containsSecrets: true,
        ),
      ]);

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      lastSwitchError = e;
      print('ClaudeConfigService: 切换官方配置失败: $e');
      return false;
    }
  }

  /// 官方模式下 settings.json 的关键字段（纯函数，便于测试）
  ///
  /// 与以往行为一致：移除地址、模型与第三方密钥，有官方 Key 时写入 ANTHROPIC_AUTH_TOKEN；
  /// 用户在官方配置中自定义的其他 env 变量保持不变。
  static void applyOfficialToSettings(
    Map<String, dynamic> settings,
    String? officialApiKey, {
    Map<String, dynamic> previous = const {},
  }) {
    final env = _ensureEnv(settings);
    for (final k in KeyFieldFloor.claudeOfficialManagedKeys) {
      env.remove(k);
    }
    // 上一把第三方密钥若写在 ANTHROPIC_API_KEY / AWS_BEARER_TOKEN_BEDROCK，切回官方必须清除，
    // 否则 Claude Code 会拿第三方密钥请求官方地址
    final prevField = previous['apiKeyField'];
    if (prevField is String && KeyFieldFloor.claudeApiKeyFields.contains(prevField)) {
      env.remove(prevField);
    }
    _removePreviousExtraEnv(env, previous);
    if (officialApiKey != null && officialApiKey.isNotEmpty) {
      env[KeyFieldFloor.claudeAuthToken] = officialApiKey;
    }
  }

  /// 更新官方配置的 env 环境变量
  /// [envVars] 要更新的环境变量映射，如果值为空字符串则删除该变量
  /// API Key保存到系统钥匙串，env配置直接写入到settings.json（不管当前是否是官方配置）
  /// 只修改env配置，不修改密钥、URL、模型配置，不执行切换操作
  Future<bool> updateOfficialConfigEnv(Map<String, String> envVars) async {
    try {
      // 确保 SettingsService 已初始化
      await _settingsService.init();

      // 1. 保存API Key到系统钥匙串
      if (envVars.containsKey(KeyFieldFloor.claudeAuthToken)) {
        final apiKey = envVars[KeyFieldFloor.claudeAuthToken]!.trim();
        await _settingsService.setOfficialClaudeApiKey(apiKey.isEmpty ? null : apiKey);
        // 从envVars中移除，避免写入到settings.json（API Key只在切换时写入）
        envVars.remove(KeyFieldFloor.claudeAuthToken);
      }

      final settingsPath = await _getSettingsFilePath();
      await LiveConfigWriter.instance.updateJson(
        AiToolType.claudecode,
        settingsPath,
        (settings) => applyOfficialEnvEdits(settings, envVars),
        containsSecrets: true,
      );

      // 清除官方配置缓存
      _clearOfficialConfigCache();

      return true;
    } catch (e) {
      print('ClaudeConfigService: 更新官方配置失败: $e');
      return false;
    }
  }

  /// 用表单中的自定义 env 变量替换 settings.json 中的自定义变量（纯函数，便于测试）。
  ///
  /// 关键字段（密钥、地址、模型）保持原值不动；表单里没有的自定义变量被删除；
  /// 值为空字符串的变量被删除。
  static void applyOfficialEnvEdits(Map<String, dynamic> settings, Map<String, String> envVars) {
    final env = _ensureEnv(settings);
    bool isManaged(String key) => KeyFieldFloor.claudeOfficialManagedKeys.contains(key);

    final keep = <String>{};
    envVars.forEach((key, value) {
      if (isManaged(key)) return;
      if (value.isEmpty) {
        env.remove(key);
      } else {
        env[key] = value;
        keep.add(key);
      }
    });

    env.removeWhere((key, _) => !isManaged(key) && !keep.contains(key));
  }
}

