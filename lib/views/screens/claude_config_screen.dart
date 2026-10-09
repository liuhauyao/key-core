import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/kc_tokens.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../widgets/key_card.dart';
import '../widgets/official_key_card.dart';
import '../widgets/key_details_dialog.dart';
import '../../models/ai_key.dart';
import '../../utils/app_localizations.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/claude_config_service.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_icon_service.dart';
import '../../models/platform_type.dart';
import 'key_form_page.dart';
import '../widgets/kc_tool_lens.dart';
import '../../models/mcp_server.dart' show AiToolType;
import '../widgets/kc_logo.dart';
import '../widgets/kc_toast.dart';

/// 环境变量项
class _EnvVarItem {
  final TextEditingController name;
  final TextEditingController value;
  
  _EnvVarItem({required this.name, required this.value});
}

/// Claude Code / Claude Desktop 切换
enum ClaudeSection { claudeCode, claudeDesktop }

/// ClaudeCode / Claude Desktop 配置管理页面
///
/// 侧栏把 Claude Code / Claude Desktop 拆成两行（ui_redesign_plan §2.2），两行都用这个页面，
/// 通过 [initialTab] 区分；[showSectionToggle] 为 false 时页头不再显示二选一的分段按钮。
class ClaudeConfigScreen extends StatefulWidget {
  const ClaudeConfigScreen({
    super.key,
    this.initialTab = ClaudeSection.claudeCode,
    this.showSectionToggle = true,
  });

  final ClaudeSection initialTab;
  final bool showSectionToggle;

  @override
  State<ClaudeConfigScreen> createState() => ClaudeConfigScreenState();
}

class ClaudeConfigScreenState extends State<ClaudeConfigScreen> {
  Timer? _selfLoadTimer;
  List<AIKey> _claudeCodeKeys = [];
  List<AIKey> _filteredKeys = []; // 过滤后的密钥列表
  AIKey? _currentKey;
  bool _isOfficial = false; // 当前是否是官方配置
  bool _isLoading = false; // 初始状态为 false，等待页面切换时加载
  bool _isRefreshing = false; // 防止重复刷新
  bool _configExists = true; // 配置文件是否存在
  String? _configDir; // 配置目录路径
  bool _hasLoadedOnce = false; // 标记是否已经加载过数据
  bool _claudeCodeKeysLoaded = false;
  bool _claudeDesktopKeysLoaded = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _desktopSearchController = TextEditingController();
  KeyManagerViewModel? _viewModel;

  late ClaudeSection _selectedSection = widget.initialTab;
  List<AIKey> _claudeDesktopKeys = [];
  List<AIKey> _filteredDesktopKeys = [];
  AIKey? _currentDesktopKey;
  bool _isDesktopOfficial = false;

  @override
  void initState() {
    super.initState();
    // PageView 不保活：页面滑出后 State 会被重建，而外部 refresh() 只在翻页回调里触发，
    // 重建后的 State 可能等不到首次加载（表现为「暂无密钥」直到手动点刷新）。
    // 停留超过一次翻页动画（300ms）仍挂载 → 视为真正可见，自行触发首次加载；路过的页面已销毁，不会加载。
    _selfLoadTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) refresh();
    });
    // 监听搜索框变化
    _searchController.addListener(_onSearchChanged);
    _desktopSearchController.addListener(_onDesktopSearchChanged);
    // 不在 initState 中加载，等待页面真正可见时再加载
    // 通过外部调用 refresh() 来触发加载
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 在 didChangeDependencies 中保存 ViewModel 引用（只初始化一次）
    if (_viewModel == null) {
      _viewModel = context.read<KeyManagerViewModel>();
      _viewModel?.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    _selfLoadTimer?.cancel();
    _searchController.dispose();
    _desktopSearchController.dispose();
    // 移除 ViewModel 监听（使用保存的引用，避免访问已停用的 context）
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel = null;
    super.dispose();
  }

  /// ViewModel 变化时的回调
  void _onViewModelChanged() {
    if (!mounted || _viewModel == null) return;
    
    // 防抖：避免频繁刷新
    if (_isRefreshing) return;
    
    // 当 ViewModel 通知变化时，检查当前密钥是否改变
    // 如果改变，刷新界面以显示最新的当前密钥
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _viewModel == null || _isRefreshing) return;
      
      final currentKey = await _viewModel!.getCurrentClaudeCodeKey();
      // 通过检查 currentKey 是否为 null 来判断是否是官方配置
      // 如果 currentKey 为 null，说明是官方配置
      final isOfficial = currentKey == null;
      
      // 检查当前密钥是否改变
      final keyChanged = _currentKey?.id != currentKey?.id;
      final officialChanged = _isOfficial != isOfficial;
      
      if (keyChanged || officialChanged) {
        // 当前密钥改变，刷新界面
        refresh(force: true);
      }
    });
  }

  void _onSearchChanged() {
    setState(() {
      _updateFilteredKeys();
    });
  }

  void _onDesktopSearchChanged() {
    setState(() {
      _updateFilteredDesktopKeys();
    });
  }

  void _updateFilteredKeys() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredKeys = _claudeCodeKeys;
    } else {
      _filteredKeys = _claudeCodeKeys.where((key) {
        return key.name.toLowerCase().contains(query) ||
            key.platform.toLowerCase().contains(query) ||
            (key.notes?.toLowerCase().contains(query) ?? false) ||
            key.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }
  }

  void _updateFilteredDesktopKeys() {
    final query = _desktopSearchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredDesktopKeys = _claudeDesktopKeys;
    } else {
      _filteredDesktopKeys = _claudeDesktopKeys.where((key) {
        return key.name.toLowerCase().contains(query) ||
            key.platform.toLowerCase().contains(query) ||
            (key.notes?.toLowerCase().contains(query) ?? false) ||
            key.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }
  }

  /// 公开的刷新方法，供外部调用
  /// [force] 是否强制刷新，即使已经加载过数据
  void refresh({bool force = false}) {
    if (mounted && !_isRefreshing && (force || !_hasLoadedOnce)) {
      _isRefreshing = true;
      _loadKeys();
      _loadDesktopKeys();
    }
  }

  Future<void> _loadKeys() async {
    if (!mounted) return;
    
    _hasLoadedOnce = true;
    final viewModel = context.read<KeyManagerViewModel>();
    
    if (!_isLoading) {
      setState(() { _isLoading = true; });
    }

    try {
      // 检测配置文件是否存在
      final configCheck = await viewModel.checkClaudeCodeConfigExists();
      final configExists = configCheck['anyExists'] as bool? ?? false;
      final configDir = configCheck['configDir'] as String?;
      
      // 加载密钥列表
      final keys = await viewModel.getClaudeCodeKeys();
      
      if (!configExists) {
        // 配置文件不存在，显示底部提示，不设置当前密钥
        if (mounted) {
        setState(() {
          _claudeCodeKeys = keys;
          _updateFilteredKeys();
          _configExists = false;
          _configDir = configDir;
          _currentKey = null;
          _isOfficial = false;
          _isLoading = false;
          _claudeCodeKeysLoaded = true;
        });
          
        }
        return; // 配置文件不存在，不继续读取当前密钥
      }
      
      // 配置文件存在，重新从配置文件读取当前激活的密钥
      final currentKey = await viewModel.getCurrentClaudeCodeKey();
      final isOfficial = currentKey == null; // 如果 currentKey 为 null，说明是官方配置

      if (mounted) {
        setState(() {
          _claudeCodeKeys = keys;
          _updateFilteredKeys();
          _currentKey = currentKey;
          _isOfficial = isOfficial;
          _configExists = true;
          _configDir = configDir;
          _isLoading = false;
          _claudeCodeKeysLoaded = true;
        });
      }
    } catch (e) {
      print('ClaudeConfigScreen: 加载密钥失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _claudeCodeKeysLoaded = true;
        });
      }
    }
  }

  /// 加载 Claude Desktop 密钥列表
  Future<void> _loadDesktopKeys() async {
    if (!mounted) return;
    final viewModel = context.read<KeyManagerViewModel>();

    try {
      // 检测配置文件是否存在
      final configCheck = await viewModel.checkClaudeDesktopConfigExists();

      // 加载密钥列表
      final keys = await viewModel.getClaudeDesktopKeys();

      // 读取当前使用的密钥
      final isOfficial = await viewModel.isOfficialClaudeDesktopConfig();
      AIKey? currentKey;
      if (!isOfficial) {
        currentKey = await viewModel.getCurrentClaudeDesktopKey();
      }

      if (mounted) {
        setState(() {
          _claudeDesktopKeys = keys;
          _updateFilteredDesktopKeys();
          _currentDesktopKey = currentKey;
          _isDesktopOfficial = isOfficial;
          _claudeDesktopKeysLoaded = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('ClaudeConfigScreen: 加载 Claude Desktop 密钥失败: $e');
      if (mounted) {
        setState(() {
          _claudeDesktopKeysLoaded = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _switchProvider(AIKey key) async {
    if (key.id == null) return;

    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    
    // 检查配置文件是否存在
    if (!_configExists) {
      if (mounted) {
        showKcToast(context, localizations?.claudeConfigNotFoundSwitchKey ?? '未找到 ClaudeCode 配置文件，无法切换密钥。请先安装 CLI 工具或检查配置文件路径。', kind: KcToastKind.warning);
      }
      return;
    }
    
    final success = await viewModel.switchClaudeCodeProvider(key.id!);
    
    if (success) {
      setState(() {
        _currentKey = key;
        _isOfficial = false;
      });
      
      if (mounted) {
        showSwitchResult(context, success: true, targetName: key.name);
      }
    } else {
      if (mounted) {
        showSwitchResult(context, success: false, targetName: key.name, error: viewModel.errorMessage, onRetry: () => _switchProvider(key));
      }
    }
  }

  Future<void> _switchToOfficial() async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    
    // 检查配置文件是否存在
    if (!_configExists) {
      if (mounted) {
        showKcToast(context, localizations?.claudeConfigNotFoundSwitchConfig ?? '未找到 ClaudeCode 配置文件，无法切换配置。请先安装 CLI 工具或检查配置文件路径。', kind: KcToastKind.warning);
      }
      return;
    }
    
    final success = await viewModel.switchToOfficialClaudeCode();
    
    if (success) {
      setState(() {
        _currentKey = null;
        _isOfficial = true;
      });
      
      if (mounted) {
        showSwitchResult(context, success: true, targetName: (localizations?.officialConfig ?? '官方配置'));
      }
    } else {
      if (mounted) {
        showSwitchResult(context, success: false, targetName: (localizations?.officialConfig ?? '官方配置'), error: viewModel.errorMessage, onRetry: _switchToOfficial);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);


    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, KcSpace.x3),
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
                  Expanded(
                    child: KcToolPageTitle(
                      tool: _selectedSection == ClaudeSection.claudeCode ? AiToolType.claudecode : AiToolType.claudeDesktop,
                      currentLabel: _lensCurrentLabel(localizations),
                      trailing: widget.showSectionToggle ? _buildSectionToggle(shadTheme) : null,
                    ),
                  ),
                  // 搜索框（两个模式都显示）
                  SizedBox(
                    width: 240,
                    height: 38,
                    child: ClipRect(
                      clipBehavior: Clip.hardEdge,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ShadInput(
                          controller: _selectedSection == ClaudeSection.claudeCode
                              ? _searchController
                              : _desktopSearchController,
                          placeholder: Text(localizations?.search ?? '搜索密钥...'),
                          leading: Icon(
                            Icons.search,
                            size: 18,
                            color: shadTheme.colorScheme.mutedForeground,
                          ),
                          trailing: (_selectedSection == ClaudeSection.claudeCode
                                  ? _searchController.text
                                  : _desktopSearchController.text)
                              .isNotEmpty
                              ? ShadButton(
                                  width: 20,
                                  height: 20,
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: shadTheme.colorScheme.mutedForeground,
                                  hoverBackgroundColor: Colors.transparent,
                                  onPressed: () {
                                    if (_selectedSection == ClaudeSection.claudeCode) {
                                      _searchController.clear();
                                      _updateFilteredKeys();
                                    } else {
                                      _desktopSearchController.clear();
                                      _updateFilteredDesktopKeys();
                                    }
                                  },
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: shadTheme.colorScheme.mutedForeground,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 刷新按钮组
                  Container(
                    height: 38,
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
                        Tooltip(
                          message: localizations?.refreshKeyList ?? '刷新列表',
                          child: ShadButton.ghost(
                            width: 38,
                            height: 38,
                            padding: EdgeInsets.zero,
                            onPressed: () => refresh(force: true),
                            child: Icon(
                              Icons.refresh,
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
            if (_selectedSection == ClaudeSection.claudeCode && _hasLoadedOnce && !_configExists)
              KcNoticeBar(message: localizations?.claudeConfigNotFoundLoad(_configDir ?? localizations.unknown) ?? '未找到 ClaudeCode 配置文件。当前路径：${_configDir ?? "未知"}'),
            // 内容区：根据选择显示 Claude Code 或 Claude Desktop
            Expanded(
              child: _selectedSection == ClaudeSection.claudeCode
                  ? (_filteredKeys.isEmpty && !_isOfficial && _searchController.text.isEmpty
                      ? _buildEmptyState(shadTheme, localizations)
                      : _buildKeyList(shadTheme, localizations))
                  : _buildDesktopContent(shadTheme, localizations),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ShadThemeData shadTheme, AppLocalizations? localizations) {
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
              Icons.code_outlined,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations?.noClaudeCodeKeys ?? '暂无 ClaudeCode 密钥',
            style: shadTheme.textTheme.h4.copyWith(
              color: shadTheme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations?.enableClaudeCodeHint ?? '请在密钥编辑页面启用 ClaudeCode 选项',
            style: shadTheme.textTheme.p.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  /// 页头「当前：X」（按当前分区）
  String? _lensCurrentLabel(AppLocalizations? l) {
    if (_selectedSection == ClaudeSection.claudeDesktop) {
      if (!_claudeDesktopKeysLoaded) return null;
      if (_isDesktopOfficial) return l?.officialConfig ?? '官方配置';
      return _currentDesktopKey?.name;
    }
    if (!_hasLoadedOnce || !_configExists) return null;
    if (_isOfficial) return l?.officialConfig ?? '官方配置';
    return _currentKey?.name;
  }

  /// 「未启用到 X 的密钥」紧凑区
  Widget _buildUnenabledSection(AiToolType tool) {
    final vm = context.read<KeyManagerViewModel>();
    final keys = vm.allKeys.where((k) => !enabledToolsOf(k).contains(tool)).toList();
    return KcUnenabledSection(
      tool: tool,
      keys: keys,
      onEnable: (k) async {
        final ok = await enableKeyForTool(context, k, tool, openEditor: (d) => _showEditKeyPage(context, d));
        if (ok && mounted) refresh(force: true);
      },
    );
  }

  Widget _buildKeyList(ShadThemeData shadTheme, AppLocalizations? localizations) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minCardWidth = 240;
        const double cardSpacing = 10;
        const double padding = KcSpace.page;
        const double cardHeight = 140; // 固定卡片高度，与 main_screen 一致
        
        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, 5);
        
        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }
        
        // 官方配置 + 密钥列表（使用过滤后的列表）
        // 官方配置始终显示，不受搜索筛选影响
        final totalItems = 1 + _filteredKeys.length; // 1 个官方配置卡片 + 过滤后的密钥列表
        
        return CustomScrollView(
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(padding),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: (cardWidth / cardHeight), // 固定高度，动态宽度
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
          ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
            // 第一个是官方配置卡片（始终显示）
            if (index == 0) {
              return _buildOfficialCard(shadTheme, localizations);
            }
            
            // 其余是密钥卡片
            final key = _filteredKeys[index - 1];
            final isCurrent = _currentKey?.id == key.id;
            
            // 使用组合 key，包含 isCurrent 状态，确保状态变化时能正确重建
            return KeyCard(
              key: ValueKey('claude_${key.id}_${isCurrent ? 'current' : 'inactive'}'),
              aiKey: key,
              isEditMode: false,
              isCurrent: isCurrent,
              cardMode: KeyCardMode.switchKey,
              lens: AiToolType.claudecode, // 工具切换页面使用切换模式
              onTap: () => _switchProvider(key),
              onView: () => _showKeyDetails(context, key),
              onEdit: () => _showEditKeyPage(context, key),
              onDelete: () {},
              onOpenManagementUrl: () {
                if (key.managementUrl != null) {
                  UrlLauncherService().openUrl(key.managementUrl!);
                }
              },
              onCopyApiEndpoint: () {
                if (key.claudeCodeBaseUrl != null) {
                  ClipboardService().copyToClipboard(key.claudeCodeBaseUrl!);
                  showKcToast(context, AppLocalizations.of(context)?.baseUrlCopied ?? 'Base URL 已复制', kind: KcToastKind.success);
                }
              },
              onCopyApiKey: () {
                final viewModel = context.read<KeyManagerViewModel>();
                if (key.id != null) {
                  viewModel.copyKeyToClipboard(key.id!);
                  showKcToast(context, localizations?.keyCopied ?? '密钥已复制', kind: KcToastKind.success);
                }
              },
            );
          },
                  childCount: totalItems,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildUnenabledSection(AiToolType.claudecode)),
          ],
        );
      },
    );
  }

  Widget _buildOfficialCard(ShadThemeData shadTheme, AppLocalizations? localizations) {
    // 官方后台管理地址
    const String officialManagementUrl = 'https://console.anthropic.com/';
    
    return OfficialKeyCard(
      key: ValueKey('official_${_isOfficial ? 'current' : 'inactive'}'),
      isCurrent: _isOfficial,
      icon: SvgPicture.asset(
        'assets/icons/platforms/claude-color.svg',
        width: 28,
        height: 28,
        allowDrawingOutsideViewBox: true,
      ),
      title: 'Claude Official',
      subtitle: localizations?.officialConfig ?? '官方配置',
      description: localizations?.useOfficialApi ?? '使用官方 API 地址',
      onTap: _switchToOfficial,
      actions: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(
                context,
                icon: Icons.visibility_outlined,
                tooltip: localizations?.details ?? '查看',
                onPressed: () {
                  _showOfficialConfigDetails(context);
                },
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                context,
                icon: Icons.language,
                tooltip: localizations?.openManagementUrl ?? '管理地址',
                onPressed: () {
                  UrlLauncherService().openUrl(officialManagementUrl);
                },
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                context,
                icon: Icons.copy_outlined,
                tooltip: localizations?.copyKey ?? '复制',
                onPressed: () {
                  _copyOfficialApiKey(context);
                },
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              context,
              icon: Icons.edit_outlined,
              tooltip: localizations?.editOfficialConfig ?? '编辑官方配置',
              onPressed: () {
                _showEditOfficialConfigDialog(context);
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 构建 Section 切换按钮组
  Widget _buildSectionToggle(ShadThemeData shadTheme) {
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleTab(
            label: 'Claude Code',
            isActive: _selectedSection == ClaudeSection.claudeCode,
            onTap: () => setState(() {
              _selectedSection = ClaudeSection.claudeCode;
              _desktopSearchController.clear();
            }),
            shadTheme: shadTheme,
          ),
          _buildToggleTab(
            label: 'Claude Desktop',
            isActive: _selectedSection == ClaudeSection.claudeDesktop,
            onTap: () => setState(() {
              _selectedSection = ClaudeSection.claudeDesktop;
              _searchController.clear();
            }),
            shadTheme: shadTheme,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTab({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required ShadThemeData shadTheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? shadTheme.colorScheme.background : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: shadTheme.textTheme.small.copyWith(
            color: isActive
                ? shadTheme.colorScheme.foreground
                : shadTheme.colorScheme.mutedForeground,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 构建 Claude Desktop 内容区
  Widget _buildDesktopContent(ShadThemeData shadTheme, AppLocalizations? localizations) {
    if (!_claudeDesktopKeysLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredDesktopKeys.isEmpty && _isDesktopOfficial && _desktopSearchController.text.isEmpty) {
      return _buildDesktopEmptyState(shadTheme, localizations);
    }

    // 官方配置 + 过滤后的密钥列表
    final totalItems = 1 + _filteredDesktopKeys.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const double minCardWidth = 240;
        const double cardSpacing = 10;
        const double padding = KcSpace.page;
        const double cardHeight = 140;

        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, 5);

        return CustomScrollView(
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(padding),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: ((availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount) / cardHeight,
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
          ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
            if (index == 0) {
              return _buildDesktopOfficialCard(shadTheme, localizations);
            }
            final key = _filteredDesktopKeys[index - 1];
            final isCurrent = _currentDesktopKey?.id == key.id;
            return KeyCard(
              key: ValueKey('claude_desktop_${key.id}_${isCurrent ? 'current' : 'inactive'}'),
              aiKey: key,
              isEditMode: false,
              isCurrent: isCurrent,
              cardMode: KeyCardMode.switchKey,
              lens: AiToolType.claudeDesktop,
              onTap: () => _switchDesktopProvider(key),
              onView: () => _showKeyDetails(context, key),
              onEdit: () => _showEditKeyPage(context, key),
              onDelete: () {},
              onOpenManagementUrl: () {
                if (key.managementUrl != null) {
                  UrlLauncherService().openUrl(key.managementUrl!);
                }
              },
              onCopyApiEndpoint: () {
                if (key.claudeDesktopBaseUrl != null) {
                  ClipboardService().copyToClipboard(key.claudeDesktopBaseUrl!);
                  showKcToast(context, AppLocalizations.of(context)?.baseUrlCopied ?? 'Base URL 已复制', kind: KcToastKind.success);
                }
              },
              onCopyApiKey: () {
                final viewModel = context.read<KeyManagerViewModel>();
                if (key.id != null) {
                  viewModel.copyKeyToClipboard(key.id!);
                  showKcToast(context, localizations?.keyCopied ?? '密钥已复制', kind: KcToastKind.success);
                }
              },
            );
          },
                  childCount: totalItems,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildUnenabledSection(AiToolType.claudeDesktop)),
          ],
        );
      },
    );
  }

  Widget _buildDesktopEmptyState(ShadThemeData shadTheme, AppLocalizations? localizations) {
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
              Icons.desktop_mac_outlined,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无 Claude Desktop 密钥',
            style: shadTheme.textTheme.h4.copyWith(
              color: shadTheme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请在密钥编辑页面启用 Claude Desktop 选项',
            style: shadTheme.textTheme.p.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建 Claude Desktop 官方配置卡片
  Widget _buildDesktopOfficialCard(ShadThemeData shadTheme, AppLocalizations? localizations) {
    return OfficialKeyCard(
      key: ValueKey('desktop_official_${_isDesktopOfficial ? 'current' : 'inactive'}'),
      isCurrent: _isDesktopOfficial,
      icon: SvgPicture.asset(
        'assets/icons/platforms/claude-color.svg',
        width: 28,
        height: 28,
        allowDrawingOutsideViewBox: true,
      ),
      title: 'Claude Desktop Official',
      subtitle: localizations?.officialConfig ?? '官方配置',
      description: '使用 Claude Desktop 官方登录',
      onTap: _switchToDesktopOfficial,
      actions: [
        Expanded(child: Container()),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildActionButton(
              context,
              icon: Icons.language,
              tooltip: localizations?.openManagementUrl ?? '管理地址',
              onPressed: () {
                UrlLauncherService().openUrl('https://console.anthropic.com/');
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 切换 Claude Desktop 密钥
  Future<void> _switchDesktopProvider(AIKey key) async {
    if (key.id == null) return;
    final viewModel = context.read<KeyManagerViewModel>();

    final success = await viewModel.switchClaudeDesktopProvider(key.id!);
    if (success) {
      setState(() {
        _currentDesktopKey = key;
        _isDesktopOfficial = false;
      });
      if (mounted) {
        showSwitchResult(context, success: true, targetName: key.name);
      }
    } else {
      if (mounted) {
        showSwitchResult(context, success: false, targetName: key.name, error: viewModel.errorMessage, onRetry: () => _switchDesktopProvider(key));
      }
    }
  }

  /// 切换回 Claude Desktop 官方配置
  Future<void> _switchToDesktopOfficial() async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);

    final success = await viewModel.switchToOfficialClaudeDesktop();
    if (success) {
      setState(() {
        _currentDesktopKey = null;
        _isDesktopOfficial = true;
      });
      if (mounted) {
        showSwitchResult(context, success: true, targetName: (localizations?.officialConfig ?? '官方配置'));
      }
    } else {
      if (mounted) {
        showSwitchResult(context, success: false, targetName: (localizations?.officialConfig ?? '官方配置'), error: viewModel.errorMessage, onRetry: _switchToDesktopOfficial);
      }
    }
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KcRadius.control),
            ),
            child: Icon(
              icon,
              size: 15,
              color: color ?? shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }

  /// 显示密钥详情
  void _showKeyDetails(BuildContext context, AIKey key) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    final decryptedKey = await viewModel.getDecryptedKey(key.id!);
    
    if (decryptedKey == null) {
      showKcToast(context, localizations?.cannotDecryptKey ?? '无法解密密钥', kind: KcToastKind.error);
      return;
    }

    showKeyDetailsSheet(
      context: context,
      builder: (context) => KeyDetailsDialog(
        aiKey: decryptedKey,
        viewModel: viewModel,
        onEdit: () {
          Navigator.pop(context);
          _showEditKeyPage(context, decryptedKey);
        },
        onCopyKey: () {
          viewModel.copyKeyToClipboard(decryptedKey.id!);
          final loc = AppLocalizations.of(context);
          showKcToast(context, loc?.keyCopiedToClipboard ?? '密钥已复制到剪贴板', kind: KcToastKind.success);
        },
        onOpenManagementUrl: () {
          if (decryptedKey.managementUrl != null) {
            UrlLauncherService().openUrl(decryptedKey.managementUrl!);
          }
        },
        onCopyText: (text) {
          ClipboardService().copyToClipboard(text);
        },
      ),
    );
  }

  /// 显示编辑密钥页面
  Future<void> _showEditKeyPage(BuildContext context, AIKey key) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);

    // ⚠️ 重要：使用解密后的密钥进行编辑（与 main_screen 保持一致）
    final decryptedKey = await viewModel.getDecryptedKey(key.id!);
    if (decryptedKey == null) {
      showKcToast(context, localizations?.cannotDecryptKey ?? '无法解密密钥', kind: KcToastKind.error);
      return;
    }

    final result = await Navigator.of(context).push<AIKey>(
      MaterialPageRoute(
        builder: (context) => KeyFormPage(editingKey: decryptedKey),
      ),
    );

    if (result != null) {
      final success = await viewModel.updateKey(result);
      if (success) {
        showKcToast(context, localizations?.keyUpdatedSuccess ?? '密钥更新成功', kind: KcToastKind.success);
        // 刷新列表
        refresh();
      } else {
        showKcToast(context, viewModel.errorMessage ?? (localizations?.updateFailed ?? '更新失败'), kind: KcToastKind.error);
      }
    }
  }

  /// 显示编辑官方配置对话框
  Future<void> _showEditOfficialConfigDialog(BuildContext context) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);
    
    // 读取配置：API Key从本地存储读取，env从settings.json读取
    final configService = ClaudeConfigService();
    final settingsService = SettingsService();
    await settingsService.init();
    
    // API Key：从本地存储读取
    final currentApiKey = settingsService.getOfficialClaudeApiKey() ?? '';
    
    // env配置：从settings.json读取（如果当前是官方配置）
    final settings = await configService.readSettings();
    final env = (settings?['env'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    
    // 创建控制器
    final apiKeyController = TextEditingController(text: currentApiKey);
    final obscureApiKeyNotifier = ValueNotifier<bool>(true); // API Key默认隐藏
    
    // 环境变量列表（从settings.json读取）
    // 使用列表存储，每个元素包含name和value的控制器
    final envVarItems = <_EnvVarItem>[];
    env.forEach((key, value) {
      // 排除标准字段和 ANTHROPIC_AUTH_TOKEN、ANTHROPIC_BASE_URL
      if (key != 'ANTHROPIC_MODEL' &&
          key != 'ANTHROPIC_DEFAULT_HAIKU_MODEL' &&
          key != 'ANTHROPIC_DEFAULT_SONNET_MODEL' &&
          key != 'ANTHROPIC_DEFAULT_OPUS_MODEL' &&
          key != 'ANTHROPIC_AUTH_TOKEN' &&
          key != 'ANTHROPIC_BASE_URL') {
        envVarItems.add(_EnvVarItem(
          name: TextEditingController(text: key),
          value: TextEditingController(text: value.toString()),
        ));
      }
    });
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 700,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: shadTheme.colorScheme.border,
                width: 1,
              ),
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
                      Icon(
                        Icons.settings_outlined,
                        size: 24,
                        color: shadTheme.colorScheme.foreground,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          localizations?.editOfficialConfig ?? '编辑官方配置',
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
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // API Key 配置（最重要的配置，放在最前面）
                        ValueListenableBuilder<bool>(
                          valueListenable: obscureApiKeyNotifier,
                          builder: (context, obscureApiKey, _) {
                            final iconColor = shadTheme.colorScheme.mutedForeground;
                            return ShadInputFormField(
                              id: 'anthropicAuthToken',
                              controller: apiKeyController,
                              label: Text(localizations?.keyValueLabel ?? 'API Key'),
                              placeholder: Text(localizations?.keyValuePlaceholder ?? '请输入 Anthropic API Key'),
                              leading: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(Icons.key, size: 18, color: iconColor),
                              ),
                              obscureText: obscureApiKey,
                              trailing: ShadButton(
                                width: 24,
                                height: 24,
                                padding: EdgeInsets.zero,
                                backgroundColor: Colors.transparent,
                                foregroundColor: iconColor,
                                hoverBackgroundColor: Colors.transparent,
                                child: Icon(
                                  obscureApiKey ? Icons.visibility_off : Icons.visibility,
                                  size: 18,
                                  color: iconColor,
                                ),
                                onPressed: () {
                                  obscureApiKeyNotifier.value = !obscureApiKeyNotifier.value;
                                },
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        // 环境变量标题行（带加号按钮）
                        Row(
                          children: [
                            Text(
                              localizations?.customEnvVar ?? '环境变量',
                              style: shadTheme.textTheme.small.copyWith(
                                color: shadTheme.colorScheme.foreground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            ShadButton.ghost(
                              width: 36,
                              height: 36,
                              padding: EdgeInsets.zero,
                              child: Icon(
                                Icons.add,
                                size: 18,
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  // 添加空白表单
                                  envVarItems.add(_EnvVarItem(
                                    name: TextEditingController(),
                                    value: TextEditingController(),
                                  ));
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // 环境变量列表
                        ...envVarItems.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: ShadInput(
                                    controller: item.name,
                                    placeholder: Text(localizations?.envVarName ?? '变量名'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: ShadInput(
                                    controller: item.value,
                                    placeholder: Text(localizations?.envVarValue ?? '变量值'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ShadButton.ghost(
                                  width: 36,
                                  height: 36,
                                  padding: EdgeInsets.zero,
                                  child: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    setDialogState(() {
                                      // 清理控制器
                                      item.name.dispose();
                                      item.value.dispose();
                                      // 从列表中移除（使用索引确保正确删除）
                                      if (index < envVarItems.length) {
                                        envVarItems.removeAt(index);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                // 底部按钮
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
                        height: 32,
                        onPressed: () => Navigator.pop(context),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.close,
                              size: 16,
                              color: shadTheme.colorScheme.foreground,
                            ),
                            const SizedBox(width: 6),
                            Text(localizations?.cancel ?? '取消'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      ShadButton(
                        height: 32,
                        onPressed: () async {
                          // 收集所有环境变量（包括空值，用于删除）
                          final envVars = <String, String>{};
                          
                          // API Key（最重要的配置）
                          final apiKey = apiKeyController.text.trim();
                          if (apiKey.isNotEmpty) {
                            envVars['ANTHROPIC_AUTH_TOKEN'] = apiKey;
                          } else {
                            // 如果API Key为空，也传递空字符串以删除
                            envVars['ANTHROPIC_AUTH_TOKEN'] = '';
                          }
                          
                          // 环境变量（按最新表单写入）
                          for (final item in envVarItems) {
                            final name = item.name.text.trim();
                            final value = item.value.text.trim();
                            // 只有当名称不为空时才保存
                            if (name.isNotEmpty) {
                              envVars[name] = value;
                            }
                          }
                          
                          // 更新配置
                          final success = await viewModel.updateOfficialClaudeCodeConfig(envVars);
                          
                          if (mounted) {
                            Navigator.pop(context);
                            if (success) {
                              showKcToast(context, localizations?.officialConfigUpdated ?? '官方配置已更新', kind: KcToastKind.success);
                              // 刷新列表
                              refresh(force: true);
                            } else {
                              showKcToast(context, localizations?.officialConfigUpdateFailed ?? '更新官方配置失败', kind: KcToastKind.error);
                            }
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check,
                              size: 16,
                              color: shadTheme.colorScheme.primaryForeground,
                            ),
                            const SizedBox(width: 6),
                            Text(localizations?.save ?? '保存'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // 清理控制器
    apiKeyController.dispose();
    obscureApiKeyNotifier.dispose();
    for (final item in envVarItems) {
      item.name.dispose();
      item.value.dispose();
    }
  }

  /// 显示官方配置详情
  Future<void> _showOfficialConfigDetails(BuildContext context) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);
    const String officialManagementUrl = 'https://console.anthropic.com/';
    
    // 读取配置：API Key从本地存储读取，env从settings.json读取
    final configService = ClaudeConfigService();
    final settingsService = SettingsService();
    await settingsService.init();
    
    // API Key：从本地存储读取
    final apiKey = settingsService.getOfficialClaudeApiKey();
    
    // env配置：从settings.json读取
    final settings = await configService.readSettings();
    final env = (settings?['env'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    
    bool showApiKey = false;
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
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
                      SvgPicture.asset(
                        'assets/icons/platforms/claude-color.svg',
                        width: 24,
                        height: 24,
                        allowDrawingOutsideViewBox: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Claude Official',
                              style: shadTheme.textTheme.h4.copyWith(
                                color: shadTheme.colorScheme.foreground,
                              ),
                            ),
                            Text(
                              localizations?.officialConfig ?? '官方配置',
                              style: shadTheme.textTheme.small.copyWith(
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        // API Key
                        _buildKeyValueRow(
                          context,
                          shadTheme,
                          localizations,
                          apiKey ?? '',
                          showApiKey,
                          (value) {
                            setDialogState(() {
                              showApiKey = value;
                            });
                          },
                          () {
                            if (apiKey != null) {
                              ClipboardService().copyToClipboard(apiKey);
                              showKcToast(context, localizations?.keyCopiedToClipboard ?? '密钥已复制到剪贴板', kind: KcToastKind.success);
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        // 管理地址
                        _buildActionRow(
                          context,
                          shadTheme,
                          localizations?.openManagementUrl ?? '管理地址',
                          officialManagementUrl,
                          Icons.language,
                          localizations?.open ?? '打开',
                          () {
                            UrlLauncherService().openUrl(officialManagementUrl);
                          },
                        ),
                        const SizedBox(height: 10),
                        // API地址
                        _buildActionRow(
                          context,
                          shadTheme,
                          'API 地址',
                          'https://api.anthropic.com',
                          Icons.code,
                          localizations?.copy ?? '复制',
                          () {
                            ClipboardService().copyToClipboard('https://api.anthropic.com');
                            showKcToast(context, AppLocalizations.of(context)?.apiUrlCopied ?? 'API 地址已复制', kind: KcToastKind.success);
                          },
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                        // 自定义环境变量（左右布局）
                        ...env.entries.where((entry) {
                          final key = entry.key;
                          return key != 'ANTHROPIC_MODEL' &&
                              key != 'ANTHROPIC_DEFAULT_HAIKU_MODEL' &&
                              key != 'ANTHROPIC_DEFAULT_SONNET_MODEL' &&
                              key != 'ANTHROPIC_DEFAULT_OPUS_MODEL' &&
                              key != 'ANTHROPIC_AUTH_TOKEN' &&
                              key != 'ANTHROPIC_BASE_URL';
                        }).map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildEnvVarRow(
                              shadTheme,
                              entry.key,
                              entry.value.toString(),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 复制官方配置的 API Key
  Future<void> _copyOfficialApiKey(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    
    // 获取官方API Key（优先从本地存储读取）
    final settingsService = SettingsService();
    await settingsService.init();
    String? apiKey = settingsService.getOfficialClaudeApiKey();
    // 如果本地存储没有，尝试从settings.json读取（用于兼容旧数据）
    if (apiKey == null || apiKey.isEmpty) {
      final configService = ClaudeConfigService();
      apiKey = await configService.getCurrentApiKey();
    }
    
    if (apiKey == null || apiKey.isEmpty) {
      showKcToast(context, localizations?.noApiKey ?? '未设置 API Key', kind: KcToastKind.warning);
      return;
    }
    
    await ClipboardService().copyWithAutoClear(
      apiKey,
      delaySeconds: 30,
    );
    
    showKcToast(context, localizations?.keyCopiedToClipboard ?? '密钥已复制到剪贴板', kind: KcToastKind.success);
  }

  Widget _buildKeyValueRow(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
    String keyValue,
    bool showKeyValue,
    ValueChanged<bool> onToggleShow,
    VoidCallback onCopy,
  ) {
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
                  keyValue.isEmpty
                      ? (localizations?.noApiKey ?? '未设置 API Key')
                      : (showKeyValue
                          ? keyValue
                          : '•' * (keyValue.length > 20 ? 20 : keyValue.length)),
                  style: shadTheme.textTheme.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            if (keyValue.isNotEmpty) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: showKeyValue ? (localizations?.hide ?? '隐藏') : (localizations?.show ?? '显示'),
                child: ShadButton.ghost(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    showKeyValue ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: shadTheme.colorScheme.mutedForeground,
                  ),
                  onPressed: () => onToggleShow(!showKeyValue),
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
                  onPressed: onCopy,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    ShadThemeData shadTheme,
    String label,
    String value,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isMonospace = false,
  }) {
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

  Widget _buildDetailRow(ShadThemeData shadTheme, String label, String value) {
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

  Widget _buildEnvVarRow(ShadThemeData shadTheme, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：变量名
        SizedBox(
          width: 200,
          child: Text(
            '$label:',
            style: shadTheme.textTheme.small.copyWith(
              fontWeight: FontWeight.w500,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 右侧：变量值
        Expanded(
          child: Text(
            value,
            style: shadTheme.textTheme.small.copyWith(
              color: shadTheme.colorScheme.foreground,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}
