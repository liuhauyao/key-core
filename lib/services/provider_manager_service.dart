import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/provider.dart';
import '../services/database_service.dart';
import '../services/crypt_service.dart';
import '../services/auth_service.dart';

/// 供应商管理服务
class ProviderManagerService {
  static ProviderManagerService? _instance;
  static List<Provider>? _presets;
  
  final DatabaseService _dbService = DatabaseService.instance;
  final CryptService _cryptService = CryptService();
  final AuthService _authService = AuthService();

  ProviderManagerService._();

  static ProviderManagerService get instance {
    _instance ??= ProviderManagerService._();
    return _instance!;
  }

  /// 加载预设供应商
  Future<List<Provider>> loadPresets() async {
    if (_presets != null) {
      return _presets!;
    }

    try {
      final String jsonStr = await rootBundle.loadString(
        'assets/config/provider_presets.json',
      );
      final Map<String, dynamic> jsonData = json.decode(jsonStr);
      final List<dynamic> providersJson = jsonData['providers'] as List<dynamic>;

      _presets = providersJson
          .map((json) => Provider.fromJson(json as Map<String, dynamic>))
          .toList();

      return _presets!;
    } catch (e) {
      debugPrint('加载供应商预设失败: $e');
      return [];
    }
  }

  /// 获取所有供应商（包括预设和用户自定义）
  Future<List<Provider>> getAllProviders() async {
    final dbProviders = await _dbService.getAllProviders();
    final List<Provider> providers = [];

    for (final map in dbProviders) {
      try {
        final provider = await _mapToProvider(map);
        providers.add(provider);
      } catch (e) {
        debugPrint('解析供应商失败: $e');
      }
    }

    return providers;
  }

  /// 获取活跃的供应商
  Future<List<Provider>> getActiveProviders() async {
    final dbProviders = await _dbService.getActiveProviders();
    final List<Provider> providers = [];

    for (final map in dbProviders) {
      try {
        final provider = await _mapToProvider(map);
        providers.add(provider);
      } catch (e) {
        debugPrint('解析供应商失败: $e');
      }
    }

    return providers;
  }

  /// 根据工具类型获取供应商
  Future<List<Provider>> getProvidersByTool(String tool) async {
    final dbProviders = await _dbService.getProvidersByTool(tool);
    final List<Provider> providers = [];

    for (final map in dbProviders) {
      try {
        final provider = await _mapToProvider(map);
        providers.add(provider);
      } catch (e) {
        debugPrint('解析供应商失败: $e');
      }
    }

    return providers;
  }

  /// 根据 ID 获取供应商
  Future<Provider?> getProviderById(String id) async {
    final map = await _dbService.getProviderById(id);
    if (map == null) return null;

    try {
      return await _mapToProvider(map);
    } catch (e) {
      debugPrint('解析供应商失败: $e');
      return null;
    }
  }

  /// API Key 是否会以主密码加密存储（未设置主密码时为明文存储，与密钥包行为一致）
  Future<bool> isEncryptionEnabled() => _authService.hasMasterPassword();

  /// 把 Provider 转为可直接写入 providers 表的 map（纯函数，便于测试）
  ///
  /// - `models` / `supported_tools` 序列化为 JSON 字符串（sqflite 不支持 List）
  /// - 明文 `api_key` 永远不会写入数据库，只写入 [storedApiKey]
  static Map<String, dynamic> toDbMap(Provider provider, {String? storedApiKey}) {
    final map = provider.toMap();
    map['models'] = json.encode(provider.models.map((m) => m.toMap()).toList());
    map['supported_tools'] = json.encode(provider.supportedTools);
    map.remove('api_key');
    map['api_key_encrypted'] = storedApiKey;
    map['api_key_nonce'] = storedApiKey == null ? null : '';
    return map;
  }

  /// 保存或更新供应商
  ///
  /// 已设置主密码时，API Key 使用主密码派生的密钥以 AES-GCM 加密后存储；
  /// 若设置了主密码但无法获取加密密钥，则拒绝保存，绝不回退为明文。
  Future<void> saveProvider(Provider provider) async {
    String? stored;
    if (provider.apiKey != null && provider.apiKey!.isNotEmpty) {
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword) {
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey == null) {
          throw StateError('无法获取加密密钥，请重新验证主密码后再保存');
        }
        stored = await _cryptService.encrypt(provider.apiKey!, encryptionKey);
      } else {
        // 未设置主密码：与现有密钥包行为一致，以明文存储（界面会给出提示）
        stored = provider.apiKey;
      }
    }

    if (stored == null) {
      // 未提供新 Key（例如仅修改启用状态，或 Key 暂时无法解密）时保留数据库中已有的密文，
      // 避免因为解密失败而把已保存的 Key 覆盖为空
      final existing = await _dbService.getProviderById(provider.id);
      stored = existing?['api_key_encrypted'] as String?;
    }

    await _dbService.insertOrUpdateProvider(toDbMap(provider, storedApiKey: stored));
  }

  /// 首次设置主密码后，把数据库中以明文存储的供应商 API Key 重新加密
  ///
  /// 返回重新加密的数量。与 KeyManagerViewModel.reEncryptAllPlaintextKeys 对应。
  Future<int> reEncryptPlaintextKeys() async {
    if (!await _authService.hasMasterPassword()) return 0;
    final encryptionKey = await _authService.getEncryptionKey();
    if (encryptionKey == null) return 0;
    var count = 0;
    for (final row in await _dbService.getAllProviders()) {
      final value = row['api_key_encrypted'] as String?;
      if (value == null || value.isEmpty || value.startsWith('{')) continue;
      final updated = Map<String, dynamic>.from(row);
      updated['api_key_encrypted'] = await _cryptService.encrypt(value, encryptionKey);
      updated['api_key_nonce'] = '';
      await _dbService.insertOrUpdateProvider(updated);
      count++;
    }
    return count;
  }

  /// 从预设创建供应商
  Future<Provider> createFromPreset(
    String presetId,
    String apiKey, {
    String? customName,
  }) async {
    final presets = await loadPresets();
    final preset = presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => throw Exception('预设供应商不存在: $presetId'),
    );

    final provider = preset.copyWith(
      id: '${preset.id}-${DateTime.now().millisecondsSinceEpoch}',
      name: customName ?? preset.name,
      apiKey: apiKey,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await saveProvider(provider);
    return provider;
  }

  /// 更新供应商活跃状态
  Future<void> updateProviderActive(String id, bool isActive) async {
    await _dbService.updateProviderActive(id, isActive);
  }

  /// 删除供应商
  Future<void> deleteProvider(String id) async {
    await _dbService.deleteProvider(id);
  }

  /// 搜索供应商
  Future<List<Provider>> searchProviders(String keyword) async {
    final dbProviders = await _dbService.searchProviders(keyword);
    final List<Provider> providers = [];

    for (final map in dbProviders) {
      try {
        final provider = await _mapToProvider(map);
        providers.add(provider);
      } catch (e) {
        debugPrint('解析供应商失败: $e');
      }
    }

    return providers;
  }

  /// 从数据库 map 转换为 Provider 对象
  Future<Provider> _mapToProvider(Map<String, dynamic> map) async {
    // 解密 API Key
    String? apiKey;
    if (map['api_key_encrypted'] != null) {
      try {
        final encryptedKey = map['api_key_encrypted'] as String;
        
        // 检查是否设置了主密码；系统安全存储不可用（如 Linux 无 keyring）时，
        // 明文格式仍可读取，加密格式则无法解密
        bool hasPassword;
        try {
          hasPassword = await _authService.hasMasterPassword();
        } catch (_) {
          hasPassword = encryptedKey.startsWith('{');
        }
        if (hasPassword) {
          final encryptionKey = await _authService.getEncryptionKey();
          if (encryptionKey != null) {
            // 检查是否是加密格式（以 { 开头）
            if (encryptedKey.startsWith('{')) {
              apiKey = await _cryptService.decrypt(encryptedKey, encryptionKey);
            } else {
              // 明文格式
              apiKey = encryptedKey;
            }
          }
        } else {
          // 没有主密码，假定是明文
          apiKey = encryptedKey;
        }
      } catch (e) {
        debugPrint('解密 API Key 失败: $e');
      }
    }

    // 解析模型列表
    List<ProviderModel> models = [];
    if (map['models'] != null) {
      try {
        final modelsJson = json.decode(map['models'] as String) as List<dynamic>;
        models = modelsJson
            .map((m) => ProviderModel.fromMap(m as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('解析模型列表失败: $e');
      }
    }

    // 解析支持的工具列表
    List<String> supportedTools = [];
    if (map['supported_tools'] != null) {
      try {
        supportedTools = (json.decode(map['supported_tools'] as String) as List<dynamic>)
            .map((e) => e as String)
            .toList();
      } catch (e) {
        debugPrint('解析工具列表失败: $e');
      }
    }

    return Provider(
      id: map['id'] as String,
      name: map['name'] as String,
      nameZh: map['name_zh'] as String?,
      providerType: map['provider_type'] as String,
      apiEndpoint: map['api_endpoint'] as String?,
      apiKey: apiKey,
      models: models,
      supportedTools: supportedTools,
      region: map['region'] as String?,
      planType: map['plan_type'] as String?,
      iconUrl: map['icon_url'] as String?,
      websiteUrl: map['website_url'] as String?,
      apiKeyUrl: map['api_key_url'] as String?,
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      description: map['description'] as String?,
      isSponsored: (map['is_sponsored'] as int?) == 1,
      family: map['family'] as String?,
    );
  }

  /// 初始化：从预设导入官方供应商（仅在首次使用时）
  Future<void> initializeFromPresets() async {
    final existing = await getAllProviders();
    if (existing.isNotEmpty) {
      return; // 已有供应商，不需要初始化
    }

    final presets = await loadPresets();
    debugPrint('发现 ${presets.length} 个预设供应商');

    // 仅导入官方供应商（不包含 API Key）
    for (final preset in presets) {
      if (preset.providerType == 'official') {
        try {
          final provider = preset.copyWith(
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            isActive: false, // 默认未激活，需要用户添加 API Key
          );
          await saveProvider(provider);
          debugPrint('导入预设供应商: ${provider.name}');
        } catch (e) {
          debugPrint('导入预设供应商失败 ${preset.name}: $e');
        }
      }
    }
  }

  /// 清除缓存
  void clearCache() {
    _presets = null;
  }
}
