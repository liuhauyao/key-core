import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/secure_storage_service.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 模拟系统钥匙串不可用（如未签名的 macOS 构建报 -34018）
class _FailingSecureStorage extends SecureStorageService {
  @override
  Future<void> writeSecret(String key, String value) async => throw Exception('-34018');
  @override
  Future<String?> readSecret(String key) async => throw Exception('-34018');
  @override
  Future<void> deleteSecret(String key) async => throw Exception('-34018');
}

/// 写入成功但读回不一致（迁移校验失败）
class _CorruptingSecureStorage extends SecureStorageService {
  final Map<String, String> data = {};
  @override
  Future<void> writeSecret(String key, String value) async => data[key] = '$value-corrupted';
  @override
  Future<String?> readSecret(String key) async => data[key];
  @override
  Future<void> deleteSecret(String key) async => data.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SettingsService.secureStorage = SecureStorageService();
    SettingsService.debugResetOfficialKeyCache();
  });

  tearDown(() {
    SettingsService.secureStorage = SecureStorageService();
    SettingsService.debugResetOfficialKeyCache();
  });

  test('legacy plaintext keys are migrated to the keychain and removed from preferences', () async {
    SharedPreferences.setMockInitialValues({
      'official_claude_api_key': 'sk-ant-legacy',
      'official_codex_api_key': 'sk-openai-legacy',
      'official_gemini_api_key': 'AIza-legacy',
      'official_claude_desktop_api_key': 'sk-desk-legacy',
      'unrelated': 'keep',
    });

    final settings = SettingsService();
    await settings.init();

    expect(settings.getOfficialClaudeApiKey(), 'sk-ant-legacy');
    expect(settings.getOfficialCodexApiKey(), 'sk-openai-legacy');
    expect(settings.getOfficialGeminiApiKey(), 'AIza-legacy');
    expect(settings.getOfficialClaudeDesktopApiKey(), 'sk-desk-legacy');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('official_claude_api_key'), isNull);
    expect(prefs.getString('official_codex_api_key'), isNull);
    expect(prefs.getString('official_gemini_api_key'), isNull);
    expect(prefs.getString('official_claude_desktop_api_key'), isNull);
    expect(prefs.getString('unrelated'), 'keep');

    expect(await storage.read(key: 'official_api_key.claude'), 'sk-ant-legacy');
    expect(await storage.read(key: 'official_api_key.codex'), 'sk-openai-legacy');
    expect(await storage.read(key: 'official_api_key.gemini'), 'AIza-legacy');
    expect(await storage.read(key: 'official_api_key.claude_desktop'), 'sk-desk-legacy');
  });

  test('keys already in the keychain are loaded on the next start', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'official_api_key.gemini': 'AIza-stored'});

    final settings = SettingsService();
    await settings.init();
    expect(settings.getOfficialGeminiApiKey(), 'AIza-stored');
    expect(settings.getOfficialClaudeApiKey(), isNull);
  });

  test('migration is idempotent across restarts', () async {
    SharedPreferences.setMockInitialValues({'official_claude_api_key': 'sk-1'});
    await SettingsService().init();

    SettingsService.debugResetOfficialKeyCache();
    final restarted = SettingsService();
    await restarted.init();
    expect(restarted.getOfficialClaudeApiKey(), 'sk-1');
    expect((await SharedPreferences.getInstance()).getString('official_claude_api_key'), isNull);
  });

  test('setters write to the keychain, never to preferences; clearing deletes', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();

    await settings.setOfficialCodexApiKey('  sk-new  ');
    expect(settings.getOfficialCodexApiKey(), 'sk-new');
    expect(await storage.read(key: 'official_api_key.codex'), 'sk-new');
    expect((await SharedPreferences.getInstance()).getString('official_codex_api_key'), isNull);

    await settings.setOfficialCodexApiKey('');
    expect(settings.getOfficialCodexApiKey(), isNull);
    expect(await storage.read(key: 'official_api_key.codex'), isNull);
  });

  test('getter values are shared between SettingsService instances', () async {
    SharedPreferences.setMockInitialValues({});
    final a = SettingsService();
    await a.init();
    await a.setOfficialClaudeDesktopApiKey('sk-d');
    final b = SettingsService();
    await b.init();
    expect(b.getOfficialClaudeDesktopApiKey(), 'sk-d');
  });

  test('keychain unavailable: legacy key stays in preferences and keeps working (no data loss)', () async {
    SharedPreferences.setMockInitialValues({'official_claude_api_key': 'sk-legacy'});
    SettingsService.secureStorage = _FailingSecureStorage();

    final settings = SettingsService();
    await settings.init();
    expect(settings.getOfficialClaudeApiKey(), 'sk-legacy');
    expect((await SharedPreferences.getInstance()).getString('official_claude_api_key'), 'sk-legacy');

    // 保存同样退回本地设置，不会抛错导致用户无法保存
    await settings.setOfficialClaudeApiKey('sk-updated');
    expect(settings.getOfficialClaudeApiKey(), 'sk-updated');
    expect((await SharedPreferences.getInstance()).getString('official_claude_api_key'), 'sk-updated');
  });

  test('read-back mismatch keeps the plaintext key instead of deleting it', () async {
    SharedPreferences.setMockInitialValues({'official_gemini_api_key': 'AIza-legacy'});
    SettingsService.secureStorage = _CorruptingSecureStorage();

    final settings = SettingsService();
    await settings.init();
    expect(settings.getOfficialGeminiApiKey(), 'AIza-legacy');
    expect((await SharedPreferences.getInstance()).getString('official_gemini_api_key'), 'AIza-legacy');
  });

  test('a key saved to preferences while the keychain was unavailable is migrated later', () async {
    SharedPreferences.setMockInitialValues({'official_codex_api_key': 'sk-newer'});
    FlutterSecureStorage.setMockInitialValues({'official_api_key.codex': 'sk-older'});

    final settings = SettingsService();
    await settings.init();
    expect(settings.getOfficialCodexApiKey(), 'sk-newer');
    expect(await storage.read(key: 'official_api_key.codex'), 'sk-newer');
    expect((await SharedPreferences.getInstance()).getString('official_codex_api_key'), isNull);
  });

  test('clearAllSettings also removes official keys from the keychain', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    await settings.init();
    await settings.setOfficialClaudeApiKey('sk-x');
    await settings.clearAllSettings();
    expect(settings.getOfficialClaudeApiKey(), isNull);
    expect(await storage.read(key: 'official_api_key.claude'), isNull);
  });
}
