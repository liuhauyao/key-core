import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../services/auth_service.dart';
import '../../utils/app_localizations.dart';
import 'master_password_dialog.dart';

/// 设置对话框 - 简洁方格设计
class SettingsDialog extends StatefulWidget {
  final VoidCallback? onImportKeys;
  final VoidCallback? onExportKeys;
  final VoidCallback? onRefresh;

  const SettingsDialog({
    super.key,
    this.onImportKeys,
    this.onExportKeys,
    this.onRefresh,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _authService = AuthService();
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
  }

  Future<void> _checkPasswordStatus() async {
    final hasPassword = await _authService.hasMasterPassword();
    setState(() {
      _hasPassword = hasPassword;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final settingsViewModel = context.watch<SettingsViewModel>();
    final shadTheme = ShadTheme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 750,
        constraints: const BoxConstraints(maxHeight: 800),
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      localizations.settings,
                      style: shadTheme.textTheme.h4.copyWith(
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                  ),
                  ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 界面设置
                    _buildSettingSection(
                      context,
                      Icons.language,
                      localizations.interfaceLanguage,
                      _buildInterfaceSettings(context, localizations, settingsViewModel),
                    ),
                    const SizedBox(height: 24),
                    // 窗口行为
                    _buildSettingSection(
                      context,
                      Icons.window,
                      localizations.windowBehavior,
                      _buildWindowBehaviorControl(context, localizations, settingsViewModel),
                    ),
                    const SizedBox(height: 24),
                    // 数据管理
                    _buildSettingSection(
                      context,
                      Icons.storage,
                      localizations.dataManagement,
                      _buildDataManagementControl(context, localizations),
                    ),
                    const SizedBox(height: 24),
                    // Claude/Codex 配置
                    _buildSettingSection(
                      context,
                      Icons.code,
                      localizations.claudeCodexConfig,
                      _buildClaudeCodexConfigControl(context, localizations),
                    ),
                    const SizedBox(height: 24),
                    // 安全设置
                    _buildSettingSection(
                      context,
                      Icons.security,
                      localizations.securitySettings,
                      _buildSecurityControl(context, localizations),
                    ),
                  ],
                ),
              ),
            ),
            // 底部按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () => Navigator.pop(context),
                    child: Text(localizations.close),
                  ),
                  const SizedBox(width: 12),
                  ShadButton(
                    onPressed: () => Navigator.pop(context),
                    leading: const Icon(Icons.save, size: 18),
                    child: Text(localizations.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSection(
    BuildContext context,
    IconData icon,
    String title,
    Widget control,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: shadTheme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: shadTheme.textTheme.small.copyWith(
                fontWeight: FontWeight.w600,
                color: shadTheme.colorScheme.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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

  Widget _buildDataManagementControl(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            context,
            Icons.import_export,
            localizations.importKeys,
            localizations.importKeysDesc,
            () {
              Navigator.pop(context);
              widget.onImportKeys?.call();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            context,
            Icons.file_download,
            localizations.exportKeys,
            localizations.exportKeysDesc,
            () {
              Navigator.pop(context);
              widget.onExportKeys?.call();
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            context,
            Icons.refresh,
            localizations.refreshList,
            localizations.refreshKeyList,
            () {
              Navigator.pop(context);
              widget.onRefresh?.call();
            },
          ),
        ),
      ],
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
                if (widget.onRefresh != null) {
                  widget.onRefresh!();
                }
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

  Widget _buildClaudeCodexConfigControl(
    BuildContext context,
    AppLocalizations localizations,
  ) {
    final shadTheme = ShadTheme.of(context);
    final settingsViewModel = context.watch<SettingsViewModel>();
    
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDirectorySettingItem(
            context,
            localizations.claudeConfigDir,
            settingsViewModel.claudeConfigDir ?? settingsViewModel.defaultClaudeConfigDir ?? '~/.claude',
            settingsViewModel.defaultClaudeConfigDir ?? '~/.claude',
            () => _browseDirectory(context, settingsViewModel, true),
            () => settingsViewModel.resetClaudeConfigDir(),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: shadTheme.colorScheme.border,
          ),
          _buildDirectorySettingItem(
            context,
            localizations.codexConfigDir,
            settingsViewModel.codexConfigDir ?? settingsViewModel.defaultCodexConfigDir ?? '~/.codex',
            settingsViewModel.defaultCodexConfigDir ?? '~/.codex',
            () => _browseDirectory(context, settingsViewModel, false),
            () => settingsViewModel.resetCodexConfigDir(),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorySettingItem(
    BuildContext context,
    String label,
    String currentPath,
    String defaultPath,
    VoidCallback onBrowse,
    VoidCallback onReset, {
    bool isLast = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    final isCustom = currentPath != defaultPath;
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w500,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    if (isCustom) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: shadTheme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppLocalizations.of(context)?.custom ?? '自定义',
                          style: shadTheme.textTheme.small.copyWith(
                            color: shadTheme.colorScheme.primary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isCustom 
                      ? '${AppLocalizations.of(context)?.currentLabel ?? '当前'}: $currentPath' 
                      : '${AppLocalizations.of(context)?.defaultLabel ?? '默认'}: $defaultPath',
                  style: shadTheme.textTheme.small.copyWith(
                    color: shadTheme.colorScheme.mutedForeground,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadButton.outline(
                onPressed: onBrowse,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 16),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context)?.browse ?? '浏览'),
                  ],
                ),
              ),
              if (isCustom) ...[
                const SizedBox(width: 8),
                ShadButton.ghost(
                  onPressed: onReset,
                  child: Icon(Icons.undo, size: 16),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _browseDirectory(
    BuildContext context,
    SettingsViewModel settingsViewModel,
    bool isClaude,
  ) async {
    final localizations = AppLocalizations.of(context);
    try {
      print('SettingsDialog: 开始选择${isClaude ? 'Claude' : 'Codex'}配置目录');
      
      // 使用 file_picker 选择目录
      // 注意：在 macOS 沙盒环境中，file_picker 会自动处理权限请求
      // 不设置 initialDirectory，让系统从用户主目录开始
      String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: isClaude 
            ? (localizations?.selectClaudeConfigDir ?? '选择 Claude 配置目录')
            : (localizations?.selectCodexConfigDir ?? '选择 Codex 配置目录'),
      );
      
      print('SettingsDialog: file_picker 返回结果: $selectedDirectory');
      
      if (selectedDirectory != null && selectedDirectory.isNotEmpty) {
        print('SettingsDialog: 选择的目录: $selectedDirectory');
        
        if (isClaude) {
          await settingsViewModel.setClaudeConfigDir(selectedDirectory);
        } else {
          await settingsViewModel.setCodexConfigDir(selectedDirectory);
        }
        
        if (context.mounted) {
          final localizations = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations?.configDirSet(selectedDirectory) ?? '已设置配置目录: $selectedDirectory'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        print('SettingsDialog: file_picker 返回 null（用户可能取消了选择或对话框未显示）');
        // 不显示错误提示，因为用户可能只是取消了选择
      }
    } catch (e, stackTrace) {
      print('SettingsDialog: 选择目录异常: $e');
      print('SettingsDialog: 堆栈跟踪: $stackTrace');
      
      if (context.mounted) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.browseDirectoryFailed(e.toString()) ?? '选择目录失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
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
}
