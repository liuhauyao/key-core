// 多密钥端到端：主密码下逐把加密、掩码按子密钥、卡片/工具页切换与工具配置联动改写、
// 删除当前密钥回落，以及导出 → 清空 → 导入的多密钥往返。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/mcp_server.dart' show AiToolType;
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/auth_service.dart';
import 'package:key_core/services/database_service.dart';
import 'package:key_core/services/export_service.dart';
import 'package:key_core/services/import_service.dart';
import 'package:key_core/services/platform_registry.dart';
import 'package:key_core/services/settings_service.dart';
import 'package:key_core/utils/key_mask.dart';
import 'package:key_core/viewmodels/key_manager_viewmodel.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late String home;
  late String settingsPath;

  Future<void> freshDb() async {
    await DatabaseService.instance.close();
    DatabaseService.debugDatabasePathOverride = inMemoryDatabasePath;
  }

  AIKey card({List<KeyEntry>? entries, int active = 0}) {
    final now = DateTime(2026, 10, 10);
    final list = entries ??
        const [
          KeyEntry(value: 'sk-first-1111', label: '主号'),
          KeyEntry(value: 'sk-second-2222', label: '备用', notes: '限流时用'),
        ];
    return AIKey(
      name: 'DS',
      platform: 'DeepSeek',
      platformType: PlatformType.deepSeek,
      keyValue: list[active.clamp(0, list.length - 1)].value,
      keyEntriesRaw: list,
      activeKeyIndex: active,
      apiEndpoint: 'https://api.deepseek.com/anthropic',
      enableClaudeCode: true,
      claudeCodeBaseUrl: 'https://api.deepseek.com/anthropic',
      claudeCodeModel: 'deepseek-chat',
      tags: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('multi_key_');
    home = p.join(tmp.path, 'home');
    Directory(p.join(home, '.claude')).createSync(recursive: true);
    settingsPath = p.join(home, '.claude', 'settings.json');
    File(settingsPath).writeAsStringSync('{}');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    SettingsService.debugHomeDirOverride = home;
    SettingsService.debugResetOfficialKeyCache();
    PlatformRegistry.initBuiltinPlatforms();
    KeyMaskCache.clear();
    await freshDb();
  });

  tearDown(() async {
    await DatabaseService.instance.close();
    SettingsService.debugHomeDirOverride = null;
    SettingsService.debugResetOfficialKeyCache();
    KeyMaskCache.clear();
    tmp.deleteSync(recursive: true);
  });

  String written() => File(settingsPath).readAsStringSync();

  test('主密码：逐把加密 → 子密钥掩码 → 切换当前密钥立即改写工具配置 → 删除当前密钥回落', () async {
    expect(await AuthService().setMasterPassword('Demo#Pass2026', skipValidation: true), isTrue);
    final vm = KeyManagerViewModel();
    expect(await vm.addKey(card()), isTrue);

    final stored = (await DatabaseService.instance.getAllKeys()).single;
    final id = stored.id!;
    expect(stored.keyEntries, hasLength(2));
    for (final e in stored.keyEntries) {
      expect(e.value.startsWith('{'), isTrue, reason: '两把都逐把加密存储');
    }
    expect(stored.keyValue, stored.keyEntries[0].value, reason: 'key_value 列镜像当前那把');
    expect(stored.keyEntries[1].label, '备用');
    expect(stored.keyEntries[1].notes, '限流时用');
    expect(stored.keyEntries[1].createdAt, isNotNull, reason: '新增子密钥补时间戳');

    // 掩码按子密钥取（缓存键 id#index），不显示密文尾巴
    expect(maskKeyForKey(stored, 0), 'sk-••••1111');
    expect(maskKeyForKey(stored, 1), 'sk-••••2222');
    expect(maskKeyForCard(stored), maskKeyForKey(stored, 0));

    // 工具页「设为当前」：卡片当前密钥（第 1 把）生效 → 配置写入明文
    expect(await vm.switchClaudeCodeProvider(id), isTrue);
    expect(written(), contains('sk-first-1111'));
    expect(vm.currentKeyRefs[AiToolType.claudecode]!.entryIndex, 0);

    // 卡片下拉切换到第 2 把（语义 1）：该卡片正在生效 → 立即用新密钥改写配置
    expect(await vm.setActiveKeyEntry(id, 1), isTrue);
    expect(written(), contains('sk-second-2222'));
    expect(written(), isNot(contains('sk-first-1111')));
    final afterSwitch = await DatabaseService.instance.getKeyById(id);
    expect(afterSwitch!.normalizedActiveIndex, 1);
    expect(afterSwitch.keyValue, afterSwitch.keyEntries[1].value, reason: 'key_value 跟随当前密钥');
    expect(vm.currentKeyRefs[AiToolType.claudecode]!.entryIndex, 1, reason: '生效引用跟着当前密钥走');

    // 删掉当前密钥（第 2 把）→ 下标向左收敛到 0，配置改写为回落后的那把
    expect(await vm.deleteKeyEntry(id, 1), isTrue);
    expect(written(), contains('sk-first-1111'));
    expect(written(), isNot(contains('sk-second-2222')));
    final afterDelete = await DatabaseService.instance.getKeyById(id);
    expect(afterDelete!.keyEntries, hasLength(1));
    expect(afterDelete.keyValue, afterDelete.keyEntries[0].value);
    expect(afterDelete.keyEntries.single.label, '主号');
    expect(vm.currentKeyRefs[AiToolType.claudecode]!.entryIndex, 0);
    // 再删最后一把：拒绝
    expect(await vm.deleteKeyEntry(id, 0), isFalse);
    expect((await DatabaseService.instance.getKeyById(id))!.keyEntries, hasLength(1));
  });

  test('子密钥独立地址：切换当前密钥后工具配置的请求地址跟着改写', () async {
    final vm = KeyManagerViewModel();
    expect(
      await vm.addKey(card(entries: const [
        KeyEntry(value: 'sk-first-1111', label: '主号'),
        KeyEntry(value: 'sk-second-2222', label: '备用', endpoint: 'https://plan-b.example.com'),
      ])),
      isTrue,
    );
    final id = (await DatabaseService.instance.getAllKeys()).single.id!;

    expect(await vm.switchClaudeCodeProvider(id), isTrue);
    expect(written(), contains('https://api.deepseek.com/anthropic'), reason: '第 1 把未配置独立地址，沿用卡片默认地址');

    expect(await vm.setActiveKeyEntry(id, 1), isTrue);
    expect(written(), contains('sk-second-2222'));
    expect(written(), contains('https://plan-b.example.com/anthropic'), reason: '只填域名时保留工具默认路径');
    expect(written(), isNot(contains('https://api.deepseek.com/anthropic')));

    expect(await vm.setActiveKeyEntry(id, 0), isTrue);
    expect(written(), contains('https://api.deepseek.com/anthropic'), reason: '切回不带独立地址的那把，恢复默认地址');
  });

  test('导出 → 清空 → 导入：多把子密钥与当前下标原样往返，并按当前主密码重新加密', () async {
    // 先无主密码（明文库）写入多密钥卡片
    final vm = KeyManagerViewModel();
    expect(await vm.addKey(card(active: 1)), isTrue);
    final before = (await DatabaseService.instance.getAllKeys()).single;
    expect(before.keyEntries, hasLength(2));

    final out = p.join(tmp.path, 'export.json');
    await ExportService().exportKeys(out);
    final exported = (jsonDecode(File(out).readAsStringSync())['keys'] as List).single as Map;
    expect(exported['key_value'], 'sk-second-2222', reason: '当前那把镜像到 key_value');
    final entriesOut = exported['key_entries'] as Map;
    expect(entriesOut['active'], 1);
    final items = (entriesOut['items'] as List).cast<Map>();
    expect(items.map((e) => e['value']), ['sk-first-1111', 'sk-second-2222']);
    expect(items.map((e) => e['label']), ['主号', '备用']);
    expect(items[1]['notes'], '限流时用');
    expect(items.every((e) => !e['value'].toString().startsWith('{')), isTrue, reason: '导出为明文，形状与 key_entries 列一致');

    // 清空数据库，并给应用设主密码 → 导入时必须逐把重新加密
    await freshDb();
    expect(await AuthService().setMasterPassword('Demo#Pass2026', skipValidation: true), isTrue);

    final r = await ImportService().importKeys(out, null);
    expect(r.success, isTrue, reason: r.errors.join('\n'));
    expect(r.importedCount, 1);

    final restored = (await DatabaseService.instance.getAllKeys()).single;
    expect(restored.keyEntries, hasLength(2));
    expect(restored.normalizedActiveIndex, 1);
    for (final e in restored.keyEntries) {
      expect(e.value.startsWith('{'), isTrue, reason: '导入时按当前主密码重新加密');
    }
    expect(restored.keyEntries[1].notes, '限流时用');
    expect(restored.keyValue, restored.keyEntries[1].value);

    // 解密后仍是原来的两把（新 VM 走真实解密路径）
    final vm2 = KeyManagerViewModel();
    await vm2.loadKeys(showLoading: false);
    final shown = vm2.allKeys.single;
    expect(maskKeyForKey(shown, 0), 'sk-••••1111');
    expect(maskKeyForKey(shown, 1), 'sk-••••2222');
  });

  test('旧导出文件（无 key_entries）仍按 key_value 还原成单密钥卡片', () async {
    final out = p.join(tmp.path, 'old.json');
    File(out).writeAsStringSync(jsonEncode({
      'version': '1.0.0',
      'keys': [
        {
          'name': 'Legacy',
          'platform': 'DeepSeek',
          'platform_type_id': 'deepSeek',
          'key_value': 'sk-legacy-9999',
        }
      ],
    }));
    final r = await ImportService().importKeys(out, null);
    expect(r.success, isTrue, reason: r.errors.join());
    final key = (await DatabaseService.instance.getAllKeys()).single;
    expect(key.keyEntries, hasLength(1));
    expect(key.keyEntries.single.value, 'sk-legacy-9999');
    expect(key.hasMultipleKeys, isFalse);
    expect(await DatabaseService.instance.getKeyByNameAndPlatform('Legacy', 'DeepSeek'), isNotNull);
  });
}
