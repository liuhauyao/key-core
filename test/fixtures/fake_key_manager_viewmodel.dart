// 不访问数据库 / 配置文件的 KeyManagerViewModel 替身。
//
// 只覆盖钥匙包网格用到的读写入口，并记录调用，便于断言
// 「拖拽排序 / 置顶 / 删除」等交互最终调用了哪个 ViewModel 方法、参数是什么。
// reorderKeys 的「筛选子集在前 + 其余保持原序」合并规则与生产实现一致。
import 'package:key_core/models/ai_key.dart';
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

  @override
  Future<AIKey?> getDecryptedKey(int id) async {
    decryptCalls.add(id);
    return _all.firstWhere((k) => k.id == id);
  }

  void _recordSwitch(String tool, int keyId) =>
      (switchCalls[tool] ??= []).add(keyId);

  @override
  Future<bool> switchClaudeCodeProvider(int keyId) async {
    _recordSwitch('claudeCode', keyId);
    return true;
  }

  @override
  Future<bool> switchCodexProvider(int keyId) async {
    _recordSwitch('codex', keyId);
    return true;
  }

  @override
  Future<bool> switchGeminiProvider(int keyId) async {
    _recordSwitch('gemini', keyId);
    return true;
  }

  @override
  Future<bool> switchClaudeDesktopProvider(int keyId) async {
    _recordSwitch('claudeDesktop', keyId);
    return true;
  }

  @override
  Future<AIKey?> getCurrentClaudeCodeKey() async => null;
  @override
  Future<AIKey?> getCurrentCodexKey() async => null;
  @override
  Future<AIKey?> getCurrentGeminiKey() async => null;
  @override
  Future<AIKey?> getCurrentClaudeDesktopKey() async => null;
}
