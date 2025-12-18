import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../widgets/key_card.dart';
import '../widgets/official_key_card.dart';
import '../widgets/key_details_dialog.dart';
import '../../models/ai_key.dart';
import '../../utils/app_localizations.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/codex_config_service.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_icon_service.dart';
import '../../models/platform_type.dart';
import 'key_form_page.dart';

/// Codex 配置管理页面
class CodexConfigScreen extends StatefulWidget {
  const CodexConfigScreen({super.key});

  @override
  State<CodexConfigScreen> createState() => CodexConfigScreenState();
}

class CodexConfigScreenState extends State<CodexConfigScreen> {
  List<AIKey> _codexKeys = [];
  List<AIKey> _filteredKeys = []; // 过滤后的密钥列表
  AIKey? _currentKey;
  bool _isLoading = false; // 初始状态为 false，等待页面切换时加载
  bool _isOfficial = false;
  bool _previousLoadingState = false;
  bool _isRefreshing = false; // 防止重复刷新
  bool _configExists = true; // 配置文件是否存在
  String? _configDir; // 配置目录路径
  bool _hasLoadedOnce = false; // 标记是否已经加载过数据
  final TextEditingController _searchController = TextEditingController();
  KeyManagerViewModel? _viewModel; // 保存 ViewModel 引用，避免在 dispose 中访问 context

  @override
  void initState() {
    super.initState();
    // 监听搜索框变化
    _searchController.addListener(_onSearchChanged);
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
    _searchController.dispose();
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
      
      final currentKey = await _viewModel!.getCurrentCodexKey();
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

  /// 获取密钥的配置信息（检查是否需要环境变量）
  Future<bool> _getProviderConfigForKey(AIKey key) async {
    try {
      final codexConfigService = CodexConfigService();
      final providerConfig = await codexConfigService.getProviderConfig(key);
      return !providerConfig.supportsAuthJson && providerConfig.envKeyName != null;
    } catch (e) {
      return false;
    }
  }

  void _updateFilteredKeys() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      _filteredKeys = _codexKeys;
    } else {
      _filteredKeys = _codexKeys.where((key) {
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
    // 如果已经加载过数据且不是强制刷新，就不需要重新加载，避免切换页面时触发刷新
    if (mounted && !_isRefreshing && (force || !_hasLoadedOnce)) {
      _loadKeys();
    }
  }

  Future<void> _loadKeys() async {
    if (!mounted || _isRefreshing) return;
    
    _isRefreshing = true;
    final viewModel = context.read<KeyManagerViewModel>();
    // 只有在首次加载时才显示加载状态，避免切换页面时闪烁
    if (!_hasLoadedOnce) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      // 检测配置文件是否存在
      final configCheck = await viewModel.checkCodexConfigExists();
      final configExists = configCheck['anyExists'] as bool? ?? false;
      final configDir = configCheck['configDir'] as String?;
      
      // 加载密钥列表
      final keys = await viewModel.getCodexKeys();
      
      if (!configExists) {
        // 配置文件不存在，显示底部提示，不设置当前密钥
        if (mounted) {
        setState(() {
          _codexKeys = keys;
          _updateFilteredKeys(); // 更新过滤后的列表
          _configExists = false;
          _configDir = configDir;
          _currentKey = null; // 配置文件不存在，没有当前密钥
          _isOfficial = false; // 配置文件不存在，不是官方配置
          _isLoading = false;
          _isRefreshing = false;
          _hasLoadedOnce = true; // 标记已加载过
        });
          
          // 显示底部提示
          final localizations = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                localizations?.codexConfigNotFoundLoad(configDir ?? localizations?.unknown ?? '未知') ?? '未找到 Codex 配置文件，可能 CLI 工具未安装或配置文件路径不正确。当前路径：${configDir ?? "未知"}',
              ),
              duration: const Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return; // 配置文件不存在，不继续读取当前密钥
      }
      
      // 配置文件存在，重新从配置文件读取当前激活的密钥
      final currentKey = await viewModel.getCurrentCodexKey();
      
      // 如果 currentKey 为 null，说明当前是官方配置
      final isOfficial = currentKey == null;

      if (mounted) {
        setState(() {
          _codexKeys = keys;
          _updateFilteredKeys(); // 更新过滤后的列表
          _currentKey = currentKey;
          _isOfficial = isOfficial;
          _configExists = true;
          _configDir = configDir;
          _isLoading = false;
          _isRefreshing = false;
          _hasLoadedOnce = true; // 标记已加载过
        });
      }
    } catch (e) {
      print('CodexConfigScreen: 加载密钥失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
          _hasLoadedOnce = true; // 即使失败也标记为已加载，避免重复显示加载状态
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.codexConfigNotFoundSwitchKey ?? '未找到 Codex 配置文件，无法切换密钥。请先安装 CLI 工具或检查配置文件路径。',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    final success = await viewModel.switchCodexProvider(key.id!);
    
    if (success) {
      if (mounted) {
        setState(() {
          _currentKey = key;
          _isOfficial = false; // 切换到自定义密钥后，不再是官方配置
        });
        
        // 检查是否需要环境变量
        final codexConfigService = CodexConfigService();
        final providerConfig = await codexConfigService.getProviderConfig(key);
        final needsEnvVar = !providerConfig.supportsAuthJson && providerConfig.envKeyName != null;
        
        if (needsEnvVar) {
          // 生成环境变量命令（永久设置）
          final envCommand = await codexConfigService.generateEnvVarCommand(key, permanent: true);
          if (envCommand != null) {
            // 显示带复制按钮的 toast
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${localizations?.keySwitched ?? '已切换'} ${key.name}。需要设置环境变量',
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '（永久设置，添加到配置文件）',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ClipboardService().copyToClipboard(envCommand);
                        if (mounted) {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(localizations?.keyCopied ?? '已复制'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        '复制命令',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(seconds: 5),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${localizations?.keySwitched ?? '已切换'} ${key.name}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${localizations?.keySwitched ?? '已切换'} ${key.name}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.switchFailed ?? '切换失败'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _switchToOfficial() async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    
    // 检查配置文件是否存在
    if (!_configExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              localizations?.codexConfigNotFoundSwitchConfig ?? '未找到 Codex 配置文件，无法切换配置。请先安装 CLI 工具或检查配置文件路径。',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    final success = await viewModel.switchToOfficialCodex();
    
    if (success) {
      if (mounted) {
        setState(() {
          _currentKey = null;
          _isOfficial = true;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.switchedToOfficial ?? '已切换 官方配置'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.switchFailed ?? '切换失败'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    // 只在状态从 false 变为 true 时显示一次通知
    if (_isLoading && !_previousLoadingState) {
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
    } else if (!_isLoading) {
      _previousLoadingState = false;
    }

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  SvgPicture.asset(
                    'assets/icons/platforms/openai.svg',
                    width: 20,
                    height: 20,
                    allowDrawingOutsideViewBox: true,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    localizations?.codexConfig ?? 'Codex 配置',
                    style: shadTheme.textTheme.h4.copyWith(
                      color: shadTheme.colorScheme.foreground,
                    ),
                  ),
                  const Spacer(),
                  // 搜索框
                  SizedBox(
                    width: 300,
                    height: 38, // 固定高度，避免输入时高度变化
                    child: ClipRect(
                      clipBehavior: Clip.hardEdge,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ShadInput(
                          controller: _searchController,
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
                                    _updateFilteredKeys();
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
                  // 刷新按钮组（与密钥管理界面样式一致）
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
                        // 刷新按钮
                        Tooltip(
                          message: localizations?.refreshKeyList ?? '刷新列表',
                          child: ShadButton.ghost(
                            width: 38,
                            height: 38,
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              refresh(force: true);
                            },
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
            // 密钥列表
            Expanded(
              child: _filteredKeys.isEmpty && !_isOfficial && _searchController.text.isEmpty
                  ? _buildEmptyState(shadTheme, localizations)
                  : _buildKeyList(shadTheme, localizations),
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
              Icons.terminal_outlined,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations?.noCodexKeys ?? '暂无 Codex 密钥',
            style: shadTheme.textTheme.h4.copyWith(
              color: shadTheme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations?.enableCodexHint ?? '请在密钥编辑页面启用 Codex 选项',
            style: shadTheme.textTheme.p.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyList(ShadThemeData shadTheme, AppLocalizations? localizations) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minCardWidth = 240;
        const double cardSpacing = 10;
        const double padding = 16;
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
        
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: (cardWidth / cardHeight), // 固定高度，动态宽度
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
          ),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            // 第一个是官方配置卡片（始终显示）
            if (index == 0) {
              return _buildOfficialCard(shadTheme, localizations);
            }
            
            // 其余是密钥卡片
            final key = _filteredKeys[index - 1];
            final isCurrent = _currentKey?.id == key.id;
            
            // 使用 FutureBuilder 异步加载配置
            return FutureBuilder(
              future: _getProviderConfigForKey(key),
              builder: (context, snapshot) {
                final needsEnvVar = snapshot.data ?? false;
                final codexConfigService = CodexConfigService();
                
                return KeyCard(
                  key: ValueKey('codex_${key.id}_${isCurrent ? 'current' : 'inactive'}'),
                  aiKey: key,
                  isEditMode: false,
                  isCurrent: isCurrent,
                  cardMode: KeyCardMode.switchKey, // 工具切换页面使用切换模式
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
                    if (key.codexBaseUrl != null) {
                      ClipboardService().copyToClipboard(key.codexBaseUrl!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Base URL 已复制')),
                      );
                    }
                  },
                  onCopyApiKey: () {
                    final viewModel = context.read<KeyManagerViewModel>();
                    if (key.id != null) {
                      viewModel.copyKeyToClipboard(key.id!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(localizations?.keyCopied ?? '密钥已复制')),
                      );
                    }
                  },
                  // 只有需要环境变量的密钥才提供复制环境变量命令的回调
                  onCopyEnvVarCommand: needsEnvVar ? () async {
                    final envCommand = await codexConfigService.generateEnvVarCommand(key, permanent: true);
                    if (envCommand != null) {
                      await ClipboardService().copyToClipboard(envCommand);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(localizations?.keyCopied ?? '已复制'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  } : null,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildOfficialCard(ShadThemeData shadTheme, AppLocalizations? localizations) {
    // OpenAI 官方后台管理地址
    const String officialManagementUrl = 'https://platform.openai.com/';
    
    return OfficialKeyCard(
      key: ValueKey('official_${_isOfficial ? 'current' : 'inactive'}'),
      isCurrent: _isOfficial,
      icon: PlatformIconService.buildIcon(
        platform: PlatformType.openAI,
        size: 28,
      ),
      title: 'Codex Official',
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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.muted,
              borderRadius: BorderRadius.circular(6),
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

  /// 显示官方配置详情
  Future<void> _showOfficialConfigDetails(BuildContext context) async {
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);
    const String officialManagementUrl = 'https://platform.openai.com/api-keys';
    
    // 读取本地存储的官方 API Key
    final settingsService = SettingsService();
    await settingsService.init();
    final apiKey = settingsService.getOfficialCodexApiKey();
    
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
                      PlatformIconService.buildIcon(
                        platform: PlatformType.openAI,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Codex Official',
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
                        _buildKeyValueRowForDetails(
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(localizations?.keyCopiedToClipboard ?? '密钥已复制到剪贴板'),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        // 管理地址
                        _buildActionRowForDetails(
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
                        _buildActionRowForDetails(
                          shadTheme,
                          'API 地址',
                          'https://api.openai.com/v1',
                          Icons.code,
                          localizations?.copy ?? '复制',
                          () {
                            ClipboardService().copyToClipboard('https://api.openai.com/v1');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('API 地址已复制')),
                            );
                          },
                          isMonospace: true,
                        ),
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
    
    // 获取官方API Key（从本地存储读取）
    final settingsService = SettingsService();
    await settingsService.init();
    String? apiKey = settingsService.getOfficialCodexApiKey();
    
    // 如果本地存储没有，尝试从 auth.json 读取
    if (apiKey == null || apiKey.isEmpty) {
      final configService = CodexConfigService();
      apiKey = await configService.getCurrentApiKey();
    }
    
    if (apiKey == null || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations?.noApiKey ?? '未设置 API Key'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    await ClipboardService().copyWithAutoClear(
      apiKey,
      delaySeconds: 30,
    );
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizations?.keyCopiedToClipboard ?? '密钥已复制到剪贴板'),
      ),
    );
  }

  Widget _buildKeyValueRowForDetails(
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
                      ? (localizations?.noApiKey ?? '未设置')
                      : (showKeyValue ? keyValue : '•' * keyValue.length),
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
                onPressed: keyValue.isEmpty ? null : () => onToggleShow(!showKeyValue),
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
                onPressed: keyValue.isEmpty ? null : onCopy,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionRowForDetails(
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

  /// 显示编辑官方配置对话框
  Future<void> _showEditOfficialConfigDialog(BuildContext context) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);
    
    // 读取本地存储的官方 API Key
    final settingsService = SettingsService();
    await settingsService.init();
    final currentApiKey = settingsService.getOfficialCodexApiKey() ?? '';
    
    // 创建控制器
    final apiKeyController = TextEditingController(text: currentApiKey);
    final obscureApiKeyNotifier = ValueNotifier<bool>(true); // API Key默认隐藏
    
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 600,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
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
                      // 说明文本
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: shadTheme.colorScheme.muted.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: shadTheme.colorScheme.mutedForeground,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                localizations?.codexOfficialConfigDescription ?? '配置官方 OpenAI API Key，用于 Codex 官方配置。API Key 将安全存储在本地，切换到官方配置时自动写入。',
                                style: shadTheme.textTheme.small.copyWith(
                                  color: shadTheme.colorScheme.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // API Key 配置
                      ValueListenableBuilder<bool>(
                        valueListenable: obscureApiKeyNotifier,
                        builder: (context, obscureApiKey, _) {
                          final iconColor = shadTheme.colorScheme.mutedForeground;
                          return ShadInputFormField(
                            id: 'openaiApiKey',
                            controller: apiKeyController,
                            label: Text(localizations?.codexOfficialApiKeyLabel ?? 'OpenAI API Key'),
                            placeholder: Text(localizations?.codexOfficialApiKeyPlaceholder ?? '请输入 OpenAI API Key (sk-...)'),
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
                          Icon(Icons.close, size: 16),
                          const SizedBox(width: 6),
                          Text(localizations?.cancel ?? '取消'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ShadButton(
                      height: 32,
                      onPressed: () async {
                        // 保存配置
                        final apiKey = apiKeyController.text.trim();
                        final success = await viewModel.updateOfficialCodexConfig(
                          apiKey.isEmpty ? null : apiKey,
                        );
                        
                        if (mounted && Navigator.of(context).canPop()) {
                          Navigator.pop(context);
                        }
                        
                        if (success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(localizations?.keyUpdatedSuccess ?? '配置已保存'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          // 刷新列表
                          refresh(force: true);
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(localizations?.updateFailed ?? '保存失败'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 16),
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
    );
    
    // 清理控制器
    apiKeyController.dispose();
    obscureApiKeyNotifier.dispose();
  }

  /// 显示密钥详情
  void _showKeyDetails(BuildContext context, AIKey key) async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    final decryptedKey = await viewModel.getDecryptedKey(key.id!);
    
    if (decryptedKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations?.cannotDecryptKey ?? '无法解密密钥'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc?.keyCopiedToClipboard ?? '密钥已复制到剪贴板')),
          );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations?.cannotDecryptKey ?? '无法解密密钥'),
          backgroundColor: Colors.red,
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.keyUpdatedSuccess ?? '密钥更新成功'),
            backgroundColor: Colors.green,
          ),
        );
        // 刷新列表
        refresh();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(viewModel.errorMessage ?? (localizations?.updateFailed ?? '更新失败')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
