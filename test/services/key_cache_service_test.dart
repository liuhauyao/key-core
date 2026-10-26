// 校验缓存升级兼容：v23 之前按卡片缓存（`key_validation_<id>`），
// 之后按子密钥缓存（`key_validation_<id>#<下标>`）；第 1 把回读老键，
// 避免老卡片升级后校验徽标凭空消失。
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/key_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 27);

  AIKey card({List<KeyEntry>? entries, int active = 0}) => AIKey(
        id: 7,
        name: 'DS',
        platform: 'DeepSeek',
        platformType: PlatformType.deepSeek,
        keyValue: entries == null ? 'sk-a' : entries[active].value,
        keyEntriesRaw: entries,
        activeKeyIndex: active,
        tags: const [],
        createdAt: now,
        updatedAt: now,
      );

  test('老卡片级校验缓存升级后仍能读到（只对第 1 把回读）', () async {
    SharedPreferences.setMockInitialValues({'key_validation_7': true});
    final service = KeyCacheService();

    expect(await service.getValidationStatus(card()), isTrue, reason: '老卡片只有卡片级缓存键');
    final multi = card(
      entries: const [KeyEntry(value: 'sk-a'), KeyEntry(value: 'sk-b')],
    );
    expect(await service.getValidationStatus(multi), isTrue);
    expect(
      await service.getValidationStatus(multi, entryIndex: 1),
      isNull,
      reason: '第 2 把没有老缓存，不能借用第 1 把的状态',
    );
  });

  test('子密钥缓存优先于老键；清缓存同时移除老键', () async {
    SharedPreferences.setMockInitialValues({
      'key_validation_7': true,
      'key_validation_7#0': false,
    });
    final service = KeyCacheService();
    final key = card();

    expect(await service.getValidationStatus(key), isFalse, reason: '按子密钥的新缓存优先');

    await service.clearCache(key);
    expect(await service.getValidationStatus(key), isNull, reason: '老键也要清掉，否则又被回读');
  });
}
