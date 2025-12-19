import '../models/ai_key.dart';
import '../models/platform_type.dart';
import '../models/platform_category.dart';
import '../services/database_service.dart';
import '../services/crypt_service.dart';
import '../services/auth_service.dart';
import '../services/clipboard_service.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../services/claude_config_service.dart';
import '../services/codex_config_service.dart';
import '../services/gemini_config_service.dart';
import '../services/settings_service.dart';
import '../services/status_bar_menu_bridge.dart';
import 'dart:io';
import 'base_viewmodel.dart';

/// 密钥管理ViewModel
class KeyManagerViewModel extends BaseViewModel {
  final DatabaseService _databaseService = DatabaseService.instance;
  final CryptService _cryptService = CryptService();
  final AuthService _authService = AuthService();
  final ClipboardService _clipboardService = ClipboardService();
  final ExportService _exportService = ExportService();
  final ImportService _importService = ImportService();
  final ClaudeConfigService _claudeConfigService = ClaudeConfigService();
  final CodexConfigService _codexConfigService = CodexConfigService();
  final GeminiConfigService _geminiConfigService = GeminiConfigService();

  List<AIKey> _allKeys = [];
  List<AIKey> _filteredKeys = [];
  String _searchQuery = '';
  PlatformType? _filterPlatform;
  PlatformCategory? _filterPlatformCategory;
  KeyStatistics? _statistics;

  // 当前使用的密钥ID
  int? _currentClaudeCodeKeyId;
  int? _currentCodexKeyId;
  int? _currentGeminiKeyId;

  List<AIKey> get keys => _filteredKeys;
  List<AIKey> get allKeys => _allKeys; // 暴露所有密钥，用于获取已添加的平台
  String get searchQuery => _searchQuery;
  PlatformType? get filterPlatform => _filterPlatform;
  PlatformCategory? get filterPlatformCategory => _filterPlatformCategory;
  KeyStatistics? get statistics => _statistics;
  
  /// 获取已添加的平台类型列表（去重）
  List<PlatformType> get addedPlatforms {
    final platforms = _allKeys.map((key) => key.platformType).toSet().toList();
    platforms.sort((a, b) => a.value.compareTo(b.value));
    return platforms;
  }

  /// 获取已添加的平台分组列表（去重，根据已添加的平台筛选）
  List<PlatformCategory> get addedPlatformCategories {
    try {
      final categories = <PlatformCategory>{};

      // 遍历所有已添加的平台，收集它们所属的分类
      for (final platform in addedPlatforms) {
        final platformCategories = PlatformCategoryManager.getCategoriesForPlatform(platform);
        categories.addAll(platformCategories);
      }

      // 排除自定义分类
      categories.remove(PlatformCategory.custom);

      // 转换为列表并按枚举值排序
      final result = categories.toList();
      result.sort((a, b) => a.index.compareTo(b.index));
      return result;
    } catch (e) {
      // 如果获取失败，返回空列表
      return [];
    }
  }

  /// 根据当前分组筛选获取可用的平台列表
  List<PlatformType> getAvailablePlatformsForCurrentCategory() {
    if (_filterPlatformCategory == null) {
      // 如果没有选择分组，返回所有已添加的平台
      return addedPlatforms;
    }

    try {
      // 获取当前分组下的所有平台
      final platformsInCategory = PlatformCategoryManager.getPlatformsByCategory(_filterPlatformCategory!);

      // 只返回已添加的平台中属于当前分组的平台
      final addedPlatformsSet = addedPlatforms.toSet();
      return platformsInCategory.where((platform) => addedPlatformsSet.contains(platform)).toList();
    } catch (e) {
      // 如果出错，返回所有已添加的平台
      return addedPlatforms;
    }
  }
  
  /// 重新加密所有明文存储的密钥
  /// 当用户首次设置主密码时，需要将所有明文密钥加密
  Future<bool> reEncryptAllPlaintextKeys() async {
    return await executeAsync(() async {
      final hasPassword = await _authService.hasMasterPassword();
      if (!hasPassword) {
        // 如果没有设置主密码，不需要重新加密
        return true;
      }
      
      final encryptionKey = await _authService.getEncryptionKey();
      if (encryptionKey == null) {
        return false;
      }
      
      int reEncryptedCount = 0;
      
      // 遍历所有密钥
      for (final key in _allKeys) {
        // 检查是否是明文格式（不以{开头）
        if (!key.keyValue.startsWith('{')) {
          try {
            // 加密密钥值
            final encryptedValue = await _cryptService.encrypt(
              key.keyValue,
              encryptionKey,
            );
            
            // 更新数据库
            final updatedKey = key.copyWith(
              keyValue: encryptedValue,
              updatedAt: DateTime.now(),
            );
            await _databaseService.updateKey(updatedKey);
            reEncryptedCount++;
          } catch (e) {
            print('重新加密密钥失败 - ID: ${key.id}, 名称: ${key.name}, 错误: $e');
            // 继续处理其他密钥，不中断整个过程
          }
        }
      }
      
      if (reEncryptedCount > 0) {
        // 重新加载列表
        await loadKeys();
        print('已重新加密 $reEncryptedCount 个明文密钥');
      }
      
      return true;
    }) ?? false;
  }

  /// 初始化
  Future<void> init() async {
    // 如果数据已经加载过，就不需要重新加载，避免页面闪烁
    if (_allKeys.isEmpty) {
      // 首次加载时也不显示加载状态，避免页面闪烁
      await loadKeys(showLoading: false);
    }
  }

  /// 加载所有密钥
  Future<void> loadKeys({bool showLoading = true}) async {
    await executeAsync(() async {
      _allKeys = await _databaseService.getAllKeys();
      _updateFilteredKeys();
      await _updateStatistics();
    }, showLoading: showLoading);
  }

  /// 刷新密钥列表
  Future<void> refresh() async {
    await loadKeys();
  }

  /// 设置搜索查询
  void setSearchQuery(String query) {
    _searchQuery = query;
    _updateFilteredKeys();
    notifyListeners();
  }

  /// 设置平台筛选
  void setPlatformFilter(PlatformType? platform) {
    _filterPlatform = platform;

    // 如果选择了特定平台，需要检查是否与当前平台分组兼容
    if (platform != null && _filterPlatformCategory != null) {
      final platformsInCategory = PlatformCategoryManager.getPlatformsByCategory(_filterPlatformCategory!);
      if (!platformsInCategory.contains(platform)) {
        // 如果平台不属于当前选中的分组，则清除分组筛选
        _filterPlatformCategory = null;
      }
    }

    _updateFilteredKeys();
    notifyListeners();
  }

  /// 设置平台分组筛选
  void setPlatformCategoryFilter(PlatformCategory? category) {
    _filterPlatformCategory = category;
    // 当选择平台分组时，如果当前选中的平台不属于该分组，则清除平台筛选
    if (category != null && _filterPlatform != null) {
      final platformsInCategory = PlatformCategoryManager.getPlatformsByCategory(category);
      if (!platformsInCategory.contains(_filterPlatform)) {
        _filterPlatform = null; // 清除平台筛选
      }
    }
    _updateFilteredKeys();
    notifyListeners();
  }

  /// 更新筛选后的密钥列表
  void _updateFilteredKeys() {
    var filtered = _allKeys;

    // 应用搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((key) {
        return key.name.toLowerCase().contains(query) ||
            key.platform.toLowerCase().contains(query) ||
            (key.notes?.toLowerCase().contains(query) ?? false) ||
            key.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }

    // 应用平台分组过滤
    if (_filterPlatformCategory != null) {
      try {
        final platformsInCategory = PlatformCategoryManager.getPlatformsByCategory(_filterPlatformCategory!);
        final categoryPlatformIds = platformsInCategory.map((p) => p.id).toSet();
        filtered = filtered
            .where((key) => categoryPlatformIds.contains(key.platformType.id))
            .toList();
      } catch (e) {
        // 如果获取配置失败，跳过分组过滤
        print('平台分组筛选失败: $e');
      }
    }

    // 应用平台过滤
    if (_filterPlatform != null) {
      filtered = filtered
          .where((key) => key.platformType == _filterPlatform)
          .toList();
    }

    _filteredKeys = filtered;
  }

  /// 重新排序密钥列表
  Future<bool> reorderKeys(List<AIKey> reorderedKeys) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      _filteredKeys = reorderedKeys;
      // 同时更新 _allKeys，保持数据一致性
      // 需要根据当前的筛选条件更新 _allKeys
      final reorderedAllKeys = <AIKey>[];
      final reorderedKeyIds = reorderedKeys.map((k) => k.id).toSet();
      
      // 先添加重新排序的密钥
      reorderedAllKeys.addAll(reorderedKeys);
      
      // 然后添加不在筛选列表中的密钥（保持原有顺序）
      for (final key in _allKeys) {
        if (!reorderedKeyIds.contains(key.id)) {
          reorderedAllKeys.add(key);
        }
      }
      
      _allKeys = reorderedAllKeys;
      notifyListeners();
      
      // 然后在后台更新数据库，不阻塞 UI
      // 使用 DESC 排序，第一个密钥应该有最大的 updated_at
      final now = DateTime.now();
      for (int i = 0; i < reorderedKeys.length; i++) {
        final key = reorderedKeys[i];
        // 创建一个新的时间戳，确保顺序正确
        // 使用微秒来确保每个密钥有不同的时间戳
        // 第一个密钥（i=0）应该有最大的 updated_at，所以用减法
        final updatedAt = now.subtract(Duration(microseconds: i));
        final updatedKey = key.copyWith(updatedAt: updatedAt);
        await _databaseService.updateKey(updatedKey);
      }
      
      return true;
    } catch (e) {
      // 如果更新失败，重新加载数据恢复状态
      await loadKeys();
      return false;
    }
  }

  /// 将密钥移动到顶部（置顶）
  Future<bool> moveKeyToTop(int keyId) async {
    try {
      final keyIndex = _filteredKeys.indexWhere((k) => k.id == keyId);
      if (keyIndex == -1) return false;
      
      // 如果已经在第一位，不需要操作
      if (keyIndex == 0) return true;
      
      // 创建新的排序列表，将目标密钥移到第一位
      final reorderedKeys = List<AIKey>.from(_filteredKeys);
      final key = reorderedKeys.removeAt(keyIndex);
      reorderedKeys.insert(0, key);
      
      // 使用现有的 reorderKeys 方法处理排序
      return await reorderKeys(reorderedKeys);
    } catch (e) {
      return false;
    }
  }

  /// 更新统计信息
  Future<void> _updateStatistics() async {
    _statistics = await _databaseService.getStatistics();
    notifyListeners();
  }

  /// 添加密钥
  Future<bool> addKey(AIKey key) async {
    return await executeAsync(() async {
      String finalKeyValue = key.keyValue;
      
      // 检查是否设置了主密码
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword) {
        // 如果设置了主密码，则加密存储
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey != null) {
          finalKeyValue = await _cryptService.encrypt(
            key.keyValue,
            encryptionKey,
          );
        }
      }
      // 如果没有设置主密码，则明文存储

      // 创建密钥对象
      final finalKey = key.copyWith(
        keyValue: finalKeyValue,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 保存到数据库
      await _databaseService.insertKey(finalKey);

      // 重新加载列表
      await loadKeys();
      return true;
    }) ?? false;
  }

  /// 更新密钥
  Future<bool> updateKey(AIKey key) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      if (key.id == null) {
        setError('密钥ID不能为空');
        return false;
      }

      String finalKeyValue = key.keyValue;
      
      // 检查是否设置了主密码
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword) {
        // 如果设置了主密码，则加密存储
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey != null) {
          // 检查密钥值是否是加密格式（简单检查）
          if (!key.keyValue.startsWith('{')) {
            finalKeyValue = await _cryptService.encrypt(
              key.keyValue,
              encryptionKey,
            );
          } else {
            finalKeyValue = key.keyValue; // 已经是加密格式，保持不变
          }
        }
      }
      // 如果没有设置主密码，则明文存储

      // 创建更新后的密钥对象，保持原有的 updatedAt，不改变排序位置
      // ⚠️ 重要：不要使用 copyWith，因为它会覆盖用户修改的字段！
      // 直接使用从表单返回的 key 对象，只更新加密后的 keyValue
      final updatedKey = AIKey(
        id: key.id,
        name: key.name,
        platform: key.platform,
        platformType: key.platformType,
        managementUrl: key.managementUrl,
        apiEndpoint: key.apiEndpoint,
        keyValue: finalKeyValue,
        keyNonce: key.keyNonce,
        expiryDate: key.expiryDate,
        tags: key.tags,
        notes: key.notes,
        isActive: key.isActive,
        createdAt: key.createdAt,
        updatedAt: key.updatedAt, // 保持原有的 updatedAt，不改变排序位置
        lastUsedAt: key.lastUsedAt,
        isFavorite: key.isFavorite,
        icon: key.icon,
        enableClaudeCode: key.enableClaudeCode,
        claudeCodeApiEndpoint: key.claudeCodeApiEndpoint,
        claudeCodeModel: key.claudeCodeModel,
        claudeCodeHaikuModel: key.claudeCodeHaikuModel,
        claudeCodeSonnetModel: key.claudeCodeSonnetModel,
        claudeCodeOpusModel: key.claudeCodeOpusModel,
        claudeCodeBaseUrl: key.claudeCodeBaseUrl,
        enableCodex: key.enableCodex,
        codexApiEndpoint: key.codexApiEndpoint,
        codexModel: key.codexModel,
        codexBaseUrl: key.codexBaseUrl,
        codexConfig: key.codexConfig,
        enableGemini: key.enableGemini,
        geminiApiEndpoint: key.geminiApiEndpoint,
        geminiModel: key.geminiModel,
        geminiBaseUrl: key.geminiBaseUrl,
        isValidated: key.isValidated,
      );

      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      final allIndex = _allKeys.indexWhere((k) => k.id == key.id);
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == key.id);

      if (allIndex != -1) {
        _allKeys[allIndex] = updatedKey;
      }
      if (filteredIndex != -1) {
        _filteredKeys[filteredIndex] = updatedKey;
      }
      notifyListeners();

      // 然后在后台更新数据库，不阻塞 UI
      await _databaseService.updateKey(updatedKey);

      // 检查该密钥是否是当前激活的密钥，如果是则立即触发配置更新
      await _refreshActiveConfigIfNeeded(updatedKey);
      
      return true;
    } catch (e) {
      // 如果更新失败，重新加载数据恢复状态
      await loadKeys(showLoading: false);
      setError(e.toString());
      return false;
    }
  }

  /// 删除密钥
  Future<bool> deleteKey(int id) async {
    return await executeAsync(() async {
      await _databaseService.secureDeleteKey(id);
      await loadKeys();
      return true;
    }) ?? false;
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(int id, bool isFavorite) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      final allIndex = _allKeys.indexWhere((k) => k.id == id);
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == id);
      
      if (allIndex != -1) {
        _allKeys[allIndex] = _allKeys[allIndex].copyWith(isFavorite: isFavorite);
      }
      if (filteredIndex != -1) {
        _filteredKeys[filteredIndex] = _filteredKeys[filteredIndex].copyWith(isFavorite: isFavorite);
      }
      notifyListeners();

      // 然后在后台更新数据库，不阻塞 UI
      await _databaseService.toggleFavorite(id, isFavorite);
      
      return true;
    } catch (e) {
      // 如果更新失败，重新加载数据恢复状态
      await loadKeys(showLoading: false);
      return false;
    }
  }

  /// 更新校验状态
  Future<bool> updateValidationStatus(int id, bool isValidated) async {
    try {
      // 先检查是否需要更新（避免不必要的 notifyListeners）
      final allIndex = _allKeys.indexWhere((k) => k.id == id);
      if (allIndex == -1) {
        return false;
      }
      
      final currentKey = _allKeys[allIndex];
      if (currentKey.isValidated == isValidated) {
        // 状态没有变化，不需要更新
        return true;
      }
      
      // 更新内存中的列表
      final updatedKey = currentKey.copyWith(isValidated: isValidated);
      _allKeys[allIndex] = updatedKey;
      
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == id);
      if (filteredIndex != -1) {
        _filteredKeys[filteredIndex] = updatedKey;
      }
      
      // 只在状态真正变化时通知监听者
      notifyListeners();

      // 然后在后台更新数据库
      await _databaseService.updateKey(updatedKey);
      
      return true;
    } catch (e) {
      await loadKeys(showLoading: false);
      return false;
    }
  }

  /// 切换激活状态
  Future<bool> toggleActive(int id, bool isActive) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      final allIndex = _allKeys.indexWhere((k) => k.id == id);
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == id);
      
      if (allIndex != -1) {
        _allKeys[allIndex] = _allKeys[allIndex].copyWith(isActive: isActive);
      }
      if (filteredIndex != -1) {
        _filteredKeys[filteredIndex] = _filteredKeys[filteredIndex].copyWith(isActive: isActive);
      }
      notifyListeners();

      // 然后在后台更新数据库，不阻塞 UI
      await _databaseService.toggleActive(id, isActive);
      
      return true;
    } catch (e) {
      // 如果更新失败，重新加载数据恢复状态
      await loadKeys(showLoading: false);
      return false;
    }
  }

  /// 复制密钥到剪贴板
  Future<bool> copyKeyToClipboard(int id) async {
    return await executeAsync(() async {
      final key = await _databaseService.getKeyById(id);
      if (key == null) {
        throw Exception('密钥不存在');
      }

      String decryptedValue;
      
      // 检查是否是加密格式
      final hasPassword = await _authService.hasMasterPassword();
      if (hasPassword && key.keyValue.startsWith('{')) {
        // 加密格式，需要解密
        final encryptionKey = await _authService.getEncryptionKey();
        if (encryptionKey == null) {
          throw Exception('未找到加密密钥');
        }
        decryptedValue = await _cryptService.decrypt(
          key.keyValue,
          encryptionKey,
        );
      } else {
        // 明文格式，直接使用
        decryptedValue = key.keyValue;
      }

      // 复制到剪贴板（带自动清空）
      await _clipboardService.copyWithAutoClear(
        decryptedValue,
        delaySeconds: 30,
      );

      // 更新最后使用时间
      await _databaseService.updateLastUsed(id);
      await loadKeys();

      return true;
    }) ?? false;
  }

  /// 解密密钥值
  Future<String?> decryptKeyValue(String keyValue) async {
    try {
      // 检查是否是加密格式
      if (!keyValue.startsWith('{')) {
        // 明文格式，直接返回
        return keyValue;
      }
      
      // 加密格式，需要解密
      final encryptionKey = await _authService.getEncryptionKey();
      if (encryptionKey == null) {
        return null;
      }
      return await _cryptService.decrypt(keyValue, encryptionKey);
    } catch (e) {
      return null;
    }
  }

  /// 获取密钥详情（解密后）
  Future<AIKey?> getDecryptedKey(int id) async {
    try {
      final key = await _databaseService.getKeyById(id);
      if (key == null) return null;

      final decryptedValue = await decryptKeyValue(key.keyValue);
      if (decryptedValue == null) return key;

      // ⚠️ 重要：不要使用 copyWith，因为它会覆盖其他字段！
      // 如果 keyValue 没有变化，直接返回 key；如果有变化，创建新的 AIKey
      if (decryptedValue == key.keyValue) {
        return key;
      }

      // 创建新的 AIKey，只更新 keyValue
      return AIKey(
        id: key.id,
        name: key.name,
        platform: key.platform,
        platformType: key.platformType,
        managementUrl: key.managementUrl,
        apiEndpoint: key.apiEndpoint,
        keyValue: decryptedValue,
        keyNonce: key.keyNonce,
        expiryDate: key.expiryDate,
        tags: key.tags,
        notes: key.notes,
        isActive: key.isActive,
        createdAt: key.createdAt,
        updatedAt: key.updatedAt,
        lastUsedAt: key.lastUsedAt,
        isFavorite: key.isFavorite,
        icon: key.icon,
        enableClaudeCode: key.enableClaudeCode,
        claudeCodeApiEndpoint: key.claudeCodeApiEndpoint,
        claudeCodeModel: key.claudeCodeModel,
        claudeCodeHaikuModel: key.claudeCodeHaikuModel,
        claudeCodeSonnetModel: key.claudeCodeSonnetModel,
        claudeCodeOpusModel: key.claudeCodeOpusModel,
        claudeCodeBaseUrl: key.claudeCodeBaseUrl,
        enableCodex: key.enableCodex,
        codexApiEndpoint: key.codexApiEndpoint,
        codexModel: key.codexModel,
        codexBaseUrl: key.codexBaseUrl,
        codexConfig: key.codexConfig,
        enableGemini: key.enableGemini,
        geminiApiEndpoint: key.geminiApiEndpoint,
        geminiModel: key.geminiModel,
        geminiBaseUrl: key.geminiBaseUrl,
        isValidated: key.isValidated,
      );
    } catch (e) {
      return null;
    }
  }

  /// 导出密钥
  /// 如果用户设置了主密码，用主密码解密后明文导出
  /// 如果用户没有设置主密码，直接明文导出
  Future<String?> exportKeys(String filePath) async {
    try {
      final result = await executeAsync(() async {
        return await _exportService.exportKeys(filePath);
      });
      return result;
    } catch (e) {
      // 如果 executeAsync 没有捕获到异常，这里捕获
      setError('导出失败: ${e.toString()}');
      return null;
    }
  }

  /// 导入密钥
  /// filePassword: 如果文件是加密的，需要提供解密密码（可选）
  Future<ImportResult> importKeys(String filePath, String? filePassword) async {
    final result = await _importService.importKeys(filePath, filePassword);
    if (result.success) {
      await loadKeys();
    }
    return result;
  }

  /// 获取启用了 ClaudeCode 的密钥列表
  Future<List<AIKey>> getClaudeCodeKeys() async {
    try {
      return await _databaseService.getClaudeCodeKeys();
    } catch (e) {
      return [];
    }
  }

  /// 获取启用了 Codex 的密钥列表
  Future<List<AIKey>> getCodexKeys() async {
    try {
      return await _databaseService.getCodexKeys();
    } catch (e) {
      return [];
    }
  }

  /// 获取启用了 Gemini 的密钥列表
  Future<List<AIKey>> getGeminiKeys() async {
    try {
      return await _databaseService.getGeminiKeys();
    } catch (e) {
      return [];
    }
  }

  /// 切换 ClaudeCode 使用的密钥
  Future<bool> switchClaudeCodeProvider(int keyId) async {
    return await executeAsync(() async {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null || !key.enableClaudeCode) {
        throw Exception('密钥不存在或未启用 ClaudeCode');
      }

      // 备份当前配置
      await _claudeConfigService.backupConfig();

      // 切换配置
      final success = await _claudeConfigService.switchProvider(key);
      if (success) {
        _currentClaudeCodeKeyId = keyId;
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 切换 Codex 使用的密钥
  Future<bool> switchCodexProvider(int keyId) async {
    return await executeAsync(() async {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null || !key.enableCodex) {
        throw Exception('密钥不存在或未启用 Codex');
      }

      // 备份当前配置
      await _codexConfigService.backupConfig();

      // 切换配置
      final success = await _codexConfigService.switchProvider(key);
      if (success) {
        _currentCodexKeyId = keyId;
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 获取当前 ClaudeCode 使用的密钥
  /// 返回 null 表示当前是官方配置
  /// 注意：总是从配置文件重新读取，不使用缓存，以确保外部修改配置后能正确反映
  Future<AIKey?> getCurrentClaudeCodeKey() async {
    // 先检查是否是官方配置
    final isOfficial = await _claudeConfigService.isOfficialConfig();
    if (isOfficial) {
      _currentClaudeCodeKeyId = null; // 官方配置没有对应的密钥ID
      return null;
    }

    // 总是从配置文件重新读取当前使用的 API Key，然后匹配密钥
    // 这样可以确保外部修改配置文件后能正确反映
    final currentApiKey = await _claudeConfigService.getCurrentApiKey();
    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      final keys = await getClaudeCodeKeys();
      
      for (final key in keys) {
        final decryptedValue = await decryptKeyValue(key.keyValue);
        // 如果解密失败，跳过这个密钥
        if (decryptedValue == null || decryptedValue.isEmpty) {
          continue;
        }
        
        // 清理解密后的值（去除首尾空白）
        final cleanedDecryptedValue = decryptedValue.trim();
        final cleanedCurrentApiKey = currentApiKey.trim();
        
        // 精确匹配
        if (cleanedDecryptedValue == cleanedCurrentApiKey) {
          _currentClaudeCodeKeyId = key.id;
          return key;
        }
      }
    }
    
    // 如果没有找到匹配的密钥，清除缓存
    _currentClaudeCodeKeyId = null;
    return null;
  }

  /// 切换回官方 ClaudeCode 配置
  Future<bool> switchToOfficialClaudeCode() async {
    return await executeAsync(() async {
      // 备份当前配置
      await _claudeConfigService.backupConfig();

      // 切换配置
      final success = await _claudeConfigService.switchToOfficial();
      if (success) {
        _currentClaudeCodeKeyId = null; // 官方配置没有对应的密钥ID
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 检查当前是否是官方 ClaudeCode 配置
  Future<bool> isOfficialClaudeCodeConfig() async {
    return await _claudeConfigService.isOfficialConfig();
  }

  /// 更新官方 ClaudeCode 配置的环境变量
  Future<bool> updateOfficialClaudeCodeConfig(Map<String, String> envVars) async {
    return await executeAsync(() async {
      final success = await _claudeConfigService.updateOfficialConfigEnv(envVars);
      if (success) {
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 获取当前 Codex 使用的密钥
  /// 返回 null 表示当前是官方配置
  /// 注意：总是从配置文件重新读取，不使用缓存，以确保外部修改配置后能正确反映
  Future<AIKey?> getCurrentCodexKey() async {
    // 先检查是否是官方配置
    final isOfficial = await _codexConfigService.isOfficialConfig();
    if (isOfficial) {
      _currentCodexKeyId = null; // 官方配置没有对应的密钥ID
      return null;
    }

    // 总是从配置文件重新读取当前使用的 API Key，然后匹配密钥
    // 这样可以确保外部修改配置文件后能正确反映
    final currentApiKey = await _codexConfigService.getCurrentApiKey();
    
    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      // 情况1：使用 auth.json 的供应商（如 OpenAI、代理转发平台）
      final keys = await getCodexKeys();
      
      for (final key in keys) {
        final decryptedValue = await decryptKeyValue(key.keyValue);
        // 如果解密失败，跳过这个密钥
        if (decryptedValue == null || decryptedValue.isEmpty) {
          continue;
        }
        
        // 清理解密后的值（去除首尾空白）
        final cleanedDecryptedValue = decryptedValue.trim();
        final cleanedCurrentApiKey = currentApiKey.trim();
        
        // 精确匹配
        if (cleanedDecryptedValue == cleanedCurrentApiKey) {
          _currentCodexKeyId = key.id;
          return key;
        }
      }
    } else {
      // 情况2：使用环境变量的供应商（如 OpenRouter）
      // 通过解析 config.toml 获取 base_url 来匹配密钥
      final configInfo = await _codexConfigService.getCurrentConfigInfo();
      if (configInfo != null && configInfo.containsKey('base_url')) {
        final baseUrl = configInfo['base_url']!;
        
        final keys = await getCodexKeys();
        
        for (final key in keys) {
          // 通过 base_url 匹配（忽略大小写和尾部斜杠）
          final keyBaseUrl = key.codexBaseUrl?.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
          final configBaseUrl = baseUrl.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');
          
          if (keyBaseUrl != null && keyBaseUrl == configBaseUrl && key.enableCodex) {
            _currentCodexKeyId = key.id;
            return key;
          }
        }
      }
    }
    
    // 如果没有找到匹配的密钥，清除缓存
    _currentCodexKeyId = null;
    return null;
  }

  /// 切换回官方 Codex 配置
  Future<bool> switchToOfficialCodex() async {
    return await executeAsync(() async {
      // 备份当前配置
      await _codexConfigService.backupConfig();

      // 切换配置
      final success = await _codexConfigService.switchToOfficial();
      if (success) {
        _currentCodexKeyId = null; // 官方配置没有对应的密钥ID
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 检查当前是否是官方 Codex 配置
  Future<bool> isOfficialCodexConfig() async {
    return await _codexConfigService.isOfficialConfig();
  }

  /// 更新官方 Codex 配置的 API Key
  /// [apiKey] 官方 Codex API Key，如果为空则清空官方配置
  Future<bool> updateOfficialCodexConfig(String? apiKey) async {
    return await executeAsync(() async {
      // 保存到本地存储
      final settingsService = SettingsService();
      await settingsService.init();
      await settingsService.setOfficialCodexApiKey(apiKey);
      
      // 如果当前是官方配置，需要重新写入配置文件
      final isOfficial = await isOfficialCodexConfig();
      if (isOfficial) {
        // 备份当前配置
        await _codexConfigService.backupConfig();
        
        // 重新切换到官方配置（会读取新的 API Key）
        final success = await _codexConfigService.switchToOfficial();
        if (success) {
          notifyListeners();
          // 通知状态栏菜单更新
          await _notifyStatusBarMenuUpdate();
        }
        return success;
      }
      
      // 如果当前不是官方配置，只保存到本地存储，不修改配置文件
      notifyListeners();
      return true;
    }) ?? false;
  }

  /// 检查密钥是否为当前使用的 ClaudeCode 密钥
  Future<bool> isCurrentClaudeCodeKey(int keyId) async {
    final currentKey = await getCurrentClaudeCodeKey();
    return currentKey?.id == keyId;
  }

  /// 检查密钥是否为当前使用的 Codex 密钥
  Future<bool> isCurrentCodexKey(int keyId) async {
    final currentKey = await getCurrentCodexKey();
    return currentKey?.id == keyId;
  }

  /// 检测 ClaudeCode 配置文件是否存在
  Future<Map<String, dynamic>> checkClaudeCodeConfigExists() async {
    try {
      return await _claudeConfigService.checkConfigExists();
    } catch (e) {
      return {
        'anyExists': false,
        'configExists': false,
        'settingsExists': false,
      };
    }
  }

  /// 检测 Codex 配置文件是否存在
  Future<Map<String, dynamic>> checkCodexConfigExists() async {
    try {
      return await _codexConfigService.checkConfigExists();
    } catch (e) {
      return {
        'anyExists': false,
        'configExists': false,
        'authExists': false,
      };
    }
  }

  /// 切换 Gemini 使用的密钥
  Future<bool> switchGeminiProvider(int keyId) async {
    return await executeAsync(() async {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null || !key.enableGemini) {
        throw Exception('密钥不存在或未启用 Gemini');
      }

      // 备份当前配置
      await _geminiConfigService.backupConfig();

      // 切换配置
      final success = await _geminiConfigService.switchProvider(key);
      if (success) {
        _currentGeminiKeyId = keyId;
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 获取当前 Gemini 使用的密钥
  /// 返回 null 表示当前是官方配置
  Future<AIKey?> getCurrentGeminiKey() async {
    // 先检查是否是官方配置
    final isOfficial = await _geminiConfigService.isOfficialConfig();
    if (isOfficial) {
      _currentGeminiKeyId = null;
      return null;
    }

    // 从配置文件重新读取当前使用的 API Key
    final currentApiKey = await _geminiConfigService.getCurrentApiKey();
    
    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      // 先检查是否匹配官方存储的 API Key
      final settingsService = SettingsService();
      await settingsService.init();
      final officialApiKey = settingsService.getOfficialGeminiApiKey();
      if (officialApiKey != null && officialApiKey.isNotEmpty && currentApiKey.trim() == officialApiKey.trim()) {
        _currentGeminiKeyId = null;
        return null; // 官方配置返回 null
      }
      
      // 如果不匹配官方存储，尝试匹配密钥列表
      final keys = await getGeminiKeys();
      
      for (final key in keys) {
        final decryptedValue = await decryptKeyValue(key.keyValue);
        if (decryptedValue == null || decryptedValue.isEmpty) {
          continue;
        }
        
        final cleanedDecryptedValue = decryptedValue.trim();
        final cleanedCurrentApiKey = currentApiKey.trim();
        
        if (cleanedDecryptedValue == cleanedCurrentApiKey) {
          _currentGeminiKeyId = key.id;
          return key;
        }
      }
      
      // 如果未找到匹配的密钥，但 API Key 存在，可能是官方配置（但官方 API Key 未设置）
      // 这种情况下，应该重新检查是否是官方配置
      final isOfficialRetry = await _geminiConfigService.isOfficialConfig();
      if (isOfficialRetry) {
        _currentGeminiKeyId = null;
        return null;
      }
    }
    
    _currentGeminiKeyId = null;
    return null;
  }

  /// 切换回官方 Gemini 配置
  Future<bool> switchToOfficialGemini() async {
    return await executeAsync(() async {
      // 备份当前配置
      await _geminiConfigService.backupConfig();

      // 切换配置
      final success = await _geminiConfigService.switchToOfficial();
      if (success) {
        _currentGeminiKeyId = null;
        notifyListeners();
        // 通知状态栏菜单更新
        await _notifyStatusBarMenuUpdate();
      }
      return success;
    }) ?? false;
  }

  /// 检查当前是否是官方 Gemini 配置
  Future<bool> isOfficialGeminiConfig() async {
    return await _geminiConfigService.isOfficialConfig();
  }

  /// 更新官方 Gemini 配置的 API Key
  Future<bool> updateOfficialGeminiConfig(String? apiKey) async {
    return await executeAsync(() async {
      // 保存到本地存储
      final settingsService = SettingsService();
      await settingsService.init();
      await settingsService.setOfficialGeminiApiKey(apiKey);
      
      // 如果当前是官方配置，需要重新写入配置文件
      final isOfficial = await isOfficialGeminiConfig();
      if (isOfficial) {
        // 备份当前配置
        await _geminiConfigService.backupConfig();
        
        // 重新切换到官方配置（会读取新的 API Key）
        final success = await _geminiConfigService.switchToOfficial();
        if (success) {
          notifyListeners();
          await _notifyStatusBarMenuUpdate();
        }
        return success;
      }
      
      // 如果当前不是官方配置，只保存到本地存储
      notifyListeners();
      return true;
    }) ?? false;
  }

  /// 检查密钥是否为当前使用的 Gemini 密钥
  Future<bool> isCurrentGeminiKey(int keyId) async {
    final currentKey = await getCurrentGeminiKey();
    return currentKey?.id == keyId;
  }

  /// 检查密钥是否是当前激活的密钥，如果是则刷新配置
  /// 这个方法在更新密钥后调用，确保配置文件与保存后的密钥值保持同步
  Future<void> _refreshActiveConfigIfNeeded(AIKey key) async {
    if (key.id == null) return;
    
    try {
      final keyId = key.id!;
      
      // 检查 ClaudeCode
      // 先检查内存中的 _currentClaudeCodeKeyId，如果匹配则说明该密钥是当前激活的
      // 如果内存中没有，则通过配置文件匹配检查（处理应用刚启动的情况）
      if (key.enableClaudeCode) {
        bool isCurrent = _currentClaudeCodeKeyId == keyId;
        if (!isCurrent) {
          // 如果内存中没有，尝试从配置文件匹配
          isCurrent = await isCurrentClaudeCodeKey(keyId);
        }
        if (isCurrent) {
          print('KeyManagerViewModel: 检测到当前保存的密钥是激活的 ClaudeCode 密钥，立即刷新配置');
          await _claudeConfigService.backupConfig();
          final success = await _claudeConfigService.switchProvider(key);
          if (success) {
            _currentClaudeCodeKeyId = keyId;
            notifyListeners();
            await _notifyStatusBarMenuUpdate();
          }
        }
      }
      
      // 检查 Codex
      // 先检查内存中的 _currentCodexKeyId，如果匹配则说明该密钥是当前激活的
      // 如果内存中没有，则通过配置文件匹配检查（处理应用刚启动的情况）
      if (key.enableCodex) {
        bool isCurrent = _currentCodexKeyId == keyId;
        if (!isCurrent) {
          // 如果内存中没有，尝试从配置文件匹配
          isCurrent = await isCurrentCodexKey(keyId);
        }
        if (isCurrent) {
          print('KeyManagerViewModel: 检测到当前保存的密钥是激活的 Codex 密钥，立即刷新配置');
          await _codexConfigService.backupConfig();
          final success = await _codexConfigService.switchProvider(key);
          if (success) {
            _currentCodexKeyId = keyId;
            notifyListeners();
            await _notifyStatusBarMenuUpdate();
          }
        }
      }
      
      // 检查 Gemini
      // 先检查内存中的 _currentGeminiKeyId，如果匹配则说明该密钥是当前激活的
      // 如果内存中没有，则通过配置文件匹配检查（处理应用刚启动的情况）
      if (key.enableGemini) {
        bool isCurrent = _currentGeminiKeyId == keyId;
        if (!isCurrent) {
          // 如果内存中没有，尝试从配置文件匹配
          isCurrent = await isCurrentGeminiKey(keyId);
        }
        if (isCurrent) {
          print('KeyManagerViewModel: 检测到当前保存的密钥是激活的 Gemini 密钥，立即刷新配置');
          await _geminiConfigService.backupConfig();
          final success = await _geminiConfigService.switchProvider(key);
          if (success) {
            _currentGeminiKeyId = keyId;
            notifyListeners();
            await _notifyStatusBarMenuUpdate();
          }
        }
      }
    } catch (e) {
      // 配置刷新失败不应该影响密钥保存的成功
      print('KeyManagerViewModel: 刷新激活配置失败: $e');
    }
  }

  /// 检测 Gemini 配置文件是否存在
  Future<Map<String, dynamic>> checkGeminiConfigExists() async {
    try {
      return await _geminiConfigService.checkConfigExists();
    } catch (e) {
      return {
        'anyExists': false,
        'settingsExists': false,
        'envExists': false,
      };
    }
  }

  /// 通知状态栏菜单更新
  Future<void> _notifyStatusBarMenuUpdate() async {
    if (Platform.isMacOS) {
      try {
        await StatusBarMenuBridge.updateStatusBarMenu();
      } catch (e) {
        // 静默忽略错误，避免影响主流程
      }
    }
  }
}

