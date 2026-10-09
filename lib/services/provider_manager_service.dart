import 'dart:async';
import 'dart:convert';
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
      print('加载供应商预设失败: $e');
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
        print('解析供应商失败: $e');
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
        print('解析供应商失败: $e');
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
        print('解析供应商失败: $e');
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
      print('解析供应商失败: $e');
      return null;
    }
  }

  /// 保存或更新供应商
  Future<void> saveProvider(Provider provider) async {
    final map = provider.toMap();
    
    // 加密 API Key
    if (provider.apiKey != null && provider.apiKey!.isNotEmpty) {
      // 检查是否设置了主密码
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword) {
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey != null) {
          final encrypted = await _cryptService.encrypt(provider.apiKey!, encryptionKey);
          map['api_key_encrypted'] = encrypted;
          map['api_key_nonce'] = ''; // GCM 模式的 nonce 包含在加密数据中
        }
      } else {
        // 如果没有设置主密码，使用明文存储（安全性较低）
        map['api_key_encrypted'] = provider.apiKey;
        map['api_key_nonce'] = '';
      }
    }
    
    // 移除明文 API Key
    map.remove('api_key');

    await _dbService.insertOrUpdateProvider(map);
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
        print('解析供应商失败: $e');
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
        
        // 检查是否设置了主密码
        final hasPassword = await _authService.hasMasterPassword();
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
        print('解密 API Key 失败: $e');
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
        print('解析模型列表失败: $e');
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
        print('解析工具列表失败: $e');
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
    print('发现 ${presets.length} 个预设供应商');

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
          print('导入预设供应商: ${provider.name}');
        } catch (e) {
          print('导入预设供应商失败 ${preset.name}: $e');
        }
      }
    }
  }

  /// 清除缓存
  void clearCache() {
    _presets = null;
  }
}
