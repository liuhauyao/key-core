import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/auth_service.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/platform_registry.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:key_core/utils/key_mask.dart';
import 'package:key_core/viewmodels/key_manager_viewmodel.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 主密码开启时：卡片 / 工具页掩码必须来自解密后的真实密钥，而不是密文尾巴；
/// 写入 Claude Code 的配置必须是明文密钥。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory tmp;
  late String home;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('mp_mask_');
    home = p.join(tmp.path, 'home');
    Directory(p.join(home, '.claude')).createSync(recursive: true);
    File(p.join(home, '.claude', 'settings.json')).writeAsStringSync('{}');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SettingsService.debugHomeDirOverride = home;
    PlatformRegistry.initBuiltinPlatforms();
    await DatabaseService.instance.close();
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
    KeyMaskCache.clear();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    SettingsService.debugHomeDirOverride = null;
    tmp.deleteSync(recursive: true);
  });

  test('明文掩码与「加密值拿不到缓存」时只显示圆点', () {
    final now = DateTime(2026);
    AIKey k(String v, {int? id}) => AIKey(id: id, name: 'x', platform: 'x', platformType: PlatformType.deepSeek, keyValue: v, tags: const [], createdAt: now, updatedAt: now);
    expect(maskKeyForCard(k('sk-abcdefgh1234')), 'sk-••••1234');
    // 加密 JSON（nonce 在 JSON 内，keyNonce 为空）——旧实现会显示 `"}` 之类的密文尾巴
    expect(maskKeyForCard(k('{"ct":"QUJD==","nonce":"xyz"}', id: 99)), '••••••••');
  });

  test('设置主密码 → 添加密钥 → 卡片掩码是真实尾号 → 写入 Claude Code 为明文', () async {
    expect(await AuthService().setMasterPassword('Demo#Pass2026', skipValidation: true), isTrue);
    final vm = KeyManagerViewModel();
    final now = DateTime(2026, 10, 10);
    expect(
      await vm.addKey(AIKey(
        name: 'DS',
        platform: 'DeepSeek',
        platformType: PlatformType.deepSeek,
        keyValue: 'sk-test-plain-9876',
        apiEndpoint: 'https://api.deepseek.com/anthropic',
        enableClaudeCode: true,
        claudeCodeBaseUrl: 'https://api.deepseek.com/anthropic',
        claudeCodeModel: 'deepseek-chat',
        tags: const [],
        createdAt: now,
        updatedAt: now,
      )),
      isTrue,
    );
    final stored = (await DatabaseService.instance.getAllKeys()).single;
    expect(stored.keyValue, isNot(contains('sk-test-plain-9876')), reason: '应加密存储');
    expect(stored.keyValue.trimLeft().startsWith('{'), isTrue);

    // 「重启」：新 VM 从数据库加载
    KeyMaskCache.clear();
    final vm2 = KeyManagerViewModel();
    await vm2.loadKeys(showLoading: false);
    final shown = maskKeyForCard(vm2.allKeys.single);
    expect(shown, 'sk-••••9876');
    expect(shown.contains('}'), isFalse);

    expect(await vm2.switchClaudeCodeProvider(stored.id!), isTrue);
    final written = File(p.join(home, '.claude', 'settings.json')).readAsStringSync();
    expect(written, contains('sk-test-plain-9876'));
    expect(written, isNot(contains(stored.keyValue)));
    expect(jsonDecode(written), isA<Map>());
  });
}
