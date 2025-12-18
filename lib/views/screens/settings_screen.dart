import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:file_picker/file_picker.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../services/auth_service.dart';
import '../../services/cloud_config_service.dart';
import '../../services/language_pack_service.dart';
import '../../config/provider_config.dart';
import '../../utils/platform_presets.dart';
import '../../utils/mcp_server_presets.dart';
import '../../services/platform_registry.dart';
import '../../utils/app_localizations.dart';
import '../../models/cloud_config.dart';
import '../../models/mcp_server.dart';
import '../widgets/master_password_dialog.dart';
import '../widgets/tool_config_card.dart';
import '../widgets/export_password_dialog.dart';

/// 设置分组枚举
enum SettingsCategory {
  general,
  tools,
  data,
  security,
}


/// 设置页面 - 独立页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

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

  @override
  bool get wantKeepAlive => true; // 保持状态，防止重建时丢失选中分类

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
    _loadConfigDate();
    _loadSupportedLanguages();
    
    // ⭐ 自动在后台检查配置更新（静默刷新）
    // App Store 版本：禁用自动检查（符合审核要求），用户可通过"检查更新"按钮手动触发
    // 非 App Store 版本：允许自动检查
    _autoCheckForUpdates();
  }
  
  /// 检测是否为 App Store 版本
  Future<bool> _isAppStoreVersion() async {
    if (!Platform.isMacOS) return false;
    try {
      final appPath = Platform.resolvedExecutable;
      final appBundlePath = appPath.split('/Contents/MacOS/').first;
      final receiptPath = '$appBundlePath/Contents/_MASReceipt/receipt';
      final receiptFile = File(receiptPath);
      return await receiptFile.exists();
    } catch (e) {
      return false;
    }
  }
  
  /// 自动后台检查配置更新（静默刷新，不显示加载状态）
  Future<void> _autoCheckForUpdates() async {
    // 延迟 500ms 执行，避免影响页面初始化
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (!mounted) return;
    
    // App Store 版本：跳过自动检查（用户可通过设置中的"检查更新"按钮手动触发）
    final isAppStore = await _isAppStoreVersion();
    if (isAppStore) {
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
        print('SettingsScreen: 1/7 刷新 ProviderConfig...');
        await ProviderConfig.init(forceRefresh: true);
        print('SettingsScreen: 2/7 刷新 PlatformPresets...');
        await PlatformPresets.init(forceRefresh: true);
        print('SettingsScreen: 3/7 刷新 McpServerPresets...');
        await McpServerPresets.init(forceRefresh: true);
        
        // 重新加载日期和语言列表
        print('SettingsScreen: 4/7 重新加载配置日期...');
        await _loadConfigDate();
        print('SettingsScreen: 5/7 重新加载支持的语言列表...');
        await _loadSupportedLanguages(forceRefresh: true);
        print('SettingsScreen: 本地语言列表已更新: ${_supportedLanguages.map((l) => l.code).join(", ")} (共 ${_supportedLanguages.length} 种)');
        
        // ⭐ 刷新 SettingsViewModel 的配置，触发 MaterialApp 更新 supportedLocales
        if (!mounted) return;
        print('SettingsScreen: 6/7 刷新 SettingsViewModel...');
        final settingsViewModel = Provider.of<SettingsViewModel>(context, listen: false);
        await settingsViewModel.refreshConfig();
        
        // ⭐ 步骤7: 强制刷新 UI，确保语言选择下拉框更新
        print('SettingsScreen: 7/7 强制刷新 UI...');
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations.configUpdateSuccess),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                width: 300,
              ),
            );
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
    
    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      await _cloudConfigService.init();
      final hasUpdate = await _cloudConfigService.checkForUpdates(force: true);
      
      if (!mounted) return;
      
      if (hasUpdate) {
        print('SettingsScreen: ========== 手动检查发现配置更新 ==========');
        
        // ⭐⭐⭐ 步骤0: 先强制刷新 CloudConfigService，确保所有后续操作使用最新配置
        print('SettingsScreen: 0/7 强制刷新 CloudConfigService 缓存...');
        await _cloudConfigService.loadConfig(forceRefresh: true);
        final freshConfig = await _cloudConfigService.getConfigData();
        print('SettingsScreen: CloudConfigService 已刷新，版本: ${freshConfig?.supportedLanguages?.length} 种语言');
        
        // 重新加载所有配置模块（强制刷新）
        print('SettingsScreen: 1/8 刷新 PlatformRegistry...');
        await PlatformRegistry.reloadDynamicPlatforms(_cloudConfigService);
        print('SettingsScreen: PlatformRegistry 已刷新，总平台数量: ${PlatformRegistry.count} (内置: ${PlatformRegistry.builtinCount}, 动态: ${PlatformRegistry.dynamicCount})');
        
        print('SettingsScreen: 2/8 刷新 ProviderConfig...');
        await ProviderConfig.init(forceRefresh: true);
        print('SettingsScreen: 3/8 刷新 PlatformPresets...');
        await PlatformPresets.init(forceRefresh: true);
        print('SettingsScreen: 4/8 刷新 McpServerPresets...');
        await McpServerPresets.init(forceRefresh: true);
        
        // 重新加载日期和语言列表（强制刷新）
        print('SettingsScreen: 5/8 重新加载配置日期...');
        await _loadConfigDate();
        print('SettingsScreen: 6/8 重新加载支持的语言列表...');
        await _loadSupportedLanguages(forceRefresh: true);
        print('SettingsScreen: 本地语言列表已更新: ${_supportedLanguages.map((l) => l.code).join(", ")} (共 ${_supportedLanguages.length} 种)');
        
        // ⭐ 刷新 SettingsViewModel 的配置，触发 MaterialApp 更新 supportedLocales
        if (!mounted) return;
        print('SettingsScreen: 7/8 刷新 SettingsViewModel...');
        final settingsViewModel = Provider.of<SettingsViewModel>(context, listen: false);
        await settingsViewModel.refreshConfig();
        
        // ⭐ 步骤8: 强制刷新 UI，确保语言选择下拉框更新
        print('SettingsScreen: 8/8 强制刷新 UI...');
        if (mounted) {
          setState(() {
            // 触发 UI 重建，包括语言选择下拉框
          });
        }
        
        print('SettingsScreen: ========== 配置刷新完成 ==========');
        
        final localizations = AppLocalizations.of(context);
        if (localizations != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.configUpdateSuccess),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        final localizations = AppLocalizations.of(context);
        if (localizations != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.configAlreadyLatest),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      final localizations = AppLocalizations.of(context);
      if (localizations != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.configUpdateCheckFailed}: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
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

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧菜单栏
              _buildSidebar(context, localizations, shadTheme),
              // 分隔线容器（只与菜单高度相同）
              _buildDivider(context, shadTheme),
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

  /// 构建左侧菜单栏
  Widget _buildSidebar(
    BuildContext context,
    AppLocalizations localizations,
    ShadThemeData shadTheme,
  ) {
    final categories = [
      (localizations.settingsGeneral, SettingsCategory.general),
      (localizations.settingsTools, SettingsCategory.tools),
      (localizations.settingsData, SettingsCategory.data),
      (localizations.settingsSecurity, SettingsCategory.security),
    ];

    // 计算菜单总高度：4个菜单项 * 32px + 3个间距 * 4px + 上下padding 16px
    final menuHeight = 4 * 32.0 + 3 * 4.0 + 16.0;

    return Container(
      width: 240,
      padding: const EdgeInsets.only(left: 24, top: 16, bottom: 16),
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
  Widget _buildDivider(BuildContext context, ShadThemeData shadTheme) {
    // 计算菜单总高度：4个菜单项 * 32px + 3个间距 * 4px + 上下padding 16px
    final menuHeight = 4 * 32.0 + 3 * 4.0 + 16.0;
    
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
          color: isSelected
              ? shadTheme.colorScheme.muted.withOpacity(0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: shadTheme.textTheme.small.copyWith(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              color: isSelected
                  ? shadTheme.colorScheme.foreground
                  : shadTheme.colorScheme.mutedForeground,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 32, top: 16, right: 32, bottom: 32),
      child: SizedBox(
        width: double.infinity,
        child: _buildCategoryContent(context, localizations, settingsViewModel, shadTheme),
      ),
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
        return _buildGeneralSettings(context, localizations, settingsViewModel, shadTheme);
      case SettingsCategory.tools:
        return _buildToolsSettings(context, localizations, settingsViewModel, shadTheme);
      case SettingsCategory.data:
        return _buildDataSettings(context, localizations, shadTheme);
      case SettingsCategory.security:
        return _buildSecuritySettings(context, localizations, shadTheme);
    }
  }

  /// 构建常规设置
  Widget _buildGeneralSettings(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
    ShadThemeData shadTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
              // 界面设置
              _buildSettingSection(
                context,
                localizations.interfaceLanguage,
                _buildInterfaceSettings(context, localizations, settingsViewModel),
              ),
        const SizedBox(height: 32),
              // 窗口行为
              _buildSettingSection(
                context,
                localizations.windowBehavior,
                _buildWindowBehaviorControl(context, localizations, settingsViewModel),
              ),
        const SizedBox(height: 32),
              // 配置模板更新
              _buildSettingSection(
                context,
                localizations.configTemplateUpdate,
                _buildConfigUpdateSettings(context, localizations),
              ),
      ],
    );
  }

  /// 构建配置更新设置
  Widget _buildConfigUpdateSettings(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.cloudConfig,
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _configDate != null
                          ? _configDate!
                          : localizations.loading,
                      style: shadTheme.textTheme.small.copyWith(
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
                ShadButton(
                  onPressed: _isCheckingUpdate ? null : _checkForUpdates,
                  child: _isCheckingUpdate
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              shadTheme.colorScheme.foreground,
                            ),
                          ),
                        )
                      : Text(localizations.checkUpdate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建工具配置设置
  Widget _buildToolsSettings(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
    ShadThemeData shadTheme,
  ) {
    // 使用 Consumer 来监听工具状态变化，避免整个 SettingsScreen 重建
    return Consumer<SettingsViewModel>(
      builder: (context, viewModel, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // 响应式布局：根据宽度动态计算每行显示的卡片数量（与密钥卡片列表一致）
            const double minCardWidth = 280; // 工具卡片最小宽度
            const double cardSpacing = 16.0; // 卡片间距
            const double padding = 0; // LayoutBuilder已经考虑了padding，这里不需要再减
            
            final availableWidth = constraints.maxWidth;
            // 动态计算列数：可用宽度 / (最小卡片宽度 + 间距)
            int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
            
            // 确保至少显示1列，最多5列
            crossAxisCount = crossAxisCount.clamp(1, 5);
            
            // 如果可用宽度不足以容纳计算出的列数，减少列数
            final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
            if (cardWidth < minCardWidth && crossAxisCount > 1) {
              crossAxisCount -= 1;
            }
            
            // 定义工具显示顺序：cursor, claudecode, codex, gemini, windsurf
            final orderedTools = [
              AiToolType.cursor,
              AiToolType.claudecode,
              AiToolType.codex,
              AiToolType.gemini,
              AiToolType.windsurf,
            ];
            
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: cardSpacing,
                mainAxisSpacing: cardSpacing,
                childAspectRatio: (cardWidth / 120), // 固定高度120，动态宽度
              ),
              itemCount: orderedTools.length,
              itemBuilder: (context, index) {
                final tool = orderedTools[index];
                return ToolConfigCard(
                  tool: tool,
                  viewModel: viewModel,
                );
              },
            );
          },
        );
      },
    );
  }

  /// 构建数据选项设置
  Widget _buildDataSettings(
    BuildContext context,
    AppLocalizations localizations,
    ShadThemeData shadTheme,
  ) {
    final viewModel = context.read<KeyManagerViewModel>();
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
                context,
            Icons.import_export,
            localizations.importKeys,
            localizations.importKeysDesc,
            () => _handleImport(context, viewModel),
          ),
              ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionCard(
                context,
            Icons.file_download,
            localizations.exportKeys,
            localizations.exportKeysDesc,
            () => _handleExport(context, viewModel),
          ),
        ),
      ],
    );
  }

  /// 构建安全选项设置
  Widget _buildSecuritySettings(
    BuildContext context,
    AppLocalizations localizations,
    ShadThemeData shadTheme,
  ) {
    return _buildSecurityControl(context, localizations);
  }

  Widget _buildSettingSection(
    BuildContext context,
    String title,
    Widget control,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            Text(
              title,
          style: shadTheme.textTheme.h4.copyWith(
                fontWeight: FontWeight.w600,
                color: shadTheme.colorScheme.foreground,
              ),
            ),
        const SizedBox(height: 16),
        control,
      ],
    );
  }

  Widget _buildInterfaceSettings(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 语言设置
          _buildSettingItem(
            context,
            localizations.interfaceLanguage,
            localizations.interfaceLanguageDesc,
            _buildLanguageControl(context, localizations, settingsViewModel),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: shadTheme.colorScheme.border,
          ),
          // 外观主题
          _buildSettingItem(
            context,
            localizations.appearanceTheme,
            localizations.appearanceThemeDesc,
            _buildThemeControl(context, localizations, settingsViewModel),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    BuildContext context,
    String label,
    String description,
    Widget control, {
    bool isLast = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: shadTheme.textTheme.p.copyWith(
                    fontWeight: FontWeight.w500,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: shadTheme.textTheme.small.copyWith(
                    color: shadTheme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }

  Widget _buildLanguageControl(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
  ) {
    final shadTheme = ShadTheme.of(context);
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
    
    // ⭐ 使用语言代码列表作为 key，确保语言列表变化时 ShadSelect 重新构建
    final languagesKey = languages.map((l) => l.code).join('_');
    
    return ShadSelect<String>(
      key: ValueKey('language_select_$languagesKey'),
      initialValue: currentLanguage,
      placeholder: Text(
        localizations.interfaceLanguage,
        style: shadTheme.textTheme.small,
      ),
      options: languages.map((lang) {
        return ShadOption<String>(
          value: lang.code,
          child: Text(
            lang.nativeName,
            style: shadTheme.textTheme.small,
          ),
        );
      }).toList(),
      selectedOptionBuilder: (context, value) {
        final lang = languages.firstWhere(
          (l) => l.code == value,
          orElse: () => languages.first,
        );
        return Text(
          lang.nativeName,
          style: shadTheme.textTheme.small,
        );
      },
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(successMessage),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          },
    );
  }

  Widget _buildThemeControl(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
  ) {
    final shadTheme = ShadTheme.of(context);
    ThemeMode currentMode = settingsViewModel.themeMode;
    
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildThemeSegmentedItem(
            context,
            Icons.light_mode,
            localizations.themeLight,
            currentMode == ThemeMode.light,
            () => settingsViewModel.setThemeMode(ThemeMode.light),
          ),
          _buildThemeSegmentedItem(
            context,
            Icons.dark_mode,
            localizations.themeDark,
            currentMode == ThemeMode.dark,
            () => settingsViewModel.setThemeMode(ThemeMode.dark),
          ),
          _buildThemeSegmentedItem(
            context,
            Icons.brightness_auto,
            localizations.themeSystem,
            currentMode == ThemeMode.system,
            () => settingsViewModel.setThemeMode(ThemeMode.system),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSegmentedItem(
    BuildContext context,
    IconData icon,
    String label,
    bool isActive,
    VoidCallback onTap,
  ) {
    final shadTheme = ShadTheme.of(context);
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive 
              ? shadTheme.colorScheme.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive 
                  ? shadTheme.colorScheme.primaryForeground
                  : shadTheme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: shadTheme.textTheme.small.copyWith(
                color: isActive 
                    ? shadTheme.colorScheme.primaryForeground
                    : shadTheme.colorScheme.mutedForeground,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowBehaviorControl(
    BuildContext context,
    AppLocalizations localizations,
    SettingsViewModel settingsViewModel,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _buildSettingItem(
        context,
        localizations.minimizeToTray,
        localizations.minimizeToTrayDescDetail,
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: settingsViewModel.minimizeToTray,
            onChanged: (value) async {
              await settingsViewModel.setMinimizeToTray(value);
              if (value && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(localizations.minimizeToTrayEnabled),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            activeColor: shadTheme.colorScheme.primary,
          ),
        ),
        isLast: true,
      ),
    );
  }

  Widget _buildSecurityControl(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _hasPassword
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _hasPassword ? Icons.lock : Icons.lock_open,
              color: _hasPassword ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasPassword
                      ? localizations.masterPasswordSet
                      : localizations.masterPasswordNotSet,
                  style: shadTheme.textTheme.small.copyWith(
                    fontWeight: FontWeight.w500,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasPassword
                      ? localizations.masterPasswordEncrypted
                      : localizations.masterPasswordPlain,
                  style: shadTheme.textTheme.small.copyWith(
                    color: shadTheme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ShadButton(
            onPressed: () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (context) => const MasterPasswordDialog(),
              );
              if (result == true) {
                await _checkPasswordStatus();
                final viewModel = context.read<KeyManagerViewModel>();
                viewModel.refresh();
              }
            },
            child: Text(
              _hasPassword ? localizations.change : localizations.set,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildActionCard(
    BuildContext context,
    IconData icon,
    String title,
    String description,
    VoidCallback onTap,
  ) {
    final shadTheme = ShadTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: shadTheme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: shadTheme.colorScheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: shadTheme.textTheme.small.copyWith(
                fontWeight: FontWeight.w600,
                color: shadTheme.colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: shadTheme.textTheme.small.copyWith(
                color: shadTheme.colorScheme.mutedForeground,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: importResult.errorCount > 0 ? Colors.orange : Colors.green,
              duration: Duration(seconds: importResult.errorCount > 0 ? 5 : 3),
            ),
          );
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

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.importFailed}: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.exportResult(exportedPath)),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 4),
            ),
          );
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
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${localizations.exportFailed}: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

}
