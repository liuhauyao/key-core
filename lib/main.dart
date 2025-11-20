import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'viewmodels/key_manager_viewmodel.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'viewmodels/mcp_viewmodel.dart';
import 'views/screens/main_screen.dart';
import 'utils/app_localizations.dart';
import 'services/settings_service.dart';
import 'services/cloud_config_service.dart';
import 'services/macos_preferences_bridge.dart';
import 'services/status_bar_menu_bridge.dart';
import 'config/provider_config.dart';
import 'utils/platform_presets.dart';
import 'utils/mcp_server_presets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化设置服务
  final settingsService = SettingsService();
  await settingsService.init();
  
  // 初始化云端配置服务并加载配置
  final cloudConfigService = CloudConfigService();
  await cloudConfigService.init();
  
  // 强制从 assets 加载默认配置（确保首次启动时使用完整配置）
  try {
    final defaultConfig = await cloudConfigService.loadLocalDefaultConfig();
    if (defaultConfig != null) {
      await cloudConfigService.saveConfigToCache(defaultConfig);
      print('Main: 成功加载并缓存默认配置，版本: ${defaultConfig.version}');
    }
  } catch (e) {
    print('Main: 加载默认配置失败: $e');
  }
  
  // 初始化所有配置模块
  await ProviderConfig.init();
  await PlatformPresets.init();
  await McpServerPresets.init();
  
  // 打印加载状态用于调试
  print('Main: ProviderConfig ClaudeCode 供应商数量: ${ProviderConfig.claudeCodeProviders.length}');
  print('Main: ProviderConfig Codex 供应商数量: ${ProviderConfig.codexProviders.length}');
  print('Main: PlatformPresets 预设数量: ${PlatformPresets.presetPlatforms.length}');
  print('Main: McpServerPresets 模板数量: ${McpServerPresets.allTemplates.length}');
  
  // 异步检查配置更新（不阻塞应用启动）
  cloudConfigService.checkForUpdates().then((hasUpdate) async {
    if (hasUpdate) {
      // 如果有更新，重新加载配置
      await ProviderConfig.init();
      await PlatformPresets.init();
      await McpServerPresets.init();
    }
  }).catchError((e) {
    // 静默忽略错误，不影响应用启动
    print('自动检查配置更新失败: $e');
  });
  
  runApp(const KeyCoreApp());
}

class KeyCoreApp extends StatelessWidget {
  const KeyCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => KeyManagerViewModel(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel()..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => McpViewModel(),
        ),
      ],
      child: Consumer2<SettingsViewModel, KeyManagerViewModel>(
        builder: (context, settingsViewModel, keyManagerViewModel, _) {
          // 初始化状态栏菜单桥接（延迟调用，确保 MethodChannel 已注册）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Platform.isMacOS) {
              // 延迟调用，确保原生端 MethodChannel 已注册
              Future.delayed(const Duration(milliseconds: 500), () async {
                await StatusBarMenuBridge.init(keyManagerViewModel);
              });
            }
          });
          
          // 监听主题变化并同步到窗口标题栏（延迟调用，确保 MethodChannel 已注册）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Platform.isMacOS) {
              // 延迟调用，确保原生端 MethodChannel 已注册
              Future.delayed(const Duration(milliseconds: 300), () {
                String themeModeString;
                if (settingsViewModel.themeMode == ThemeMode.system) {
                  themeModeString = 'system'; // 传递 'system' 让原生代码处理
                } else {
                  themeModeString = settingsViewModel.themeMode == ThemeMode.dark ? 'dark' : 'light';
                }
                // 不等待结果，避免异常影响主流程
                MacOSPreferencesBridge.updateWindowTheme(themeModeString).catchError((_) {
                  // 静默忽略错误
                });
              });
            }
          });
          
          // 配置 Shadcn UI 主题
          final shadLightTheme = ShadThemeData(
            brightness: Brightness.light,
            colorScheme: ShadSlateColorScheme.light(
              primary: const Color(0xFF007AFF),
            ),
          );
          
          final shadDarkTheme = ShadThemeData(
            brightness: Brightness.dark,
            colorScheme: ShadSlateColorScheme.dark(
              primary: const Color(0xFF007AFF),
            ),
          );
          
          // 根据主题模式选择对应的 ShadTheme
          // 注意：对于 system 模式，将在 MaterialApp 的 builder 中动态处理
          final currentShadTheme = settingsViewModel.themeMode == ThemeMode.dark
              ? shadDarkTheme
              : shadLightTheme;
          
          return ShadTheme(
            data: currentShadTheme,
            child: MaterialApp(
              title: '密枢',
              // 国际化支持
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('zh', ''),
                Locale('en', ''),
              ],
              locale: Locale(settingsViewModel.currentLanguage),
              // 主题设置 - 使用 Shadcn UI 提供的主题，同时保留自定义配置
              themeMode: settingsViewModel.themeMode,
              theme: ThemeData(
                primarySwatch: Colors.blue,
                primaryColor: const Color(0xFF007AFF),
                useMaterial3: true,
                appBarTheme: const AppBarTheme(
                  elevation: 0,
                  centerTitle: true,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  titleTextStyle: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                cardTheme: CardThemeData(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                appBarTheme: const AppBarTheme(
                  elevation: 0,
                  centerTitle: true,
                  backgroundColor: Color(0xFF1C1C1E),
                  foregroundColor: Colors.white,
                  titleTextStyle: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                cardTheme: CardThemeData(
                  color: const Color(0xFF2C2C2E),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                scaffoldBackgroundColor: const Color(0xFF1C1C1E),
              ),
              home: const MainScreen(),
              debugShowCheckedModeBanner: false,
            ),
          );
        },
      ),
    );
  }
}
