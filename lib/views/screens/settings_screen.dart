import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../services/auth_service.dart';
import '../../services/settings_service.dart';
import '../../services/cloud_config_service.dart';
import '../../config/provider_config.dart';
import '../../utils/platform_presets.dart';
import '../../utils/mcp_server_presets.dart';
import '../../utils/app_localizations.dart';
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
  bool _hasPassword = false;
  SettingsCategory _selectedCategory = SettingsCategory.general;
  bool _isCheckingUpdate = false;
  String? _updateStatus;
  String? _configVersion;

  @override
  bool get wantKeepAlive => true; // 保持状态，防止重建时丢失选中分类

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
    _loadConfigVersion();
  }

  Future<void> _checkPasswordStatus() async {
    final hasPassword = await _authService.hasMasterPassword();
    setState(() {
      _hasPassword = hasPassword;
    });
  }

  Future<void> _loadConfigVersion() async {
    await _cloudConfigService.init();
    final version = await _cloudConfigService.getLocalConfigVersion();
    setState(() {
      _configVersion = version;
    });
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateStatus = null;
    });

    try {
      await _cloudConfigService.init();
      final hasUpdate = await _cloudConfigService.checkForUpdates(force: true);
      
      if (hasUpdate) {
        // 重新加载所有配置模块
        await ProviderConfig.init();
        await PlatformPresets.init();
        await McpServerPresets.init();
        final newVersion = await _cloudConfigService.getLocalConfigVersion();
        setState(() {
          _updateStatus = '配置已更新到版本 $newVersion';
          _configVersion = newVersion;
        });
      } else {
        setState(() {
          _updateStatus = '配置已是最新版本';
        });
      }
    } catch (e) {
      setState(() {
        _updateStatus = '检查更新失败: $e';
      });
    } finally {
      setState(() {
        _isCheckingUpdate = false;
      });
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
              // 配置更新
              _buildSettingSection(
                context,
                '配置更新',
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
                      '云端配置',
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _configVersion != null
                          ? '当前版本: $_configVersion'
                          : '加载中...',
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
                      : const Text('检查更新'),
                ),
              ],
            ),
            if (_updateStatus != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _updateStatus!,
                  style: shadTheme.textTheme.small.copyWith(
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ],
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
            
            // 定义工具显示顺序：cursor, claudecode, codex, gemini, windsurf, cline
            final orderedTools = [
              AiToolType.cursor,
              AiToolType.claudecode,
              AiToolType.codex,
              AiToolType.gemini,
              AiToolType.windsurf,
              AiToolType.cline,
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
    final isZh = settingsViewModel.currentLanguage == 'zh';
    
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
          _buildSegmentedItem(
            context,
            localizations.chinese,
            isZh,
            () {
              settingsViewModel.setLanguage('zh');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localizations.languageChangedZh),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          _buildSegmentedItem(
            context,
            localizations.english,
            !isZh,
            () {
              settingsViewModel.setLanguage('en');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localizations.languageChangedEn),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedItem(
    BuildContext context,
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
        child: Text(
          label,
          style: shadTheme.textTheme.small.copyWith(
            color: isActive 
                ? shadTheme.colorScheme.primaryForeground
                : shadTheme.colorScheme.mutedForeground,
            fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
      ),
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
      // 1. 获取下载目录并生成文件路径
      final downloadsDir = await SettingsService.getDownloadsDirectory();
      final fileName = 'ai-keys-export-${DateTime.now().toIso8601String().split('T')[0]}.json';
      final filePath = path.join(downloadsDir, fileName);

      // 2. 执行导出（不再需要密码）
      final exportedPath = await viewModel.exportKeys(filePath);

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
