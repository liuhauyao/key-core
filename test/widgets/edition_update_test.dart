// 版本区分（form_v3.md §10）：App Store 版只在 App Store 更新、无仓库/许可证/GitHub；开源版 GitHub Releases + SHA-256
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:key_core/config/edition.dart';
import 'package:key_core/services/app_update_service.dart';
import 'package:key_core/views/widgets/app_update_section.dart';

import '../fixtures/fake_key_manager_viewmodel.dart';
import '../fixtures/test_app.dart';

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> pump(WidgetTester t, {KcEdition? edition, AppUpdateService? svc}) async {
  await setSurface(t, const Size(900, 600));
  await t.pumpWidget(buildTestApp(
    viewModel: FakeKeyManagerViewModel(const []),
    home: Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: AppUpdateSection(currentVersion: '1.0.5', edition: edition, service: svc))),
  ));
  await settle(t);
}

void main() {
  setUpAll(installTestPlatformMocks);
  test('默认（未传 KC_EDITION）为开源版；App Store ID 是明确标注的占位符', () {
    expect(Edition.isOss, isTrue);
    expect(Edition.appStoreIdIsPlaceholder, isTrue);
    expect(Edition.appStoreUrl, contains('APP_STORE_ID_PLACEHOLDER'));
  });

  test('版本比较 / 选包 / 解析 SHA256', () {
    expect(AppUpdateService.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(AppUpdateService.compareVersions('1.0.5+5', '1.0.5'), 0);
    expect(AppUpdateService.compareVersions('v1'.substring(1), '1.0.1'), lessThan(0));
    final assets = [
      const ReleaseAsset('KeyCore-1.1.0-linux.AppImage', 'u1', 1),
      const ReleaseAsset('KeyCore-1.1.0-mac.dmg', 'u2', 1),
      const ReleaseAsset('KeyCore-1.1.0-win.exe', 'u3', 1),
    ];
    expect(AppUpdateService.pickAsset(assets, os: 'macos')!.name, endsWith('.dmg'));
    expect(AppUpdateService.pickAsset(assets, os: 'windows')!.name, endsWith('.exe'));
    expect(AppUpdateService.pickAsset(assets, os: 'linux')!.name, endsWith('.AppImage'));
    final h = 'a' * 64;
    expect(AppUpdateService.parseSha256('$h  KeyCore-1.1.0-mac.dmg\n${'b' * 64}  other', 'KeyCore-1.1.0-mac.dmg'), h);
    expect(AppUpdateService.parseSha256(h, 'x'), h);
  });

  testWidgets('App Store 版：只有「在 App Store 中打开」，没有仓库 / 许可证 / GitHub', (t) async {
    await pump(t, edition: KcEdition.appstore);
    expect(byKey('update.openAppStore'), findsOneWidget);
    expect(byKey('update.check'), findsNothing);
    expect(byKey('update.link.repo'), findsNothing);
    expect(byKey('update.link.license'), findsNothing);
    expect(find.textContaining('github', findRichText: true), findsNothing);
    expect(find.textContaining('GitHub'), findsNothing);
  });

  testWidgets('开源版：检查更新（GitHub Releases）→ 发现新版本 → 下载按钮；附仓库/许可证链接', (t) async {
    final client = MockClient((req) async => http.Response(
        '{"tag_name":"v9.0.0","body":"","html_url":"x","assets":[{"name":"a-linux.AppImage","browser_download_url":"d","size":1}]}', 200));
    await pump(t, edition: KcEdition.oss, svc: AppUpdateService(client: client));
    expect(byKey('update.link.repo'), findsOneWidget);
    expect(byKey('update.link.license'), findsOneWidget);
    await t.tap(byKey('update.check'));
    await settle(t, rounds: 4);
    expect(find.text('发现新版本 9.0.0（当前 1.0.5）'), findsOneWidget);
    expect(byKey('update.download'), findsOneWidget);
  });

  test('没有 SHA-256 校验文件时拒绝安装', () async {
    final svc = AppUpdateService(client: MockClient((_) async => http.Response('', 200)));
    const rel = ReleaseInfo(version: '9.0.0', tag: 'v9.0.0', notes: '', pageUrl: '', assets: [
      ReleaseAsset('a-linux.AppImage', 'd', 1),
      ReleaseAsset('a-mac.dmg', 'd', 1),
      ReleaseAsset('a-win.exe', 'd', 1),
    ]);
    expect(() => svc.downloadAndVerify(rel), throwsA(isA<UpdateException>().having((e) => e.code, 'code', 'no_checksum')));
  });
}
