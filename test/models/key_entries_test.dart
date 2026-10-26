// 多密钥（子密钥列表）数据层：`key_entries` 列 / 导出文件字段的解析、当前密钥镜像、
// 增删改与当前下标；以及「无该列即单密钥」的老数据零迁移回退。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';

final _now = DateTime(2026, 10, 10);

AIKey _key({
  String value = 'sk-a',
  List<KeyEntry>? entries,
  int active = 0,
  String? nonce,
}) =>
    AIKey(
      id: 1,
      name: 'DS',
      platform: 'DeepSeek',
      platformType: PlatformType.deepSeek,
      keyValue: value,
      keyNonce: nonce,
      keyEntriesRaw: entries,
      activeKeyIndex: active,
      tags: const [],
      createdAt: _now,
      updatedAt: _now,
    );

Map<String, dynamic> _row({Object? keyEntries, String keyValue = 'sk-a', String? nonce}) => {
      'name': 'DS',
      'platform': 'DeepSeek',
      'platform_type': PlatformType.deepSeek.index,
      'platform_type_id': 'deepSeek',
      'key_value': keyValue,
      'key_nonce': nonce,
      'key_entries': keyEntries,
      'created_at': _now.toIso8601String(),
      'updated_at': _now.toIso8601String(),
    };

void main() {
  group('老数据（无 key_entries）', () {
    test('由 key_value 合成唯一一把，行为与单密钥完全一致', () {
      final k = _key(value: 'sk-legacy');
      expect(k.keyEntries, hasLength(1));
      expect(k.keyEntries.single.label, isNull);
      expect(k.hasMultipleKeys, isFalse);
      expect(k.normalizedActiveIndex, 0);
      expect(k.activeEntry.value, 'sk-legacy');
      expect(k.toMap()['key_entries'], isNull, reason: '不写默认值，避免把单密钥升级成多密钥形态');
    });

    test('fromMap 无该列时 activeEntry 取 key_value', () {
      final k = AIKey.fromMap(_row(keyValue: 'sk-legacy'));
      expect(k.keyEntries, hasLength(1));
      expect(k.activeEntry.value, 'sk-legacy');
      expect(k.normalizedActiveIndex, 0);
    });
  });

  group('parseKeyEntries', () {
    test('接受 JSON 字符串与 Map；active 收敛到合法范围', () {
      final raw = jsonEncode({
        'active': 9,
        'items': [
          {'value': 'sk-1', 'label': '主号'},
          {'value': 'sk-2'},
        ],
      });
      final (items, active) = AIKey.parseKeyEntries(raw);
      expect(items, hasLength(2));
      expect(items!.first.label, '主号');
      expect(active, 1, reason: 'active 越界时夹到最后一把');

      final (fromMap, active2) = AIKey.parseKeyEntries({'items': [{'value': 'x'}], 'active': -3});
      expect(fromMap!.single.value, 'x');
      expect(active2, 0);
    });

    test('空 / 无效 / 空列表一律回退为「无该列」', () {
      for (final bad in <Object?>[null, '', '  ', 'not json', '[1,2]', {}, {'items': []}, {'items': 'x'}]) {
        final (items, active) = AIKey.parseKeyEntries(bad);
        expect(items, isNull, reason: '输入：$bad');
        expect(active, 0);
      }
    });

    test('KeyEntry 支持 snake_case 字段（导出文件兼容）', () {
      final (items, _) = AIKey.parseKeyEntries({
        'items': [
          {'value': 'sk-1', 'last_used_at': '2026-10-01T00:00:00.000', 'created_at': '2026-01-01T00:00:00.000', 'validated': 1}
        ],
      });
      expect(items!.single.lastUsedAt, DateTime(2026, 10, 1));
      expect(items.single.createdAt, DateTime(2026, 1, 1));
      expect(items.single.validated, isTrue, reason: 'validated 兼容 SQLite 的 0/1');
    });
  });

  group('当前密钥镜像', () {
    final entries = [
      const KeyEntry(value: 'sk-1', label: '主号', notes: 'n1', validated: true, lastUsedAt: null),
      KeyEntry(value: 'sk-2', label: '备用', validated: false, lastUsedAt: DateTime(2026, 10, 5)),
    ];

    test('切换当前密钥：key_value / 校验态 / 最后使用时间跟随，子密钥列表不变', () {
      final k = _key(value: 'sk-1', entries: entries).withActiveKeyIndex(1);
      expect(k.keyValue, 'sk-2', reason: 'key_value 列镜像当前那把');
      expect(k.lastUsedAt, DateTime(2026, 10, 5));
      expect(k.isValidated, isFalse);
      expect(k.keyEntries, entries);

      final back = k.withActiveKeyIndex(0);
      expect(back.keyValue, 'sk-1');
      expect(back.isValidated, isTrue);
      expect(back.lastUsedAt, isNull);
    });

    test('normalizedActiveIndex 收敛越界下标', () {
      expect(_key(entries: entries, active: 5).normalizedActiveIndex, 1);
      expect(_key(entries: entries, active: -2).normalizedActiveIndex, 0);
    });

    test('单密钥时 keyEntriesRaw 为空，copyWith(keyValue) 仍然生效', () {
      final k = _key(value: 'sk-a').copyWith(keyValue: 'sk-b');
      expect(k.keyValue, 'sk-b');
      expect(k.keyEntries.single.value, 'sk-b');
    });

    test('toMap / fromMap 往返保留多把密钥与当前下标', () {
      final k = _key(entries: entries, active: 1);
      final row = k.toMap()..['id'] = 1;
      final back = AIKey.fromMap(row);
      expect(back.keyEntries, entries);
      expect(back.activeKeyIndex, 1);
      expect(back.keyValue, 'sk-2');
      expect(back.hasMultipleKeys, isTrue);
    });
  });

  group('增删改', () {
    final entries = [
      const KeyEntry(value: 'sk-1', label: '主号'),
      const KeyEntry(value: 'sk-2', label: '备用'),
      const KeyEntry(value: 'sk-3'),
    ];

    test('appendEntry 追加后仍是原当前密钥', () {
      final k = _key(entries: entries, active: 1).appendEntry(const KeyEntry(value: 'sk-4', label: '应急'));
      expect(k.keyEntries.map((e) => e.value), ['sk-1', 'sk-2', 'sk-3', 'sk-4']);
      expect(k.keyValue, 'sk-2');
      expect(k.normalizedActiveIndex, 1);
    });

    test('replaceEntry 只改目标那把；改的是当前密钥时 key_value 跟随', () {
      final k = _key(entries: entries, active: 1).replaceEntry(1, entries[1].copyWith(value: 'sk-2b', validated: true));
      expect(k.keyEntries[1].value, 'sk-2b');
      expect(k.keyValue, 'sk-2b');
      expect(k.isValidated, isTrue);
      expect(k.replaceEntry(9, entries[0]).keyEntries, k.keyEntries, reason: '越界下标不改动');
    });

    test('removeEntry：删当前密钥时下标向左收敛，key_value 换成新的当前密钥', () {
      final k = _key(entries: entries, active: 2).removeEntry(2);
      expect(k.keyEntries.map((e) => e.value), ['sk-1', 'sk-2']);
      expect(k.normalizedActiveIndex, 1);
      expect(k.keyValue, 'sk-2');
    });

    test('removeEntry：删非当前密钥时仍停在原来那把', () {
      final k = _key(entries: entries, active: 2).removeEntry(0);
      expect(k.keyEntries.map((e) => e.value), ['sk-2', 'sk-3']);
      expect(k.normalizedActiveIndex, 1);
      expect(k.keyValue, 'sk-3', reason: '原来生效的仍是 sk-3，只是下标前移');
    });

    test('removeEntry：删当前密钥前面那把时下标跟着前移，当前密钥不变', () {
      final k = _key(entries: entries, active: 1).removeEntry(0);
      expect(k.keyEntries.map((e) => e.value), ['sk-2', 'sk-3']);
      expect(k.normalizedActiveIndex, 0);
      expect(k.activeEntry.value, 'sk-2', reason: '仍是原来那把，不能滑到 sk-3');
    });

    test('removeEntry：只剩一把或下标越界时不动', () {
      final single = _key(value: 'sk-only');
      expect(single.removeEntry(0).keyEntries, hasLength(1));
      expect(_key(entries: entries, active: 0).removeEntry(-1).keyEntries, entries);
      expect(_key(entries: entries, active: 0).removeEntry(3).keyEntries, entries);
    });

    test('withKeyEntries 重建卡片并同步当前密钥', () {
      final k = _key(entries: entries, active: 2).withKeyEntries(
        [const KeyEntry(value: 'sk-x'), const KeyEntry(value: 'sk-y')],
        active: 1,
      );
      expect(k.keyEntries.map((e) => e.value), ['sk-x', 'sk-y']);
      expect(k.keyValue, 'sk-y');
    });
  });

  test('KeyEntry：displayLabel 回退「密钥 N」，JSON 往返等价', () {
    expect(const KeyEntry(value: 'v').displayLabel(0), '密钥 1');
    expect(const KeyEntry(value: 'v', label: '   ').displayLabel(2), '密钥 3');
    expect(const KeyEntry(value: 'v', label: ' 主号 ').displayLabel(0), '主号');

    final e = KeyEntry(
      value: 'sk-1',
      label: '主号',
      notes: 'n',
      validated: true,
      lastUsedAt: DateTime(2026, 10, 5),
      createdAt: DateTime(2026, 1, 1),
    );
    expect(KeyEntry.fromJson(e.toJson()), e);
    expect(KeyEntry.fromJson(const {}).value, '');
    expect(const KeyEntry(value: 'a'), const KeyEntry(value: 'a'));
    expect(const KeyEntry(value: 'a'), isNot(const KeyEntry(value: 'b')));
  });

  group('子密钥独立请求地址', () {
    final entries = [
      const KeyEntry(value: 'sk-1', label: '主号', endpoint: 'https://api.acme.com'),
      const KeyEntry(value: 'sk-2', label: '备用'),
    ];

    test('端点为空的条目回退卡片默认地址', () {
      final k = _key(entries: entries).copyWith(apiEndpoint: 'https://default.example');
      expect(k.hasEntryEndpoints, isTrue);
      expect(k.endpointFor(0), 'https://api.acme.com');
      expect(k.endpointFor(1), 'https://default.example', reason: '未配置则用卡片默认地址');
      expect(k.activeEndpoint, 'https://api.acme.com');
      expect(k.withActiveKeyIndex(1).activeEndpoint, 'https://default.example');
    });

    test('JSON 往返保留 endpoint（兼容 api_endpoint 别名）', () {
      final e = const KeyEntry(value: 'sk-1', endpoint: 'https://api.acme.com/v1');
      expect(KeyEntry.fromJson(e.toJson()).endpoint, 'https://api.acme.com/v1');
      expect(KeyEntry.fromJson(const {'value': 'v', 'api_endpoint': 'https://x.dev'}).endpoint, 'https://x.dev');
      expect(const KeyEntry(value: 'v').hasEndpoint, isFalse);
      expect(const KeyEntry(value: 'v', endpoint: '  ').hasEndpoint, isFalse);
    });

    test('endpointHost 只取主机名（无协议 / 带路径均可）', () {
      expect(const KeyEntry(value: 'v', endpoint: 'https://api.acme.com/v1').endpointHost, 'api.acme.com');
      expect(const KeyEntry(value: 'v', endpoint: 'api.acme.com').endpointHost, 'api.acme.com');
      expect(const KeyEntry(value: 'v', endpoint: 'http://127.0.0.1:8080').endpointHost, '127.0.0.1');
      expect(const KeyEntry(value: 'v').endpointHost, isNull);
    });

    test('projectedForEntry：只有域名时替换 origin、保留各工具路径', () {
      final k = _key(entries: entries).copyWith(
        claudeCodeBaseUrl: 'https://old.example/anthropic',
        codexBaseUrl: 'https://old.example/v1',
        geminiBaseUrl: 'https://old.example/v1beta',
        openclawBaseUrl: 'https://old.example/api',
        claudeDesktopBaseUrl: 'https://old.example/anthropic',
      );
      final t = k.projectedForEntry(0);
      expect(t.apiEndpoint, 'https://api.acme.com');
      expect(t.claudeCodeBaseUrl, 'https://api.acme.com/anthropic');
      expect(t.codexBaseUrl, 'https://api.acme.com/v1');
      expect(t.geminiBaseUrl, 'https://api.acme.com/v1beta');
      expect(t.openclawBaseUrl, 'https://api.acme.com/api');
      expect(t.claudeDesktopBaseUrl, 'https://api.acme.com/anthropic');
    });

    test('projectedForEntry：带路径的完整地址原样用于所有工具', () {
      final k = _key(entries: [
        const KeyEntry(value: 'sk-1', endpoint: 'https://api.acme.com/plan-b/'),
      ]).copyWith(claudeCodeBaseUrl: 'https://old.example/anthropic', codexBaseUrl: 'https://old.example/v1');
      final t = k.projectedForEntry(0);
      expect(t.claudeCodeBaseUrl, 'https://api.acme.com/plan-b', reason: '去掉末尾斜杠');
      expect(t.codexBaseUrl, 'https://api.acme.com/plan-b');
      expect(t.apiEndpoint, 'https://api.acme.com/plan-b/');
    });

    test('projectedForEntry：该把未配置地址时不动卡片地址，只切当前下标', () {
      final k = _key(entries: entries).copyWith(apiEndpoint: 'https://default.example', codexBaseUrl: 'https://old.example/v1');
      final t = k.projectedForEntry(1);
      expect(t.normalizedActiveIndex, 1);
      expect(t.apiEndpoint, 'https://default.example');
      expect(t.codexBaseUrl, 'https://old.example/v1');
      expect(t.keyValue, 'sk-2');
    });
  });
}
