import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/config/provider_config.dart';
import 'package:key_core/models/cloud_config.dart';
import 'package:key_core/services/openclaw_config_service.dart';

/// OpenClaw 平台映射：内置映射必须能被真实预设的 platformType 命中，
/// 且模型列表以（可远程更新的）预设为准
void main() {
  final raw = jsonDecode(File('assets/config/app_config.json').readAsStringSync()) as Map<String, dynamic>;
  final presets = CloudConfig.fromJson(raw).config.providers;
  setUpAll(() => ProviderConfig.debugSetPresets(presets));

  test('每个内置映射都对应一个真实预设（直接或经别名）', () {
    final types = presets.map((p) => p.platformType).toSet();
    final reverseAlias = {for (final e in OpenClawConfigService.platformAliases.entries) e.value: e.key};
    for (final key in OpenClawConfigService.platformMapping.keys) {
      final platformType = types.contains(key) ? key : reverseAlias[key];
      expect(platformType != null && types.contains(platformType), isTrue, reason: '内置映射 $key 没有对应的预设');
    }
  });

  test('Google（platformType=gemini）与 Kimi（moonshot）命中 OpenClaw 内置 provider', () {
    final google = OpenClawConfigService.platformInfoFor('gemini')!;
    expect(google.openclawProviderId, 'google');
    expect(google.envKey, 'GEMINI_API_KEY');
    final kimi = OpenClawConfigService.platformInfoFor('moonshot')!;
    expect(kimi.openclawProviderId, 'moonshot');
    expect(kimi.envKey, 'MOONSHOT_API_KEY');
  });

  test('内置 provider 的模型列表取自预设，而不是代码里写死的旧模型', () {
    for (final p in presets.where((p) => p.openclaw?.models?.isNotEmpty == true)) {
      final info = OpenClawConfigService.platformInfoFor(p.platformType);
      expect(info, isNotNull, reason: p.id);
      expect(info!.models.first.id, p.openclaw!.models!.first.id, reason: p.id);
    }
  });

  test('所有带 openclaw 块的预设都能生成 OpenClaw 配置，且环境变量不冲突', () {
    final envKeys = <String, String>{};
    for (final p in presets.where((p) => p.openclaw != null)) {
      final info = OpenClawConfigService.platformInfoFor(p.platformType);
      expect(info, isNotNull, reason: p.id);
      final prev = envKeys[info!.envKey];
      expect(prev == null, isTrue, reason: '${p.id} 与 $prev 共用 ${info.envKey}');
      envKeys[info.envKey] = p.id;
    }
  });
}
