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
import 'services/language_pack_service.dart';
import 'services/macos_preferences_bridge.dart';
import 'services/tray_menu_bridge.dart';
import 'services/macos_bookmark_service.dart';
import 'services/region_filter_service.dart';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'config/provider_config.dart';
import 'utils/platform_presets.dart';
import 'utils/mcp_server_presets.dart';
import 'utils/platform_icon_service.dart';
import 'services/platform_registry.dart';

// 全局 NavigatorKey，用于保持导航状态
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  print('🚀 MAIN: 应用main函数开始执行');
  WidgetsFlutterBinding.ensureInitialized();
  print('🔧 MAIN: WidgetsFlutterBinding.ensureInitialized() 完成');
  
  // Windows/Linux: 初始化 window_manager（用于窗口管理）
  if (Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    // 配置窗口选项
    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  // 初始化设置服务
  final settingsService = SettingsService();
  await settingsService.init();
  
  // macOS: 恢复 Security-Scoped Bookmark 访问权限（延迟调用，确保 MethodChannel 已注册）
  // 注意：原生端已经在 applicationDidFinishLaunching 中恢复了权限
  // 这里只是验证权限是否已恢复
  if (Platform.isMacOS) {
    // 延迟调用，确保 MethodChannel 已注册（延迟 2 秒，确保原生端的 MethodChannel 注册完成）
    Future.delayed(const Duration(milliseconds: 2000), () async {
      try {
        final bookmarkService = MacOSBookmarkService();
        
        // 检查是否有保存的 bookmark
        final hasBookmark = await bookmarkService.hasHomeDirAuthorization();
        
        if (hasBookmark) {
          // 尝试恢复权限（验证）
          final restored = await bookmarkService.restoreHomeDirAccess();
          if (restored) {
          } else {
          }
        } else {
        }
      } catch (e) {
        // 忽略错误，因为原生端已经恢复了权限
      }
    });
  }
  
  // 初始化云端配置服务并加载配置
  final cloudConfigService = CloudConfigService();
  await cloudConfigService.init();
  
  // 初始化语言包服务
  final languagePackService = LanguagePackService();
  await languagePackService.init();
  
  // 强制从 assets 加载默认配置（确保首次启动时使用完整配置）
  try {
    final defaultConfig = await cloudConfigService.loadLocalDefaultConfig();
    if (defaultConfig != null) {
      await cloudConfigService.saveConfigToCache(defaultConfig);
    }
  } catch (e) {
  }
  
  // 初始化平台注册表（内置平台）
  PlatformRegistry.initBuiltinPlatforms();
  
  // 加载动态平台（从云端配置）
  await PlatformRegistry.loadDynamicPlatforms(cloudConfigService);

  // 初始化地区过滤服务
  print('🔍 MAIN: 即将调用RegionFilterService.init()');
  await RegionFilterService.init();
  print('✅ MAIN: RegionFilterService.init() 执行完成');

  // 初始化所有配置模块
  await ProviderConfig.init();
  await PlatformPresets.init();
  await McpServerPresets.init();
  await PlatformIconService.init();
  
  // 输出配置加载总结
  final configData = await cloudConfigService.getConfigData();
  if (configData != null) {
    print('配置加载总结 - 供应商总数: ${configData.providers.length}, 平台总数: ${PlatformRegistry.count} (内置: ${PlatformRegistry.builtinCount}, 动态: ${PlatformRegistry.dynamicCount}), ClaudeCode供应商: ${ProviderConfig.claudeCodeProviders.length}, Codex供应商: ${ProviderConfig.codexProviders.length}, 平台预设: ${PlatformPresets.presetPlatforms.length}');
  }
  
  // 获取当前语言设置并检查语言包更新
  final currentLanguage = await settingsService.getLanguage();
  languagePackService.checkLanguagePackUpdate(currentLanguage).then((hasUpdate) {
    if (hasUpdate) {
    }
  }).catchError((e) {
  });
  
  // 打印加载状态用于调试
  
  // 异步检查配置更新（不阻塞应用启动）
  // 注意：配置更新只是更新 JSON 数据（供应商列表、MCP 服务器模板等），不涉及可执行代码
  // 这是被 App Store 允许的数据更新方式
  // App Store 版本：禁用自动检查，但保留手动检查功能（用户可在设置中手动触发）
  // 非 App Store 版本：允许自动检查更新
  // 检测是否为 App Store 版本：检查应用 receipt 文件（App Store 应用会有 receipt）
  bool isAppStoreVersion = false;
  if (Platform.isMacOS) {
    try {
      final appPath = Platform.resolvedExecutable;
      // App Store 应用会有 _MASReceipt 目录
      // 路径格式：/Applications/AppName.app/Contents/MacOS/AppName
      // receipt 路径：/Applications/AppName.app/Contents/_MASReceipt/receipt
      final appBundlePath = appPath.split('/Contents/MacOS/').first;
      final receiptPath = '$appBundlePath/Contents/_MASReceipt/receipt';
      final receiptFile = File(receiptPath);
      isAppStoreVersion = await receiptFile.exists();
      if (isAppStoreVersion) {
      }
    } catch (e) {
      // 如果检测失败，默认允许更新检查（非 App Store 版本）
    }
  }
  
  // 仅在非 App Store 版本时自动检查更新
  // App Store 版本的用户可以通过设置页面的"检查更新"按钮手动触发更新
  if (!isAppStoreVersion) {
    cloudConfigService.checkForUpdates(force: false).then((hasUpdate) async {
      if (hasUpdate) {
        // 如果有更新，重新加载动态平台
        await PlatformRegistry.reloadDynamicPlatforms(cloudConfigService);
        // 强制刷新并重新加载配置模块
        await ProviderConfig.init(forceRefresh: true);
        await PlatformPresets.init(forceRefresh: true);
        await McpServerPresets.init(forceRefresh: true);
        // 打印更新后的状态
      }
    }).catchError((e) {
      // 静默忽略错误，不影响应用启动
      print('自动检查配置更新失败: $e');
    });
  } else {
  }
  
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
          
          // 初始化托盘菜单桥接（跨平台支持）
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // 延迟调用，确保原生端 MethodChannel 已注册（macOS）或 tray_manager 已初始化（Windows/Linux）
            Future.delayed(const Duration(milliseconds: 500), () async {
              await TrayMenuBridge.init(keyManagerViewModel);
            });
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
            // 使用全局 NavigatorKey 保持导航状态
            // 不使用 key，避免 MaterialApp 重建导致导航栈重置
            navigatorKey: navigatorKey,
              title: '密枢',
              // 国际化支持
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
            supportedLocales: settingsViewModel.supportedLanguages.map((lang) {
              // 解析语言代码，支持 language_COUNTRY 格式（如 zh_TW）
              final parts = lang.code.split('_');
              if (parts.length == 2) {
                return Locale(parts[0], parts[1]); // 如 zh_TW -> Locale('zh', 'TW')
              }
              return Locale(lang.code);
            }).toList(),
            locale: () {
              // 解析当前语言代码
              final parts = settingsViewModel.currentLanguage.split('_');
              final currentLocale = parts.length == 2
                  ? Locale(parts[0], parts[1])
                  : Locale(settingsViewModel.currentLanguage);
              return currentLocale;
            }(),
            // Locale 解析回调：处理 Flutter 不原生支持的 locale
            // 例如 zh_TW 会被映射到 zh，但我们的自定义 AppLocalizations 仍然使用 zh_TW
            localeResolutionCallback: (locale, supportedLocales) {
              if (locale == null) return supportedLocales.first;
              
              // 对于我们的自定义 locale（如 zh_TW），返回基础语言代码
              // 这样 Material 和 Cupertino 组件会使用 zh 的本地化
              // 但我们的 AppLocalizations 仍然会使用完整的 locale 代码
              final languageCode = locale.languageCode;
              
              // 检查是否有完全匹配的 locale
              for (final supportedLocale in supportedLocales) {
                if (supportedLocale.languageCode == locale.languageCode &&
                    supportedLocale.countryCode == locale.countryCode) {
                  return supportedLocale;
                }
              }
              
              // 如果没有完全匹配，查找语言代码匹配的
              for (final supportedLocale in supportedLocales) {
                if (supportedLocale.languageCode == languageCode) {
                  return supportedLocale;
                }
              }
              
              // 如果都没有匹配，返回第一个支持的 locale
              return supportedLocales.first;
            },
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
