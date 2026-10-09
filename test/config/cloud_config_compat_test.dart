import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/cloud_config.dart';
import 'package:key_core/services/cloud_config_service.dart';

/// 远程配置的版本兼容：schemaVersion 门槛、缓存无损、升级后自带配置优先
void main() {
  Map<String, dynamic> base() =>
      jsonDecode(File('assets/config/app_config.json').readAsStringSync()) as Map<String, dynamic>;

  CloudConfig make({String? version, String? lastUpdated, int? schema, void Function(Map<String, dynamic>)? edit}) {
    final j = base();
    if (version != null) j['version'] = version;
    if (lastUpdated != null) j['lastUpdated'] = lastUpdated;
    if (schema != null) j['schemaVersion'] = schema;
    edit?.call(j);
    return CloudConfig.fromJson(j);
  }

  test('schemaVersion 高于本版本支持的远程配置会被拒绝', () {
    expect(CloudConfigService.isSchemaSupported(make()), isTrue);
    expect(
      CloudConfigService.isSchemaSupported(make(schema: CloudConfigService.maxSupportedSchemaVersion + 1)),
      isFalse,
    );
  });

  test('未知字段（更新版本新增）在缓存往返中不会丢失', () {
    final c = make(edit: (j) {
      (j['config']['providers'] as List).first['futureToolBlock'] = {'x': 1};
      j['config']['futureSection'] = [1, 2];
    });
    final roundTrip = CloudConfig.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    final j = roundTrip.toJson();
    expect((j['config']['providers'] as List).first['futureToolBlock'], {'x': 1});
    expect(j['config']['futureSection'], [1, 2]);
  });

  test('缓存与自带配置比较新旧（先比 version 再比 lastUpdated）', () {
    int cmp(String v, String t) => CloudConfigService.compareCacheWithBundled(make(version: v, lastUpdated: t),
        bundledVersion: '1.2.0', bundledLastUpdated: '2026-10-10T00:00:00');
    expect(cmp('1.1.0', '2026-12-01T00:00:00'), lessThan(0), reason: '升级应用后，旧版本号的缓存不能盖过新自带配置');
    expect(cmp('1.2.0', '2026-10-10T00:00:00'), 0);
    expect(cmp('1.2.0', '2026-10-11T00:00:00'), greaterThan(0));
    expect(cmp('1.3.0', '2026-01-01T00:00:00'), greaterThan(0));
  });
}
