// 详情抽屉「更多工具」：接 PR #27 的 ViewModel API（setKeyToolConfig / applyKeyToTool / removeKeyFromTool /
// switchGrokBuildToOfficial / getToolAppliedKeyIds / getToolDefaultKeyId）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/mcp_server.dart';
import 'package:key_core/utils/platform_icon_service.dart';
import 'package:key_core/views/widgets/key_details_dialog.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/fake_keys.dart';
import '../fixtures/test_app.dart';

class _VM extends FakeKeyManagerViewModel {
  _VM(super.keys);
  final applied = <AiToolType, Set<int>>{};
  int? grokDefault;
  final calls = <String>[];

  @override
  Future<Set<int>> getToolAppliedKeyIds(AiToolType tool) async => applied[tool] ?? {};
  @override
  Future<int?> getToolDefaultKeyId(AiToolType tool) async => tool == AiToolType.grokBuild ? grokDefault : null;
  @override
  Future<bool> setKeyToolConfig(int keyId, AiToolType tool, {required bool enabled, String? baseUrl, String? model}) async {
    calls.add('set ${tool.value} $enabled');
    return true;
  }
  @override
  Future<bool> applyKeyToTool(AiToolType tool, int keyId, {bool makeDefault = true}) async {
    calls.add('apply ${tool.value}');
    (applied[tool] ??= {}).add(keyId);
    if (tool == AiToolType.grokBuild) grokDefault = keyId;
    return true;
  }
  @override
  Future<bool> removeKeyFromTool(AiToolType tool, int keyId) async {
    calls.add('remove ${tool.value}');
    applied[tool]?.remove(keyId);
    return true;
  }
  @override
  Future<bool> switchGrokBuildToOfficial() async {
    calls.add('official');
    grokDefault = null;
    applied[AiToolType.grokBuild]?.clear();
    return true;
  }
}

Finder byKey(String k) => find.byKey(ValueKey(k));

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    await PlatformIconService.init();
  });

  testWidgets('五个新工具都有一行；开关→写入→（Grok）切回官方 / 移除', (t) async {
    await setSurface(t, const Size(900, 700));
    final keys = buildFakeKeys();
    final vm = _VM(keys);
    await t.pumpWidget(buildTestApp(
        viewModel: vm,
        home: Scaffold(body: SingleChildScrollView(child: NewToolsSection(aiKey: keys.first, viewModel: vm)))));
    await settle(t, rounds: 4);
    for (final id in ['opencode', 'grok_build', 'hermes', 'pi', 'mcode']) {
      final rows = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('newTools.row.'));
      expect(rows, findsNWidgets(5), reason: id);
    }
    final grok = AiToolType.grokBuild.value;
    // 未启用时「写入」不可点
    await t.tap(byKey('newTools.apply.$grok'));
    await settle(t);
    expect(vm.calls, isEmpty);
    await t.tap(byKey('newTools.enable.$grok'));
    await settle(t, rounds: 3);
    await t.tap(byKey('newTools.apply.$grok'));
    await settle(t, rounds: 3);
    expect(find.text('生效中'), findsOneWidget);
    await t.tap(byKey('newTools.grokOfficial'));
    await settle(t, rounds: 3);
    expect(vm.calls, ['set $grok true', 'apply $grok', 'official']);
    final oc = AiToolType.opencode.value;
    await t.tap(byKey('newTools.enable.$oc'));
    await settle(t, rounds: 3);
    await t.tap(byKey('newTools.apply.$oc'));
    await settle(t, rounds: 3);
    expect(find.text('已写入'), findsOneWidget);
    await t.tap(byKey('newTools.remove.$oc'));
    await settle(t, rounds: 3);
    expect(vm.calls.last, 'remove $oc');
  });
}
