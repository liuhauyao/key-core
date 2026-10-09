// 密钥详情：右侧 560px 抽屉（ui_redesign_plan §5.3，mockup 03）。
// 类名与原有构造参数不变（各工具页仍可直接复用）；新增的回调都是可选的，不传时对应操作不显示。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/ai_key.dart';
import '../../models/mcp_server.dart' show AiToolType;
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import 'kc_logo.dart';
import 'key_card.dart' show enabledToolsOf, toolConfigPathHint, toolModelOf;

export 'key_card.dart' show toolModelOf;

/// 以右侧抽屉形式打开详情（遮罩 overlay，150ms 滑入；减少动态效果时无动画）
Future<T?> showKeyDetailsSheet<T>({required BuildContext context, required WidgetBuilder builder}) {
  final kc = context.kc;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: kc.overlay,
    transitionDuration: KcMotion.of(context, KcMotion.slide),
    pageBuilder: (ctx, _, __) => Align(
      alignment: Alignment.centerRight,
      child: builder(ctx),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: KcMotion.curve)),
      child: child,
    ),
  );
}

/// 开启某个工具前是否还需要先在编辑页补全配置（请求地址 / 模型）。Gemini 只用官方 API，无需配置
bool toolNeedsSetup(AIKey k, AiToolType t) {
  bool empty(String? v) => v == null || v.trim().isEmpty;
  switch (t) {
    case AiToolType.claudecode:
      return empty(k.claudeCodeBaseUrl);
    case AiToolType.claudeDesktop:
      return empty(k.claudeDesktopBaseUrl);
    case AiToolType.codex:
      return empty(k.codexBaseUrl) || empty(k.codexModel);
    case AiToolType.openclaw:
      return empty(k.openclawBaseUrl) || empty(k.openclawModel);
    default:
      return false;
  }
}

bool toolEnabledOf(AIKey k, AiToolType t) => enabledToolsOf(k).contains(t);

AIKey withToolEnabled(AIKey k, AiToolType t, bool v) {
  switch (t) {
    case AiToolType.claudecode:
      return k.copyWith(enableClaudeCode: v);
    case AiToolType.claudeDesktop:
      return k.copyWith(enableClaudeDesktop: v);
    case AiToolType.codex:
      return k.copyWith(enableCodex: v);
    case AiToolType.gemini:
      return k.copyWith(enableGemini: v);
    case AiToolType.openclaw:
      return k.copyWith(enableOpenclaw: v);
    default:
      return k;
  }
}

/// 「复制为环境变量」的文本：按已启用的工具给出对应变量；都没有时给通用变量
String buildEnvExport(AIKey k) {
  String q(String v) => "'${v.replaceAll("'", "'\\''")}'";
  final lines = <String>[];
  if (k.enableClaudeCode || k.enableClaudeDesktop) {
    final base = k.claudeCodeBaseUrl ?? k.claudeDesktopBaseUrl;
    if (base != null) lines.add('export ANTHROPIC_BASE_URL=${q(base)}');
    lines.add('export ANTHROPIC_AUTH_TOKEN=${q(k.keyValue)}');
  }
  if (k.enableCodex) {
    if (k.codexBaseUrl != null) lines.add('export OPENAI_BASE_URL=${q(k.codexBaseUrl!)}');
    lines.add('export OPENAI_API_KEY=${q(k.keyValue)}');
  }
  if (k.enableGemini) {
    lines.add('export GEMINI_API_KEY=${q(k.keyValue)}');
  }
  if (lines.isEmpty) {
    if (k.apiEndpoint != null) lines.add('export API_BASE_URL=${q(k.apiEndpoint!)}');
    lines.add('export API_KEY=${q(k.keyValue)}');
  }
  return lines.join('\n');
}

/// 密钥详情（抽屉内容）
class KeyDetailsDialog extends StatefulWidget {
  final AIKey aiKey;
  final KeyManagerViewModel viewModel;
  final VoidCallback onEdit;
  final VoidCallback onCopyKey;
  final VoidCallback onOpenManagementUrl;
  final Function(String) onCopyText; // 更灵活的复制文本回调

  /// 「设为当前」：把某个工具切到这把密钥（不传则不显示按钮）
  final ValueChanged<AiToolType>? onSwitchTool;

  /// 工具开关（enableXxx）。返回更新后的密钥；返回 null 表示没有保存（例如缺模型，已跳去编辑页）
  final Future<AIKey?> Function(AIKey key, AiToolType tool, bool enabled)? onToggleTool;

  /// 底栏「删除密钥」
  final VoidCallback? onDelete;

  /// 底栏「复制为环境变量」
  final ValueChanged<String>? onCopyEnv;

  const KeyDetailsDialog({
    super.key,
    required this.aiKey,
    required this.viewModel,
    required this.onEdit,
    required this.onCopyKey,
    required this.onOpenManagementUrl,
    required this.onCopyText,
    this.onSwitchTool,
    this.onToggleTool,
    this.onDelete,
    this.onCopyEnv,
  });

  @override
  State<KeyDetailsDialog> createState() => KeyDetailsDialogState();
}

class KeyDetailsDialogState extends State<KeyDetailsDialog> {
  bool _showKeyValue = false;
  late AIKey _key = widget.aiKey;
  final Set<AiToolType> _busy = {};

  @override
  void didUpdateWidget(covariant KeyDetailsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aiKey != widget.aiKey) _key = widget.aiKey;
  }

  String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _maskedFull(String v) {
    if (v.length <= 8) return '•' * v.length;
    final dash = v.indexOf('-');
    final prefix = (dash > 0 && dash <= 6) ? v.substring(0, dash + 1) : '';
    return '$prefix${'•' * 20}${v.substring(v.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;

    return Material(
      key: const ValueKey('keyDetails.sheet'),
      color: cs.card,
      elevation: 0,
      child: Container(
        width: width < 640 ? width : 560,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.border)),
          boxShadow: kc.shadowLg,
        ),
        child: SafeArea(
          left: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, l),
              Divider(height: 1, thickness: 1, color: cs.border),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x5, KcSpace.page, KcSpace.x6),
                  child: AnimatedBuilder(
                    animation: widget.viewModel,
                    builder: (context, _) => _body(context, l),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: cs.border),
              _footer(context, l),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations? l) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x4, KcSpace.x4, KcSpace.x4),
      child: Row(
        children: [
          KcPlatformLogo(platform: _key.platformType, customIconFileName: _key.icon, name: _key.name, size: 40, logoSize: 26),
          const SizedBox(width: KcSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(_key.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.title.copyWith(color: cs.foreground)),
                  ),
                  if (_key.isFavorite) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.star_rounded, size: 16, color: kc.warn),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    _key.platform,
                    l?.createdOn(_date(_key.createdAt)) ?? '创建于 ${_date(_key.createdAt)}',
                    l?.updatedOn(_date(_key.updatedAt)) ?? '更新于 ${_date(_key.updatedAt)}',
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KcType.caption.copyWith(color: cs.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: KcSpace.x2),
          ShadButton.outline(
            key: const ValueKey('keyDetails.edit'),
            height: KcSize.control,
            leading: const Icon(Icons.edit_outlined, size: 15),
            onPressed: widget.onEdit,
            child: Text(l?.edit ?? '编辑'),
          ),
          const SizedBox(width: KcSpace.x1),
          Tooltip(
            message: l?.close ?? '关闭',
            child: ShadButton.ghost(
              key: const ValueKey('keyDetails.close'),
              width: KcSize.control,
              height: KcSize.control,
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).maybePop(),
              child: Icon(Icons.close, size: 18, color: kc.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: KcSpace.x1_5),
        child: Text(text, style: KcType.caption.copyWith(color: context.kc.text2, fontWeight: FontWeight.w500)),
      );

  Widget _field(BuildContext context, {required Widget child, List<Widget> actions = const []}) {
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      height: KcSize.control + 2,
      padding: const EdgeInsets.only(left: KcSpace.x3, right: KcSpace.x1),
      decoration: BoxDecoration(
        color: cs.background,
        borderRadius: BorderRadius.circular(KcRadius.control),
        border: Border.all(color: cs.input),
      ),
      child: Row(children: [Expanded(child: child), ...actions]),
    );
  }

  Widget _iconAction(BuildContext context, {Key? key, required IconData icon, required String tip, VoidCallback? onTap}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(KcRadius.control),
        child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 15, color: context.kc.text2)),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations? l) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final mono = KcType.mono.copyWith(color: cs.foreground);
    final ids = widget.viewModel.currentKeyIds;
    final enabled = enabledToolsOf(_key);
    final activeCount = enabled.where((t) => _key.id != null && ids[t] == _key.id).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, l?.keyValue ?? 'API 密钥'),
        _field(
          context,
          child: Text(
            _showKeyValue ? _key.keyValue : _maskedFull(_key.keyValue),
            key: const ValueKey('keyDetails.keyValue'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono,
          ),
          actions: [
            _iconAction(
              context,
              key: const ValueKey('keyDetails.reveal'),
              icon: _showKeyValue ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              tip: _showKeyValue ? (l?.hide ?? '隐藏') : (l?.show ?? '显示'),
              onTap: () => setState(() => _showKeyValue = !_showKeyValue),
            ),
            _iconAction(context, icon: Icons.copy_outlined, tip: l?.copy ?? '复制', onTap: widget.onCopyKey),
          ],
        ),
        const SizedBox(height: KcSpace.x4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(context, l?.requestAddress ?? '请求地址'),
                _field(
                  context,
                  child: Text(_key.apiEndpoint ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono),
                  actions: [
                    if (_key.apiEndpoint != null)
                      _iconAction(context,
                          icon: Icons.copy_outlined, tip: l?.copy ?? '复制', onTap: () => widget.onCopyText(_key.apiEndpoint!)),
                  ],
                ),
              ]),
            ),
            const SizedBox(width: KcSpace.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(context, l?.managementUrl ?? '管理后台'),
                _field(
                  context,
                  child: Text(_key.managementUrl ?? '—',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: kc.actionText)),
                  actions: [
                    if (_key.managementUrl != null)
                      _iconAction(context, icon: Icons.open_in_new, tip: l?.open ?? '打开', onTap: widget.onOpenManagementUrl),
                  ],
                ),
              ]),
            ),
          ],
        ),
        if (_key.tags.isNotEmpty || _key.expiryDate != null) ...[
          const SizedBox(height: KcSpace.x3),
          Wrap(spacing: KcSpace.x1_5, runSpacing: KcSpace.x1_5, children: [
            if (_key.isExpired)
              _pill(context, l?.expired ?? '已过期', kc.dangerText, kc.dangerSoft)
            else if (_key.expiryDate != null)
              _pill(context, '${l?.expiryDate ?? '过期时间'} ${_date(_key.expiryDate!)}',
                  _key.isExpiringSoon ? kc.warnText : kc.text2, _key.isExpiringSoon ? kc.warnSoft : kc.subtle),
            for (final t in _key.tags) _pill(context, t, kc.text2, kc.subtle),
          ]),
        ],
        const SizedBox(height: KcSpace.x6),
        Row(children: [
          Text(l?.usedInTools ?? '用在哪些工具', style: KcType.section.copyWith(color: cs.foreground)),
          const SizedBox(width: KcSpace.x2),
          Text(l?.usedInToolsSummary(enabled.length, activeCount) ?? '${enabled.length} 个已启用 · $activeCount 个生效中',
              style: KcType.caption.copyWith(color: cs.mutedForeground)),
        ]),
        const SizedBox(height: KcSpace.x1),
        Text(l?.usedInToolsHint ?? '开关 = 出现在该工具的候选列表；「设为当前」才会写入该工具的配置文件',
            style: KcType.caption.copyWith(color: cs.mutedForeground)),
        const SizedBox(height: KcSpace.x2),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.border),
            borderRadius: BorderRadius.circular(KcRadius.panel),
          ),
          child: Column(children: [
            for (final (i, t) in kcKeyTools.indexed) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: cs.border),
              _toolRow(context, l, t, ids),
            ],
          ]),
        ),
        if (_key.notes != null && _key.notes!.trim().isNotEmpty) ...[
          const SizedBox(height: KcSpace.x6),
          Text(l?.notes ?? '备注', style: KcType.section.copyWith(color: cs.foreground)),
          const SizedBox(height: KcSpace.x1_5),
          Text(_key.notes!, style: KcType.body.copyWith(color: kc.text2)),
        ],
      ],
    );
  }

  Widget _pill(BuildContext context, String text, Color fg, Color bg) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: KcType.badge.copyWith(color: fg))]),
      );

  Widget _toolRow(BuildContext context, AppLocalizations? l, AiToolType t, Map<AiToolType, int?> ids) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final on = toolEnabledOf(_key, t);
    final active = on && _key.id != null && ids[t] == _key.id;
    final model = toolModelOf(_key, t);

    Widget status;
    if (!on) {
      status = Text(l?.notEnabled ?? '未启用', style: KcType.caption.copyWith(color: cs.mutedForeground));
    } else if (active) {
      status = _pill(context, '● ${l?.statusActive ?? '生效中'}', kc.okText, kc.okSoft);
    } else if (t == AiToolType.openclaw || widget.onSwitchTool == null) {
      status = Text(l?.enabledShort ?? '已启用', style: KcType.caption.copyWith(color: kc.text2));
    } else {
      status = ShadButton.outline(
        key: ValueKey('keyDetails.setCurrent.${t.value}'),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: kc.actionText,
        onPressed: () => widget.onSwitchTool!(t),
        child: Text(l?.setAsCurrent ?? '设为当前', style: KcType.caption.copyWith(fontWeight: FontWeight.w500)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KcSpace.x3, vertical: KcSpace.x2),
      child: Row(
        children: [
          SizedBox(
            height: 24,
            child: FittedBox(
              child: Switch(
                key: ValueKey('keyDetails.toggle.${t.value}'),
                value: on,
                activeTrackColor: cs.primary,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: cs.border,
                trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                onChanged: widget.onToggleTool == null || _busy.contains(t)
                    ? null
                    : (v) async {
                        setState(() => _busy.add(t));
                        final updated = await widget.onToggleTool!(_key, t, v);
                        if (!mounted) return;
                        setState(() {
                          _busy.remove(t);
                          if (updated != null) _key = updated;
                        });
                      },
              ),
            ),
          ),
          const SizedBox(width: KcSpace.x2),
          KcToolLogo(tool: t, size: 20),
          const SizedBox(width: KcSpace.x2),
          SizedBox(
            width: 116,
            child: Text(kcToolName(t),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.body.copyWith(color: cs.foreground)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(on ? (model ?? '—') : '—',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.mono.copyWith(color: cs.foreground)),
                Text(toolConfigPathHint(t),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KcType.mono.copyWith(fontSize: 11, color: cs.mutedForeground)),
              ],
            ),
          ),
          const SizedBox(width: KcSpace.x2),
          status,
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, AppLocalizations? l) {
    final kc = context.kc;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KcSpace.page, vertical: KcSpace.x3),
      child: Row(
        children: [
          if (widget.onDelete != null)
            ShadButton.ghost(
              key: const ValueKey('keyDetails.delete'),
              foregroundColor: kc.dangerText,
              leading: Icon(Icons.delete_outline, size: 16, color: kc.dangerText),
              onPressed: widget.onDelete,
              child: Text(l?.deleteKey ?? '删除密钥'),
            ),
          const Spacer(),
          if (widget.onCopyEnv != null)
            ShadButton.outline(
              key: const ValueKey('keyDetails.copyEnv'),
              leading: const Icon(Icons.terminal, size: 16),
              onPressed: () => widget.onCopyEnv!(buildEnvExport(_key)),
              child: Text(l?.copyAsEnv ?? '复制为环境变量'),
            ),
        ],
      ),
    );
  }
}
