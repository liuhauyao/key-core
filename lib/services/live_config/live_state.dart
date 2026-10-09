import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../settings_service.dart';
import 'live_config_writer.dart';

/// Key Core 在设备本地记录的“上次写进工具配置的是什么”。
///
/// 借鉴 CC Switch 的 `~/.cc-switch/live-state.json`：用来实现“供应商独有字段切入时写、
/// 切走时只删上一把密钥带进来且值未被用户改过的”。文件位于 `~/.keycore/live-state.json`，
/// 与工具配置在同一次 [LiveConfigWriter.apply] 中提交（原子、0600）。
class LiveState {
  LiveState._();

  /// 测试用：覆盖文件路径
  @visibleForTesting
  static String? debugPathOverride;

  static Future<String> path() async {
    final override = debugPathOverride;
    if (override != null) return override;
    final home = await SettingsService.getUserHomeDir();
    return p.join(home, '.keycore', 'live-state.json');
  }

  /// 读取某个工具的状态（不存在或解析失败时返回空 Map，状态缺失只会让清理更保守）
  static Map<String, dynamic> readSection(String? content, String tool) {
    if (content == null || content.trim().isEmpty) return {};
    try {
      final doc = jsonDecode(content);
      if (doc is Map && doc[tool] is Map) {
        return Map<String, dynamic>.from(doc[tool] as Map);
      }
    } catch (_) {}
    return {};
  }

  /// 生成更新某个工具状态的 [LiveEdit]；状态文件损坏时整体重建（不影响工具配置）。
  static LiveEdit edit(String statePath, String tool, Map<String, dynamic> section) {
    return LiveEdit(
      statePath,
      (current) {
        Map<String, dynamic> doc;
        try {
          final decoded = current == null || current.trim().isEmpty ? null : jsonDecode(current);
          doc = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
        } catch (_) {
          doc = <String, dynamic>{};
        }
        if (section.isEmpty) {
          doc.remove(tool);
        } else {
          doc[tool] = section;
        }
        return JsonPatch.encode(doc, original: current);
      },
      containsSecrets: true,
    );
  }
}
