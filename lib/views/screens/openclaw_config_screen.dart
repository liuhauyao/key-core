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
      final info = OpenClawConfigService.platformMapping[platformId];
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

    if (item.isEnabled) {
      // 已启用 → 关闭
      await _service.removeProviderKey(platformId: item.platformId);
      item.isEnabled = false;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已从 OpenClaw 配置中移除 ${item.aiKey.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // 未启用 → 写入
      final decrypted = await vm.decryptKeyValue(item.aiKey.keyValue);
      if (decrypted == null || decrypted.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('密钥解密失败'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // 同一 envKey 下先关闭其他密钥
      final itemEnvKey = item.providerInfo?.envKey;
      if (itemEnvKey != null) {
        for (final other in _compatibleKeys) {
          if (other != item &&
              other.providerInfo?.envKey == itemEnvKey &&
              other.isEnabled) {
            other.isEnabled = false;
          }
        }
      }

      await _service.applyProviderKey(
        keyId: item.aiKey.id!,
        decryptedKey: decrypted,
        platformId: item.platformId,
        openclawBaseUrl: item.aiKey.openclawBaseUrl,
        openclawModel: item.aiKey.openclawModel,
      );
      item.isEnabled = true;

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已将 ${item.aiKey.name} 写入 OpenClaw 配置'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
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
                          ? _buildEmptyState(shadTheme)
                          : _buildKeyGrid(shadTheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ShadThemeData shadTheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.background,
        border: Border(
          bottom: BorderSide(color: shadTheme.colorScheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/platforms/openclaw-color.svg',
            width: 20,
            height: 20,
            allowDrawingOutsideViewBox: true,
          ),
          const SizedBox(width: 12),
          Text(
            'OpenClaw',
            style: shadTheme.textTheme.h4.copyWith(
              color: shadTheme.colorScheme.foreground,
            ),
          ),
          const Spacer(),
          Container(
            height: 38,
            decoration: BoxDecoration(
              border: Border.all(color: shadTheme.colorScheme.border, width: 1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Tooltip(
              message: '刷新列表',
              child: ShadButton.ghost(
                width: 38,
                height: 38,
                padding: EdgeInsets.zero,
                onPressed: () => refresh(force: true),
                child: Icon(Icons.refresh, size: 18, color: shadTheme.colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
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
            '未检测到 OpenClaw',
            style: shadTheme.textTheme.h4.copyWith(color: shadTheme.colorScheme.foreground),
          ),
          const SizedBox(height: 8),
          Text(
            '请先安装 OpenClaw 并运行初始化（openclaw onboard）',
            style: shadTheme.textTheme.p.copyWith(color: shadTheme.colorScheme.mutedForeground),
          ),
          const SizedBox(height: 4),
          Text(
            '配置目录：$_configDir',
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 16),
                    SizedBox(width: 6),
                    Text('官网'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ShadButton(
                onPressed: () => refresh(force: true),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 16),
                    SizedBox(width: 6),
                    Text('重新检测'),
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
            '暂未配置密钥',
            style: shadTheme.textTheme.h4.copyWith(color: shadTheme.colorScheme.foreground),
          ),
          const SizedBox(height: 8),
          Text(
            '请先在密钥管理中添加密钥，并在编辑密钥时开启 OpenClaw',
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
        const double padding = 16;
        const double cardHeight = 140;

        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, 5);

        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: cardWidth / cardHeight,
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
          ),
          itemCount: _compatibleKeys.length,
          itemBuilder: (context, index) {
            final item = _compatibleKeys[index];
            return KeyCard(
              key: ValueKey('openclaw_${item.aiKey.id}_${item.isEnabled ? 'on' : 'off'}'),
              aiKey: item.aiKey,
              isEditMode: false,
              isCurrent: item.isEnabled,
              cardMode: KeyCardMode.switchKey,
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API Endpoint 已复制')),
                  );
                }
              },
              onCopyApiKey: () {
                final vm = context.read<KeyManagerViewModel>();
                if (item.aiKey.id != null) {
                  vm.copyKeyToClipboard(item.aiKey.id!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('密钥已复制')),
                  );
                }
              },
              onCopyEnvVarCommand: null,
            );
          },
        );
      },
    );
  }

  void _showKeyDetails(BuildContext context, AIKey key) async {
    final vm = context.read<KeyManagerViewModel>();
    final decryptedKey = await vm.getDecryptedKey(key.id!);
    if (decryptedKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法解密密钥'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (!mounted) return;
    showDialog(
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('密钥已复制到剪贴板')),
          );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法解密密钥'), backgroundColor: Colors.red),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '密钥更新成功' : (vm.errorMessage ?? '更新失败')),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        if (success) refresh();
      }
    }
  }
}
