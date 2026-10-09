import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/provider.dart';
import '../../services/tool_switcher_service.dart';
import '../../viewmodels/providers_viewmodel.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/provider_widgets.dart';
import 'provider_form_page.dart';

enum ProvidersTab { list, tools, backups }

/// 供应商中心：供应商列表 / 工具一键切换 / 配置备份
///
/// 交互参考 CC Switch：先维护供应商（预设 + API Key），再在每个工具下一键启用；
/// 每次写入前自动备份，可在「配置备份」中恢复。
class ProvidersScreen extends StatefulWidget {
  final ProvidersTab initialTab;

  const ProvidersScreen({super.key, this.initialTab = ProvidersTab.list});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  late ProvidersTab _tab = widget.initialTab;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final vm = context.read<ProvidersViewModel>();
      if (!vm.hasLoaded && !vm.isLoading) {
        vm.load().then((_) => vm.loadBackups());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _tabLabel(ProvidersTab tab) {
    final l = l10nOf(context);
    switch (tab) {
      case ProvidersTab.list:
        return l.providersTabList;
      case ProvidersTab.tools:
        return l.providersTabTools;
      case ProvidersTab.backups:
        return l.providersTabBackups;
    }
  }

  static const _tabIcons = {
    ProvidersTab.list: Icons.hub_outlined,
    ProvidersTab.tools: Icons.swap_horiz_rounded,
    ProvidersTab.backups: Icons.history_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final vm = context.watch<ProvidersViewModel>();

    Widget body;
    if (vm.isLoading && !vm.hasLoaded) {
      body = Center(child: CircularProgressIndicator(color: theme.colorScheme.primary));
    } else if (vm.error != null && !vm.hasLoaded) {
      body = Center(
        child: Text(vm.error!, style: TextStyle(color: theme.colorScheme.destructive)),
      );
    } else {
      switch (_tab) {
        case ProvidersTab.list:
          body = _ProviderListView(searchController: _searchController);
          break;
        case ProvidersTab.tools:
          body = const _ToolSwitchView();
          break;
        case ProvidersTab.backups:
          body = const _BackupsView();
          break;
      }
    }

    return Container(
      color: theme.colorScheme.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Row(
              children: [
                SegmentedPills<ProvidersTab>(
                  values: ProvidersTab.values,
                  selected: _tab,
                  keyOf: (t) => Key('providers_tab_${t.name}'),
                  labelOf: _tabLabel,
                  leadingOf: (t) => Icon(
                    _tabIcons[t],
                    size: 16,
                    color: t == _tab
                        ? theme.colorScheme.foreground
                        : theme.colorScheme.mutedForeground,
                  ),
                  onSelected: (t) {
                    setState(() => _tab = t);
                    if (t == ProvidersTab.backups) vm.loadBackups();
                    if (t == ProvidersTab.tools) vm.refreshLiveStates();
                  },
                ),
                const Spacer(),
                _EncryptionBadge(enabled: vm.encryptionEnabled),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _EncryptionBadge extends StatelessWidget {
  final bool enabled;

  const _EncryptionBadge({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final l = l10nOf(context);
    return Tooltip(
      message: enabled ? l.providersEncryptedNotice : l.providersPlainNotice,
      child: SmallTag(
        enabled ? l.masterPasswordEncrypted : l.masterPasswordNotSet,
        icon: enabled ? Icons.lock_outline : Icons.lock_open_outlined,
        color: enabled ? Colors.green : Colors.orange,
      ),
    );
  }
}

Future<void> _openForm(BuildContext context, {Provider? existing}) async {
  final vm = context.read<ProvidersViewModel>();
  final messenger = ScaffoldMessenger.of(context);
  final l = l10nOf(context);
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: ProviderFormPage(existing: existing),
      ),
    ),
  );
  if (saved == true) {
    messenger.showSnackBar(SnackBar(
      content: Text(l.providersSaved),
      duration: const Duration(seconds: 2),
    ));
  }
}

// =============================================================================
// 供应商列表
// =============================================================================

class _ProviderListView extends StatelessWidget {
  final TextEditingController searchController;

  const _ProviderListView({required this.searchController});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    final vm = context.watch<ProvidersViewModel>();
    final items = vm.filteredProviders;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: ShadInput(
                  key: const Key('providers_search'),
                  controller: searchController,
                  onChanged: vm.setSearchQuery,
                  placeholder: Text(l.providersSearch),
                  leading: Icon(Icons.search, size: 18, color: theme.colorScheme.mutedForeground),
                ),
              ),
              const SizedBox(width: 12),
              ShadButton(
                key: const Key('providers_add'),
                leading: const Icon(Icons.add, size: 16),
                onPressed: () => _openForm(context),
                child: Text(l.providersAdd),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(onAdd: () => _openForm(context))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _ProviderCard(provider: items[i]),
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hub_outlined, size: 56, color: theme.colorScheme.mutedForeground),
          const SizedBox(height: 12),
          Text(l.providersEmpty, style: theme.textTheme.large),
          const SizedBox(height: 6),
          Text(l.providersEmptyHint, style: theme.textTheme.muted),
          const SizedBox(height: 16),
          ShadButton.outline(
            leading: const Icon(Icons.add, size: 16),
            onPressed: onAdd,
            child: Text(l.providersAdd),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final Provider provider;

  const _ProviderCard({required this.provider});

  String _typeLabel(BuildContext context) {
    final l = l10nOf(context);
    switch (provider.providerType) {
      case 'official':
        return l.providersTypeOfficial;
      case 'relay':
        return l.providersTypeRelay;
      default:
        return l.providersTypeCustom;
    }
  }

  Future<void> _delete(BuildContext context) async {
    final l = l10nOf(context);
    final vm = context.read<ProvidersViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ConfirmDialog.show(
      context: context,
      title: l.confirmDelete,
      message: l.providersDeleteConfirm(provider.name),
      confirmText: l.delete,
    );
    if (ok != true) return;
    await vm.deleteProvider(provider);
    messenger.showSnackBar(SnackBar(
      content: Text(l.providersDeleted),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    final vm = context.read<ProvidersViewModel>();
    final usedBy = vm.toolsUsing(provider.id);
    final alias = providerLocalizedAlias(context, provider);
    final hasKey = provider.apiKey?.isNotEmpty ?? false;

    return Opacity(
      opacity: provider.isActive ? 1 : 0.6,
      child: PanelCard(
        key: Key('provider_card_${provider.id}'),
        highlighted: usedBy.isNotEmpty,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProviderAvatar(provider),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        provider.name,
                        style: theme.textTheme.large.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (alias != null) Text(alias, style: theme.textTheme.muted),
                      SmallTag(_typeLabel(context)),
                      if (provider.isSponsored)
                        const SmallTag('★', color: Colors.amber),
                      if (!provider.isActive)
                        SmallTag(l.providersDisabled, color: Colors.orange),
                      if (usedBy.isNotEmpty)
                        SmallTag(
                          l.providersInUseBy(usedBy.map(ToolMeta.nameOf).join(', ')),
                          color: theme.colorScheme.primary,
                          icon: Icons.check_circle,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (provider.apiEndpoint != null)
                    Text(
                      provider.apiEndpoint!,
                      style: theme.textTheme.muted.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasKey ? Icons.key_rounded : Icons.key_off_rounded,
                            size: 14,
                            color: hasKey ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasKey
                                ? '${l.providersKeySet} ${maskApiKey(provider.apiKey)}'
                                : l.providersKeyMissing,
                            style: theme.textTheme.small.copyWith(fontSize: 12),
                          ),
                        ],
                      ),
                      if (provider.models.isNotEmpty)
                        Text(
                          '${provider.models.first.id} · '
                          '${l.providersModelsCount(provider.models.length.toString())}',
                          style: theme.textTheme.muted.copyWith(fontSize: 12),
                        ),
                      ...provider.supportedTools
                          .where((t) => ToolMeta.of(t) != null)
                          .map((t) => Tooltip(
                                message: ToolMeta.nameOf(t),
                                child: ToolLogo(t, size: 14),
                              )),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: provider.isActive ? l.providersDisable : l.providersEnable,
                  child: ShadSwitch(
                    key: Key('provider_active_${provider.id}'),
                    value: provider.isActive,
                    onChanged: (v) => vm.setActive(provider, v),
                  ),
                ),
                const SizedBox(width: 4),
                ShadButton.ghost(
                  key: Key('provider_edit_${provider.id}'),
                  size: ShadButtonSize.sm,
                  onPressed: () => _openForm(context, existing: provider),
                  child: const Icon(Icons.edit_outlined, size: 18),
                ),
                ShadButton.ghost(
                  key: Key('provider_delete_${provider.id}'),
                  size: ShadButtonSize.sm,
                  onPressed: () => _delete(context),
                  child: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.destructive),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 工具一键切换
// =============================================================================

class _ToolSwitchView extends StatelessWidget {
  const _ToolSwitchView();

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 900;
        final cardWidth = twoColumns
            ? (constraints.maxWidth - 48 - 16) / 2
            : constraints.maxWidth - 48;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(l.toolsHint, style: theme.textTheme.muted),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: ProvidersViewModel.tools
                  .map((t) => SizedBox(width: cardWidth, child: _ToolCard(tool: t)))
                  .toList(),
            ),
          ],
        );
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  final String tool;

  const _ToolCard({required this.tool});

  Future<void> _switch(BuildContext context, Provider provider) async {
    final l = l10nOf(context);
    final vm = context.read<ProvidersViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final toolName = ToolMeta.nameOf(tool);
    try {
      await vm.switchTool(tool, provider);
      messenger.showSnackBar(SnackBar(
        content: Text(l.toolsSwitchSuccess(toolName, provider.name)),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.toolsSwitchFailed(e.toString())),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    final vm = context.watch<ProvidersViewModel>();
    final current = vm.currentProvider(tool);
    final live = vm.liveState(tool);
    final candidates = vm.providersForTool(tool);
    final busy = vm.isSwitching(tool);

    return PanelCard(
      key: Key('tool_card_$tool'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ToolLogo(tool, size: 24),
              const SizedBox(width: 10),
              Text(
                ToolMeta.nameOf(tool),
                style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _infoRow(
            context,
            l.toolsCurrentProvider,
            current?.name ?? l.toolsNotSet,
            valueKey: Key('tool_current_$tool'),
            emphasize: current != null,
          ),
          if (live != null) ...[
            _infoRow(context, l.toolsConfigFile, live.configPath, mono: true),
            if (!live.configExists)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(l.toolsConfigMissing,
                    style: theme.textTheme.muted.copyWith(fontSize: 12)),
              ),
            if (live.model != null) _infoRow(context, l.toolsLiveModel, live.model!, mono: true),
            if (live.baseUrl != null)
              _infoRow(context, l.toolsLiveEndpoint, live.baseUrl!, mono: true),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: theme.colorScheme.border),
          const SizedBox(height: 10),
          if (candidates.isEmpty)
            Text(l.toolsNoProviders, style: theme.textTheme.muted)
          else
            ...candidates.map((p) {
              final isCurrent = current?.id == p.id;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    ProviderAvatar(p, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name,
                              style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600)),
                          if (p.models.isNotEmpty)
                            Text(p.models.first.id,
                                style: theme.textTheme.muted.copyWith(fontSize: 12)),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      SmallTag(l.toolsInUse,
                          color: theme.colorScheme.primary, icon: Icons.check_circle)
                    else
                      ShadButton.outline(
                        key: Key('switch_${tool}_${p.id}'),
                        size: ShadButtonSize.sm,
                        enabled: !busy && (p.apiKey?.isNotEmpty ?? false),
                        onPressed: () => _switch(context, p),
                        child: Text(l.toolsSwitch),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value, {
    Key? valueKey,
    bool mono = false,
    bool emphasize = false,
  }) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.muted.copyWith(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value,
              key: valueKey,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.small.copyWith(
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
                color: emphasize ? theme.colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 配置备份
// =============================================================================

class _BackupsView extends StatelessWidget {
  const _BackupsView();

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _restore(BuildContext context, ConfigBackup backup, String timeText) async {
    final l = l10nOf(context);
    final vm = context.read<ProvidersViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ConfirmDialog.show(
      context: context,
      title: l.backupsRestoreTitle,
      message: l.backupsRestoreConfirm(ToolMeta.nameOf(vm.backupTool), timeText),
      confirmText: l.backupsRestore,
    );
    if (ok != true) return;
    try {
      await vm.restoreBackup(backup);
      messenger.showSnackBar(SnackBar(
        content: Text(l.backupsRestored),
        duration: const Duration(seconds: 2),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(l.backupsRestoreFailed(e.toString())),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    final vm = context.watch<ProvidersViewModel>();
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final live = vm.liveState(vm.backupTool);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Row(
          children: [
            SegmentedPills<String>(
              values: ProvidersViewModel.tools,
              selected: vm.backupTool,
              keyOf: (t) => Key('backup_tool_$t'),
              labelOf: ToolMeta.nameOf,
              leadingOf: (t) => ToolLogo(t, size: 14),
              onSelected: vm.selectBackupTool,
            ),
            const Spacer(),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              leading: const Icon(Icons.refresh, size: 16),
              onPressed: vm.loadBackups,
              child: Text(l.providersRefresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l.backupsDesc, style: theme.textTheme.muted),
        if (live != null) ...[
          const SizedBox(height: 4),
          Text(live.configPath,
              style: theme.textTheme.muted.copyWith(fontSize: 12, fontFamily: 'monospace')),
        ],
        const SizedBox(height: 16),
        if (vm.isLoadingBackups)
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ))
        else if (vm.backups.isEmpty)
          PanelCard(
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: theme.colorScheme.mutedForeground),
                const SizedBox(width: 12),
                Text(l.backupsEmpty, style: theme.textTheme.muted),
              ],
            ),
          )
        else
          ...vm.backups.asMap().entries.map((entry) {
            final b = entry.value;
            final timeText = b.createdAt != null ? fmt.format(b.createdAt!) : b.fileName;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PanelCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, color: theme.colorScheme.mutedForeground),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(timeText,
                              style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            '${b.fileName} · ${_formatSize(b.sizeBytes)}',
                            style: theme.textTheme.muted.copyWith(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    ShadButton.outline(
                      key: Key('restore_backup_${entry.key}'),
                      size: ShadButtonSize.sm,
                      leading: const Icon(Icons.restore, size: 16),
                      onPressed: () => _restore(context, b, timeText),
                      child: Text(l.backupsRestore),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
