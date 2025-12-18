import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/model_info.dart';
import '../models/ai_key.dart';

/// 密钥缓存服务
/// 用于缓存模型列表、余额数据和校验状态
class KeyCacheService {
  static const String _modelsPrefix = 'key_models_';
  static const String _balancePrefix = 'key_balance_';
  static const String _validationPrefix = 'key_validation_';
  static const String _cacheTimestampPrefix = 'key_cache_timestamp_';

  /// 获取缓存键（基于密钥ID）
  String _getModelsKey(int? keyId) => '$_modelsPrefix${keyId ?? 0}';
  String _getBalanceKey(int? keyId) => '$_balancePrefix${keyId ?? 0}';
  String _getValidationKey(int? keyId) => '$_validationPrefix${keyId ?? 0}';
  String _getTimestampKey(int? keyId) => '$_cacheTimestampPrefix${keyId ?? 0}';

  /// 保存模型列表到缓存
  Future<void> saveModelList(AIKey key, List<ModelInfo> models) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      final modelsJson = models.map((m) => m.toJson()).toList();
      await prefs.setString(_getModelsKey(keyId), jsonEncode(modelsJson));
      await prefs.setInt(_getTimestampKey(keyId), DateTime.now().millisecondsSinceEpoch);
      print('KeyCacheService: 已缓存模型列表，密钥ID: $keyId, 模型数量: ${models.length}');
    } catch (e) {
      print('KeyCacheService: 保存模型列表失败: $e');
    }
  }

  /// 从缓存读取模型列表
  Future<List<ModelInfo>?> getModelList(AIKey key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      final modelsJsonStr = prefs.getString(_getModelsKey(keyId));
      if (modelsJsonStr == null) {
        return null;
      }
      final modelsJson = jsonDecode(modelsJsonStr) as List;
      final models = modelsJson.map((json) => ModelInfo.fromJson(json as Map<String, dynamic>)).toList();
      return models;
    } catch (e) {
      print('KeyCacheService: 读取模型列表失败: $e');
      return null;
    }
  }

  /// 保存余额到缓存
  Future<void> saveBalance(AIKey key, Map<String, dynamic> balanceData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      await prefs.setString(_getBalanceKey(keyId), jsonEncode(balanceData));
      await prefs.setInt(_getTimestampKey(keyId), DateTime.now().millisecondsSinceEpoch);
      print('KeyCacheService: 已缓存余额，密钥ID: $keyId');
    } catch (e) {
      print('KeyCacheService: 保存余额失败: $e');
    }
  }

  /// 从缓存读取余额
  Future<Map<String, dynamic>?> getBalance(AIKey key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      final balanceJsonStr = prefs.getString(_getBalanceKey(keyId));
      if (balanceJsonStr == null) {
        return null;
      }
      final balanceData = jsonDecode(balanceJsonStr) as Map<String, dynamic>;
      return balanceData;
    } catch (e) {
      print('KeyCacheService: 读取余额失败: $e');
      return null;
    }
  }

  /// 保存校验状态到缓存
  Future<void> saveValidationStatus(AIKey key, bool isValidated) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      await prefs.setBool(_getValidationKey(keyId), isValidated);
      await prefs.setInt(_getTimestampKey(keyId), DateTime.now().millisecondsSinceEpoch);
      print('KeyCacheService: 已缓存校验状态，密钥ID: $keyId, 状态: $isValidated');
    } catch (e) {
      print('KeyCacheService: 保存校验状态失败: $e');
    }
  }

  /// 从缓存读取校验状态
  Future<bool?> getValidationStatus(AIKey key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      final isValidated = prefs.getBool(_getValidationKey(keyId));
      return isValidated;
    } catch (e) {
      print('KeyCacheService: 读取校验状态失败: $e');
      return null;
    }
  }

  /// 清除指定密钥的缓存
  Future<void> clearCache(AIKey key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      await prefs.remove(_getModelsKey(keyId));
      await prefs.remove(_getBalanceKey(keyId));
      await prefs.remove(_getValidationKey(keyId));
      await prefs.remove(_getTimestampKey(keyId));
      print('KeyCacheService: 已清除缓存，密钥ID: $keyId');
    } catch (e) {
      print('KeyCacheService: 清除缓存失败: $e');
    }
  }

  /// 获取缓存时间戳
  Future<DateTime?> getCacheTimestamp(AIKey key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyId = key.id ?? 0;
      final timestamp = prefs.getInt(_getTimestampKey(keyId));
      if (timestamp == null) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      print('KeyCacheService: 读取缓存时间戳失败: $e');
      return null;
    }
  }
}



