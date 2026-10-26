import '../utils/key_mask.dart';
import '../models/ai_key.dart';
import '../models/platform_type.dart';
import '../models/platform_category.dart';
import '../models/mcp_server.dart' show AiToolType;
import '../services/database_service.dart';
import '../services/crypt_service.dart';
import '../services/auth_service.dart';
import '../services/clipboard_service.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../services/claude_config_service.dart';
import '../services/claude_desktop_config_service.dart';
import '../services/codex_config_service.dart';
import '../services/gemini_config_service.dart';
import '../services/settings_service.dart';
import '../services/status_bar_menu_bridge.dart';
import '../services/region_filter_service.dart';
import '../services/openclaw_config_service.dart';
import '../services/tool_providers/tool_provider_service.dart';
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
  final ClaudeDesktopConfigService _claudeDesktopConfigService = ClaudeDesktopConfigService();

  List<AIKey> _allKeys = [];
  List<AIKey> _filteredKeys = [];
  String _searchQuery = '';
  PlatformType? _filterPlatform;
  PlatformCategory? _filterPlatformCategory;
  KeyStatistics? _statistics;

  // 当前使用的密钥ID（卡片级）
  int? _currentClaudeCodeKeyId;
  int? _currentCodexKeyId;
  int? _currentGeminiKeyId;
  int? _currentClaudeDesktopKeyId;

  // 当前生效的是卡片内的第几把子密钥
  int? _currentClaudeCodeEntryIndex;
  int? _currentCodexEntryIndex;
  int? _currentGeminiEntryIndex;
  int? _currentClaudeDesktopEntryIndex;

  bool _currentToolKeysLoaded = false;

  ActiveKeyRef? _refFor(int? keyId, int? entryIndex) => (keyId == null || entryIndex == null)
      ? null
      : ActiveKeyRef(keyId, entryIndex);

  /// 取卡片中指定那把子密钥（[entryIndex] 为空时用卡片当前密钥）。
  ///
  /// 返回的卡片 `keyValue` 已镜像那把，且该把的独立地址已覆盖到各工具 base URL，
  /// 工具侧服务无需感知多密钥 / 多地址。
  AIKey _keyAtEntry(AIKey key, int? entryIndex) => key.projectedForEntry(entryIndex);

  /// 各工具当前生效的密钥引用（卡片 + 子密钥下标）。供工具页 / 详情抽屉判断「哪把生效」。
  Map<AiToolType, ActiveKeyRef?> get currentKeyRefs => {
        AiToolType.claudecode: _refFor(_currentClaudeCodeKeyId, _currentClaudeCodeEntryIndex),
        AiToolType.claudeDesktop: _refFor(_currentClaudeDesktopKeyId, _currentClaudeDesktopEntryIndex),
        AiToolType.codex: _refFor(_currentCodexKeyId, _currentCodexEntryIndex),
        AiToolType.gemini: _refFor(_currentGeminiKeyId, _currentGeminiEntryIndex),
      };

  /// 各工具当前生效的密钥 id（null = 官方配置 / 未配置）。供侧栏、卡片工具状态 chip 使用。
  /// 由 [currentKeyRefs] 派生：只关心「卡片是否生效」的旧调用点保持行为不变。
  Map<AiToolType, int?> get currentKeyIds =>
      currentKeyRefs.map((tool, ref) => MapEntry(tool, ref?.keyId));

  /// [currentKeyIds] 是否已经从配置文件读取过一次
  bool get currentToolKeysLoaded => _currentToolKeysLoaded;

  /// 并行读取各工具当前密钥（读 4 个配置文件），读完通知一次。单个工具失败不影响其他工具。
  Future<void> refreshCurrentToolKeys() async {
    Future<void> guard(Future<Object?> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    await Future.wait([
      guard(getCurrentClaudeCodeKey),
      guard(getCurrentClaudeDesktopKey),
      guard(getCurrentCodexKey),
      guard(getCurrentGeminiKey),
    ]);
    _currentToolKeysLoaded = true;
    notifyListeners();
  }

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
        final platformCategories =
            PlatformCategoryManager.getCategoriesForPlatform(platform);
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
      final platformsInCategory =
          PlatformCategoryManager.getPlatformsByCategory(
              _filterPlatformCategory!);

      // 只返回已添加的平台中属于当前分组的平台
      final addedPlatformsSet = addedPlatforms.toSet();
      return platformsInCategory
          .where((platform) => addedPlatformsSet.contains(platform))
          .toList();
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

          // 遍历所有密钥（逐把判断是否明文）
          for (final key in _allKeys) {
            var changed = false;
            final entries = <KeyEntry>[];
            for (final entry in key.keyEntries) {
              if (isEncryptedValue(entry.value)) {
                entries.add(entry);
                continue;
              }
              try {
                final encryptedValue = await _cryptService.encrypt(
                  entry.value,
                  encryptionKey,
                );
                entries.add(entry.copyWith(value: encryptedValue));
                changed = true;
              } catch (e) {
                print('重新加密密钥失败 - ID: ${key.id}, 名称: ${key.name}, 错误: $e');
                entries.add(entry);
              }
            }

            if (!changed) continue;
            try {
              final updatedKey = key.copyWith(
                keyEntries: entries,
                updatedAt: DateTime.now(),
              );
              await _databaseService.updateKey(updatedKey);
              reEncryptedCount++;
            } catch (e) {
              print('更新密钥失败 - ID: ${key.id}, 名称: ${key.name}, 错误: $e');
            }
          }

          if (reEncryptedCount > 0) {
            // 重新加载列表
            await loadKeys();
            print('已重新加密 $reEncryptedCount 个明文密钥');
          }

          return true;
        }) ??
        false;
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
      await _refreshMaskCache();
      _updateFilteredKeys();
      await _updateStatistics();
    }, showLoading: showLoading);
  }

  /// 加密存储的密钥：解密后只把「前缀 + 后 4 位」掩码放进缓存（明文不保留），供卡片 / 工具页显示。
  /// 逐把子密钥判断，缓存键为 `id#entryIndex`。
  Future<void> _refreshMaskCache() async {
    KeyMaskCache.clear();
    for (final k in _allKeys) {
      if (k.id == null) continue;
      final entries = k.keyEntries;
      for (var i = 0; i < entries.length; i++) {
        final value = entries[i].value;
        if (!isEncryptedValue(value)) continue;
        final plain = await decryptKeyValue(value);
        if (plain != null && !plain.trimLeft().startsWith('{')) {
          KeyMaskCache.put(k.id!, i, plain);
        }
      }
    }
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
      final platformsInCategory =
          PlatformCategoryManager.getPlatformsByCategory(
              _filterPlatformCategory!);
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
      final platformsInCategory =
          PlatformCategoryManager.getPlatformsByCategory(category);
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
        final platformsInCategory =
            PlatformCategoryManager.getPlatformsByCategory(
                _filterPlatformCategory!);
        final categoryPlatformIds =
            platformsInCategory.map((p) => p.id).toSet();
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
      filtered =
          filtered.where((key) => key.platformType == _filterPlatform).toList();
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

  /// 添加密钥（逐把子密钥各自加密）
  Future<bool> addKey(AIKey key) async {
    return await executeAsync(() async {
          // 检查是否设置了主密码
          final hasPassword = await _authService.hasMasterPassword();
          final encryptionKey = hasPassword ? await _authService.getEncryptionKey() : null;

          final now = DateTime.now();
          final entries = <KeyEntry>[];
          for (final entry in key.keyEntries) {
            entries.add(entry.copyWith(
              value: (encryptionKey != null && !isEncryptedValue(entry.value))
                  ? await _cryptService.encrypt(entry.value, encryptionKey)
                  : entry.value,
              createdAt: entry.createdAt ?? now,
            ));
          }
          // 没有设置主密码时明文存储

          final finalKey = key.copyWith(
            keyEntries: entries,
            createdAt: now,
            updatedAt: now,
          );

          // 保存到数据库
          await _databaseService.insertKey(finalKey);

          // 重新加载列表
          await loadKeys();
          return true;
        }) ??
        false;
  }

  /// 更新密钥
  Future<bool> updateKey(AIKey key) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      if (key.id == null) {
        setError('密钥ID不能为空');
        return false;
      }

      // 逐把加密：仅对明文形态的子密钥加密（表单未改动的已密文密钥保持原样，
      // 避免二次加密破坏原值）
      final hasPassword = await _authService.hasMasterPassword();
      final encryptionKey = hasPassword ? await _authService.getEncryptionKey() : null;
      final encryptedEntries = <KeyEntry>[];
      for (final entry in key.keyEntries) {
        encryptedEntries.add(entry.copyWith(
          value: (encryptionKey != null && !isEncryptedValue(entry.value))
              ? await _cryptService.encrypt(entry.value, encryptionKey)
              : entry.value,
        ));
      }
      final activeIdx = key.normalizedActiveIndex.clamp(0, encryptedEntries.length - 1);
      // 如果没有设置主密码，则明文存储

      // 表单不管理的字段沿用数据库中的值，避免编辑时被清空：
      // - toolConfigs（新工具的按密钥设置，由工具页写入）；
      // - claudeDesktopModel（旧版 Desktop 兜底模型，表单不再展示）；
      // - 关闭 Gemini 时表单会把 geminiModel/geminiBaseUrl 置空，重新开启后应能恢复。
      final existing = await _databaseService.getKeyById(key.id!);
      final toolConfigs = key.toolConfigs.isNotEmpty ? key.toolConfigs : (existing?.toolConfigs ?? const {});
      final claudeDesktopModel = key.claudeDesktopModel ?? existing?.claudeDesktopModel;
      final geminiModel = key.geminiModel ?? (key.enableGemini ? null : existing?.geminiModel);
      final geminiBaseUrl = key.geminiBaseUrl ?? (key.enableGemini ? null : existing?.geminiBaseUrl);

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
        keyValue: encryptedEntries[activeIdx].value,
        keyNonce: key.keyNonce,
        keyEntriesRaw: encryptedEntries,
        activeKeyIndex: activeIdx,
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
        geminiModel: geminiModel,
        geminiBaseUrl: geminiBaseUrl,
        enableOpenclaw: key.enableOpenclaw,
        openclawBaseUrl: key.openclawBaseUrl,
        openclawModel: key.openclawModel,
        enableClaudeDesktop: key.enableClaudeDesktop,
        claudeDesktopBaseUrl: key.claudeDesktopBaseUrl,
        claudeDesktopModel: claudeDesktopModel,
        claudeDesktopSonnetModel: key.claudeDesktopSonnetModel,
        claudeDesktopHaikuModel: key.claudeDesktopHaikuModel,
        claudeDesktopOpusModel: key.claudeDesktopOpusModel,
        claudeCodeConfig: key.claudeCodeConfig,
        toolConfigs: toolConfigs,
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
      await _refreshActiveConfigIfNeeded(updatedKey, previous: existing);

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
          // 先把这把密钥从累加型工具（OpenCode/Hermes/Pi/MiniMax Code/OpenClaw）的配置里移除，
          // 避免删除后密钥仍残留在工具配置文件中（孤儿配置）。清理失败不阻断删除。
          final existing = await _databaseService.getKeyById(id);
          if (existing != null) await _removeKeyFromAdditiveTools(existing);
          await _databaseService.secureDeleteKey(id);
          await loadKeys();
          return true;
        }) ??
        false;
  }

  /// 主界面 / 工具页下拉：切换卡片的当前密钥。
  ///
  /// 若该卡片正被某工具使用（生效中），按已确认语义**立即用新密钥改写该工具的配置文件**：
  /// 复用 [_refreshActiveConfigIfNeeded]（它对该卡片生效中的每个工具重写配置）。
  Future<bool> setActiveKeyEntry(int keyId, int entryIndex) async {
    try {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null) return false;
      if (entryIndex < 0 || entryIndex >= key.keyEntries.length) return false;
      if (key.normalizedActiveIndex == entryIndex) return true;

      final updated = key.withActiveKeyIndex(entryIndex).copyWith(updatedAt: DateTime.now());

      // 先改内存，UI 立即响应
      final allIndex = _allKeys.indexWhere((k) => k.id == keyId);
      if (allIndex != -1) _allKeys[allIndex] = updated;
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == keyId);
      if (filteredIndex != -1) _filteredKeys[filteredIndex] = updated;
      notifyListeners();

      // 写库
      await _databaseService.updateKey(updated);

      // 工具联动改写 + 状态栏刷新
      await _refreshActiveConfigIfNeeded(updated, previous: key);
      // 卡片未被任何工具使用时也要刷新状态栏（菜单显示的是卡片当前密钥的别名）
      await _notifyStatusBarMenuUpdate();
      return true;
    } catch (e) {
      await loadKeys(showLoading: false);
      setError(e.toString());
      return false;
    }
  }

  /// 删除卡片内的一把子密钥（至少保留一把）。
  ///
  /// 若删的是当前密钥，下标向左收敛；随后按 [setActiveKeyEntry] 的同一套联动改写处理。
  Future<bool> deleteKeyEntry(int keyId, int entryIndex) async {
    try {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null) return false;
      if (key.keyEntries.length <= 1) return false;
      if (entryIndex < 0 || entryIndex >= key.keyEntries.length) return false;

      final updated = key.removeEntry(entryIndex).copyWith(updatedAt: DateTime.now());
      final newActive =
          updated.normalizedActiveIndex != key.normalizedActiveIndex;

      final allIndex = _allKeys.indexWhere((k) => k.id == keyId);
      if (allIndex != -1) _allKeys[allIndex] = updated;
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == keyId);
      if (filteredIndex != -1) _filteredKeys[filteredIndex] = updated;
      notifyListeners();

      // 掩码缓存按 id#index 存，删除后原有下标会上移，直接整表重建
      await _databaseService.updateKey(updated);
      await _refreshMaskCache();

      // 删除导致当前密钥变化时，同样要改写生效中的工具配置
      if (newActive) {
        await _refreshActiveConfigIfNeeded(updated, previous: key);
      }
      await _notifyStatusBarMenuUpdate();
      return true;
    } catch (e) {
      await loadKeys(showLoading: false);
      setError(e.toString());
      return false;
    }
  }

  /// 更新某把子密钥的校验状态（卡片徽章展示当前密钥的校验态）
  Future<bool> updateEntryValidationStatus(int keyId, int entryIndex, bool validated) async {
    try {
      final allIndex = _allKeys.indexWhere((k) => k.id == keyId);
      if (allIndex == -1) return false;
      final key = _allKeys[allIndex];
      if (entryIndex < 0 || entryIndex >= key.keyEntries.length) return false;

      final updated = key.replaceEntry(
        entryIndex,
        key.keyEntries[entryIndex].copyWith(validated: validated),
      );
      _allKeys[allIndex] = updated;
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == keyId);
      if (filteredIndex != -1) _filteredKeys[filteredIndex] = updated;
      notifyListeners();

      await _databaseService.updateKey(updated);
      return true;
    } catch (e) {
      await loadKeys(showLoading: false);
      return false;
    }
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(int id, bool isFavorite) async {
    // 不使用 executeAsync，避免触发加载状态导致页面闪烁
    try {
      // 先更新内存中的列表，立即反映到 UI，实现无感更新
      final allIndex = _allKeys.indexWhere((k) => k.id == id);
      final filteredIndex = _filteredKeys.indexWhere((k) => k.id == id);

      if (allIndex != -1) {
        _allKeys[allIndex] =
            _allKeys[allIndex].copyWith(isFavorite: isFavorite);
      }
      if (filteredIndex != -1) {
        _filteredKeys[filteredIndex] =
            _filteredKeys[filteredIndex].copyWith(isFavorite: isFavorite);
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
        _filteredKeys[filteredIndex] =
            _filteredKeys[filteredIndex].copyWith(isActive: isActive);
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

  /// 复制密钥到剪贴板（[entryIndex] 缺省为卡片当前密钥）
  Future<bool> copyKeyToClipboard(int id, {int? entryIndex}) async {
    return await executeAsync(() async {
          final key = await _databaseService.getKeyById(id);
          if (key == null) {
            throw Exception('密钥不存在');
          }

          final index = entryIndex ?? key.normalizedActiveIndex;
          if (index < 0 || index >= key.keyEntries.length) {
            throw Exception('密钥不存在');
          }
          final storedValue = key.keyEntries[index].value;

          String decryptedValue;

          // 检查是否是加密格式
          final hasPassword = await _authService.hasMasterPassword();
          if (hasPassword && isEncryptedValue(storedValue)) {
            // 加密格式，需要解密
            final encryptionKey = await _authService.getEncryptionKey();
            if (encryptionKey == null) {
              throw Exception('未找到加密密钥');
            }
            decryptedValue = await _cryptService.decrypt(
              storedValue,
              encryptionKey,
            );
          } else {
            // 明文格式，直接使用
            decryptedValue = storedValue;
          }

          // 复制到剪贴板（带自动清空）
          await _clipboardService.copyWithAutoClear(
            decryptedValue,
            delaySeconds: 30,
          );

          // 更新该把密钥的最后使用时间
          await _databaseService.updateEntryLastUsed(id, index, DateTime.now());
          await loadKeys();

          return true;
        }) ??
        false;
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

      // 逐把解密：任一被锁无法解密时退回原始 key（与旧行为一致）
      var changed = false;
      final entries = <KeyEntry>[];
      for (final e in key.keyEntries) {
        final plain = await decryptKeyValue(e.value);
        if (plain == null) return key;
        if (plain != e.value) changed = true;
        entries.add(plain == e.value ? e : e.copyWith(value: plain));
      }
      if (!changed) return key;
      // copyWith(keyEntries:) 会把 keyValue 镜像为当前那把的解密值，其余字段原样保留
      return key.copyWith(keyEntries: entries);
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
      final keys = await _databaseService.getCodexKeys();
      final isChinaFilterEnabled =
          await RegionFilterService.isChinaRegionFilterEnabled();
      if (!isChinaFilterEnabled) {
        return keys;
      }

      return keys.where((key) {
        return !RegionFilterService.isKeyRestrictedInChina(
          platformId: key.platformType.id,
          platformName: key.platform,
          apiEndpoint: key.apiEndpoint,
          codexBaseUrl: key.codexBaseUrl,
          claudeCodeBaseUrl: key.claudeCodeBaseUrl,
          managementUrl: key.managementUrl,
        );
      }).toList();
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

  /// 切换 ClaudeCode 使用的密钥（[entryIndex] 指定卡片内的第几把，缺省用当前密钥）
  Future<bool> switchClaudeCodeProvider(int keyId, {int? entryIndex}) async {
    return await executeAsync(() async {
          final key = await _databaseService.getKeyById(keyId);
          if (key == null || !key.enableClaudeCode) {
            throw Exception('密钥不存在或未启用 ClaudeCode');
          }

          // 目标那把子密钥：keyValue 已随 activeKeyIndex 镜像，工具侧服务无需改动
          final target = _keyAtEntry(key, entryIndex);

          // 备份当前配置
          await _claudeConfigService.backupConfig();

          // 切换配置
          final success = await _claudeConfigService.switchProvider(target);
          if (!success) throw ToolSwitchException(_claudeConfigService.lastSwitchError);
          if (success) {
            _currentClaudeCodeKeyId = keyId;
            _currentClaudeCodeEntryIndex = target.normalizedActiveIndex;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 切换 Codex 使用的密钥（[entryIndex] 指定卡片内的第几把，缺省用当前密钥）
  Future<bool> switchCodexProvider(int keyId, {int? entryIndex}) async {
    return await executeAsync(() async {
          final key = await _databaseService.getKeyById(keyId);
          if (key == null || !key.enableCodex) {
            throw Exception('密钥不存在或未启用 Codex');
          }
          final target = _keyAtEntry(key, entryIndex);

          final isChinaFilterEnabled =
              await RegionFilterService.isChinaRegionFilterEnabled();
          if (isChinaFilterEnabled &&
              RegionFilterService.isKeyRestrictedInChina(
                platformId: key.platformType.id,
                platformName: key.platform,
                apiEndpoint: target.apiEndpoint,
                codexBaseUrl: target.codexBaseUrl,
                claudeCodeBaseUrl: target.claudeCodeBaseUrl,
                managementUrl: key.managementUrl,
              )) {
            throw Exception('当前地区不支持该供应商');
          }

          // 备份当前配置
          await _codexConfigService.backupConfig();

          // 切换配置
          final success = await _codexConfigService.switchProvider(target);
          if (!success) throw ToolSwitchException(_codexConfigService.lastSwitchError);
          if (success) {
            _currentCodexKeyId = keyId;
            _currentCodexEntryIndex = target.normalizedActiveIndex;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 获取当前 ClaudeCode 使用的密钥
  /// 返回 null 表示当前是官方配置
  /// 注意：总是从配置文件重新读取，不使用缓存，以确保外部修改配置后能正确反映
  Future<AIKey?> getCurrentClaudeCodeKey() async {
    // 先检查是否是官方配置
    final isOfficial = await _claudeConfigService.isOfficialConfig();
    if (isOfficial) {
      _currentClaudeCodeKeyId = null; // 官方配置没有对应的密钥ID
      _currentClaudeCodeEntryIndex = null;
      return null;
    }

    // 总是从配置文件重新读取当前使用的 API Key，然后匹配密钥
    // 这样可以确保外部修改配置文件后能正确反映
    final currentApiKey = await _claudeConfigService.getCurrentApiKey();
    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      final keys = await getClaudeCodeKeys();
      final matched = await _matchKeyEntryByValue(keys, currentApiKey);
      if (matched != null) {
        _currentClaudeCodeKeyId = matched.id;
        _currentClaudeCodeEntryIndex = matched.normalizedActiveIndex;
        return matched;
      }
    }

    // 如果没有找到匹配的密钥，清除缓存
    _currentClaudeCodeKeyId = null;
    _currentClaudeCodeEntryIndex = null;
    return null;
  }

  /// 在候选卡片中逐把子密钥解密比对，返回「命中那把被置为当前密钥」的卡片副本。
  ///
  /// 返回值已用 [AIKey.withActiveKeyIndex] 调整成命中那把，调用方可直接读
  /// `keyValue` / 掩码 / 别名；`id` 仍是卡片 id。
  Future<AIKey?> _matchKeyEntryByValue(List<AIKey> keys, String currentApiKey) async {
    final target = currentApiKey.trim();
    if (target.isEmpty) return null;
    for (final key in keys) {
      final entries = key.keyEntries;
      for (var i = 0; i < entries.length; i++) {
        final plain = await decryptKeyValue(entries[i].value);
        if (plain == null || plain.trim().isEmpty) continue;
        if (plain.trim() == target) return key.withActiveKeyIndex(i);
      }
    }
    return null;
  }

  /// 切换回官方 ClaudeCode 配置
  Future<bool> switchToOfficialClaudeCode() async {
    return await executeAsync(() async {
          // 备份当前配置
          await _claudeConfigService.backupConfig();

          // 切换配置
          final success = await _claudeConfigService.switchToOfficial();
          if (!success) throw ToolSwitchException(_claudeConfigService.lastSwitchError);
          if (success) {
            _currentClaudeCodeKeyId = null; // 官方配置没有对应的密钥ID
            _currentClaudeCodeEntryIndex = null;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 检查当前是否是官方 ClaudeCode 配置
  Future<bool> isOfficialClaudeCodeConfig() async {
    return await _claudeConfigService.isOfficialConfig();
  }

  /// 更新官方 ClaudeCode 配置的环境变量
  Future<bool> updateOfficialClaudeCodeConfig(
      Map<String, String> envVars) async {
    return await executeAsync(() async {
          final success =
              await _claudeConfigService.updateOfficialConfigEnv(envVars);
          if (success) {
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 获取当前 Codex 使用的密钥
  /// 返回 null 表示当前是官方配置
  /// 注意：总是从配置文件重新读取，不使用缓存，以确保外部修改配置后能正确反映
  Future<AIKey?> getCurrentCodexKey() async {
    // 先检查是否是官方配置
    final isOfficial = await _codexConfigService.isOfficialConfig();
    if (isOfficial) {
      _currentCodexKeyId = null; // 官方配置没有对应的密钥ID
      _currentCodexEntryIndex = null;
      return null;
    }

    // 总是从配置文件重新读取当前使用的 API Key，然后匹配密钥
    // 这样可以确保外部修改配置文件后能正确反映
    final currentApiKey = await _codexConfigService.getCurrentApiKey();

    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      // 情况1：使用 auth.json 的供应商（如 OpenAI、代理转发平台）
      final keys = await getCodexKeys();
      final matched = await _matchKeyEntryByValue(keys, currentApiKey);
      if (matched != null) {
        _currentCodexKeyId = matched.id;
        _currentCodexEntryIndex = matched.normalizedActiveIndex;
        return matched;
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
          final keyBaseUrl = key.codexBaseUrl
              ?.trim()
              .toLowerCase()
              .replaceAll(RegExp(r'/+$'), '');
          final configBaseUrl =
              baseUrl.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

          if (keyBaseUrl != null &&
              keyBaseUrl == configBaseUrl &&
              key.enableCodex) {
            _currentCodexKeyId = key.id;
            _currentCodexEntryIndex = key.normalizedActiveIndex;
            return key;
          }
        }
      }
    }

    // 如果没有找到匹配的密钥，清除缓存
    _currentCodexKeyId = null;
    _currentCodexEntryIndex = null;
    return null;
  }

  /// 切换回官方 Codex 配置
  Future<bool> switchToOfficialCodex() async {
    return await executeAsync(() async {
          final isChinaFilterEnabled =
              await RegionFilterService.isChinaRegionFilterEnabled();
          if (isChinaFilterEnabled) {
            throw Exception('当前地区不支持官方 Codex 配置');
          }

          // 备份当前配置
          await _codexConfigService.backupConfig();

          // 切换配置
          final success = await _codexConfigService.switchToOfficial();
          if (!success) throw ToolSwitchException(_codexConfigService.lastSwitchError);
          if (success) {
            _currentCodexKeyId = null; // 官方配置没有对应的密钥ID
            _currentCodexEntryIndex = null;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 检查当前是否是官方 Codex 配置
  Future<bool> isOfficialCodexConfig() async {
    return await _codexConfigService.isOfficialConfig();
  }

  /// 更新官方 Codex 配置的 API Key
  /// [apiKey] 官方 Codex API Key，如果为空则清空官方配置
  Future<bool> updateOfficialCodexConfig(String? apiKey) async {
    return await executeAsync(() async {
          final isChinaFilterEnabled =
              await RegionFilterService.isChinaRegionFilterEnabled();
          if (isChinaFilterEnabled) {
            throw Exception('当前地区不支持官方 Codex 配置');
          }

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
        }) ??
        false;
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

  /// 切换 Gemini 使用的密钥（[entryIndex] 指定卡片内的第几把，缺省用当前密钥）
  Future<bool> switchGeminiProvider(int keyId, {int? entryIndex}) async {
    return await executeAsync(() async {
          final key = await _databaseService.getKeyById(keyId);
          if (key == null || !key.enableGemini) {
            throw Exception('密钥不存在或未启用 Gemini');
          }

          final target = _keyAtEntry(key, entryIndex);

          // 备份当前配置
          await _geminiConfigService.backupConfig();

          // 切换配置
          final success = await _geminiConfigService.switchProvider(target);
          if (!success) throw ToolSwitchException(_geminiConfigService.lastSwitchError);
          if (success) {
            _currentGeminiKeyId = keyId;
            _currentGeminiEntryIndex = target.normalizedActiveIndex;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 获取当前 Gemini 使用的密钥
  /// 返回 null 表示当前是官方配置
  Future<AIKey?> getCurrentGeminiKey() async {
    // 未命中任何密钥 / 官方态时，卡片与子密钥都要清空
    _currentGeminiKeyId = null;
    _currentGeminiEntryIndex = null;

    // 先检查是否是官方配置
    final isOfficial = await _geminiConfigService.isOfficialConfig();
    if (isOfficial) {
      return null;
    }

    // 从配置文件重新读取当前使用的 API Key
    final currentApiKey = await _geminiConfigService.getCurrentApiKey();

    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      // 先检查是否匹配官方存储的 API Key
      final settingsService = SettingsService();
      await settingsService.init();
      final officialApiKey = settingsService.getOfficialGeminiApiKey();
      if (officialApiKey != null &&
          officialApiKey.isNotEmpty &&
          currentApiKey.trim() == officialApiKey.trim()) {
        return null; // 官方配置返回 null
      }

      // 如果不匹配官方存储，尝试匹配密钥列表（逐把解密比对）
      final keys = await getGeminiKeys();
      final matched = await _matchKeyEntryByValue(keys, currentApiKey);
      if (matched != null) {
        _currentGeminiKeyId = matched.id;
        _currentGeminiEntryIndex = matched.normalizedActiveIndex;
        return matched;
      }

      // 如果未找到匹配的密钥，但 API Key 存在，可能是官方配置（但官方 API Key 未设置）
      // 这种情况下，应该重新检查是否是官方配置
      final isOfficialRetry = await _geminiConfigService.isOfficialConfig();
      if (isOfficialRetry) {
        return null;
      }
    }

    return null;
  }

  /// 切换回官方 Gemini 配置
  Future<bool> switchToOfficialGemini() async {
    return await executeAsync(() async {
          // 备份当前配置
          await _geminiConfigService.backupConfig();

          // 切换配置
          final success = await _geminiConfigService.switchToOfficial();
          if (!success) throw ToolSwitchException(_geminiConfigService.lastSwitchError);
          if (success) {
            _currentGeminiKeyId = null;
            _currentGeminiEntryIndex = null;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
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
        }) ??
        false;
  }

  /// 检查密钥是否为当前使用的 Gemini 密钥
  Future<bool> isCurrentGeminiKey(int keyId) async {
    final currentKey = await getCurrentGeminiKey();
    return currentKey?.id == keyId;
  }

  /// 检查密钥是否是当前激活的密钥，如果是则刷新配置
  /// 这个方法在更新密钥后调用，确保配置文件与保存后的密钥值保持同步
  Future<void> _refreshActiveConfigIfNeeded(AIKey key, {AIKey? previous}) async {
    if (key.id == null) return;

    try {
      final keyId = key.id!;
      // 当前密钥的独立地址已覆盖到各工具 base URL，写配置时统一用这个副本
      final target = key.projectedForEntry(key.normalizedActiveIndex);

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
          final success = await _claudeConfigService.switchProvider(target);
          if (success) {
            _currentClaudeCodeKeyId = keyId;
            _currentClaudeCodeEntryIndex = key.normalizedActiveIndex;
            notifyListeners();
            await _notifyStatusBarMenuUpdate();
          }
        }
      }

      // 检查 Codex
      // 先检查内存中的 _currentCodexKeyId，如果匹配则说明该密钥是当前激活的
      // 如果内存中没有，则通过配置文件匹配检查（处理应用刚启动的情况）
      if (key.enableCodex) {
        final isChinaFilterEnabled =
            await RegionFilterService.isChinaRegionFilterEnabled();
        final isRestrictedInChina = isChinaFilterEnabled &&
            RegionFilterService.isKeyRestrictedInChina(
              platformId: key.platformType.id,
              platformName: key.platform,
              apiEndpoint: target.apiEndpoint,
              codexBaseUrl: target.codexBaseUrl,
              claudeCodeBaseUrl: target.claudeCodeBaseUrl,
              managementUrl: key.managementUrl,
            );
        if (!isRestrictedInChina) {
          bool isCurrent = _currentCodexKeyId == keyId;
          if (!isCurrent) {
            // 如果内存中没有，尝试从配置文件匹配
            isCurrent = await isCurrentCodexKey(keyId);
          }
          if (isCurrent) {
            print('KeyManagerViewModel: 检测到当前保存的密钥是激活的 Codex 密钥，立即刷新配置');
            await _codexConfigService.backupConfig();
            final success = await _codexConfigService.switchProvider(target);
            if (success) {
              _currentCodexKeyId = keyId;
              _currentCodexEntryIndex = key.normalizedActiveIndex;
              notifyListeners();
              await _notifyStatusBarMenuUpdate();
            }
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
          final success = await _geminiConfigService.switchProvider(target);
          if (success) {
            _currentGeminiKeyId = keyId;
            _currentGeminiEntryIndex = key.normalizedActiveIndex;
            notifyListeners();
            await _notifyStatusBarMenuUpdate();
          }
        }
      }

      // 检查 Claude Desktop
      if (key.enableClaudeDesktop) {
        bool isCurrent = _currentClaudeDesktopKeyId == keyId;
        if (!isCurrent) {
          isCurrent = await isCurrentClaudeDesktopKey(keyId);
        }
        if (isCurrent) {
          print('KeyManagerViewModel: 检测到当前保存的密钥是激活的 Claude Desktop 密钥，立即刷新配置');
          await _claudeDesktopConfigService.backupConfig();
          final success = await _claudeDesktopConfigService.switchProvider(target);
          if (success) {
            _currentClaudeDesktopKeyId = keyId;
            _currentClaudeDesktopEntryIndex = key.normalizedActiveIndex;
            notifyListeners();
            await _notifyStatusBarMenuUpdate();
          }
        }
      }
    } catch (e) {
      // 配置刷新失败不应该影响密钥保存的成功
      print('KeyManagerViewModel: 刷新激活配置失败: $e');
    }
    await _refreshToolProvidersIfApplied(key, previous: previous);
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

  /// 获取启用了 Claude Desktop 的密钥列表
  Future<List<AIKey>> getClaudeDesktopKeys() async {
    try {
      return await _databaseService.getClaudeDesktopKeys();
    } catch (e) {
      return [];
    }
  }

  /// 切换 Claude Desktop 使用的密钥（[entryIndex] 指定卡片内的第几把，缺省用当前密钥）
  Future<bool> switchClaudeDesktopProvider(int keyId, {int? entryIndex}) async {
    return await executeAsync(() async {
          final key = await _databaseService.getKeyById(keyId);
          if (key == null || !key.enableClaudeDesktop) {
            throw Exception('密钥不存在或未启用 Claude Desktop');
          }

          final target = _keyAtEntry(key, entryIndex);

          // 备份当前配置
          await _claudeDesktopConfigService.backupConfig();

          // 切换配置
          final success = await _claudeDesktopConfigService.switchProvider(target);
          if (!success) throw ToolSwitchException(_claudeDesktopConfigService.lastSwitchError);
          if (success) {
            _currentClaudeDesktopKeyId = keyId;
            _currentClaudeDesktopEntryIndex = target.normalizedActiveIndex;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 获取当前 Claude Desktop 使用的密钥
  /// 返回 null 表示当前是官方配置
  Future<AIKey?> getCurrentClaudeDesktopKey() async {
    // 未命中任何密钥 / 官方态时，卡片与子密钥都要清空
    _currentClaudeDesktopKeyId = null;
    _currentClaudeDesktopEntryIndex = null;

    // 先检查是否是官方配置
    final isOfficial = await _claudeDesktopConfigService.isOfficialConfig();
    if (isOfficial) {
      return null;
    }

    // 从配置文件重新读取当前使用的 API Key
    final currentApiKey = await _claudeDesktopConfigService.getCurrentApiKey();

    if (currentApiKey != null && currentApiKey.isNotEmpty) {
      final keys = await getClaudeDesktopKeys();
      final matched = await _matchKeyEntryByValue(keys, currentApiKey);
      if (matched != null) {
        _currentClaudeDesktopKeyId = matched.id;
        _currentClaudeDesktopEntryIndex = matched.normalizedActiveIndex;
        return matched;
      }
    }

    return null;
  }

  /// 切换回官方 Claude Desktop 配置
  Future<bool> switchToOfficialClaudeDesktop() async {
    return await executeAsync(() async {
          // 备份当前配置
          await _claudeDesktopConfigService.backupConfig();

          // 切换配置
          final success = await _claudeDesktopConfigService.switchToOfficial();
          if (!success) throw ToolSwitchException(_claudeDesktopConfigService.lastSwitchError);
          if (success) {
            _currentClaudeDesktopKeyId = null;
            _currentClaudeDesktopEntryIndex = null;
            notifyListeners();
            // 通知状态栏菜单更新
            await _notifyStatusBarMenuUpdate();
          }
          return success;
        }) ??
        false;
  }

  /// 检查密钥是否为当前使用的 Claude Desktop 密钥
  Future<bool> isCurrentClaudeDesktopKey(int keyId) async {
    final currentKey = await getCurrentClaudeDesktopKey();
    return currentKey?.id == keyId;
  }

  /// 检查当前是否是官方 Claude Desktop 配置
  Future<bool> isOfficialClaudeDesktopConfig() async {
    return await _claudeDesktopConfigService.isOfficialConfig();
  }

  /// 检测 Claude Desktop 配置文件是否存在
  Future<Map<String, dynamic>> checkClaudeDesktopConfigExists() async {
    try {
      return await _claudeDesktopConfigService.checkConfigExists();
    } catch (e) {
      return {
        'dirExists': false,
        'configExists': false,
      };
    }
  }

  /// 通知状态栏菜单更新
  // ---------------------------------------------------------------------------
  // 新工具（OpenCode / Grok Build / Hermes / Pi / MiniMax Code）的密钥切换
  // ---------------------------------------------------------------------------

  final ToolProviderService _toolProviderService = ToolProviderService();

  /// 最近一次新工具写入失败的原因（供 UI 提示）
  String? lastToolProviderError;

  /// 对某个新工具启用的密钥
  List<AIKey> keysForTool(AiToolType tool) => _allKeys.where((k) => k.isToolEnabled(tool.value)).toList();

  /// 设置密钥对某个新工具的启用状态与覆盖项（只改数据库，不写工具配置）
  Future<bool> setKeyToolConfig(int keyId, AiToolType tool, {required bool enabled, String? baseUrl, String? model}) async {
    final key = await _databaseService.getKeyById(keyId);
    if (key == null) return false;
    final configs = {for (final e in key.toolConfigs.entries) e.key: Map<String, dynamic>.from(e.value)};
    final cfg = configs[tool.value] ?? <String, dynamic>{};
    cfg['enabled'] = enabled;
    if (baseUrl != null) baseUrl.trim().isEmpty ? cfg.remove('baseUrl') : cfg['baseUrl'] = baseUrl.trim();
    if (model != null) model.trim().isEmpty ? cfg.remove('model') : cfg['model'] = model.trim();
    configs[tool.value] = cfg;
    final updated = key.copyWith(toolConfigs: configs);
    await _databaseService.updateKey(updated);
    final i = _allKeys.indexWhere((k) => k.id == keyId);
    if (i >= 0) _allKeys[i] = updated;
    notifyListeners();
    return true;
  }

  /// 把密钥写入新工具（[entryIndex] 指定卡片内的第几把，缺省用当前密钥；
  /// [makeDefault]：同时设为该工具默认；Grok Build 总是切换）
  Future<bool> applyKeyToTool(AiToolType tool, int keyId,
      {int? entryIndex, bool makeDefault = true}) async {
    lastToolProviderError = null;
    try {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null) throw ToolProviderException('密钥不存在');
      final target = _keyAtEntry(key, entryIndex);
      final plain = await decryptKeyValue(target.keyValue);
      if (plain == null || plain.isEmpty) throw ToolProviderException('无法解密密钥');
      await _toolProviderService.apply(tool, target, plain, makeDefault: makeDefault);
      notifyListeners();
      return true;
    } catch (e) {
      lastToolProviderError = e.toString();
      return false;
    }
  }

  /// 从新工具配置中移除密钥（Grok Build：若正在使用则切回官方）
  Future<bool> removeKeyFromTool(AiToolType tool, int keyId) async {
    lastToolProviderError = null;
    try {
      final key = await _databaseService.getKeyById(keyId);
      if (key == null) return false;
      await _toolProviderService.remove(tool, key, decryptedKey: await decryptKeyValue(key.keyValue));
      notifyListeners();
      return true;
    } catch (e) {
      lastToolProviderError = e.toString();
      return false;
    }
  }

  /// Grok Build 切回官方登录
  Future<bool> switchGrokBuildToOfficial() async {
    try {
      await _toolProviderService.switchGrokToOfficial();
      notifyListeners();
      return true;
    } catch (e) {
      lastToolProviderError = e.toString();
      return false;
    }
  }

  /// 已写入某个累加型工具的密钥 id
  Future<Set<int>> getToolAppliedKeyIds(AiToolType tool) => _toolProviderService.appliedKeyIds(tool);

  /// 某个新工具当前默认使用的密钥 id（Grok Build 按 api_key 反查；官方态返回 null）
  Future<int?> getToolDefaultKeyId(AiToolType tool) async {
    if (tool != AiToolType.grokBuild) return _toolProviderService.defaultKeyId(tool);
    final current = await _toolProviderService.currentGrokApiKey();
    if (current == null || current.isEmpty) return null;
    for (final key in _allKeys) {
      for (final entry in key.keyEntries) {
        if (await decryptKeyValue(entry.value) == current) return key.id;
      }
    }
    return null;
  }

  /// 编辑密钥后：已写入新工具的，按新值重写（保持原有“是否默认”状态）
  Future<void> _refreshToolProvidersIfApplied(AIKey key, {AIKey? previous}) async {
    if (key.id == null) return;
    final plain = await decryptKeyValue(key.keyValue);
    final target = key.projectedForEntry(key.normalizedActiveIndex);
    if (plain == null || plain.isEmpty) return;
    for (final tool in ToolProviderService.tools) {
      try {
        if (tool == AiToolType.grokBuild) {
          final current = await _toolProviderService.currentGrokApiKey();
          final before = previous == null ? null : await decryptKeyValue(previous.keyValue);
          if (current != null && (current == plain || (before != null && current == before))) {
            await _toolProviderService.apply(tool, target, plain);
          }
          continue;
        }
        if (!(await _toolProviderService.appliedKeyIds(tool)).contains(key.id)) continue;
        final isDefault = await _toolProviderService.defaultKeyId(tool) == key.id;
        await _toolProviderService.apply(tool, key, plain, makeDefault: isDefault);
      } catch (e) {
        print('KeyManagerViewModel: 刷新 ${tool.value} 配置失败: $e');
      }
    }
    // OpenClaw：该密钥正被应用时，按新值重写
    try {
      final oc = OpenClawConfigService();
      final applied = await oc.getAppliedKeyIds();
      if (applied.values.contains(key.id) && key.enableOpenclaw) {
        await oc.applyProviderKey(
          keyId: key.id!,
          decryptedKey: plain,
          platformId: key.platformType.id,
          openclawBaseUrl: target.openclawBaseUrl,
          openclawModel: key.openclawModel,
        );
      }
    } catch (e) {
      print('KeyManagerViewModel: 刷新 OpenClaw 配置失败: $e');
    }
  }

  /// 删除密钥前：从累加型工具中移除（新工具 + OpenClaw）
  Future<void> _removeKeyFromAdditiveTools(AIKey key) async {
    final plain = await decryptKeyValue(key.keyValue);
    for (final tool in ToolProviderService.tools) {
      try {
        await _toolProviderService.remove(tool, key, decryptedKey: plain);
      } catch (e) {
        print('KeyManagerViewModel: 从 ${tool.value} 移除密钥失败: $e');
      }
    }
    try {
      final oc = OpenClawConfigService();
      final applied = await oc.getAppliedKeyIds();
      if (applied.values.contains(key.id)) {
        await oc.removeProviderKey(platformId: key.platformType.id);
      }
    } catch (e) {
      print('KeyManagerViewModel: 从 OpenClaw 移除密钥失败: $e');
    }
  }

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

/// 某工具当前生效的密钥引用：卡片 id + 卡片内子密钥下标
class ActiveKeyRef {
  final int keyId;
  final int entryIndex;

  const ActiveKeyRef(this.keyId, this.entryIndex);

  @override
  bool operator ==(Object other) =>
      other is ActiveKeyRef && other.keyId == keyId && other.entryIndex == entryIndex;

  @override
  int get hashCode => Object.hash(keyId, entryIndex);

  @override
  String toString() => 'ActiveKeyRef($keyId#$entryIndex)';
}

/// 切换失败：携带配置服务给出的原因（文件、行号等），由 executeAsync 写入 errorMessage。
class ToolSwitchException implements Exception {
  final Object? cause;
  ToolSwitchException(this.cause);

  @override
  String toString() {
    final c = cause?.toString().trim() ?? '';
    return c.startsWith('Exception: ') ? c.substring(11) : c;
  }
}
