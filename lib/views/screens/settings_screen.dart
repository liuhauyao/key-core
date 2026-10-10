import '../widgets/kc_controls.dart';
import '../widgets/kc_menu.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../viewmodels/skills_viewmodel.dart';
import '../../services/skills_path_service.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_config_service.dart';
import '../../services/language_pack_service.dart';
import '../../config/provider_config.dart';
import '../../utils/platform_presets.dart';
import '../../utils/mcp_server_presets.dart';
import '../../utils/platform_icon_service.dart';
import '../../services/platform_registry.dart';
import '../../utils/app_localizations.dart';
import '../../models/cloud_config.dart';
import '../../models/mcp_server.dart';
import '../widgets/master_password_dialog.dart';
import '../widgets/export_password_dialog.dart';
import '../../services/macos_bookmark_service.dart';
import '../../services/settings_service.dart';
import '../../services/region_filter_service.dart';
import '../../constants/app_constants.dart';
import '../widgets/kc_toast.dart';
import '../../theme/kc_tokens.dart';
import '../../config/edition.dart';
import '../widgets/app_update_section.dart';
import '../widgets/kc_settings.dart';
import '../widgets/tool_settings_row.dart';

/// 设置分组枚举
enum SettingsCategory {
  general,
  tools,
  data,
  security,
  about,
}


/// 设置页面 - 独立页面
class SettingsScreen extends StatefulWidget {
  /// 由外部（全局侧栏）控制的分类。非 null 时页面内不再绘制第二条子导航，
  /// 只显示页标题 + 内容（ui_redesign_plan §5.1 / §5.6）。
  final SettingsCategory? category;

  const SettingsScreen({super.key, this.category});

  /// 侧栏使用的分类标签（与页内原有子导航一致）
  static List<(String, SettingsCategory)> categoryLabels(AppLocalizations localizations) {
    return [
      (localizations.settingsGeneral, SettingsCategory.general),
      (localizations.settingsTools, SettingsCategory.tools),
      (localizations.settingsData, SettingsCategory.data),
      (localizations.settingsSecurity, SettingsCategory.security),
      (localizations.settingsAbout, SettingsCategory.about),
    ];
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with AutomaticKeepAliveClientMixin {
  final _authService = AuthService();
  final _cloudConfigService = CloudConfigService();
  final _languagePackService = LanguagePackService();
  bool _hasPassword = false;
  SettingsCategory _selectedCategory = SettingsCategory.general;
  bool _isCheckingUpdate = false;
  String? _configDate;
  List<SupportedLanguage> _supportedLanguages = [];
  
  // 用户主目录授权状态
  bool _isHomeDirAuthorized = false;
  bool _isCheckingAuthorization = true;

  // 地区过滤状态
  bool _chinaRegionFilterEnabled = false;
  bool _isRegionFilterLoading = true;
  bool _shouldShowRegionFilter = false;

  @override
  bool get wantKeepAlive => true; // 保持状态，防止重建时丢失选中分类

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
    _loadConfigDate();
    _loadSupportedLanguages();
    _checkInitialAuthorization();
    _loadRegionFilterStatus();
    _loadRegionFilterVisibility();
    
    // ⭐ 自动在后台检查配置更新（静默刷新）
    // App Store 版本：禁用自动检查（符合审核要求），用户可通过"检查更新"按钮手动触发
    // 非 App Store 版本：允许自动检查
    _autoCheckForUpdates();
  }
  
  /// 应用启动时检查授权状态
  Future<void> _checkInitialAuthorization() async {
    if (!Platform.isMacOS) {
      setState(() {
        _isHomeDirAuthorized = true;
        _isCheckingAuthorization = false;
      });
      return;
    }
    
    try {
      final bookmarkService = MacOSBookmarkService();
      final hasAuth = await bookmarkService.hasHomeDirAuthorization();
      
      // 如果有 bookmark，尝试恢复权限验证
      if (hasAuth) {
        final restored = await bookmarkService.restoreHomeDirAccess();
        setState(() {
          _isHomeDirAuthorized = restored;
          _isCheckingAuthorization = false;
        });
      } else {
        setState(() {
          _isHomeDirAuthorized = false;
          _isCheckingAuthorization = false;
        });
      }
    } catch (e) {
      print('检查授权状态失败: $e');
      setState(() {
        _isHomeDirAuthorized = false;
        _isCheckingAuthorization = false;
      });
    }
  }

  /// 加载地区过滤状态
  Future<void> _loadRegionFilterStatus() async {
    try {
      final isEnabled = await RegionFilterService.isChinaRegionFilterEnabled().timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );

      if (mounted) {
        setState(() {
          _chinaRegionFilterEnabled = isEnabled;
          _isRegionFilterLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chinaRegionFilterEnabled = false;
          _isRegionFilterLoading = false;
        });
      }
    }
  }

  /// 加载地区过滤设置项显示状态
  Future<void> _loadRegionFilterVisibility() async {
    try {
      final shouldShow = await RegionFilterService.shouldShowRegionFilterSetting();

      if (mounted) {
        setState(() {
          _shouldShowRegionFilter = shouldShow;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _shouldShowRegionFilter = false;
        });
      }
    }
  }

  /// 自动后台检查配置更新（静默刷新，不显示加载状态）
  Future<void> _autoCheckForUpdates() async {
    // 延迟 500ms 执行，避免影响页面初始化
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // App Store 版本：跳过自动检查（用户可通过设置中的"检查更新"按钮手动触发）
    if (Edition.isAppStore) {
      print('SettingsScreen: App Store 版本，跳过自动配置更新检查');
      return;
    }
    
    try {
      await _cloudConfigService.init();
      // ⭐ 使用 force: true 强制检查，确保每次都能检测到最新配置
      final hasUpdate = await _cloudConfigService.checkForUpdates(force: true);
      
      if (!mounted) return;
      
      if (hasUpdate) {
        print('SettingsScreen: ========== 检测到配置更新，开始后台刷新 ==========');
        
        // ⭐⭐⭐ 步骤0: 先强制刷新 CloudConfigService，确保所有后续操作使用最新配置
        print('SettingsScreen: 0/7 强制刷新 CloudConfigService 缓存...');
        await _cloudConfigService.loadConfig(forceRefresh: true);
        final freshConfig = await _cloudConfigService.getConfigData();
        print('SettingsScreen: CloudConfigService 已刷新，版本: ${freshConfig?.supportedLanguages?.length} 种语言');
        
        // 静默刷新所有配置模块
        print('SettingsScreen: 1/9 刷新 PlatformRegistry...');
        await PlatformRegistry.reloadDynamicPlatforms(_cloudConfigService);
        print('SettingsScreen: 2/9 刷新 ProviderConfig...');
        await ProviderConfig.init(forceRefresh: true);
        print('SettingsScreen: 3/9 刷新 PlatformPresets...');
        await PlatformPresets.init(forceRefresh: true);
        print('SettingsScreen: 4/9 刷新 McpServerPresets...');
        await McpServerPresets.init(forceRefresh: true);
        print('SettingsScreen: 5/9 刷新 PlatformIconService...');
        await PlatformIconService.init(forceRefresh: true);
        
        // 清除语言包缓存并重新加载
        print('SettingsScreen: 6/9 清除语言包缓存...');
        final currentLanguage = _supportedLanguages.isNotEmpty ? _supportedLanguages.first.code : 'zh';
        await _languagePackService.clearLanguagePackCache(currentLanguage);
        AppLocalizations.clearLoadedPacksCache();
        
        // 重新加载日期和语言列表
        print('SettingsScreen: 7/9 重新加载配置日期...');
        await _loadConfigDate();
        print('SettingsScreen: 8/9 重新加载支持的语言列表...');
        await _loadSupportedLanguages(forceRefresh: true);
        print('SettingsScreen: 本地语言列表已更新: ${_supportedLanguages.map((l) => l.code).join(", ")} (共 ${_supportedLanguages.length} 种)');
        
        // ⭐ 刷新 SettingsViewModel 的配置，触发 MaterialApp 更新 supportedLocales
        if (!mounted) return;
        print('SettingsScreen: 9/9 刷新 SettingsViewModel...');
        final settingsViewModel = Provider.of<SettingsViewModel>(context, listen: false);
        await settingsViewModel.refreshConfig();
        
        // ⭐ 步骤10: 强制刷新 UI，确保语言选择下拉框更新
        print('SettingsScreen: 10/10 强制刷新 UI...');
        if (mounted) {
          setState(() {
            // 触发 UI 重建，包括语言选择下拉框
          });
        }
        
        print('SettingsScreen: ========== 配置后台刷新完成 ==========');
        
        // 可选：显示一个小提示（不打扰用户）
        if (mounted) {
          final localizations = AppLocalizations.of(context);
          if (localizations != null) {
            showKcToast(context, localizations.configUpdateSuccess, kind: KcToastKind.success);
          }
        }
      } else {
        print('SettingsScreen: 配置已是最新版本，无需更新');
      }
    } catch (e) {
      print('SettingsScreen: 后台检查配置更新失败: $e');
      // 静默失败，不影响用户体验
    }
  }

  Future<void> _loadSupportedLanguages({bool forceRefresh = false}) async {
    await _languagePackService.init();
    // 如果强制刷新，先清除 CloudConfigService 的缓存
    if (forceRefresh) {
      await _cloudConfigService.loadConfig(forceRefresh: true);
    }
    
    // ⭐ 直接从 _cloudConfigService 获取语言列表，避免使用不同实例的缓存
    final configData = await _cloudConfigService.getConfigData(forceRefresh: forceRefresh);
    final languages = configData?.supportedLanguages ?? [];
    
    print('SettingsScreen._loadSupportedLanguages: 从 CloudConfigService 获取到 ${languages.length} 种语言');
    print('SettingsScreen._loadSupportedLanguages: 语言列表: ${languages.map((l) => l.code).join(", ")}');
    
    if (mounted) {
      setState(() {
        _supportedLanguages = languages;
      });
    }
  }

  Future<void> _checkPasswordStatus() async {
    final hasPassword = await _authService.hasMasterPassword();
    setState(() {
      _hasPassword = hasPassword;
    });
  }

  Future<void> _loadConfigDate() async {
    await _cloudConfigService.init();
    final dateStr = await _cloudConfigService.getLocalConfigDate();
    if (dateStr != null && mounted) {
      try {
        final date = DateTime.parse(dateStr);
        final localizations = AppLocalizations.of(context);
        if (localizations != null) {
          final formattedDate = _formatDate(date, localizations);
          setState(() {
            _configDate = formattedDate;
          });
        } else {
          // 如果本地化未准备好，使用简单格式
          setState(() {
            _configDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _configDate = dateStr;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _configDate = null;
        });
      }
    }
  }

  String _formatDate(DateTime date, AppLocalizations localizations) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    // 格式化时间部分：HH:mm:ss
    final timeStr = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
    
    if (dateOnly == today) {
      return '${localizations.configDateToday} $timeStr';
    } else if (dateOnly == today.subtract(const Duration(days: 1))) {
      return '${localizations.configDateYesterday} $timeStr';
    } else {
      // 格式化日期时间：YYYY-MM-DD HH:mm:ss
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $timeStr';
    }
  }

  Future<void> _checkForUpdates() async {
    if (!mounted) return;
    
    print('SettingsScreen: ========== 手动检查配置更新 ==========');
    
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      await _cloudConfigService.init();
      print('SettingsScreen: CloudConfigService 已初始化');
      print('SettingsScreen: 开始检查更新（force=true）...');
      final hasUpdate = await _cloudConfigService.checkForUpdates(force: true);
      print('SettingsScreen: 检查更新结果: hasUpdate=$hasUpdate');
      
      if (!mounted) return;
      
      if (hasUpdate) {
        print('SettingsScreen: ========== 手动检查发现配置更新 ==========');
        
        // ⭐⭐⭐ 步骤0: 先强制刷新 CloudConfigService，确保所有后续操作使用最新配置
        print('SettingsScreen: 0/7 强制刷新 CloudConfigService 缓存...');
        await _cloudConfigService.loadConfig(forceRefresh: true);
        final freshConfig = await _cloudConfigService.getConfigData();
        print('SettingsScreen: CloudConfigService 已刷新，版本: ${freshConfig?.supportedLanguages?.length} 种语言');
        
        // 重新加载所有配置模块（强制刷新）
        print('SettingsScreen: 1/9 刷新 PlatformRegistry...');
        await PlatformRegistry.reloadDynamicPlatforms(_cloudConfigService);
        print('SettingsScreen: PlatformRegistry 已刷新，总平台数量: ${PlatformRegistry.count} (内置: ${PlatformRegistry.builtinCount}, 动态: ${PlatformRegistry.dynamicCount})');
        
        print('SettingsScreen: 2/9 刷新 ProviderConfig...');
        await ProviderConfig.init(forceRefresh: true);
        print('SettingsScreen: 3/9 刷新 PlatformPresets...');
        await PlatformPresets.init(forceRefresh: true);
        print('SettingsScreen: 4/9 刷新 McpServerPresets...');
        await McpServerPresets.init(forceRefresh: true);
        print('SettingsScreen: 5/10 刷新 PlatformIconService...');
        await PlatformIconService.init(forceRefresh: true);
        
        // 清除语言包缓存并重新加载
        print('SettingsScreen: 6/10 清除语言包缓存...');
        final currentLanguage = _supportedLanguages.isNotEmpty ? _supportedLanguages.first.code : 'zh';
        await _languagePackService.clearLanguagePackCache(currentLanguage);
        AppLocalizations.clearLoadedPacksCache();
        
        // 重新加载日期和语言列表（强制刷新）
        print('SettingsScreen: 7/10 重新加载配置日期...');
        await _loadConfigDate();
        print('SettingsScreen: 8/10 重新加载支持的语言列表...');
        await _loadSupportedLanguages(forceRefresh: true);
        print('SettingsScreen: 本地语言列表已更新: ${_supportedLanguages.map((l) => l.code).join(", ")} (共 ${_supportedLanguages.length} 种)');
        
        // ⭐ 刷新 SettingsViewModel 的配置，触发 MaterialApp 更新 supportedLocales
        if (!mounted) return;
        print('SettingsScreen: 8/9 刷新 SettingsViewModel...');
        final settingsViewModel = Provider.of<SettingsViewModel>(context, listen: false);
        await settingsViewModel.refreshConfig();
        
        // ⭐ 步骤9: 强制刷新 UI，确保语言选择下拉框更新
        print('SettingsScreen: 9/9 强制刷新 UI...');
        if (mounted) {
          setState(() {
            // 触发 UI 重建，包括语言选择下拉框
          });
        }
        
        print('SettingsScreen: ========== 配置刷新完成 ==========');
        
        final localizations = AppLocalizations.of(context);
        if (localizations != null && mounted) {
          showKcToast(context, localizations.configUpdateSuccess, kind: KcToastKind.success);
        }
      } else {
        final localizations = AppLocalizations.of(context);
        if (localizations != null && mounted) {
          showKcToast(context, localizations.configAlreadyLatest, kind: KcToastKind.success);
        }
      }
    } catch (e) {
      if (!mounted) return;
      final localizations = AppLocalizations.of(context);
      if (localizations != null) {
        showKcToast(context, '${localizations.configUpdateCheckFailed}: $e', kind: KcToastKind.success);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // 必须调用，用于 AutomaticKeepAliveClientMixin
    final localizations = AppLocalizations.of(context)!;
    // 使用 read 而不是 watch，避免工具状态变化时触发整个页面重建
    // 只在需要响应式更新的地方使用 watch
    final settingsViewModel = context.read<SettingsViewModel>();
    final shadTheme = ShadTheme.of(context);
    final sidebarCategories = _settingsSidebarCategories(localizations);
    final menuHeight = _settingsMenuHeightForItemCount(sidebarCategories.length);

    final external = widget.category;
    if (external != null) {
      if (_selectedCategory != external) _selectedCategory = external;
      return Scaffold(
        backgroundColor: shadTheme.colorScheme.background,
        body: KeyedSubtree(
          key: ValueKey('settings.page.${_selectedCategory.name}'),
          child: _buildCategoryContent(context, localizations, settingsViewModel, shadTheme),
        ),
      );
    }

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧菜单栏
              _buildSidebar(
                context,
                localizations,
                shadTheme,
                sidebarCategories,
                menuHeight,
              ),
              // 分隔线容器（只与菜单高度相同）
              _buildDivider(context, shadTheme, menuHeight),
              // 右侧内容区域
              Expanded(
                child: _buildContentArea(context, localizations, settingsViewModel, shadTheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<(String, SettingsCategory)> _settingsSidebarCategories(AppLocalizations localizations) {
    return SettingsScreen.categoryLabels(localizations);
  }

  double _settingsMenuHeightForItemCount(int n) {
    return n * 32.0 + (n - 1) * 4.0 + 16.0;
  }

  /// 构建左侧菜单栏
  Widget _buildSidebar(
    BuildContext context,
    AppLocalizations localizations,
    ShadThemeData shadTheme,
    List<(String, SettingsCategory)> categories,
    double menuHeight,
  ) {
    return Container(
      key: const ValueKey('settings.sidebar'),
      width: 200,
      padding: const EdgeInsets.only(left: 16, right: 12, top: 12, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          SizedBox(
            height: menuHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < categories.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  _buildSidebarItem(
                    context,
                    categories[i].$1,
                    categories[i].$2,
                    shadTheme,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分隔线（只与菜单高度相同）
  Widget _buildDivider(BuildContext context, ShadThemeData shadTheme, double menuHeight) {
    return Container(
      width: 1,
      height: menuHeight,
      margin: const EdgeInsets.only(top: 16),
      color: shadTheme.colorScheme.border,
    );
  }

  /// 构建侧边栏菜单项（GitHub风格）
  Widget _buildSidebarItem(
    BuildContext context,
    String label,
    SettingsCategory category,
    ShadThemeData shadTheme,
  ) {
    final isSelected = _selectedCategory == category;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = category;
        });
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? context.kc.actionSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: shadTheme.textTheme.small.copyWith(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              color: isSelected ? context.kc.actionText : shadTheme.colorScheme.foreground,
              height: 1.2,
                ),
              ),
        ),
      ),
    );
  }

  /// 构建右侧内容区域
  Widget _buildContentArea(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
    ShadThemeData shadTheme,
  ) {
    return KeyedSubtree(
      key: ValueKey('settings.page.${_selectedCategory.name}'),
      child: _buildCategoryContent(context, localizations, settingsViewModel, shadTheme),
    );
  }

  /// 构建分类内容
  Widget _buildCategoryContent(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
    ShadThemeData shadTheme,
  ) {
    switch (_selectedCategory) {
      case SettingsCategory.general:
        return _pageGeneral(context, localizations, settingsViewModel);
      case SettingsCategory.tools:
        return _pageTools(context, localizations);
      case SettingsCategory.data:
        return _pageData(context, localizations);
      case SettingsCategory.security:
        return _pageSecurity(context, localizations);
      case SettingsCategory.about:
        return _pageAbout(context, localizations);
    }
  }







  /// 请求用户主目录授权
  Future<void> _requestHomeDirAuthorization(
    BuildContext context,
    SettingsViewModel viewModel,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }
    
    try {
      final bookmarkService = MacOSBookmarkService();
      final homeDir = await SettingsService.getUserHomeDir();
      
      // 使用 file_picker 选择目录（这会触发 macOS 权限请求）
      final selectedDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '请选择用户主目录以授予访问权限',
        initialDirectory: homeDir,
      );
      
      if (selectedDir != null && selectedDir.isNotEmpty) {
        // 立即保存 Security-Scoped Bookmark（必须在权限有效时创建）
        final success = await bookmarkService.saveHomeDirBookmark(selectedDir);
        
        if (success) {
          // 等待一小段时间，确保 bookmark 已保存
          await Future.delayed(const Duration(milliseconds: 100));
          
          // 验证权限是否已恢复
          final restored = await bookmarkService.restoreHomeDirAccess();
          
          // 更新状态
          setState(() {
            _isHomeDirAuthorized = restored;
          });
          
          if (context.mounted) {
            showKcToast(context, restored 
                  ? '授权成功，应用已获得用户主目录访问权限'
                  : '授权已保存，但权限恢复失败，请重启应用', kind: restored ? KcToastKind.success : KcToastKind.warning);
          }
        } else {
          if (context.mounted) {
            showKcToast(context, '授权失败，请重试', kind: KcToastKind.error);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        showKcToast(context, '授权失败: $e', kind: KcToastKind.error);
      }
    }
  }







  Widget _buildLanguageControl(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
  ) {
    final currentLanguage = settingsViewModel.currentLanguage;
    
    // 如果没有加载到支持的语言列表，使用默认的中英文
    final languages = _supportedLanguages.isEmpty
        ? [
            SupportedLanguage(
              code: 'zh',
              name: 'Chinese',
              nativeName: '简体中文',
              file: 'zh.json',
              lastUpdated: DateTime.now().toIso8601String(),
            ),
            SupportedLanguage(
              code: 'en',
              name: 'English',
              nativeName: 'English',
              file: 'en.json',
              lastUpdated: DateTime.now().toIso8601String(),
            ),
          ]
        : _supportedLanguages;
    
    
    return KcSelect<String>(
      key: const ValueKey('settings.language'),
      width: 150,
      value: currentLanguage,
      options: [for (final lang in languages) (lang.code, lang.nativeName)],
      onChanged: (String? newLanguage) async {
            if (newLanguage != null && newLanguage != currentLanguage) {
              if (!mounted) return;
              
              final selectedLang = languages.firstWhere(
                (l) => l.code == newLanguage,
                orElse: () => languages.first,
              );
              
              // 检查是否需要下载语言包
              final needsDownload = await _languagePackService.needsDownload(newLanguage);
              
              ScaffoldMessengerState? messengerState;
              if (needsDownload) {
                // 显示下载提示（使用当前语言的本地化）
                messengerState = ScaffoldMessenger.of(context);
                final currentLocalizations = AppLocalizations.of(context);
                final downloadingMessage = currentLocalizations?.translate('downloading_language_pack') ?? '正在下载语言包...';
                
                messengerState.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(downloadingMessage),
                        ),
                      ],
                    ),
                    duration: const Duration(seconds: 30), // 给足够的时间下载
                  ),
                );
              }
              
              // 切换语言（setLanguage 内部会加载语言包）
              await settingsViewModel.setLanguage(newLanguage);
              
              if (!mounted) return;
              
              // 如果显示了下载提示，关闭它
              if (needsDownload && messengerState != null) {
                messengerState.hideCurrentSnackBar();
              }
              
              // 等待 MaterialApp 重建和 Localizations 重新加载
              await Future.delayed(const Duration(milliseconds: 200));
              
              // 再次检查 mounted
              if (!mounted) return;
              
              // 显示切换成功消息（使用新语言的翻译）
              final newLocalizations = AppLocalizations.of(context);
              final successMessage = newLocalizations?.languageChangedSuccess ?? 
                                    'Language changed to ${selectedLang.nativeName}';
              
              if (mounted) {
                showKcToast(context, successMessage, kind: KcToastKind.success);
              }
            }
          },
    );
  }







  Future<void> _handleImport(BuildContext context, KeyManagerViewModel viewModel) async {
    final localizations = AppLocalizations.of(context)!;
    
    try {
      // 1. 选择文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: localizations.selectImportFile,
      );

      if (result == null || result.files.single.path == null) {
        // 用户取消选择，静默处理
        return;
      }

      final filePath = result.files.single.path!;

      // 2. 读取文件内容检测是否加密
      final file = File(filePath);
      final fileContent = await file.readAsString();
      
      // 检测文件是否加密
      bool isEncrypted = false;
      try {
        jsonDecode(fileContent);
        isEncrypted = false; // 能解析说明是明文
      } catch (e) {
        // 不能解析，可能是加密的
        try {
          final json = jsonDecode(fileContent);
          if (json is Map && json.containsKey('data') && json.containsKey('iv')) {
            isEncrypted = true; // 是加密格式
          }
        } catch (_) {
          isEncrypted = true; // 默认认为是加密的
        }
      }

      // 3. 如果文件是加密的，要求输入密码
      String? password;
      if (isEncrypted) {
        final inputPassword = await showDialog<String>(
          context: context,
          builder: (context) => const ExportPasswordDialog(isImportMode: true),
        );

        if (inputPassword == null || inputPassword.isEmpty) {
          // 用户取消密码输入，静默处理
          return;
        }
        password = inputPassword;
      }

      // 4. 执行导入
      final importResult = await viewModel.importKeys(filePath, password);

      // 5. 显示结果
      if (mounted) {
        if (importResult.success) {
          // 刷新密钥列表
          await viewModel.refresh();
          
          // 如果导入了MCP服务，刷新MCP服务列表
          if (importResult.mcpImportedCount > 0 || importResult.mcpUpdatedCount > 0) {
            try {
              final mcpViewModel = context.read<McpViewModel>();
              await mcpViewModel.refresh();
            } catch (e) {
              // MCP ViewModel可能未初始化，忽略错误
            }
          }
          
          // 显示成功消息
          String message = importResult.message;
          if (importResult.errorCount > 0 && importResult.errors.isNotEmpty) {
            message += '\n\n错误：\n${importResult.errors.take(3).join('\n')}';
            if (importResult.errors.length > 3) {
              message += '\n...还有 ${importResult.errors.length - 3} 个错误';
            }
          }

          showKcToast(context, message, kind: importResult.errorCount > 0 ? KcToastKind.warning : KcToastKind.success);
        } else {
          // 显示失败消息
          String errorMessage = localizations.importFailed;
          if (importResult.errors.isNotEmpty) {
            final firstError = importResult.errors.first;
            if (firstError.contains('解密失败') || firstError.contains('decrypt') || firstError.contains('密码可能不正确')) {
              errorMessage = localizations.decryptFailed;
            } else if (firstError.contains('文件已加密') || firstError.contains('需要提供解密密码')) {
              errorMessage = '文件已加密，需要提供解密密码';
            } else if (firstError.contains('文件不存在') || firstError.contains('not found')) {
              errorMessage = localizations.fileNotFound;
            } else if (firstError.contains('格式') || firstError.contains('format')) {
              errorMessage = localizations.invalidFileFormat;
            } else {
              errorMessage = '$errorMessage: ${importResult.errors.first}';
            }
          }

          showKcToast(context, errorMessage, kind: KcToastKind.error);
        }
      }
    } catch (e) {
      if (mounted) {
        showKcToast(context, '${localizations.importFailed}: ${e.toString()}', kind: KcToastKind.error);
      }
    }
  }

  Future<void> _handleExport(BuildContext context, KeyManagerViewModel viewModel) async {
    final localizations = AppLocalizations.of(context)!;

    try {
      // 1. 让用户选择保存位置
      final fileName = 'ai-keys-export-${DateTime.now().toIso8601String().split('T')[0]}.json';
      String? selectedPath = await FilePicker.platform.saveFile(
        dialogTitle: localizations.exportKeys,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (selectedPath == null) {
        // 用户取消了保存
        return;
      }

      // 2. 执行导出
      final exportedPath = await viewModel.exportKeys(selectedPath);

      // 3. 显示结果
      if (mounted) {
        if (exportedPath != null) {
          showKcToast(context, localizations.exportResult(exportedPath), kind: KcToastKind.success);
        } else {
          // 检查是否有错误信息
          String errorMessage = localizations.exportFailed;
          if (viewModel.hasError && viewModel.errorMessage != null) {
            final error = viewModel.errorMessage!;
            // 提取更友好的错误信息
            if (error.contains('未找到加密密钥') || error.contains('encryption key')) {
              errorMessage = '${localizations.exportFailed}: 未找到加密密钥，请先设置主密码';
            } else if (error.contains('权限') || error.contains('permission')) {
              errorMessage = '${localizations.exportFailed}: 没有写入文件的权限';
            } else {
              errorMessage = '${localizations.exportFailed}: ${error.replaceAll('Exception: ', '').replaceAll('导出失败: ', '')}';
            }
          }
          
          showKcToast(context, errorMessage, kind: KcToastKind.error);
        }
      }
    } catch (e) {
      if (mounted) {
        showKcToast(context, '${localizations.exportFailed}: ${e.toString()}', kind: KcToastKind.error);
      }
    }
  }



  // ───────────────────────── v4：系统设置风格页面（settings_*.png 稿件） ─────────────────────────

  String _tt(String k, String f) => AppLocalizations.of(context)?.tr(k, f) ?? f;

  Widget _themeSeg(SettingsViewModel vm, AppLocalizations l) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    Widget seg(ThemeMode m, IconData icon, String label) {
      final on = vm.themeMode == m;
      return GestureDetector(
        key: ValueKey('settings.theme.${m.name}'),
        onTap: () => vm.setThemeMode(m),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: on ? cs.card : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
            boxShadow: on ? kc.shadowSm : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: on ? cs.foreground : kc.text2),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: on ? cs.foreground : kc.text2)),
          ]),
        ),
      );
    }

    return Container(
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(ThemeMode.light, Icons.light_mode_outlined, l.themeLight),
        seg(ThemeMode.dark, Icons.dark_mode_outlined, l.themeDark),
        seg(ThemeMode.system, Icons.contrast, l.themeSystem),
      ]),
    );
  }

  Widget _pageGeneral(BuildContext context, AppLocalizations l, SettingsViewModel vm) {
    return Consumer<SettingsViewModel>(builder: (context, vm, _) {
      return KcSettingsPage(
        title: l.settingsGeneral,
        subtitle: _tt('settings_general_sub', '语言、外观与窗口行为'),
        children: [
          KcSettingsSection(title: _tt('settings_appearance', '外观'), rows: [
            KcSettingsRow(
              title: l.interfaceLanguage,
              subtitle: l.interfaceLanguageDesc,
              trailing: _buildLanguageControl(context, l, vm),
            ),
            KcSettingsRow(title: l.appearanceTheme, trailing: _themeSeg(vm, l)),
            if (_shouldShowRegionFilter)
              KcSettingsRow(
                key: const ValueKey('settings.regionFilter'),
                title: l.regionRestrictionsTitle,
                subtitle: l.regionRestrictionsDesc,
                trailing: _isRegionFilterLoading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                    : KcSwitch(value: _chinaRegionFilterEnabled, onChanged: (v) => _setRegionFilter(v, l)),
              ),
          ]),
          KcSettingsSection(title: l.windowBehavior, rows: [
            KcSettingsRow(
              title: l.minimizeToTray,
              subtitle: l.minimizeToTrayDescDetail,
              trailing: KcSwitch(
                key: const ValueKey('settings.minimizeToTray'),
                value: vm.minimizeToTray,
                onChanged: (v) async {
                  await vm.setMinimizeToTray(v);
                  if (v && context.mounted) showKcToast(context, l.minimizeToTrayEnabled, kind: KcToastKind.success);
                },
              ),
            ),
          ]),
          KcSettingsSection(title: _tt('settings_updates', '更新'), rows: [
            KcSettingsRow(
              title: l.cloudConfig,
              subtitle: _tt('settings_templates_desc', '模型列表、请求地址等供应商预设'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (_configDate != null)
                  Text(_configDate!, style: KcType.caption.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground)),
                const SizedBox(width: 10),
                ShadButton.outline(
                  key: const ValueKey('settings.templates.check'),
                  size: ShadButtonSize.sm,
                  onPressed: _isCheckingUpdate ? null : _checkForUpdates,
                  child: _isCheckingUpdate
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
                      : Text(l.checkUpdate),
                ),
              ]),
            ),
          ]),
        ],
      );
    });
  }

  Future<void> _setRegionFilter(bool value, AppLocalizations l) async {
    try {
      await RegionFilterService.setChinaRegionFilter(value);
      setState(() => _chinaRegionFilterEnabled = value);
      if (!mounted) return;
      showKcToast(context, value ? l.regionRestrictionsEnabled : l.regionRestrictionsDisabled, kind: KcToastKind.success);
      await context.read<KeyManagerViewModel>().refresh();
      await PlatformRegistry.reloadDynamicPlatforms(_cloudConfigService);
      await PlatformPresets.init(forceRefresh: true);
    } catch (_) {
      if (mounted) showKcToast(context, l.regionRestrictionsFailed, kind: KcToastKind.error);
    }
  }

  static const _orderedTools = [
    AiToolType.cursor,
    AiToolType.claudecode,
    AiToolType.codex,
    AiToolType.gemini,
    AiToolType.claudeDesktop,
    AiToolType.windsurf,
    AiToolType.openclaw,
  ];

  Widget _pageTools(BuildContext context, AppLocalizations l) {
    return Consumer<SettingsViewModel>(builder: (context, vm, _) {
      final tools = [..._orderedTools, ...AiToolType.syncOnlyTools.where((t) => !_orderedTools.contains(t))];
      final on = tools.where(vm.isToolEnabled).length;
      final kc = context.kc;
      return KcSettingsPage(
        title: l.settingsTools,
        subtitle: _tt('settings_tools_sub', '检测状态、配置路径与启用'),
        children: [
          if (Platform.isMacOS)
            KcSettingsSection(title: _tt('settings_access', '访问授权'), rows: [
              KcSettingsRow(
                leading: const KcIconTile(Icons.folder_outlined, color: KcIconTile.blue),
                title: _tt('home_dir_access', '主目录访问'),
                subtitle: _isCheckingAuthorization
                    ? _tt('checking', '正在检查…')
                    : _tt('home_dir_access_desc', '用于读写各工具的配置文件'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!_isCheckingAuthorization)
                    _isHomeDirAuthorized
                        ? KcStatusChip(_tt('authorized', '已授权'), kind: KcChipKind.ok)
                        : KcStatusChip(_tt('unauthorized', '未授权'), kind: KcChipKind.warn),
                  const SizedBox(width: 8),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: _isCheckingAuthorization ? null : () => _requestHomeDirAuthorization(context, vm),
                    child: Text(_isHomeDirAuthorized ? _tt('reauthorize', '重新授权') : _tt('authorize', '授权')),
                  ),
                ]),
              ),
            ]),
          KcSettingsSection(
            key: const ValueKey('settings.tools.list'),
            title: '${_tt('settings_ai_tools', 'AI 工具')}  ·  ${_tt('enabled_count', '已启用 {n} / {m}').replaceAll('{n}', '$on').replaceAll('{m}', '${tools.length}')}',
            dividerIndent: 50,
            rows: [for (final t in tools) ToolSettingsRow(key: ValueKey('toolRow.wrap.${t.value}'), tool: t, viewModel: vm)],
            footer: _tt('settings_tools_footer', '关闭某个工具后，侧栏、密钥卡片和 MCP / Skills 同步都不再显示它；已写入的工具配置文件不会被修改。'),
          ),
          Consumer<SkillsViewModel>(builder: (context, svm, _) {
            if (svm.skillsSourceDir == null) WidgetsBinding.instance.addPostFrameCallback((_) => svm.init());
            return KcSettingsSection(title: l.skillsSettingsTitle, rows: [
              KcSettingsRow(
                leading: const KcIconTile(Icons.auto_awesome_outlined, color: KcIconTile.purple),
                title: l.skillsSourcePath,
                subtitle: svm.skillsSourceDir ?? '~/.keycore/skills/',
                mono: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  ShadButton.outline(size: ShadButtonSize.sm, onPressed: () => svm.refresh(), child: Text(l.skillsRescan)),
                  const SizedBox(width: 6),
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () async {
                      final dir = await SkillsPathService().ensureSkillsSourceDir();
                      if (Platform.isMacOS) {
                        await Process.run('open', [dir]);
                      } else if (Platform.isWindows) {
                        await Process.run('explorer', [dir]);
                      } else {
                        await Process.run('xdg-open', [dir]);
                      }
                    },
                    child: Text(l.skillsOpenDirectory),
                  ),
                ]),
              ),
              KcSettingsRow(
                title: l.skillsSyncAll,
                trailing: ShadButton.outline(
                  size: ShadButtonSize.sm,
                  leading: Icon(Icons.sync, size: 14, color: kc.text2),
                  onPressed: () async {
                    await svm.syncAll(replaceExisting: false);
                    if (context.mounted) showKcToast(context, l.skillsSyncAllDone, kind: KcToastKind.success);
                  },
                  child: Text(_tt('sync_now', '立即同步')),
                ),
              ),
            ]);
          }),
        ],
      );
    });
  }

  Widget _pageData(BuildContext context, AppLocalizations l) {
    final vm = context.read<KeyManagerViewModel>();
    return KcSettingsPage(
      title: l.settingsData,
      subtitle: _tt('settings_data_sub', '导入与导出'),
      children: [
        KcSettingsSection(title: _tt('settings_import_export', '导入与导出'), rows: [
          KcSettingsRow(
            leading: const KcIconTile(Icons.file_download_outlined, color: KcIconTile.green),
            title: l.importKeys,
            subtitle: l.importKeysDesc,
            trailing: ShadButton.outline(
              key: const ValueKey('settings.data.import'),
              size: ShadButtonSize.sm,
              leading: const Icon(Icons.file_download_outlined, size: 14),
              onPressed: () => _handleImport(context, vm),
              child: Text(l.tr('import_ellipsis', '导入…')),
            ),
          ),
          KcSettingsRow(
            leading: const KcIconTile(Icons.file_upload_outlined, color: KcIconTile.blue),
            title: l.exportKeys,
            subtitle: l.exportKeysDesc,
            trailing: ShadButton.outline(
              key: const ValueKey('settings.data.export'),
              size: ShadButtonSize.sm,
              leading: const Icon(Icons.file_upload_outlined, size: 14),
              onPressed: () => _handleExport(context, vm),
              child: Text(l.tr('export_ellipsis', '导出…')),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _pageSecurity(BuildContext context, AppLocalizations l) {
    return KcSettingsPage(
      title: l.settingsSecurity,
      subtitle: _tt('settings_security_sub', '主密码与加密'),
      children: [
        KcSettingsSection(title: _tt('master_password', '主密码'), rows: [
          KcSettingsRow(
            key: const ValueKey('settings.security.row'),
            leading: const KcIconTile(Icons.lock_outline, color: KcIconTile.orange),
            title: _hasPassword ? l.masterPasswordSet : l.masterPasswordNotSet,
            subtitle: _hasPassword ? l.masterPasswordEncrypted : l.masterPasswordPlain,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _hasPassword
                  ? KcStatusChip(l.tr('encrypted', '已加密'), kind: KcChipKind.ok, icon: Icons.check)
                  : KcStatusChip(l.tr('not_encrypted', '未加密'), kind: KcChipKind.warn),
              const SizedBox(width: 8),
              ShadButton.outline(
                key: const ValueKey('settings.security.password'),
                size: ShadButtonSize.sm,
                onPressed: () async {
                  final result = await showDialog<bool>(context: context, builder: (_) => const MasterPasswordDialog());
                  if (result == true) {
                    await _checkPasswordStatus();
                    if (!context.mounted) return;
                    context.read<KeyManagerViewModel>().refresh();
                  }
                },
                child: Text(_hasPassword ? '${l.change}…' : l.set),
              ),
            ]),
          ),
        ]),
      ],
    );
  }

  Widget _pageAbout(BuildContext context, AppLocalizations l) {
    final cs = ShadTheme.of(context).colorScheme;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        final version = info?.version ?? AppConstants.appVersion;
        final build = info?.buildNumber ?? '';
        final os = Platform.isMacOS ? 'macOS' : (Platform.isWindows ? 'Windows' : 'Linux');
        final card = Container(
          key: const ValueKey('settings.about.card'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.card,
            borderRadius: BorderRadius.circular(KcRadius.panel),
            border: Border.all(color: cs.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/images/app_about.png', width: 72, height: 72, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 72)),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(l.tr('app_name_cn', '密枢'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: cs.foreground)),
                  const SizedBox(width: 6),
                  Text('Key Core', style: TextStyle(fontSize: 15, color: cs.mutedForeground)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text('${l.tr('version', '版本')} $version${build.isEmpty ? '' : ' ($build)'}  ·  $os',
                      style: KcType.caption.copyWith(color: cs.mutedForeground)),
                  const SizedBox(width: 8),
                  KcStatusChip(Edition.isAppStore ? 'App Store' : l.tr('edition_oss', '开源版')),
                ]),
                const SizedBox(height: 8),
                Text(l.aboutIntroText, maxLines: 3, overflow: TextOverflow.ellipsis, style: KcType.caption.copyWith(color: cs.mutedForeground, height: 1.5)),
              ]),
            ),
          ]),
        );
        return KcSettingsPage(
          title: l.settingsAbout,
          children: [
            card,
            AppUpdateSection(currentVersion: info?.version),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(l.aboutCopyright, style: TextStyle(fontSize: 11.5, color: cs.mutedForeground)),
            ),
          ],
        );
      },
    );
  }
}
