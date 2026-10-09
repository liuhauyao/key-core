import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/ai_key.dart';
import '../../services/openclaw_config_service.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../widgets/key_card.dart';
import '../widgets/key_details_dialog.dart';
import 'key_form_page.dart';
import '../widgets/kc_toast.dart';
import '../../theme/kc_tokens.dart';
import '../widgets/kc_tool_lens.dart';
import '../../models/mcp_server.dart';
import '../../utils/app_localizations.dart';

/// 某个钥匙包密钥与 OpenClaw 供应商的关联信息
class _CompatibleKey {
  final AIKey aiKey;
  final String platformId;
  final OpenClawPlatformInfo? providerInfo; // 平台不在 mapping 时为 null
  bool isEnabled;

  _CompatibleKey({
    required this.aiKey,
    required this.platformId,
    this.providerInfo,
    this.isEnabled = false,
  });
}

/// OpenClaw 密钥配置页面
/// 自动检测钥匙包中 OpenClaw 支持的供应商密钥，通过卡片开关直接写入 OpenClaw 配置
class OpenClawConfigScreen extends StatefulWidget {
  const OpenClawConfigScreen({super.key});

  @override
  State<OpenClawConfigScreen> createState() => OpenClawConfigScreenState();
}

class OpenClawConfigScreenState extends State<OpenClawConfigScreen> {
  final OpenClawConfigService _service = OpenClawConfigService();

  bool _isLoading = false;
  bool _hasLoadedOnce = false;
  bool _isRefreshing = false;
  bool _dirExists = false;
  String _configDir = '';

  List<_CompatibleKey> _compatibleKeys = [];

  KeyManagerViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      _viewModel = context.read<KeyManagerViewModel>();
      _viewModel?.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    _viewModel = null;
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted || _isRefreshing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _hasLoadedOnce && !_isRefreshing) {
        _loadCompatibleKeys();
      }
    });
  }

  void refresh({bool force = false}) {
    if (mounted && !_isRefreshing && (force || !_hasLoadedOnce)) {
      _loadConfig();
    }
  }

  Future<void> _loadConfig() async {
    if (!mounted || _isRefreshing) return;
    _isRefreshing = true;
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final check = await _service.checkConfigExists();
      final dirExists = check['dirExists'] as bool? ?? false;
      final configDir = check['configDir'] as String? ?? '';
      if (mounted) {
        setState(() {
          _dirExists = dirExists;
          _configDir = configDir;
        });
      }
      if (dirExists) {
        await _loadCompatibleKeys();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _hasLoadedOnce = true;
      });
    }
  }

  Future<void> _loadCompatibleKeys() async {
    final vm = _viewModel;
    if (vm == null || !mounted) return;

    final allKeys = vm.allKeys;
    final appliedKeyIds = await _service.getAppliedKeyIds();

    final compatible = <_CompatibleKey>[];
    for (final key in allKeys) {
      if (!key.isActive) continue;
      if (!key.enableOpenclaw) continue; // 只显示在编辑表单中开启了 OpenClaw 的密钥
      final platformId = key.platformType.id;
      final info = OpenClawConfigService.platformInfoFor(platformId);
      final isEnabled = info != null
          ? appliedKeyIds[info.envKey] == key.id
          : false;
      compatible.add(_CompatibleKey(
        aiKey: key,
        platformId: platformId,
        providerInfo: info,
        isEnabled: isEnabled,
      ));
    }

    // 已启用的排前面，其次按平台排序
    compatible.sort((a, b) {
      if (a.isEnabled != b.isEnabled) return a.isEnabled ? -1 : 1;
      final aKey = a.providerInfo?.envKey ?? a.platformId;
      final bKey = b.providerInfo?.envKey ?? b.platformId;
      return aKey.compareTo(bKey);
    });

    if (mounted) {
      setState(() => _compatibleKeys = compatible);
    }
  }

  Future<void> _toggleKey(_CompatibleKey item) async {
    final vm = _viewModel;
    if (vm == null) return;
    final l = AppLocalizations.of(context);

    if (item.isEnabled) {
      // 已启用 → 关闭
      try {
        await _service.removeProviderKey(platformId: item.platformId);
      } catch (e) {
        _showWriteError(e);
        return;
      }
      item.isEnabled = false;
      if (mounted) {
        setState(() {});
        showKcToast(context, l?.openclawRemoved(item.aiKey.name) ?? '已从 OpenClaw 配置中移除 ${item.aiKey.name}');
      }
      return;
    }

    // 未启用 → 写入
    // 平台不在 OpenClaw 映射里时 applyProviderKey 什么都不写，过去这里仍提示「已写入」并把开关拨到开，
    // 属于假成功。现在如实告知，开关保持关闭。
    if (item.providerInfo == null) {
      showKcToast(
        context,
        l?.openclawPlatformUnsupported(item.aiKey.platform) ??
            'OpenClaw 暂不支持 ${item.aiKey.platform}，没有写入任何配置。',
        kind: KcToastKind.warning,
      );
      if (mounted) setState(() {});
      return;
    }

    final decrypted = await vm.decryptKeyValue(item.aiKey.keyValue);
    if (decrypted == null || decrypted.isEmpty) {
      if (mounted) {
        showKcToast(context, l?.keyDecryptFailed ?? '密钥解密失败', kind: KcToastKind.error);
      }
      return;
    }

    final OpenClawApplyResult result;
    try {
      result = await _service.applyProviderKey(
        keyId: item.aiKey.id!,
        decryptedKey: decrypted,
        platformId: item.platformId,
        openclawBaseUrl: item.aiKey.openclawBaseUrl,
        openclawModel: item.aiKey.openclawModel,
      );
    } catch (e) {
      // 例如 openclaw.json 无法解析：已中止写入，原文件未被修改；其他开关保持原状
      _showWriteError(e);
      return;
    }

    // 写入成功后，同一 envKey 下的其他密钥才视为被替换（过去在写入前就先关掉，失败时状态会错）
    final itemEnvKey = item.providerInfo?.envKey;
    if (itemEnvKey != null) {
      for (final other in _compatibleKeys) {
        if (other != item && other.providerInfo?.envKey == itemEnvKey && other.isEnabled) {
          other.isEnabled = false;
        }
      }
    }
    item.isEnabled = true;

    if (mounted) {
      setState(() {});
      final modelRef = result.modelRef;
      final message = modelRef != null
          ? (l?.openclawWrittenWithModel(item.aiKey.name, modelRef) ??
              '已将 ${item.aiKey.name} 写入 OpenClaw，并设置默认模型为 $modelRef')
          : (l?.openclawWritten(item.aiKey.name) ?? '已将 ${item.aiKey.name} 写入 OpenClaw 配置');
      showKcToast(context, message);
    }
  }

  void _showWriteError(Object error) {
    if (!mounted) return;
    final reason = humanizeError(error);
    showKcToast(
      context,
      AppLocalizations.of(context)?.openclawWriteFailed(reason) ?? '写入 OpenClaw 配置失败：$reason',
      kind: KcToastKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(shadTheme),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : !_dirExists
                      ? _buildNotInstalled(shadTheme)
                      : _compatibleKeys.isEmpty
                          ? ListView(
                              primary: false,
                              children: [
                                SizedBox(height: 320, child: _buildEmptyState(shadTheme)),
                                _buildUnenabledSection(),
                              ],
                            )
                          : _buildKeyGrid(shadTheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ShadThemeData shadTheme) {
    final l = AppLocalizations.of(context);
    final written = _compatibleKeys.where((k) => k.isEnabled).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, KcSpace.x3),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.background,
        border: Border(bottom: BorderSide(color: shadTheme.colorScheme.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: KcToolPageTitle(
              tool: AiToolType.openclaw,
              subtitle: _hasLoadedOnce && _dirExists
                  ? (l?.openclawEnabledSummary(written, toolConfigPathHint(AiToolType.openclaw)) ??
                      '$written 个已写入  ·  写入 ${toolConfigPathHint(AiToolType.openclaw)}')
                  : null,
            ),
          ),
          Tooltip(
            message: l?.refreshKeyList ?? '刷新列表',
            child: ShadButton.outline(
              width: 32,
              height: 32,
              padding: EdgeInsets.zero,
              onPressed: () => refresh(force: true),
              child: Icon(Icons.refresh, size: 16, color: context.kc.text2),
            ),
          ),
        ],
      ),
    );
  }

  /// 「未启用到 OpenClaw 的密钥」紧凑区
  Widget _buildUnenabledSection() {
    final vm = context.read<KeyManagerViewModel>();
    final keys = vm.allKeys.where((k) => k.isActive && !k.enableOpenclaw).toList();
    return KcUnenabledSection(
      tool: AiToolType.openclaw,
      keys: keys,
      onEnable: (k) async {
        final ok = await enableKeyForTool(context, k, AiToolType.openclaw, openEditor: (d) => _showEditKeyPage(context, d));
        if (ok && mounted) refresh(force: true);
      },
    );
  }

  Widget _buildNotInstalled(ShadThemeData shadTheme) {
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
            child: SvgPicture.asset(
              'assets/icons/platforms/openclaw-color.svg',
              width: 64,
              height: 64,
              allowDrawingOutsideViewBox: true,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)?.openclawNotDetected ?? '未检测到 OpenClaw',
            style: shadTheme.textTheme.h4.copyWith(color: shadTheme.colorScheme.foreground),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.openclawInstallHint ?? '请先安装 OpenClaw 并运行初始化（openclaw onboard）',
            style: shadTheme.textTheme.p.copyWith(color: shadTheme.colorScheme.mutedForeground),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)?.configDirLabel(_configDir) ?? '配置目录：$_configDir',
            style: shadTheme.textTheme.small.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShadButton.outline(
                onPressed: () => UrlLauncherService().openUrl('https://openclaw.ai'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language, size: 16),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context)?.officialWebsite ?? '官网'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ShadButton(
                onPressed: () => refresh(force: true),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh, size: 16),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context)?.detectAgain ?? '重新检测'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ShadThemeData shadTheme) {
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
              Icons.key_off_outlined,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)?.openclawNoKeys ?? '还没有启用到 OpenClaw 的密钥',
            style: shadTheme.textTheme.h4.copyWith(color: shadTheme.colorScheme.foreground),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)?.openclawNoKeysHint ?? '在下方「未启用到 OpenClaw 的密钥」里点「启用」，或在编辑密钥时打开 OpenClaw',
            style: shadTheme.textTheme.p.copyWith(color: shadTheme.colorScheme.mutedForeground),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildKeyGrid(ShadThemeData shadTheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minCardWidth = 240;
        const double cardSpacing = 10;
        const double padding = KcSpace.page;
        const double cardHeight = 140;

        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, 5);

        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }

        return CustomScrollView(
          primary: false,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(padding),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: cardWidth / cardHeight,
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
          ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
            final item = _compatibleKeys[index];
            return KeyCard(
              key: ValueKey('openclaw_${item.aiKey.id}_${item.isEnabled ? 'on' : 'off'}'),
              aiKey: item.aiKey,
              isEditMode: false,
              isCurrent: item.isEnabled,
              cardMode: KeyCardMode.switchKey,
              lens: AiToolType.openclaw,
              onTap: () => _toggleKey(item),
              onToggle: (_) => _toggleKey(item),
              onView: () => _showKeyDetails(context, item.aiKey),
              onEdit: () => _showEditKeyPage(context, item.aiKey),
              onDelete: () {},
              onOpenManagementUrl: () {
                if (item.aiKey.managementUrl != null) {
                  UrlLauncherService().openUrl(item.aiKey.managementUrl!);
                }
              },
              onCopyApiEndpoint: () {
                if (item.aiKey.apiEndpoint != null) {
                  ClipboardService().copyToClipboard(item.aiKey.apiEndpoint!);
                  showKcToast(context, AppLocalizations.of(context)?.apiUrlCopied ?? 'API Endpoint 已复制', kind: KcToastKind.success);
                }
              },
              onCopyApiKey: () {
                final vm = context.read<KeyManagerViewModel>();
                if (item.aiKey.id != null) {
                  vm.copyKeyToClipboard(item.aiKey.id!);
                  showKcToast(context, AppLocalizations.of(context)?.keyCopied ?? '密钥已复制', kind: KcToastKind.success);
                }
              },
              onCopyEnvVarCommand: null,
            );
          },
                  childCount: _compatibleKeys.length,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _buildUnenabledSection()),
          ],
        );
      },
    );
  }

  void _showKeyDetails(BuildContext context, AIKey key) async {
    final vm = context.read<KeyManagerViewModel>();
    final decryptedKey = await vm.getDecryptedKey(key.id!);
    if (decryptedKey == null) {
      if (mounted) {
        showKcToast(context, AppLocalizations.of(context)?.cannotDecryptKey ?? '无法解密密钥', kind: KcToastKind.error);
      }
      return;
    }
    if (!mounted) return;
    showKeyDetailsSheet(
      context: context,
      builder: (context) => KeyDetailsDialog(
        aiKey: decryptedKey,
        viewModel: vm,
        onEdit: () {
          Navigator.pop(context);
          _showEditKeyPage(context, decryptedKey);
        },
        onCopyKey: () {
          vm.copyKeyToClipboard(decryptedKey.id!);
          showKcToast(context, AppLocalizations.of(context)?.keyCopiedToClipboard ?? '密钥已复制到剪贴板', kind: KcToastKind.success);
        },
        onOpenManagementUrl: () {
          if (decryptedKey.managementUrl != null) {
            UrlLauncherService().openUrl(decryptedKey.managementUrl!);
          }
        },
        onCopyText: (text) => ClipboardService().copyToClipboard(text),
      ),
    );
  }

  Future<void> _showEditKeyPage(BuildContext context, AIKey key) async {
    final vm = context.read<KeyManagerViewModel>();
    final decryptedKey = await vm.getDecryptedKey(key.id!);
    if (decryptedKey == null) {
      if (mounted) {
        showKcToast(context, AppLocalizations.of(context)?.cannotDecryptKey ?? '无法解密密钥', kind: KcToastKind.error);
      }
      return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<AIKey>(
      MaterialPageRoute(builder: (context) => KeyFormPage(editingKey: decryptedKey)),
    );
    if (result != null) {
      final success = await vm.updateKey(result);
      if (mounted) {
        showKcToast(
            context,
            success
                ? (AppLocalizations.of(context)?.keyUpdatedSuccess ?? '密钥更新成功')
                : (vm.errorMessage ?? (AppLocalizations.of(context)?.updateFailed ?? '更新失败')),
            kind: success ? KcToastKind.success : KcToastKind.error);
        if (success) refresh();
      }
    }
  }
}
