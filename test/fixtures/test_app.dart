// 组装 MainScreen 测试所需的最小 App：ShadTheme + Material + Provider + 本地化。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:key_core/theme/kc_tokens.dart';
import 'package:key_core/utils/app_localizations.dart';
import 'package:key_core/viewmodels/key_manager_viewmodel.dart';
import 'package:key_core/viewmodels/settings_viewmodel.dart';

import 'fake_key_manager_viewmodel.dart';

/// 让 path_provider 指向临时目录，避免服务在测试里抛 MissingPluginException。
void installTestPlatformMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = Directory.systemTemp.createTempSync('kc_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path);
  SharedPreferences.setMockInitialValues({});
}

/// 等待本地化、平台图标等异步加载完成。
Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget buildTestApp({
  required FakeKeyManagerViewModel viewModel,
  required Widget home,
  Brightness brightness = Brightness.light,
  SettingsViewModel? settings,
}) {
  final shad = KcTheme.shad(brightness);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<KeyManagerViewModel>.value(value: viewModel),
      ChangeNotifierProvider<SettingsViewModel>(create: (_) => settings ?? SettingsViewModel()),
    ],
    child: ShadTheme(
      data: shad,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: KcTheme.material(brightness),
        home: home,
      ),
    ),
  );
}
