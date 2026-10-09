// 每个内置平台（custom 除外）都必须解析到仓库里真实存在的 logo 文件（ui_redesign_plan.md §4.6）。
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/models/platform_type.dart';
import 'package:key_core/services/platform_registry.dart';
import 'package:key_core/utils/platform_icon_service.dart';

import '../fixtures/test_app.dart';

void main() {
  setUpAll(() async {
    installTestPlatformMocks();
    PlatformRegistry.initBuiltinPlatforms();
    await PlatformIconService.init();
  });

  test('内置平台都有真实 logo（custom 走首字回退）', () {
    final builtins = PlatformRegistry.all.where((p) => p.isBuiltin).toList();
    expect(builtins.length, greaterThan(40));
    final missing = <String>[];
    for (final p in builtins) {
      if (p.id == PlatformType.custom.id) continue;
      final path = PlatformIconService.getIconAssetPath(p);
      if (path == null || !File(path).existsSync()) missing.add('${p.id} -> $path');
    }
    expect(missing, isEmpty);
    expect(PlatformIconService.hasBrandLogo(PlatformType.custom), isFalse);
  });

  test('原先缺失的 9 个映射', () {
    const expected = {
      'google': 'gemini-color.svg',
      'kimi': 'kimi-color.svg',
      'qwen': 'qwen-color.svg',
      'wenxin': 'wenxin-color.svg',
      'coze': 'coze.svg',
      'katCoder': 'kwaikat.svg',
      'bailing': 'bailing-color.png',
      'dmxapi': 'dmxapi-color.svg',
      'packycode': 'packycode.svg',
    };
    expected.forEach((id, file) {
      final p = PlatformRegistry.get(id) ?? PlatformType.dynamic(id: id, value: id, iconName: 'x', color: const Color(0xFF000000));
      expect(PlatformIconService.getIconFileName(p), file, reason: id);
      expect(File('assets/icons/platforms/$file').existsSync(), isTrue, reason: file);
    });
  });

  test('配置中写了 icon 的 provider 仍优先使用配置', () {
    expect(PlatformIconService.getIconFileName(PlatformType.deepSeek), 'deepseek-color.svg');
    expect(PlatformIconService.getIconFileName(PlatformType.anthropic), 'anthropic.svg');
  });

  testWidgets('新增 / 新映射的 logo 都能被 flutter_svg / Image 解码', (tester) async {
    for (final f in const ['packycode.svg', 'dmxapi-color.svg', 'kwaikat.svg', 'qwen-color.svg', 'wenxin-color.svg', 'coze.svg', 'kimi-color.svg', 'gemini-color.svg']) {
      final loader = SvgAssetLoader('assets/icons/platforms/$f');
      final info = await tester.runAsync(() => vg.loadPicture(loader, null));
      expect(info, isNotNull, reason: f);
      expect(info!.size.width, greaterThan(0), reason: f);
      info.picture.dispose();
    }
    final bytes = File('assets/icons/platforms/bailing-color.png').readAsBytesSync();
    expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
  });
}
