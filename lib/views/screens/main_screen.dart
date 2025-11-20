import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reorderables/reorderables.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../widgets/key_card.dart';
import '../widgets/search_bar.dart' as custom;
import '../widgets/platform_filter.dart';
import '../widgets/app_switcher.dart';
import '../widgets/confirm_dialog.dart';
import 'key_form_page.dart';
import 'claude_config_screen.dart';
import 'codex_config_screen.dart';
import 'gemini_config_screen.dart';
import 'mcp_config_screen.dart';
import 'settings_screen.dart';
import '../widgets/master_password_dialog.dart';
import '../../models/ai_key.dart';
import '../../models/platform_type.dart';
import '../../models/mcp_server.dart';
import '../../services/database_service.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/auth_service.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_helper.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PageController _pageController = PageController();
  final GlobalKey<ClaudeConfigScreenState> _claudeConfigScreenKey = GlobalKey<ClaudeConfigScreenState>();
  final GlobalKey<CodexConfigScreenState> _codexConfigScreenKey = GlobalKey<CodexConfigScreenState>();
  final GlobalKey<GeminiConfigScreenState> _geminiConfigScreenKey = GlobalKey<GeminiConfigScreenState>();
  // 使用 ValueKey 来保持设置页面状态，避免 children 列表变化时重置
  static const _settingsScreenKey = ValueKey('settings_screen');
  bool _isEditMode = false;
  AppType _activeApp = AppType.keyManager;
  bool _previousLoadingState = false;
  int? _lastRefreshedPageIndex; // 记录上次刷新的页面索引，避免重复刷新
  int? _targetPageIndex; // 记录目标页面索引，用于区分中间页面和目标页面

  @override
  void initState() {
    super.initState();
    // 监听搜索框变化以更新清除按钮
    _searchController.addListener(() {
      setState(() {});
    });
    // 初始化ViewModel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KeyManagerViewModel>().init();
      // 触发初始页面的首次加载（如果是 ClaudeCode 或 Codex）
      if (_lastRefreshedPageIndex == null) {
        _triggerPageLoad(0);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }
  
  void _onAppSwitched(AppType app) {
    // 获取可见的应用列表，然后找到对应的页面索引
    final visibleApps = _getVisibleApps(context);
    final pageIndex = visibleApps.indexOf(app);
    if (pageIndex == -1) return; // 如果应用不在可见列表中，不切换
    
    // 如果目标页面和当前页面相同，不需要切换
    if (_targetPageIndex == pageIndex && _lastRefreshedPageIndex == pageIndex) {
      return;
    }
    
    // 记录目标页面索引
    _targetPageIndex = pageIndex;
    
    setState(() {
      _activeApp = app;
    });
    
    // 执行页面切换动画
    _pageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    ).then((_) {
      // 动画完成后，不需要刷新目标页面
      // 所有页面都会在首次进入时自动加载（通过 initState）
      // 只有在需要强制刷新时才调用 refresh(force: true)
      if (mounted && _targetPageIndex == pageIndex && _pageController.hasClients) {
        final currentPage = _pageController.page?.round();
        if (currentPage == pageIndex) {
          _lastRefreshedPageIndex = pageIndex;
        }
      }
      // 只有当这是最新的目标页面时才清除标记
      if (_targetPageIndex == pageIndex) {
        _targetPageIndex = null;
      }
    }).catchError((error) {
      // 动画被中断或出错时，清除目标页面标记
      if (_targetPageIndex == pageIndex) {
        _targetPageIndex = null;
      }
    });
  }
  
  void _onPageChanged(int index) {
    // 获取可见的应用列表，然后找到对应的应用
    final visibleApps = _getVisibleApps(context);
    if (index >= 0 && index < visibleApps.length) {
    setState(() {
        _activeApp = visibleApps[index];
    });
    }
    
    // 页面切换时，只有在真正切换到目标页面时才触发首次加载
    // 这样可以避免路过页面时触发不必要的加载
    if (_targetPageIndex == null) {
      // 用户手动滑动的情况，触发目标页面的首次加载
      if (_lastRefreshedPageIndex != index) {
        _lastRefreshedPageIndex = index;
        _triggerPageLoad(index);
      }
    } else if (_targetPageIndex == index) {
      // 这是目标页面，触发首次加载
      _lastRefreshedPageIndex = index;
      _triggerPageLoad(index);
    }
    // 如果 _targetPageIndex != null 且 _targetPageIndex != index，说明是中间页面，不加载
  }

  /// 触发页面的首次加载（仅在页面真正可见时）
  void _triggerPageLoad(int pageIndex) {
    final visibleApps = _getVisibleApps(context);
    if (pageIndex >= 0 && pageIndex < visibleApps.length) {
      final app = visibleApps[pageIndex];
      if (app == AppType.claudeCode) {
        _claudeConfigScreenKey.currentState?.refresh();
      } else if (app == AppType.codex) {
        _codexConfigScreenKey.currentState?.refresh();
      } else if (app == AppType.gemini) {
        _geminiConfigScreenKey.currentState?.refresh();
      }
      // MCP 和密钥列表页面使用 ViewModel 缓存，不需要手动触发
    }
  }
  
  void _refreshPageData(int pageIndex) {
    // 获取可见的应用列表，然后根据应用类型刷新
    // 注意：ClaudeCode 和 Codex 页面会在 initState 中自动加载，不需要在这里刷新
    // MCP 页面也会在 initState 中自动加载，不需要在这里刷新
    // 密钥列表页面使用 ViewModel 缓存，也不需要刷新
    // 这个方法现在主要用于需要强制刷新的场景，但页面切换时不应该调用
    final visibleApps = _getVisibleApps(context);
    if (pageIndex >= 0 && pageIndex < visibleApps.length) {
      final app = visibleApps[pageIndex];
      // 页面切换时不刷新，所有页面都在首次进入时自动加载
      // 只有在需要强制刷新时才调用 refresh(force: true)
    }
  }

  /// 获取可见的应用列表（根据工具启用状态过滤）
  List<AppType> _getVisibleApps(BuildContext context) {
    try {
      final settingsViewModel = context.read<SettingsViewModel>();
      final enabledTools = settingsViewModel.getEnabledTools();
      
      final visibleApps = AppType.values.where((app) {
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
      
      // 如果当前活动应用不在可见列表中，且当前不在设置页面，才切换到第一个可见应用
      // 如果当前在设置页面，保持不变，避免在设置页面时切换页面
      if (!visibleApps.contains(_activeApp) && visibleApps.isNotEmpty) {
        // 如果当前在设置页面，保持不变
        if (_activeApp == AppType.settings) {
          // 设置页面始终可见，所以不需要切换
          return visibleApps;
        }
        // 否则切换到第一个可见应用
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _onAppSwitched(visibleApps.first);
          }
        });
      }
      
      return visibleApps;
    } catch (e) {
      // 如果无法获取SettingsViewModel，返回所有应用
      return AppType.values;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Consumer<KeyManagerViewModel>(
        builder: (context, viewModel, child) {
          final localizations = AppLocalizations.of(context);
          
          // 只在状态从 false 变为 true 时显示一次通知
          if (viewModel.isLoading && !_previousLoadingState) {
            _previousLoadingState = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(localizations?.loading ?? '加载中...'),
                      ],
                    ),
                    duration: const Duration(seconds: 1),
                    backgroundColor: Colors.black87,
                  ),
                );
              }
            });
          } else if (!viewModel.isLoading) {
            _previousLoadingState = false;
          }
          
          return SafeArea(
            top: false, // macOS 沉浸式标题栏：不预留顶部安全区域
            bottom: false,
            left: false,
            right: false,
            child: Column(
              children: [
                // macOS 26 风格：沉浸式标题栏（与界面融为一体）
                _buildImmersiveTitleBar(context, viewModel),
                // 页面内容区域
                Expanded(
                  child: Consumer<SettingsViewModel>(
                    builder: (context, settingsViewModel, child) {
                      final visibleApps = _getVisibleApps(context);
                      final settingsIndex = visibleApps.indexOf(AppType.settings);
                      
                      // 如果当前在设置页面，确保PageView保持在设置页面
                      // 必须在 postFrameCallback 中执行，避免在 build 过程中调用 setState
                      // 注意：只有在工具状态变化导致页面列表重建时才使用 jumpToPage
                      // 用户主动切换时应该使用 animateToPage（通过 _onAppSwitched）
                      if (_activeApp == AppType.settings && settingsIndex != -1) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _pageController.hasClients) {
                            final currentPage = _pageController.page?.round();
                            // 如果当前页面索引不是设置页面的索引，且没有正在进行的动画，才跳转
                            if (currentPage != settingsIndex && _targetPageIndex == null) {
                              // 只有在没有动画进行时才使用 jumpToPage（工具状态变化导致的重建）
                              // 如果有动画进行（_targetPageIndex != null），说明是用户主动切换，不干扰
                              _pageController.jumpToPage(settingsIndex);
                              _lastRefreshedPageIndex = settingsIndex;
                            }
                          }
                        });
                      }
                      
                      return PageView(
                        controller: _pageController,
                        onPageChanged: (index) {
                          // 如果当前在设置页面，且工具状态变化导致页面列表重建，
                          // 但用户仍然在设置页面，不要触发 onPageChanged 中的状态更新
                          if (_activeApp == AppType.settings && index == settingsIndex) {
                            // 只更新刷新索引，不更新 _activeApp，避免触发其他逻辑
                            _lastRefreshedPageIndex = settingsIndex;
                            return;
                          }
                          _onPageChanged(index);
                        },
                        children: visibleApps.map((app) {
                          switch (app) {
                            case AppType.keyManager:
                              return _buildKeyManagerPage(context, viewModel);
                            case AppType.claudeCode:
                              return ClaudeConfigScreen(key: _claudeConfigScreenKey);
                            case AppType.codex:
                              return CodexConfigScreen(key: _codexConfigScreenKey);
                            case AppType.gemini:
                              return GeminiConfigScreen(key: _geminiConfigScreenKey);
                            case AppType.mcp:
                              return const McpConfigScreen();
                            case AppType.settings:
                              return SettingsScreen(key: _settingsScreenKey);
                          }
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildKeyManagerPage(BuildContext context, KeyManagerViewModel viewModel) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    return Column(
      children: [
                // 工具栏：搜索、筛选、设置（同一行）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: shadTheme.colorScheme.background,
                    border: Border(
                      bottom: BorderSide(
                        color: shadTheme.colorScheme.border,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // 搜索栏（左侧）
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: const EdgeInsets.only(right: 12),
                          height: 38, // 固定高度，避免输入时高度变化
                          child: ClipRect(
                            clipBehavior: Clip.hardEdge,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Builder(
                                builder: (context) {
                                  final localizations = AppLocalizations.of(context);
                                  final shadTheme = ShadTheme.of(context);
                              return ShadInput(
                                controller: _searchController,
                                onChanged: (query) => viewModel.setSearchQuery(query),
                                placeholder: Text(localizations?.search ?? '搜索密钥...'),
                                leading: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: shadTheme.colorScheme.mutedForeground,
                                ),
                                trailing: _searchController.text.isNotEmpty
                                    ? ShadButton(
                                        width: 20,
                                        height: 20,
                                        padding: EdgeInsets.zero,
                                        backgroundColor: Colors.transparent,
                                        foregroundColor: shadTheme.colorScheme.mutedForeground,
                                        hoverBackgroundColor: Colors.transparent,
                                        onPressed: () {
                                          _searchController.clear();
                                          viewModel.setSearchQuery('');
                                        },
                                        child: const Icon(Icons.clear, size: 14),
                                      )
                                    : null,
                              );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 平台过滤器（中间）
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Builder(
                            builder: (context) {
                              final localizations = AppLocalizations.of(context);
                              // 只显示已添加的平台
                              final addedPlatforms = viewModel.addedPlatforms;
                              return ShadSelect<PlatformType?>(
                                key: ValueKey('platform_filter_${viewModel.filterPlatform}_${addedPlatforms.length}'),
                                initialValue: viewModel.filterPlatform,
                                placeholder: Text(localizations?.allPlatforms ?? '全部平台'),
                                options: [
                                  ShadOption<PlatformType?>(
                                    value: null,
                                    child: Text(localizations?.allPlatforms ?? '全部平台'),
                                  ),
                                  ...addedPlatforms.map((platform) {
                                    return ShadOption<PlatformType?>(
                                      value: platform,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          PlatformIconHelper.buildIcon(
                                            platform: platform,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(platform.value),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                                selectedOptionBuilder: (context, value) {
                                  if (value == null) {
                                    return Text(localizations?.allPlatforms ?? '全部平台');
                                  }
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      PlatformIconHelper.buildIcon(
                                        platform: value,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(value.value),
                                    ],
                                  );
                                },
                                onChanged: (value) => viewModel.setPlatformFilter(value),
                              );
                            },
                          ),
                        ),
                      ),
                      // 按钮组：拖动模式、添加
                      Container(
                        height: 38, // 与输入框高度一致
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: shadTheme.colorScheme.border,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 拖动模式按钮
                            Tooltip(
                              message: _isEditMode 
                                  ? (localizations?.finishEdit ?? '完成编辑')
                                  : (localizations?.edit ?? '编辑'),
                              child: _isEditMode
                                  ? ShadButton.ghost(
                                      width: 38,
                                      height: 38,
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        setState(() {
                                          _isEditMode = !_isEditMode;
                                        });
                                      },
                                      child: Icon(
                                        Icons.check,
                                        size: 18,
                                        color: shadTheme.colorScheme.primary,
                                      ),
                                    )
                                  : ShadButton.ghost(
                                      width: 38,
                                      height: 38,
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        setState(() {
                                          _isEditMode = !_isEditMode;
                                        });
                                      },
                                      child: Icon(
                                        Icons.drag_handle,
                                        size: 18,
                                        color: shadTheme.colorScheme.primary,
                                      ),
                                    ),
                            ),
                            // 分隔线
                            Container(
                              width: 1,
                              height: 20,
                              color: shadTheme.colorScheme.border,
                            ),
                            // 刷新按钮
                            Tooltip(
                              message: localizations?.refreshKeyList ?? '刷新列表',
                              child: ShadButton.ghost(
                                width: 38,
                                height: 38,
                                padding: EdgeInsets.zero,
                                onPressed: () => viewModel.refresh(),
                                child: Icon(
                                  Icons.refresh,
                                  size: 18,
                                  color: shadTheme.colorScheme.primary,
                                ),
                              ),
                            ),
                            // 分隔线
                            Container(
                              width: 1,
                              height: 20,
                              color: shadTheme.colorScheme.border,
                            ),
                            // 添加按钮
                            Tooltip(
                              message: localizations?.addKeyTooltip ?? '添加密钥',
                              child: ShadButton.ghost(
                                width: 38,
                                height: 38,
                                padding: EdgeInsets.zero,
                                onPressed: () => _showAddKeyPage(context),
                                child: Icon(
                                  Icons.add,
                                  size: 18,
                                  color: shadTheme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 统计数据
                if (viewModel.statistics != null)
                  _buildStatisticsCard(viewModel.statistics!),
                // 密钥列表
                Expanded(
                  child: viewModel.keys.isEmpty
                      ? _buildEmptyState(viewModel)
                      : _buildKeyList(viewModel, _isEditMode),
                ),
              ],
            );
  }

  /// macOS 26 风格：沉浸式标题栏（与界面融为一体）
  Widget _buildImmersiveTitleBar(BuildContext context, KeyManagerViewModel viewModel) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    // macOS 标准标题栏高度 + 窗口控制按钮区域
    // 考虑窗口控制按钮（红绿灯）的高度，通常为 28px，加上内边距
    // 增加上边距以避免滑块进入窗口控制按钮的可点击区域
    return Container(
      height: 56, // 增加高度以容纳上边距
      padding: const EdgeInsets.only(top: 20, left: 20), // 增加上边距避免被标题栏点击事件遮挡
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.background,
        // 移除底部边框
      ),
      child: Stack(
        children: [
          // 页面切换导航居中显示
          Center(
            child: AppSwitcher(
              activeApp: _activeApp,
              onSwitch: _onAppSwitched,
            ),
          ),
          // 右侧：统计信息（仅在钥匙包页面显示）
          if (_activeApp == AppType.keyManager && viewModel.statistics != null)
            Positioned(
              right: 16,
              top: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompactStatItem(
                    context,
                    localizations?.total ?? '总数',
                    viewModel.statistics!.total,
                    shadTheme,
                  ),
                  const SizedBox(width: 16),
                  _buildCompactStatItem(
                    context,
                    localizations?.active ?? '活跃',
                    viewModel.statistics!.active,
                    shadTheme,
                    color: Colors.green,
                  ),
                  if (viewModel.statistics!.expiringSoon > 0) ...[
                    const SizedBox(width: 16),
                    _buildCompactStatItem(
                      context,
                      localizations?.expiringSoon ?? '即将过期',
                      viewModel.statistics!.expiringSoon,
                      shadTheme,
                      color: Colors.orange,
                    ),
                  ],
                  if (viewModel.statistics!.expired > 0) ...[
                    const SizedBox(width: 16),
                    _buildCompactStatItem(
                      context,
                      localizations?.expired ?? '已过期',
                      viewModel.statistics!.expired,
                      shadTheme,
                      color: Colors.red,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactStatItem(
    BuildContext context,
    String label,
    int value,
    ShadThemeData theme, {
    Color? color,
  }) {
    final displayColor = color ?? theme.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value.toString(),
          style: theme.textTheme.small.copyWith(
            fontWeight: FontWeight.w600,
            color: displayColor,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsCard(KeyStatistics stats) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.muted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                localizations?.statistics ?? '统计信息',
                style: shadTheme.textTheme.p.copyWith(
                  fontWeight: FontWeight.w600,
                  color: shadTheme.colorScheme.foreground,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(localizations?.total ?? '总数', stats.total, Colors.blue, shadTheme),
                  _buildStatItem(localizations?.active ?? '活跃', stats.active, Colors.green, shadTheme),
                  _buildStatItem(localizations?.expiringSoon ?? '即将过期', stats.expiringSoon, Colors.orange, shadTheme),
                  _buildStatItem(localizations?.expired ?? '已过期', stats.expired, Colors.red, shadTheme),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color, ShadThemeData theme) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.small.copyWith(
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(KeyManagerViewModel viewModel) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    if (viewModel.isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: shadTheme.colorScheme.primary,
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.muted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.vpn_key_outlined,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations?.noKeys ?? '暂无密钥',
            style: shadTheme.textTheme.h4.copyWith(
              color: shadTheme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations?.addFirstKey ?? '点击上方按钮添加您的第一个AI密钥',
            style: shadTheme.textTheme.p.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyList(KeyManagerViewModel viewModel, bool isEditMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算每行卡片数量，卡片最小宽度为 240px
        const double minCardWidth = 240;
        const double cardSpacing = 10;
        const double padding = 16;
        const double cardHeight = 160; // 固定卡片高度，与 MCP 卡片一致
        
        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        
        // 确保至少显示1列，最多5列
        crossAxisCount = crossAxisCount.clamp(1, 5);
        
        // 如果可用宽度不足以容纳计算出的列数，减少列数
        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }
        
        final keys = List<AIKey>.from(viewModel.keys);
        
        // 构建卡片列表
        final cardWidgets = keys.map((key) {
          return KeyCard(
            key: ValueKey(key.id),
            aiKey: key,
            isEditMode: isEditMode,
            onTap: () => _showKeyDetails(context, key),
            onEdit: () => _showEditKeyPage(context, key, viewModel),
            onDelete: () => _deleteKey(context, key, viewModel),
            onOpenManagementUrl: () {
              if (key.managementUrl != null) {
                UrlLauncherService().openUrl(key.managementUrl!);
              }
            },
            onCopyApiEndpoint: () {
              if (key.apiEndpoint != null) {
                ClipboardService().copyToClipboard(key.apiEndpoint!);
                _showSnackBar(context, 'API地址已复制');
              }
            },
            onCopyApiKey: () {
              viewModel.copyKeyToClipboard(key.id!);
              final loc = AppLocalizations.of(context);
              _showSnackBar(context, loc?.keyCopied ?? '密钥已复制');
            },
          );
        }).toList();

        // 编辑模式下使用 ReorderableWrap
        if (isEditMode) {
          return Padding(
            padding: const EdgeInsets.all(padding),
            child: ReorderableWrap(
              spacing: cardSpacing,
              runSpacing: cardSpacing,
              needsLongPressDraggable: false, // 禁用长按拖动，允许直接拖动
              onReorder: (oldIndex, newIndex) {
                // ReorderableWrap 的索引计算
                // 根据官方示例，ReorderableWrap 的 newIndex 已经是正确的插入位置
                // 不需要再调整
                final reorderedKeys = List<AIKey>.from(viewModel.keys);
                
                // 先移除拖动项
                final draggedKey = reorderedKeys.removeAt(oldIndex);
                
                // 直接使用 newIndex 作为插入位置
                // ReorderableWrap 已经处理了索引调整
                final insertIndex = newIndex.clamp(0, reorderedKeys.length);
                
                reorderedKeys.insert(insertIndex, draggedKey);
                viewModel.reorderKeys(reorderedKeys);
              },
              onNoReorder: (index) {
                // 拖动取消时的回调
              },
              children: cardWidgets.asMap().entries.map((entry) {
                final index = entry.key;
                final card = entry.value;
                return SizedBox(
                  key: ValueKey(keys[index].id),
                  width: cardWidth,
                  height: cardHeight,
                  child: card,
                );
              }).toList(),
            ),
          );
        }

        // 非编辑模式使用普通 GridView
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: (cardWidth / cardHeight), // 固定高度，动态宽度
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
          ),
          itemCount: cardWidgets.length,
          itemBuilder: (context, index) => cardWidgets[index],
        );
      },
    );
  }

  void _showKeyDetails(BuildContext context, AIKey key) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    final decryptedKey = await viewModel.getDecryptedKey(key.id!);
    
    if (decryptedKey == null) {
      _showSnackBar(context, localizations?.cannotDecryptKey ?? '无法解密密钥', isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _KeyDetailsDialog(
        aiKey: decryptedKey,
        viewModel: viewModel,
        onEdit: () {
          Navigator.pop(context);
          _showEditKeyPage(context, decryptedKey, viewModel);
        },
        onCopyKey: () {
          viewModel.copyKeyToClipboard(decryptedKey.id!);
          final loc = AppLocalizations.of(context);
          _showSnackBar(context, loc?.keyCopiedToClipboard ?? '密钥已复制到剪贴板');
        },
        onOpenManagementUrl: () {
          if (decryptedKey.managementUrl != null) {
            UrlLauncherService().openUrl(decryptedKey.managementUrl!);
          }
        },
        onCopyApiEndpoint: () {
          if (decryptedKey.apiEndpoint != null) {
            ClipboardService().copyToClipboard(decryptedKey.apiEndpoint!);
            _showSnackBar(context, 'API地址已复制');
          }
        },
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value,
      {bool isSecret = false, VoidCallback? onCopy}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isSecret ? '•' * value.length : value,
                    style: TextStyle(
                      fontFamily: isSecret ? 'monospace' : null,
                    ),
                  ),
                ),
                if (isSecret && onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: onCopy,
                    tooltip: AppLocalizations.of(context)?.copy ?? '复制',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showAddKeyPage(BuildContext context) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    
    final result = await Navigator.of(context).push<AIKey>(
      MaterialPageRoute(
        builder: (context) => const KeyFormPage(),
      ),
    );

    if (result != null) {
      final success = await viewModel.addKey(result);
      if (success) {
        _showSnackBar(context, localizations?.keyAddedSuccess ?? '密钥添加成功');
        // 强制刷新 ClaudeCode、Codex 和 Gemini 页面（因为添加了新密钥）
        _claudeConfigScreenKey.currentState?.refresh(force: true);
        _codexConfigScreenKey.currentState?.refresh(force: true);
        _geminiConfigScreenKey.currentState?.refresh(force: true);
      } else {
        _showSnackBar(context, viewModel.errorMessage ?? (localizations?.addFailed ?? '添加失败'), isError: true);
      }
    }
  }

  Future<void> _showEditKeyPage(
      BuildContext context, AIKey key, KeyManagerViewModel viewModel) async {
    final localizations = AppLocalizations.of(context);
    // 获取解密后的密钥用于编辑
    final decryptedKey = await viewModel.getDecryptedKey(key.id!);
    if (decryptedKey == null) {
      _showSnackBar(context, localizations?.cannotDecryptKey ?? '无法解密密钥', isError: true);
      return;
    }

    final result = await Navigator.of(context).push<AIKey>(
      MaterialPageRoute(
        builder: (context) => KeyFormPage(editingKey: decryptedKey),
      ),
    );

    if (result != null) {
      // 保存 ScaffoldMessenger 引用，避免异步操作后 context 失效
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final success = await viewModel.updateKey(result);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      if (success) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(localizations?.keyUpdatedSuccess ?? '密钥更新成功'),
            duration: const Duration(seconds: 2),
          ),
        );
        // 强制刷新 ClaudeCode、Codex 和 Gemini 页面（因为更新了密钥）
        _claudeConfigScreenKey.currentState?.refresh(force: true);
        _codexConfigScreenKey.currentState?.refresh(force: true);
        _geminiConfigScreenKey.currentState?.refresh(force: true);
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(viewModel.errorMessage ?? (localizations?.updateFailed ?? '更新失败')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _deleteKey(
      BuildContext context, AIKey key, KeyManagerViewModel viewModel) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: localizations?.confirmDelete ?? '确认删除',
      message: localizations?.deleteKeyConfirm(key.name) ?? 
          '确定要删除密钥"${key.name}"吗？此操作不可撤销。',
      confirmText: localizations?.delete ?? '删除',
      isDangerous: true,
    );

    if (confirmed == true) {
      final success = await viewModel.deleteKey(key.id!);
      if (success) {
        _showSnackBar(context, localizations?.keyDeleted ?? '密钥已删除');
        // 强制刷新 ClaudeCode、Codex 和 Gemini 页面（因为删除了密钥）
        _claudeConfigScreenKey.currentState?.refresh(force: true);
        _codexConfigScreenKey.currentState?.refresh(force: true);
        _geminiConfigScreenKey.currentState?.refresh(force: true);
      } else {
        _showSnackBar(
            context, viewModel.errorMessage ?? (localizations?.deleteFailed ?? '删除失败'), isError: true);
      }
    }
  }


  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// 密钥详情弹窗
class _KeyDetailsDialog extends StatefulWidget {
  final AIKey aiKey;
  final KeyManagerViewModel viewModel;
  final VoidCallback onEdit;
  final VoidCallback onCopyKey;
  final VoidCallback onOpenManagementUrl;
  final VoidCallback onCopyApiEndpoint;

  const _KeyDetailsDialog({
    super.key,
    required this.aiKey,
    required this.viewModel,
    required this.onEdit,
    required this.onCopyKey,
    required this.onOpenManagementUrl,
    required this.onCopyApiEndpoint,
  });

  @override
  State<_KeyDetailsDialog> createState() => _KeyDetailsDialogState();
}

class _KeyDetailsDialogState extends State<_KeyDetailsDialog> {
  bool _showKeyValue = false;

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 700),
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                  PlatformIconHelper.buildIcon(
                    platform: widget.aiKey.platformType,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.aiKey.name,
                      style: shadTheme.textTheme.h4.copyWith(
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: localizations?.edit ?? '编辑',
                    child: ShadButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      onPressed: widget.onEdit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    child: Icon(
                      Icons.close,
                      size: 20,
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
                  children: [
                    _buildDetailRow(localizations?.platformLabel ?? '平台', widget.aiKey.platform),
                    const SizedBox(height: 12),
                    // 管理地址
                    if (widget.aiKey.managementUrl != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.managementUrl ?? '管理地址',
                        widget.aiKey.managementUrl!,
                        Icons.language,
                        localizations?.open ?? '打开',
                        widget.onOpenManagementUrl,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // API地址
                    if (widget.aiKey.apiEndpoint != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.apiEndpoint ?? 'API地址',
                        widget.aiKey.apiEndpoint!,
                        Icons.code,
                        localizations?.copy ?? '复制',
                        widget.onCopyApiEndpoint,
                        isMonospace: true,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 密钥值
                    _buildKeyValueRow(context),
                    const SizedBox(height: 10),
                    if (widget.aiKey.expiryDate != null) ...[
                      _buildDetailRow(localizations?.expiryDate ?? '过期日期', widget.aiKey.formattedExpiryDate),
                      const SizedBox(height: 10),
                    ],
                    if (widget.aiKey.tags.isNotEmpty) ...[
                      _buildDetailRow(localizations?.tags ?? '标签', widget.aiKey.tags.join(', ')),
                      const SizedBox(height: 10),
                    ],
                    if (widget.aiKey.notes != null && widget.aiKey.notes!.isNotEmpty) ...[
                      _buildDetailRow(localizations?.notes ?? '备注', widget.aiKey.notes!),
                      const SizedBox(height: 10),
                    ],
                    // 创建时间和更新时间在同一行
                    _buildTimeRow(
                      context,
                      localizations?.createdTime ?? '创建时间',
                      _formatDateTime(widget.aiKey.createdAt),
                      localizations?.updatedTime ?? '更新时间',
                      _formatDateTime(widget.aiKey.updatedAt),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildDetailRow(String label, String value) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isMonospace = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.primary,
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontSize: isMonospace ? 13 : null,
                ),
              ),
            ),
            Tooltip(
              message: tooltip,
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                child: Icon(icon, size: 18, color: shadTheme.colorScheme.mutedForeground),
                onPressed: onPressed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKeyValueRow(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${localizations?.keyValueLabel ?? '密钥值'}:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _showKeyValue
                      ? widget.aiKey.keyValue
                      : '•' * widget.aiKey.keyValue.length,
                  style: shadTheme.textTheme.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _showKeyValue ? (localizations?.hide ?? '隐藏') : (localizations?.show ?? '显示'),
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _showKeyValue ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  setState(() {
                    _showKeyValue = !_showKeyValue;
                  });
                },
              ),
            ),
            Tooltip(
              message: localizations?.copy ?? '复制',
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: widget.onCopyKey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRow(
    BuildContext context,
    String createdLabel,
    String createdValue,
    String updatedLabel,
    String updatedValue,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$createdLabel / $updatedLabel:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$createdValue / $updatedValue',
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
