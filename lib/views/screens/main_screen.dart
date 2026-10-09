import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reorderables/reorderables.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../widgets/key_card.dart';
import '../widgets/key_details_dialog.dart';
import '../widgets/app_switcher.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/kc_toast.dart';
import 'key_form_page.dart';
import 'claude_config_screen.dart';
import 'codex_config_screen.dart';
import 'gemini_config_screen.dart';
import 'openclaw_config_screen.dart';
import 'mcp_config_screen.dart';
import 'skills_config_screen.dart';
import 'settings_screen.dart';
import '../widgets/first_launch_dialog.dart';
import '../../models/ai_key.dart';
import '../../models/platform_type.dart';
import '../../models/platform_category.dart';
import '../../services/database_service.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/first_launch_service.dart';
import '../../services/settings_service.dart';
import '../../services/key_validation_service.dart';
import '../../services/model_list_service.dart';
import '../widgets/model_list_dialog.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../utils/app_localizations.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import '../../models/mcp_server.dart' show AiToolType;
import '../../services/codex_config_service.dart';
import '../../theme/kc_tokens.dart';
import '../widgets/kc_logo.dart';
import '../widgets/kc_segmented.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PageController _pageController = PageController();
  final GlobalKey<ClaudeConfigScreenState> _claudeConfigScreenKey = GlobalKey<ClaudeConfigScreenState>();
  final GlobalKey<ClaudeConfigScreenState> _claudeDesktopConfigScreenKey = GlobalKey<ClaudeConfigScreenState>();
  final GlobalKey<CodexConfigScreenState> _codexConfigScreenKey = GlobalKey<CodexConfigScreenState>();
  final GlobalKey<GeminiConfigScreenState> _geminiConfigScreenKey = GlobalKey<GeminiConfigScreenState>();
  final GlobalKey<OpenClawConfigScreenState> _openClawConfigScreenKey = GlobalKey<OpenClawConfigScreenState>();
  // 使用 ValueKey 来保持设置页面状态，避免 children 列表变化时重置
  static const _settingsScreenKey = ValueKey('settings_screen');
  bool _isEditMode = false;
  AppType _activeApp = AppType.keyManager;
  SettingsCategory _settingsCategory = SettingsCategory.general;
  _KeySegment _segment = _KeySegment.all;
  int? _lastRefreshedPageIndex; // 记录上次刷新的页面索引，避免重复刷新
  int? _targetPageIndex; // 记录目标页面索引，用于区分中间页面和目标页面
  final ScrollController _keyListScrollController = ScrollController();
  final GlobalKey _keyListKey = GlobalKey();
  Timer? _edgeScrollTimer;
  bool _isDragging = false;
  Offset? _lastDragPosition;

  @override
  void initState() {
    super.initState();
    // 监听搜索框变化以更新清除按钮
    _searchController.addListener(() {
      setState(() {});
    });
    // 初始化ViewModel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final keyVm = context.read<KeyManagerViewModel>();
      keyVm.init().then((_) {
        // 侧栏工具行显示「当前生效密钥」：进入时并行读一次各工具配置
        if (mounted) keyVm.refreshCurrentToolKeys();
      });
      // 触发初始页面的首次加载（如果是 ClaudeCode 或 Codex）
      if (_lastRefreshedPageIndex == null) {
        _triggerPageLoad(0);
      }
      // 首次启动检测：检查配置目录访问权限（仅在 macOS）
      if (Platform.isMacOS) {
        _checkFirstLaunchPermissions();
      }
    });
  }

  /// 检查首次启动时的配置目录访问权限
  Future<void> _checkFirstLaunchPermissions() async {
    try {
      final firstLaunchService = FirstLaunchService();
      await firstLaunchService.init();
      
      // 如果已经检查过权限，不再重复检查
      if (firstLaunchService.hasCheckedPermissions()) {
        return;
      }
      
      // 延迟一下，确保 UI 已经渲染完成
      await Future.delayed(const Duration(milliseconds: 1000));
      
      if (!mounted) return;
      
      // 检查是否需要用户主目录授权
      final needsAuth = await firstLaunchService.needsHomeDirAuthorization();
      
      if (!needsAuth) {
        // 用户主目录可以访问，标记为已检查
        await firstLaunchService.markPermissionsChecked();
        return;
      }
      
      // 获取默认用户主目录路径
      final homeDir = await SettingsService.getUserHomeDir();
      
      // 显示统一的用户主目录选择对话框
      final selected = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => FirstLaunchDialog(
          defaultHomeDir: homeDir,
          onComplete: () {
            // 对话框关闭后的回调
          },
        ),
      );
      
      // 无论用户是否选择，都标记为已检查，避免重复提示
      await firstLaunchService.markPermissionsChecked();
    } catch (e) {
      // 静默处理错误，不影响应用启动
      print('MainScreen: 首次启动权限检查失败: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    _keyListScrollController.dispose();
    _edgeScrollTimer?.cancel();
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
          // 动画结束再兜底触发一次首次加载：PageView 不保活，页面滑出后 State 会被重建，
          // 只靠 onPageChanged 时可能拿到旧的 / 尚未挂载的 State，导致工具页显示「暂无密钥」直到手动刷新。
          // refresh() 在已加载过时是空操作，不会重复读取。
          _triggerPageLoad(pageIndex);
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
      } else if (app == AppType.claudeDesktop) {
        _claudeDesktopConfigScreenKey.currentState?.refresh();
      } else if (app == AppType.codex) {
        _codexConfigScreenKey.currentState?.refresh();
      } else if (app == AppType.gemini) {
        _geminiConfigScreenKey.currentState?.refresh();
      } else if (app == AppType.openClaw) {
        _openClawConfigScreenKey.currentState?.refresh();
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
      
      final visibleApps = AppType.visibleFor(enabledTools);
      
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
          
          
          return SafeArea(
            top: false, // macOS 沉浸式标题栏：不预留顶部安全区域
            bottom: false,
            left: false,
            right: false,
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 全局侧栏（ui_redesign_plan §5.1）：窄窗口收为图标轨
                AppSidebar(
                  activeApp: _activeApp,
                  apps: _getVisibleApps(context),
                  onSwitch: _onAppSwitched,
                  collapsed: constraints.maxWidth < kSidebarCollapseBreakpoint,
                  settingsCategory: _settingsCategory,
                  onSettingsCategory: (c) => setState(() => _settingsCategory = c),
                ),
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
                              return ClaudeConfigScreen(
                                key: _claudeConfigScreenKey,
                                initialTab: ClaudeSection.claudeCode,
                                showSectionToggle: false,
                              );
                            case AppType.claudeDesktop:
                              return ClaudeConfigScreen(
                                key: _claudeDesktopConfigScreenKey,
                                initialTab: ClaudeSection.claudeDesktop,
                                showSectionToggle: false,
                              );
                            case AppType.codex:
                              return CodexConfigScreen(key: _codexConfigScreenKey);
                            case AppType.gemini:
                              return GeminiConfigScreen(key: _geminiConfigScreenKey);
                            case AppType.openClaw:
                              return OpenClawConfigScreen(key: _openClawConfigScreenKey);
                            case AppType.mcp:
                              return const McpConfigScreen();
                            case AppType.skills:
                              return const SkillsConfigScreen();
                            case AppType.settings:
                              return SettingsScreen(key: _settingsScreenKey, category: _settingsCategory);
                          }
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  /// 钥匙包页：页头（标题 + 副标题 + 搜索 + 管理 + 刷新 + 主按钮）/ 管理提示条 / 过滤分段 / 网格
  Widget _buildKeyManagerPage(BuildContext context, KeyManagerViewModel viewModel) {
    final localizations = AppLocalizations.of(context);
    final currentIds = viewModel.currentKeyIds;
    final source = List<AIKey>.from(viewModel.keys);
    final filtered = source.where((k) => _matchesSegment(k, _segment, currentIds)).toList();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isEditMode) setState(() => _isEditMode = false);
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildKeyPageHeader(context, viewModel),
            if (_isEditMode) _buildManageNotice(context),
            if (viewModel.allKeys.isNotEmpty) _buildFilterRow(context, viewModel, source, currentIds),
            Expanded(
              child: viewModel.allKeys.isEmpty
                  ? _buildEmptyState(viewModel)
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            localizations?.noKeysMatchFilter ?? '没有符合条件的密钥',
                            style: KcType.body.copyWith(color: ShadTheme.of(context).colorScheme.mutedForeground),
                          ),
                        )
                      : _buildKeyList(viewModel, _isEditMode, filtered),
            ),
          ],
        ),
      ),
    );
  }

  static bool _matchesSegment(AIKey k, _KeySegment s, Map<AiToolType, int?> currentIds) {
    switch (s) {
      case _KeySegment.all:
        return true;
      case _KeySegment.inUse:
        return k.id != null && currentIds.values.contains(k.id);
      case _KeySegment.unused:
        return enabledToolsOf(k).isEmpty;
      case _KeySegment.attention:
        return k.isExpired || k.isExpiringSoon;
    }
  }

  Widget _buildKeyPageHeader(BuildContext context, KeyManagerViewModel viewModel) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final localizations = AppLocalizations.of(context);
    final all = viewModel.allKeys;
    final ids = viewModel.currentKeyIds.values.whereType<int>().toSet();
    final inUse = all.where((k) => ids.contains(k.id)).length;

    Widget iconButton({Key? key, required IconData icon, required String tip, required VoidCallback onPressed, bool active = false}) {
      return Tooltip(
        key: key,
        message: tip,
        child: ShadButton.outline(
          width: KcSize.control,
          height: KcSize.control,
          padding: EdgeInsets.zero,
          backgroundColor: active ? kc.actionSoft : null,
          onPressed: onPressed,
          child: Icon(icon, size: 16, color: active ? cs.primary : kc.text2),
        ),
      );
    }

    return Container(
      height: KcSize.pageHeader,
      padding: const EdgeInsets.symmetric(horizontal: KcSpace.page),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.border))),
      child: Row(
        children: [
          Text(
            _isEditMode ? (localizations?.manageKeysTitle ?? '管理密钥') : (localizations?.keys ?? '钥匙包'),
            style: KcType.page.copyWith(color: cs.foreground),
          ),
          const SizedBox(width: KcSpace.x3),
          Expanded(
            child: Text(
              localizations?.keyGridSubtitle(all.length, inUse) ?? '${all.length} 个密钥 · $inUse 个正被工具使用',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KcType.caption.copyWith(color: cs.mutedForeground, fontFeatures: KcType.tabular),
            ),
          ),
          const SizedBox(width: KcSpace.x2),
          // 搜索框固定 240 宽、靠右；之前 Flexible 的剩余空间不会被重分配，导致右侧空出一大块
          SizedBox(
            width: 240,
            child: ShadInput(
              key: const ValueKey('keyGrid.search'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              style: KcType.body,
              controller: _searchController,
              onChanged: (query) => viewModel.setSearchQuery(query),
              placeholder: Text(localizations?.search ?? '搜索密钥...'),
              leading: Icon(Icons.search, size: 16, color: cs.mutedForeground),
              trailing: _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        viewModel.setSearchQuery('');
                      },
                      child: Icon(Icons.close, size: 14, color: cs.mutedForeground),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: KcSpace.x2),
          iconButton(
            key: const ValueKey('keyGrid.manageToggle'),
            icon: _isEditMode ? Icons.check : Icons.drag_indicator,
            tip: _isEditMode ? (localizations?.finishEdit ?? '完成编辑') : (localizations?.manageToggleTip ?? '管理：排序 / 置顶 / 删除'),
            active: _isEditMode,
            onPressed: () => setState(() => _isEditMode = !_isEditMode),
          ),
          const SizedBox(width: KcSpace.x2),
          iconButton(
            key: const ValueKey('keyGrid.refresh'),
            icon: Icons.refresh,
            tip: localizations?.refreshKeyList ?? '刷新列表',
            onPressed: () {
              viewModel.refresh();
              viewModel.refreshCurrentToolKeys();
            },
          ),
          const SizedBox(width: KcSpace.x2),
          if (_isEditMode)
            ShadButton(
              key: const ValueKey('keyGrid.done'),
              height: KcSize.control,
              onPressed: () => setState(() => _isEditMode = false),
              child: Text(localizations?.done ?? '完成'),
            )
          else
            ShadButton(
              key: const ValueKey('keyGrid.add'),
              height: KcSize.control,
              leading: const Icon(Icons.add, size: 16),
              onPressed: () => _showAddKeyPage(context),
              child: Text(localizations?.addKey ?? '添加密钥'),
            ),
        ],
      ),
    );
  }

  Widget _buildManageNotice(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final localizations = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('keyGrid.manageNotice'),
      margin: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, 0),
      padding: const EdgeInsets.symmetric(horizontal: KcSpace.x3, vertical: KcSpace.x2),
      decoration: BoxDecoration(
        color: kc.actionSoft,
        borderRadius: BorderRadius.circular(KcRadius.panel),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: kc.actionText),
          const SizedBox(width: KcSpace.x2),
          Expanded(
            child: Text(
              localizations?.manageHint ?? '拖动卡片调整顺序；拖到窗口上下边缘会自动滚动。每张卡片底部可置顶 / 编辑 / 删除。',
              style: KcType.caption.copyWith(color: cs.foreground),
            ),
          ),
          const SizedBox(width: KcSpace.x2),
          Text(localizations?.escToExit ?? 'Esc 退出', style: KcType.caption.copyWith(color: cs.mutedForeground)),
        ],
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context, KeyManagerViewModel viewModel, List<AIKey> source, Map<AiToolType, int?> ids) {
    final localizations = AppLocalizations.of(context);
    int count(_KeySegment s) => source.where((k) => _matchesSegment(k, s, ids)).length;
    final segments = [
      (_KeySegment.all, localizations?.segmentAll ?? '全部'),
      (_KeySegment.inUse, localizations?.segmentInUse ?? '正在使用'),
      (_KeySegment.unused, localizations?.segmentUnused ?? '未用到工具'),
      (_KeySegment.attention, localizations?.segmentAttention ?? '需处理'),
    ];
    final addedCategories = viewModel.addedPlatformCategories;
    final availablePlatforms = viewModel.getAvailablePlatformsForCurrentCategory();

    return Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, 0),
      child: Row(
        children: [
          KcSegmented<_KeySegment>(
            value: _segment,
            items: [for (final (s, label) in segments) (s, label, count(s))],
            onChanged: (s) => setState(() => _segment = s),
          ),
          const SizedBox(width: KcSpace.x3),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: ShadSelect<PlatformCategory?>(
              key: ValueKey('platform_category_filter_${viewModel.filterPlatformCategory}_${addedCategories.length}'),
              initialValue: viewModel.filterPlatformCategory,
              placeholder: Text(localizations?.allCategories ?? '全部分组'),
              options: [
                ShadOption<PlatformCategory?>(value: null, child: Text(localizations?.allCategories ?? '全部分组')),
                ...addedCategories.map((category) => ShadOption<PlatformCategory?>(
                      value: category,
                      child: Text(_getPlatformCategoryDisplayName(category, context)),
                    )),
              ],
              selectedOptionBuilder: (selectContext, value) => Text(
                value == null ? (localizations?.allCategories ?? '全部分组') : _getPlatformCategoryDisplayName(value, selectContext),
                overflow: TextOverflow.ellipsis,
              ),
              onChanged: (value) => viewModel.setPlatformCategoryFilter(value),
                    ),
                  ),
                ),
                const SizedBox(width: KcSpace.x2),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: ShadSelect<PlatformType?>(
              key: ValueKey('platform_filter_${viewModel.filterPlatform}_${viewModel.filterPlatformCategory}_${availablePlatforms.length}'),
              initialValue: viewModel.filterPlatform,
              placeholder: Text(localizations?.allPlatforms ?? '全部平台'),
              options: [
                ShadOption<PlatformType?>(value: null, child: Text(localizations?.allPlatforms ?? '全部平台')),
                ...availablePlatforms.map((platform) => ShadOption<PlatformType?>(
                      value: platform,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        KcPlatformLogo(platform: platform, size: 18, logoSize: 13, radius: 4),
                        const SizedBox(width: 8),
                        Text(platform.value),
                      ]),
                    )),
              ],
              selectedOptionBuilder: (context, value) {
                if (value == null) return Text(localizations?.allPlatforms ?? '全部平台');
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  KcPlatformLogo(platform: value, size: 18, logoSize: 13, radius: 4),
                  const SizedBox(width: 8),
                  Flexible(child: Text(value.value, overflow: TextOverflow.ellipsis)),
                ]);
              },
              onChanged: (value) => viewModel.setPlatformFilter(value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(KeyManagerViewModel viewModel) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final localizations = AppLocalizations.of(context);
    if (viewModel.isLoading) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.vpn_key_outlined, size: 26, color: kc.text2),
            ),
            const SizedBox(height: KcSpace.x4),
            Text(localizations?.emptyKeysTitle ?? '钥匙包还是空的', style: KcType.title.copyWith(color: cs.foreground)),
            const SizedBox(height: KcSpace.x1_5),
            Text(
              localizations?.emptyKeysDesc ?? '添加第一把密钥后，就能一键切换到 Claude Code、Codex、Gemini 等工具。',
              textAlign: TextAlign.center,
              style: KcType.body.copyWith(color: cs.mutedForeground),
            ),
            const SizedBox(height: KcSpace.x5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShadButton(
                  key: const ValueKey('keyGrid.emptyAdd'),
                  leading: const Icon(Icons.add, size: 16),
                  onPressed: () => _showAddKeyPage(context),
                  child: Text(localizations?.addKey ?? '添加密钥'),
                ),
                const SizedBox(width: KcSpace.x2),
                ShadButton.outline(
                  key: const ValueKey('keyGrid.emptyImport'),
                  leading: const Icon(Icons.file_open_outlined, size: 16),
                  onPressed: () {
                    setState(() => _settingsCategory = SettingsCategory.data);
                    _onAppSwitched(AppType.settings);
                  },
                  child: Text(localizations?.importBackupFile ?? '导入备份文件'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyList(KeyManagerViewModel viewModel, bool isEditMode, List<AIKey> visibleKeys) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算每行卡片数量，卡片最小宽度为 240px
        const double minCardWidth = 240;
        const double cardSpacing = 10;
        const double padding = KcSpace.page; // 与页头左右 padding 对齐（原 16，列数算法不变）
        const double cardHeight = 140; // 固定卡片高度，减小高度以优化空间利用
        
        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        
        // 确保至少显示1列，最多5列
        crossAxisCount = crossAxisCount.clamp(1, 5);
        
        // 如果可用宽度不足以容纳计算出的列数，减少列数
        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }
        
        final keys = visibleKeys;
        final currentIds = viewModel.currentKeyIds;
        
        // 构建卡片列表
        final cardWidgets = keys.map((key) {
          return KeyCard(
            key: ValueKey(key.id),
            aiKey: key,
            isEditMode: isEditMode,
            cardMode: KeyCardMode.view, // 密钥管理界面使用查看模式
            onView: () => _showKeyDetails(context, key),
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
                _showSnackBar(context, AppLocalizations.of(context)?.apiEndpointCopied ?? '请求地址已复制');
              }
            },
            onCopyApiKey: () {
              viewModel.copyKeyToClipboard(key.id!);
              final loc = AppLocalizations.of(context);
              _showSnackBar(context, loc?.keyCopied ?? '密钥已复制');
            },
            currentKeyIds: currentIds,
            onSwitchTool: (tool) => _switchToolFromCard(key, tool),
            onEnableTool: (tool) => _enableToolFromCard(context, viewModel, key, tool),
            onMoveToTop: () async {
              final success = await viewModel.moveKeyToTop(key.id!);
              if (success) {
                final loc = AppLocalizations.of(context);
                _showSnackBar(context, loc?.movedToTop ?? '已置顶');
              }
            },
          );
        }).toList();

        // 编辑模式下使用 ReorderableWrap
        if (isEditMode) {
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerMove: (event) {
              if (_isDragging) {
                _lastDragPosition = event.position;
                _checkEdgeScroll();
              }
            },
            onPointerUp: (_) {
              _isDragging = false;
              _lastDragPosition = null;
              _stopEdgeScrolling();
            },
            child: SingleChildScrollView(
              key: _keyListKey,
              controller: _keyListScrollController,
              child: Padding(
                padding: const EdgeInsets.all(padding),
                child: ReorderableWrap(
                  spacing: cardSpacing,
                  runSpacing: cardSpacing,
                  needsLongPressDraggable: false, // 禁用长按拖动，允许直接拖动
                  buildDraggableFeedback: (context, constraints, child) =>
                      KeyCardDragFeedback(constraints: constraints, child: child),
                  onReorder: (oldIndex, newIndex) {
                    // ReorderableWrap 的索引计算
                    // 根据官方示例，ReorderableWrap 的 newIndex 已经是正确的插入位置
                    // 不需要再调整
                    // 过滤（搜索 / 分段）只影响显示：传给 reorderKeys 的是可见子集，
                    // 其余密钥由 reorderKeys 保持原序（与原实现的筛选合并逻辑一致）
                    final reorderedKeys = List<AIKey>.from(keys);
                    
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
                    _isDragging = false;
                    _lastDragPosition = null;
                    _stopEdgeScrolling();
                  },
                  children: cardWidgets.asMap().entries.map((entry) {
                    final index = entry.key;
                    final card = entry.value;
                    return Listener(
                      onPointerDown: (_) {
                        // 拖动开始
                        _isDragging = true;
                      },
                      child: SizedBox(
                        key: ValueKey(keys[index].id),
                        width: cardWidth,
                        height: cardHeight,
                        child: card,
                      ),
                    );
                  }).toList(),
                ),
              ),
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

    showKeyDetailsSheet(
      context: context,
      builder: (context) => KeyDetailsDialog(
        aiKey: decryptedKey,
        viewModel: viewModel,
        onEdit: () {
          Navigator.pop(context);
          _showEditKeyPage(context, decryptedKey, viewModel);
        },
        onCopyText: (text) {
          ClipboardService().copyToClipboard(text);
          final shown = text.length > 30 ? '${text.substring(0, 30)}...' : text;
          _showSnackBar(context, AppLocalizations.of(context)?.copiedText(shown) ?? '已复制：$shown');
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
        onSwitchTool: (tool) => _switchToolFromCard(decryptedKey, tool),
        onToggleTool: (k, tool, enabled) => _toggleToolForKey(context, viewModel, k, tool, enabled),
        onDelete: () {
          Navigator.pop(context);
          _deleteKey(this.context, key, viewModel);
        },
        onCopyEnv: (text) {
          ClipboardService().copyToClipboard(text);
          _showSnackBar(context, AppLocalizations.of(context)?.envVarsCopied ?? '环境变量已复制（含密钥，请勿外传）');
        },
      ),
    );
  }

  /// 卡片「＋」菜单里选「启用到 X」：直接打开 enable 标志（缺模型时转编辑页）
  Future<void> _enableToolFromCard(BuildContext context, KeyManagerViewModel viewModel, AIKey key, AiToolType tool) async {
    if (key.id == null) return;
    final decrypted = await viewModel.getDecryptedKey(key.id!);
    if (!context.mounted) return;
    if (decrypted == null) {
      _showSnackBar(context, AppLocalizations.of(context)?.cannotDecryptKey ?? '无法解密密钥', isError: true);
      return;
    }
    await _toggleToolForKey(context, viewModel, decrypted, tool, true, inSheet: false);
  }

  /// 详情抽屉里的工具开关：只改 enableXxx（不写工具配置）。开启时若该工具还缺请求地址 / 模型，转去编辑页补全
  Future<AIKey?> _toggleToolForKey(
      BuildContext context, KeyManagerViewModel viewModel, AIKey key, AiToolType tool, bool enabled,
      {bool inSheet = true}) async {
    final l = AppLocalizations.of(context);
    final name = kcToolName(tool);
    if (enabled && toolNeedsSetup(key, tool)) {
      _showSnackBar(context, l?.toolModelMissing(name) ?? '$name 还缺少请求地址或模型，请先在编辑页补全', isError: true);
      if (inSheet) Navigator.pop(context);
      _showEditKeyPage(this.context, key, viewModel);
      return null;
    }
    final updated = withToolEnabled(key, tool, enabled);
    final ok = await viewModel.updateKey(updated);
    if (!context.mounted) return ok ? updated : null;
    if (ok) {
      _showSnackBar(context, enabled ? (l?.toolEnabledFor(name) ?? '已启用到 $name') : (l?.toolDisabledFor(name) ?? '已从 $name 的候选列表移除'));
      return updated;
    }
    _showSnackBar(context, viewModel.errorMessage ?? (l?.updateFailed ?? '更新失败'), isError: true);
    return null;
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
      final success = await viewModel.updateKey(result);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      if (success) {
        showKcToast(this.context, localizations?.keyUpdatedSuccess ?? '密钥更新成功', kind: KcToastKind.success);
        // 强制刷新 ClaudeCode、Codex 和 Gemini 页面（因为更新了密钥）
        _claudeConfigScreenKey.currentState?.refresh(force: true);
        _codexConfigScreenKey.currentState?.refresh(force: true);
        _geminiConfigScreenKey.currentState?.refresh(force: true);
      } else {
        showKcToast(this.context, viewModel.errorMessage ?? (localizations?.updateFailed ?? '更新失败'), kind: KcToastKind.error);
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


  Future<bool> _switchTool(KeyManagerViewModel vm, AiToolType tool, int keyId) {
    switch (tool) {
      case AiToolType.claudecode:
        return vm.switchClaudeCodeProvider(keyId);
      case AiToolType.claudeDesktop:
        return vm.switchClaudeDesktopProvider(keyId);
      case AiToolType.codex:
        return vm.switchCodexProvider(keyId);
      case AiToolType.gemini:
        return vm.switchGeminiProvider(keyId);
      default:
        return Future.value(false);
    }
  }

  Future<bool> _switchToolToOfficial(KeyManagerViewModel vm, AiToolType tool) {
    switch (tool) {
      case AiToolType.claudecode:
        return vm.switchToOfficialClaudeCode();
      case AiToolType.claudeDesktop:
        return vm.switchToOfficialClaudeDesktop();
      case AiToolType.codex:
        return vm.switchToOfficialCodex();
      case AiToolType.gemini:
        return vm.switchToOfficialGemini();
      default:
        return Future.value(false);
    }
  }

  /// 卡片上点击「已启用」工具 chip：直接切换，toast 里带「撤销」（恢复到切换前的密钥或官方配置）
  Future<void> _switchToolFromCard(AIKey key, AiToolType tool) async {
    if (key.id == null) return;
    final vm = context.read<KeyManagerViewModel>();
    final previous = vm.currentKeyIds[tool];
    bool ok;
    Object? error;
    try {
      ok = await _switchTool(vm, tool, key.id!);
    } catch (e) {
      ok = false;
      error = e;
    }
    if (!mounted) return;
    error ??= ok ? null : vm.errorMessage;
    showSwitchResult(
      context,
      success: ok,
      targetName: key.name,
      toolName: kcToolName(tool),
      error: error,
      onRetry: () => _switchToolFromCard(key, tool),
      onUndo: ok && previous != key.id ? () => _undoToolSwitch(tool, previous) : null,
    );
    if (ok && tool == AiToolType.codex) {
      await _maybeWarnCodexEnvVar(vm, key);
    }
  }

  Future<void> _undoToolSwitch(AiToolType tool, int? previousKeyId) async {
    final vm = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    bool ok;
    Object? error;
    try {
      ok = previousKeyId != null ? await _switchTool(vm, tool, previousKeyId) : await _switchToolToOfficial(vm, tool);
    } catch (e) {
      ok = false;
      error = e;
    }
    if (!mounted) return;
    String name = localizations?.officialShort ?? '官方';
    if (previousKeyId != null) {
      for (final k in vm.allKeys) {
        if (k.id == previousKeyId) name = k.name;
      }
    }
    if (ok) {
      showKcToast(context, localizations?.undoSwitchRestored(kcToolName(tool), name) ?? '已恢复：${kcToolName(tool)} 使用 $name');
    } else {
      showSwitchResult(context, success: false, targetName: name, toolName: kcToolName(tool), error: error ?? vm.errorMessage);
    }
  }

  /// 与 Codex 页一致：该供应商不支持 auth.json 时，提示需要设置环境变量
  Future<void> _maybeWarnCodexEnvVar(KeyManagerViewModel vm, AIKey key) async {
    try {
      final decrypted = await vm.getDecryptedKey(key.id!);
      if (decrypted == null) return;
      final svc = CodexConfigService();
      final pc = await svc.getProviderConfig(decrypted);
      if (pc.supportsAuthJson || pc.envKeyName == null) return;
      final cmd = await svc.generateEnvVarCommand(decrypted, permanent: true);
      if (cmd == null || !mounted) return;
      final l = AppLocalizations.of(context);
      showKcToast(
        context,
        l?.codexEnvVarRequired ?? 'Codex 还需要设置环境变量才能使用这把密钥',
        kind: KcToastKind.warning,
        actionLabel: l?.copyCommand ?? '复制命令',
        onAction: () => ClipboardService().copyToClipboard(cmd),
      );
    } catch (_) {
      // 只是附加提示，失败不影响切换结果
    }
  }

  /// 获取平台分组的显示名称
  String _getPlatformCategoryDisplayName(PlatformCategory category, BuildContext context) {
    return category.getValue(context); // 使用 PlatformCategory 自带的本地化方法
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    showKcToast(context, message, kind: isError ? KcToastKind.error : KcToastKind.success);
  }

  /// 检查边缘滚动
  void _checkEdgeScroll() {
    if (!_isDragging || _lastDragPosition == null) {
      _stopEdgeScrolling();
      return;
    }
    
    // 获取列表的 RenderBox
    final renderBox = _keyListKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      _stopEdgeScrolling();
      return;
    }
    
    // 获取列表在屏幕上的位置
    final listPosition = renderBox.localToGlobal(Offset.zero);
    final listSize = renderBox.size;
    
    // 计算鼠标相对于列表的位置
    final mouseY = _lastDragPosition!.dy;
    final relativeY = mouseY - listPosition.dy;
    
    // 边缘区域阈值（像素）
    const edgeThreshold = 80.0;
    const scrollSpeed = 8.0; // 滚动速度（像素/帧）
    
    // 检查是否在上边缘
    if (relativeY < edgeThreshold && relativeY >= 0) {
      // 向上滚动
      _startEdgeScrolling(-scrollSpeed);
    }
    // 检查是否在下边缘
    else if (relativeY > listSize.height - edgeThreshold && relativeY <= listSize.height) {
      // 向下滚动
      _startEdgeScrolling(scrollSpeed);
    } else {
      // 不在边缘区域，停止滚动
      _stopEdgeScrolling();
    }
  }

  /// 开始边缘滚动
  void _startEdgeScrolling(double speed) {
    // 如果已经在滚动且速度相同，不需要重新启动
    if (_edgeScrollTimer != null && _edgeScrollTimer!.isActive) {
      return;
    }
    
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!_keyListScrollController.hasClients) {
        timer.cancel();
        return;
      }
      
      final currentOffset = _keyListScrollController.offset;
      final maxScrollExtent = _keyListScrollController.position.maxScrollExtent;
      final minScrollExtent = _keyListScrollController.position.minScrollExtent;
      
      double newOffset = currentOffset + speed;
      
      // 限制滚动范围
      if (newOffset < minScrollExtent) {
        newOffset = minScrollExtent;
        timer.cancel();
      } else if (newOffset > maxScrollExtent) {
        newOffset = maxScrollExtent;
        timer.cancel();
      }
      
      // 如果已经到达边界，停止滚动
      if ((speed < 0 && currentOffset <= minScrollExtent) ||
          (speed > 0 && currentOffset >= maxScrollExtent)) {
        timer.cancel();
        return;
      }
      
      _keyListScrollController.jumpTo(newOffset);
    });
  }

  /// 停止边缘滚动
  void _stopEdgeScrolling() {
    _edgeScrollTimer?.cancel();
    _edgeScrollTimer = null;
  }
}

/// 钥匙包过滤分段
enum _KeySegment { all, inUse, unused, attention }
