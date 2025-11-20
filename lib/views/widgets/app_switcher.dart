import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../models/mcp_server.dart';

/// 应用类型枚举
enum AppType {
  keyManager(Icons.vpn_key, null),
  claudeCode(Icons.code, 'assets/icons/platforms/claude-color.svg'),
  codex(Icons.terminal, 'assets/icons/platforms/openai.svg'),
  gemini(Icons.auto_awesome, 'assets/icons/platforms/gemini-color.svg'),
  mcp(Icons.dns, 'assets/icons/platforms/mcp.svg'),
  settings(Icons.settings, null);

  const AppType(this.icon, this.logoPath);
  final IconData icon;
  final String? logoPath;
  
  String getLabel(BuildContext? context) {
    final localizations = context != null ? AppLocalizations.of(context) : null;
    switch (this) {
      case AppType.keyManager:
        return localizations?.keys ?? '钥匙包';
      case AppType.claudeCode:
        return 'ClaudeCode';
      case AppType.codex:
        return 'Codex';
      case AppType.gemini:
        return 'Gemini';
      case AppType.mcp:
        return 'MCP';
      case AppType.settings:
        return localizations?.settings ?? '设置';
    }
  }
}

/// macOS 风格的应用切换器
class AppSwitcher extends StatelessWidget {
  final AppType activeApp;
  final ValueChanged<AppType> onSwitch;

  const AppSwitcher({
    super.key,
    required this.activeApp,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    
    // 使用Consumer监听SettingsViewModel的变化，实现响应式更新
    return Consumer<SettingsViewModel>(
      builder: (context, settingsViewModel, child) {
        // 获取可见的应用列表（根据工具启用状态过滤）
        final visibleApps = _getVisibleApps(context, settingsViewModel);
    
    return Container(
      padding: const EdgeInsets.all(4),
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
            children: visibleApps.map((app) {
          final isActive = app == activeApp;
          return GestureDetector(
            onTap: () => onSwitch(app),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? shadTheme.colorScheme.background
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 如果有 logoPath，使用 SVG logo，否则使用 Material Icon
                  app.logoPath != null
                      ? _buildSvgIcon(
                          app.logoPath!,
                          isActive,
                          shadTheme,
                        )
                      : Icon(
                          app.icon,
                          size: 16,
                          color: isActive
                              ? shadTheme.colorScheme.foreground
                              : shadTheme.colorScheme.mutedForeground,
                        ),
                  const SizedBox(width: 6),
                  Text(
                    app.getLabel(context),
                    style: shadTheme.textTheme.small.copyWith(
                      color: isActive
                          ? shadTheme.colorScheme.foreground
                          : shadTheme.colorScheme.mutedForeground,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
      },
    );
  }

  /// 构建 SVG 图标，所有图标都显示原始颜色
  Widget _buildSvgIcon(String logoPath, bool isActive, ShadThemeData shadTheme) {
    return SvgPicture.asset(
      logoPath,
      width: 16,
      height: 16,
      // 所有图标都显示原始颜色，不使用 colorFilter
      allowDrawingOutsideViewBox: true,
    );
  }

  /// 获取可见的应用列表（根据工具启用状态过滤）
  List<AppType> _getVisibleApps(BuildContext context, SettingsViewModel settingsViewModel) {
    try {
      final enabledTools = settingsViewModel.getEnabledTools();
      
      return AppType.values.where((app) {
        // 钥匙包、MCP、设置始终显示
        if (app == AppType.keyManager || app == AppType.mcp || app == AppType.settings) {
          return true;
        }
        // ClaudeCode、Codex 和 Gemini 根据启用状态显示
        if (app == AppType.claudeCode) {
          return enabledTools.contains(AiToolType.claudecode);
        }
        if (app == AppType.codex) {
          return enabledTools.contains(AiToolType.codex);
        }
        if (app == AppType.gemini) {
          return enabledTools.contains(AiToolType.gemini);
        }
        return true;
      }).toList();
    } catch (e) {
      // 如果无法获取SettingsViewModel，返回所有应用
      return AppType.values;
    }
  }
}

