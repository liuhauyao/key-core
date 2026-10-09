import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/provider.dart';
import '../services/provider_manager_service.dart';
import '../services/tool_switcher_service.dart';

/// 供应商页面使用的后端接口（默认实现直接委托现有服务，测试中可替换）
abstract class ProviderBackend {
  Future<List<Provider>> loadPresets();
  Future<List<Provider>> getAllProviders();
  Future<void> saveProvider(Provider provider);
  Future<void> deleteProvider(String id);
  Future<bool> isEncryptionEnabled();
  Future<void> switchTool(Provider provider, String tool);
  Future<ToolLiveState> readLiveState(String tool);
  Future<List<ConfigBackup>> listBackups(String tool);
  Future<void> restoreBackup(String tool, String backupPath);
  Future<Map<String, String>> loadCurrentSelections();
  Future<void> saveCurrentSelection(String tool, String? providerId);
}

class DefaultProviderBackend implements ProviderBackend {
  static const String _prefPrefix = 'provider_current_';

  final ProviderManagerService _providers = ProviderManagerService.instance;
  final ToolSwitcherService _switcher = ToolSwitcherService.instance;

  @override
  Future<List<Provider>> loadPresets() => _providers.loadPresets();

  @override
  Future<List<Provider>> getAllProviders() => _providers.getAllProviders();

  @override
  Future<void> saveProvider(Provider provider) => _providers.saveProvider(provider);

  @override
  Future<void> deleteProvider(String id) => _providers.deleteProvider(id);

  @override
  Future<bool> isEncryptionEnabled() => _providers.isEncryptionEnabled();

  @override
  Future<void> switchTool(Provider provider, String tool) =>
      _switcher.switchTool(provider, tool);

  @override
  Future<ToolLiveState> readLiveState(String tool) => _switcher.readLiveState(tool);

  @override
  Future<List<ConfigBackup>> listBackups(String tool) => _switcher.listBackups(tool);

  @override
  Future<void> restoreBackup(String tool, String backupPath) =>
      _switcher.restoreBackup(tool, backupPath);

  @override
  Future<Map<String, String>> loadCurrentSelections() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, String>{};
    for (final tool in ToolSwitcherService.switchableTools) {
      final id = prefs.getString('$_prefPrefix$tool');
      if (id != null) result[tool] = id;
    }
    return result;
  }

  @override
  Future<void> saveCurrentSelection(String tool, String? providerId) async {
    final prefs = await SharedPreferences.getInstance();
    if (providerId == null) {
      await prefs.remove('$_prefPrefix$tool');
    } else {
      await prefs.setString('$_prefPrefix$tool', providerId);
    }
  }
}

/// 供应商编辑表单提交的数据
class ProviderDraft {
  final Provider? preset;
  final String name;
  final String? endpoint;

  /// 为空表示保持原有 API Key 不变（编辑时）
  final String? apiKey;
  final String? defaultModel;
  final List<String> supportedTools;
  final String? websiteUrl;
  final String? description;

  const ProviderDraft({
    this.preset,
    required this.name,
    this.endpoint,
    this.apiKey,
    this.defaultModel,
    this.supportedTools = const [],
    this.websiteUrl,
    this.description,
  });
}

/// 供应商管理 / 工具切换 / 配置备份 视图模型
class ProvidersViewModel extends ChangeNotifier {
  /// 界面中展示的工具（顺序即展示顺序）
  static const List<String> tools = ToolSwitcherService.switchableTools;

  final ProviderBackend _backend;

  ProvidersViewModel({ProviderBackend? backend})
      : _backend = backend ?? DefaultProviderBackend();

  bool _isLoading = false;
  bool _loaded = false;
  String? _error;
  bool _encryptionEnabled = false;
  List<Provider> _providers = [];
  List<Provider> _presets = [];
  Map<String, String> _currentByTool = {};
  final Map<String, ToolLiveState> _liveStates = {};
  final Set<String> _switchingTools = {};
  String _searchQuery = '';

  String _backupTool = tools.first;
  List<ConfigBackup> _backups = [];
  bool _isLoadingBackups = false;

  bool get isLoading => _isLoading;
  bool get hasLoaded => _loaded;
  String? get error => _error;
  bool get encryptionEnabled => _encryptionEnabled;
  List<Provider> get providers => List.unmodifiable(_providers);
  List<Provider> get presets => List.unmodifiable(_presets);
  String get searchQuery => _searchQuery;
  String get backupTool => _backupTool;
  List<ConfigBackup> get backups => List.unmodifiable(_backups);
  bool get isLoadingBackups => _isLoadingBackups;

  bool isSwitching(String tool) => _switchingTools.contains(tool);
  ToolLiveState? liveState(String tool) => _liveStates[tool];

  List<Provider> get filteredProviders {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return providers;
    return _providers.where((p) {
      return p.name.toLowerCase().contains(q) ||
          (p.nameZh?.toLowerCase().contains(q) ?? false) ||
          (p.apiEndpoint?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// 支持指定工具且已启用的供应商
  List<Provider> providersForTool(String tool) =>
      _providers.where((p) => p.isActive && p.supportedTools.contains(tool)).toList();

  /// 指定工具当前使用的供应商（由 Key Core 切换记录）
  Provider? currentProvider(String tool) {
    final id = _currentByTool[tool];
    if (id == null) return null;
    for (final p in _providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 正在被哪些工具使用
  List<String> toolsUsing(String providerId) =>
      _currentByTool.entries.where((e) => e.value == providerId).map((e) => e.key).toList();

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// 加载全部数据
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _presets = await _backend.loadPresets();
      _providers = await _backend.getAllProviders();
      try {
        _encryptionEnabled = await _backend.isEncryptionEnabled();
      } catch (_) {
        // 系统安全存储不可用时按未加密展示；保存时 ProviderManagerService 会报错而不是静默写入明文
        _encryptionEnabled = false;
      }
      _currentByTool = Map<String, String>.from(await _backend.loadCurrentSelections());
      await refreshLiveStates(notify: false);
      _loaded = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLiveStates({bool notify = true}) async {
    for (final tool in tools) {
      try {
        _liveStates[tool] = await _backend.readLiveState(tool);
      } catch (_) {
        _liveStates.remove(tool);
      }
    }
    if (notify) notifyListeners();
  }

  /// 根据表单数据构造 Provider（新建时 [existing] 为空）
  static Provider buildProvider(ProviderDraft draft, {Provider? existing, DateTime? now}) {
    final ts = now ?? DateTime.now();
    final base = existing ?? draft.preset;
    var models = List<ProviderModel>.from(base?.models ?? const []);
    final defaultModel = draft.defaultModel?.trim();
    if (defaultModel != null && defaultModel.isNotEmpty) {
      final idx = models.indexWhere((m) => m.id == defaultModel);
      final chosen = idx >= 0
          ? models.removeAt(idx)
          : ProviderModel(id: defaultModel, displayName: defaultModel);
      models = [chosen, ...models];
    }
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final newKey = clean(draft.apiKey);

    if (existing != null) {
      return existing.copyWith(
        name: draft.name.trim(),
        apiEndpoint: clean(draft.endpoint),
        apiKey: newKey ?? existing.apiKey,
        models: models,
        supportedTools: draft.supportedTools,
        websiteUrl: clean(draft.websiteUrl),
        description: clean(draft.description),
        updatedAt: ts,
      );
    }

    final preset = draft.preset;
    return Provider(
      id: '${preset?.id ?? 'custom'}-${ts.millisecondsSinceEpoch}',
      name: draft.name.trim(),
      nameZh: preset?.nameZh,
      providerType: preset?.providerType ?? 'custom',
      apiEndpoint: clean(draft.endpoint),
      apiKey: newKey,
      models: models,
      supportedTools: draft.supportedTools,
      region: preset?.region,
      planType: preset?.planType,
      iconUrl: preset?.iconUrl,
      websiteUrl: clean(draft.websiteUrl) ?? preset?.websiteUrl,
      apiKeyUrl: preset?.apiKeyUrl,
      isActive: true,
      createdAt: ts,
      updatedAt: ts,
      description: clean(draft.description) ?? preset?.description,
      isSponsored: preset?.isSponsored ?? false,
      family: preset?.family,
    );
  }

  /// 新建或更新供应商；返回保存后的对象
  Future<Provider> saveDraft(ProviderDraft draft, {Provider? existing}) async {
    final provider = buildProvider(draft, existing: existing);
    await _backend.saveProvider(provider);
    _providers = await _backend.getAllProviders();
    notifyListeners();
    return provider;
  }

  Future<void> setActive(Provider provider, bool active) async {
    await _backend.saveProvider(provider.copyWith(isActive: active, updatedAt: DateTime.now()));
    _providers = await _backend.getAllProviders();
    notifyListeners();
  }

  Future<void> deleteProvider(Provider provider) async {
    await _backend.deleteProvider(provider.id);
    for (final tool in toolsUsing(provider.id)) {
      _currentByTool.remove(tool);
      await _backend.saveCurrentSelection(tool, null);
    }
    _providers = await _backend.getAllProviders();
    notifyListeners();
  }

  /// 一键切换：把 [provider] 写入 [tool] 的配置
  Future<void> switchTool(String tool, Provider provider) async {
    _switchingTools.add(tool);
    notifyListeners();
    try {
      await _backend.switchTool(provider, tool);
      _currentByTool[tool] = provider.id;
      await _backend.saveCurrentSelection(tool, provider.id);
      try {
        _liveStates[tool] = await _backend.readLiveState(tool);
      } catch (_) {}
      if (tool == _backupTool) await _reloadBackups(notify: false);
    } finally {
      _switchingTools.remove(tool);
      notifyListeners();
    }
  }

  Future<void> selectBackupTool(String tool) async {
    _backupTool = tool;
    await loadBackups();
  }

  Future<void> loadBackups() => _reloadBackups();

  Future<void> _reloadBackups({bool notify = true}) async {
    _isLoadingBackups = true;
    if (notify) notifyListeners();
    try {
      _backups = await _backend.listBackups(_backupTool);
    } catch (_) {
      _backups = [];
    } finally {
      _isLoadingBackups = false;
      if (notify) notifyListeners();
    }
  }

  /// 从备份恢复；恢复后配置可能不再对应任何供应商，因此清除切换记录
  Future<void> restoreBackup(ConfigBackup backup) async {
    final tool = _backupTool;
    await _backend.restoreBackup(tool, backup.path);
    _currentByTool.remove(tool);
    await _backend.saveCurrentSelection(tool, null);
    try {
      _liveStates[tool] = await _backend.readLiveState(tool);
    } catch (_) {}
    await _reloadBackups();
  }
}
