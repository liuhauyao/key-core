import 'package:flutter/material.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/provider.dart';
import '../../services/url_launcher_service.dart';
import '../../viewmodels/providers_viewmodel.dart';
import '../widgets/provider_widgets.dart';

/// 新建 / 编辑供应商页面
///
/// 交互参考 CC Switch：顶部选择预设（或自定义）后自动填充 API 地址、模型与适用工具，
/// 用户只需填写 API Key。API Key 交由 ProviderManagerService 使用主密码加密存储。
class ProviderFormPage extends StatefulWidget {
  final Provider? existing;
  final Provider? initialPreset;

  const ProviderFormPage({super.key, this.existing, this.initialPreset});

  @override
  State<ProviderFormPage> createState() => _ProviderFormPageState();
}

class _ProviderFormPageState extends State<ProviderFormPage> {
  final _nameController = TextEditingController();
  final _endpointController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _websiteController = TextEditingController();
  final _descriptionController = TextEditingController();

  Provider? _preset;
  final Set<String> _tools = {};
  bool _obscureKey = true;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _endpointController.text = existing.apiEndpoint ?? '';
      _modelController.text = existing.models.isNotEmpty ? existing.models.first.id : '';
      _websiteController.text = existing.websiteUrl ?? '';
      _descriptionController.text = existing.description ?? '';
      _tools.addAll(existing.supportedTools);
    } else if (widget.initialPreset != null) {
      _applyPreset(widget.initialPreset);
    } else {
      _tools.addAll(ToolMeta.all.map((t) => t.id));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _websiteController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _applyPreset(Provider? preset) {
    setState(() {
      _preset = preset;
      _error = null;
      _tools.clear();
      if (preset == null) {
        _nameController.clear();
        _endpointController.clear();
        _modelController.clear();
        _websiteController.clear();
        _descriptionController.clear();
        _tools.addAll(ToolMeta.all.map((t) => t.id));
        return;
      }
      _nameController.text = preset.name;
      _endpointController.text = preset.apiEndpoint ?? '';
      _modelController.text = preset.models.isNotEmpty ? preset.models.first.id : '';
      _websiteController.text = preset.websiteUrl ?? '';
      _descriptionController.text = preset.description ?? '';
      _tools.addAll(preset.supportedTools);
    });
  }

  List<ProviderModel> get _suggestedModels =>
      (widget.existing ?? _preset)?.models ?? const [];

  String? get _apiKeyUrl => (widget.existing ?? _preset)?.apiKeyUrl;

  Future<void> _save() async {
    final l = l10nOf(context);
    final name = _nameController.text.trim();
    final key = _apiKeyController.text.trim();
    String? error;
    if (name.isEmpty) {
      error = l.providersNameRequired;
    } else if (!_isEditing && key.isEmpty) {
      error = l.providersApiKeyRequired;
    } else if (!_tools.any((t) => ToolMeta.of(t) != null)) {
      error = l.providersToolsRequired;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final vm = context.read<ProvidersViewModel>();
    try {
      // 保持顺序：可切换工具在前，其余（如 codex/opencode）保留预设中的原值
      final ordered = [
        ...ToolMeta.all.map((t) => t.id).where(_tools.contains),
        ..._tools.where((t) => ToolMeta.of(t) == null),
      ];
      await vm.saveDraft(
        ProviderDraft(
          preset: _preset,
          name: name,
          endpoint: _endpointController.text,
          apiKey: key,
          defaultModel: _modelController.text,
          supportedTools: ordered,
          websiteUrl: _websiteController.text,
          description: _descriptionController.text,
        ),
        existing: widget.existing,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l.providersSaveFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final l = l10nOf(context);
    final vm = context.watch<ProvidersViewModel>();

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Text(_isEditing ? l.providersEdit : l.providersAdd),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ShadButton(
              key: const Key('provider_form_save'),
              onPressed: _saving ? null : _save,
              child: Text(l.save),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!_isEditing) ...[
                _sectionTitle(l.providersPreset, theme),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetChip(
                      key: const Key('preset_custom'),
                      label: l.providersCustom,
                      selected: _preset == null,
                      onTap: () => _applyPreset(null),
                      theme: theme,
                    ),
                    ...vm.presets.map((p) => _presetChip(
                          key: Key('preset_${p.id}'),
                          label: providerLocalizedAlias(context, p) ?? p.name,
                          selected: _preset?.id == p.id,
                          sponsored: p.isSponsored,
                          onTap: () => _applyPreset(p),
                          theme: theme,
                        )),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              _sectionTitle(l.details, theme),
              const SizedBox(height: 12),
              _field(
                l.providersName,
                ShadInput(
                  key: const Key('provider_name'),
                  controller: _nameController,
                  placeholder: const Text('My Provider'),
                ),
                theme,
              ),
              _field(
                l.providersEndpoint,
                ShadInput(
                  key: const Key('provider_endpoint'),
                  controller: _endpointController,
                  placeholder: const Text('https://api.example.com/v1'),
                ),
                theme,
              ),
              _field(
                l.providersApiKey,
                ShadInput(
                  key: const Key('provider_api_key'),
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  placeholder: Text(_isEditing
                      ? '${l.providersApiKeyKeep}  ${maskApiKey(widget.existing?.apiKey)}'
                      : 'sk-...'),
                  trailing: GestureDetector(
                    onTap: () => setState(() => _obscureKey = !_obscureKey),
                    child: Icon(
                      _obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 18,
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                theme,
                footer: Row(
                  children: [
                    Icon(
                      vm.encryptionEnabled ? Icons.lock_outline : Icons.warning_amber_rounded,
                      size: 14,
                      color: vm.encryptionEnabled ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        vm.encryptionEnabled
                            ? l.providersEncryptedNotice
                            : l.providersPlainNotice,
                        style: theme.textTheme.muted.copyWith(fontSize: 12),
                      ),
                    ),
                    if (_apiKeyUrl != null)
                      ShadButton.link(
                        size: ShadButtonSize.sm,
                        onPressed: () => UrlLauncherService().openUrl(_apiKeyUrl!),
                        child: Text(l.providersGetApiKey),
                      ),
                  ],
                ),
              ),
              _field(
                l.providersDefaultModel,
                ShadInput(
                  key: const Key('provider_model'),
                  controller: _modelController,
                  placeholder: const Text('model-id'),
                ),
                theme,
                footer: _suggestedModels.isEmpty
                    ? null
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _suggestedModels
                            .map((m) => ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  label: Text(m.id, style: const TextStyle(fontSize: 12)),
                                  onPressed: () =>
                                      setState(() => _modelController.text = m.id),
                                ))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 12),
              _sectionTitle(l.providersSupportedTools, theme),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ToolMeta.all.map((t) {
                  final selected = _tools.contains(t.id);
                  return FilterChip(
                    key: Key('tool_chip_${t.id}'),
                    avatar: ToolLogo(t.id, size: 16),
                    label: Text(t.displayName),
                    selected: selected,
                    showCheckmark: false,
                    selectedColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                    side: BorderSide(
                      color: selected ? theme.colorScheme.primary : theme.colorScheme.border,
                    ),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _tools.add(t.id);
                      } else {
                        _tools.remove(t.id);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              _sectionTitle(l.optional, theme),
              const SizedBox(height: 12),
              _field(
                l.providersWebsite,
                ShadInput(controller: _websiteController, placeholder: const Text('https://')),
                theme,
              ),
              _field(
                l.providersDescription,
                ShadInput(controller: _descriptionController, maxLines: 3),
                theme,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('provider_form_error'),
                    style: TextStyle(color: theme.colorScheme.destructive),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required ShadThemeData theme,
    bool sponsored = false,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primary : theme.colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.small.copyWith(
                color: selected
                    ? theme.colorScheme.primaryForeground
                    : theme.colorScheme.foreground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (sponsored) ...[
              const SizedBox(width: 4),
              Icon(Icons.star_rounded,
                  size: 14,
                  color: selected ? theme.colorScheme.primaryForeground : Colors.amber),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, ShadThemeData theme) {
    return Text(
      title,
      style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _field(String label, Widget child, ShadThemeData theme, {Widget? footer}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.small.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          child,
          if (footer != null) ...[
            const SizedBox(height: 6),
            footer,
          ],
        ],
      ),
    );
  }
}
