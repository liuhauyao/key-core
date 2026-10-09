// 不访问数据库 / 配置文件的 KeyManagerViewModel 替身。
//
// 只覆盖钥匙包网格用到的读写入口，并记录调用，便于断言
// 「拖拽排序 / 置顶 / 删除」等交互最终调用了哪个 ViewModel 方法、参数是什么。
// reorderKeys 的「筛选子集在前 + 其余保持原序」合并规则与生产实现一致。
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/mcp_server.dart' show AiToolType;
import 'package:key_core/services/database_service.dart';
import 'package:key_core/viewmodels/key_manager_viewmodel.dart';

class FakeKeyManagerViewModel extends KeyManagerViewModel {
  FakeKeyManagerViewModel(List<AIKey> keys) : _all = List.of(keys);

  List<AIKey> _all;
  String _query = '';

  final List<List<int?>> reorderCalls = [];
  final List<int> moveToTopCalls = [];
  final List<int> deleteCalls = [];
  final Map<String, List<int>> switchCalls = {};
  final List<int> decryptCalls = [];

  /// 各工具当前生效的密钥（测试可直接改写）；切换成功会更新它
  final Map<AiToolType, int?> current = {
    AiToolType.claudecode: null,
    AiToolType.claudeDesktop: null,
    AiToolType.codex: null,
    AiToolType.gemini: null,
  };

  /// 为 true 时所有 switch* 返回失败
  bool failSwitches = false;

  @override
  Map<AiToolType, int?> get currentKeyIds => Map.of(current);

  @override
  bool get currentToolKeysLoaded => true;

  @override
  Future<void> refreshCurrentToolKeys() async => notifyListeners();

  @override
  List<AIKey> get keys => _query.isEmpty
      ? _all
      : _all.where((k) => k.name.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  List<AIKey> get allKeys => _all;

  @override
  KeyStatistics? get statistics => KeyStatistics(
        total: _all.length,
        active: _all.length,
        inactive: 0,
        expiringSoon: 0,
        expired: 0,
        favorites: _all.where((k) => k.isFavorite).length,
      );

  @override
  Future<void> init() async {}

  @override
  Future<void> loadKeys({bool showLoading = true}) async {}

  @override
  Future<void> refresh() async {}

  @override
  void setSearchQuery(String query) {
    _query = query;
    notifyListeners();
  }

  @override
  Future<bool> reorderKeys(List<AIKey> reorderedKeys) async {
    reorderCalls.add(reorderedKeys.map((k) => k.id).toList());
    final ids = reorderedKeys.map((k) => k.id).toSet();
    _all = [...reorderedKeys, ..._all.where((k) => !ids.contains(k.id))];
    notifyListeners();
    return true;
  }

  @override
  Future<bool> moveKeyToTop(int keyId) async {
    moveToTopCalls.add(keyId);
    final visible = List.of(keys);
    final i = visible.indexWhere((k) => k.id == keyId);
    if (i <= 0) return i == 0;
    visible.insert(0, visible.removeAt(i));
    return reorderKeys(visible);
  }

  @override
  Future<bool> deleteKey(int id) async {
    deleteCalls.add(id);
    _all = _all.where((k) => k.id != id).toList();
    notifyListeners();
    return true;
  }

  final List<AIKey> updateCalls = [];

  /// 工具页：配置文件是否存在（false 时页面显示常驻提示条）
  bool toolConfigExists = true;

  Map<String, dynamic> _configCheck() =>
      {'anyExists': toolConfigExists, 'configExists': toolConfigExists, 'configDir': '/home/test/.tool'};

  @override
  Future<Map<String, dynamic>> checkClaudeCodeConfigExists() async => _configCheck();
  @override
  Future<Map<String, dynamic>> checkCodexConfigExists() async => _configCheck();
  @override
  Future<Map<String, dynamic>> checkGeminiConfigExists() async => _configCheck();
  @override
  Future<Map<String, dynamic>> checkClaudeDesktopConfigExists() async => _configCheck();

  @override
  Future<List<AIKey>> getClaudeCodeKeys() async => _all.where((k) => k.enableClaudeCode).toList();
  @override
  Future<List<AIKey>> getCodexKeys() async => _all.where((k) => k.enableCodex).toList();
  @override
  Future<List<AIKey>> getGeminiKeys() async => _all.where((k) => k.enableGemini).toList();
  @override
  Future<List<AIKey>> getClaudeDesktopKeys() async => _all.where((k) => k.enableClaudeDesktop).toList();
  @override
  Future<bool> isOfficialClaudeDesktopConfig() async => current[AiToolType.claudeDesktop] == null;

  @override
  Future<bool> updateKey(AIKey key) async {
    updateCalls.add(key);
    _all = [for (final k in _all) k.id == key.id ? key : k];
    notifyListeners();
    return true;
  }

  @override
  Future<AIKey?> getDecryptedKey(int id) async {
    decryptCalls.add(id);
    return _all.firstWhere((k) => k.id == id);
  }

  bool _recordSwitch(String tool, int keyId, AiToolType t) {
    (switchCalls[tool] ??= []).add(keyId);
    if (failSwitches) return false;
    current[t] = keyId;
    notifyListeners();
    return true;
  }

  AIKey? _byId(int? id) {
    if (id == null) return null;
    for (final k in _all) {
      if (k.id == id) return k;
    }
    return null;
  }

  @override
  Future<bool> switchClaudeCodeProvider(int keyId) async =>
      _recordSwitch('claudeCode', keyId, AiToolType.claudecode);

  @override
  Future<bool> switchCodexProvider(int keyId) async =>
      _recordSwitch('codex', keyId, AiToolType.codex);

  @override
  Future<bool> switchGeminiProvider(int keyId) async =>
      _recordSwitch('gemini', keyId, AiToolType.gemini);

  @override
  Future<bool> switchClaudeDesktopProvider(int keyId) async =>
      _recordSwitch('claudeDesktop', keyId, AiToolType.claudeDesktop);

  final List<String> officialCalls = [];

  bool _official(String tool, AiToolType t) {
    officialCalls.add(tool);
    if (failSwitches) return false;
    current[t] = null;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> switchToOfficialClaudeCode() async => _official('claudeCode', AiToolType.claudecode);
  @override
  Future<bool> switchToOfficialCodex() async => _official('codex', AiToolType.codex);
  @override
  Future<bool> switchToOfficialGemini() async => _official('gemini', AiToolType.gemini);
  @override
  Future<bool> switchToOfficialClaudeDesktop() async => _official('claudeDesktop', AiToolType.claudeDesktop);

  @override
  Future<AIKey?> getCurrentClaudeCodeKey() async => _byId(current[AiToolType.claudecode]);
  @override
  Future<AIKey?> getCurrentCodexKey() async => _byId(current[AiToolType.codex]);
  @override
  Future<AIKey?> getCurrentGeminiKey() async => _byId(current[AiToolType.gemini]);
  @override
  Future<AIKey?> getCurrentClaudeDesktopKey() async => _byId(current[AiToolType.claudeDesktop]);
}
