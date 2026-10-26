// 多密钥卡片「当前 / 选中子密钥」选择触发器（v3 设计语言）。
//
// 外观 = 普通 caption 文本 + 尾部 expand_more；文案 = 别名 · 主机名（未配置独立地址时显示「默认地址」）；
// hover 时文字转 actionText 并出现 subtle 圆角底（复用 card 的 hover 风格）。
// 点击弹出 KcMenu（与卡片 ⋯ 菜单同一点击弹出、同一项高亮规则、同一面板规格）；
// 菜单项两行：第一行别名，第二行地址（或「默认地址」），尾部为掩码后的密钥。
// 单密钥卡片不渲染（保证与今天像素一致）。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/ai_key.dart';
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../utils/key_mask.dart';
import 'kc_menu.dart';

class KcKeyEntryPicker extends StatefulWidget {
  const KcKeyEntryPicker({
    super.key,
    required this.aiKey,
    required this.activeIndex,
    required this.onSelected,
  });

  final AIKey aiKey;

  /// 触发器显示的下标（主界面 = 卡片当前密钥；工具页 = 本页选中项）
  final int activeIndex;

  /// 选中某项（主界面写当前密钥；工具页只改本页选中）
  final ValueChanged<int> onSelected;

  @override
  State<KcKeyEntryPicker> createState() => _KcKeyEntryPickerState();
}

class _KcKeyEntryPickerState extends State<KcKeyEntryPicker> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _hovering = false;

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final entries = widget.aiKey.keyEntries;
    final value = await showKcMenu<int>(
      context: context,
      anchor: rect,
      selected: widget.activeIndex,
      minWidth: 240,
      entries: [
        for (var i = 0; i < entries.length; i++)
          KcMenuItem<int>(
            value: i,
            label: entries[i].displayLabel(i),
            subtitle: _endpointText(context, entries[i]),
            leading: _ValidationDot(validated: entries[i].validated),
            trailing: maskKeyForKey(widget.aiKey, i),
            key: ValueKey('keyEntryPicker.item.$i'),
          ),
      ],
    );
    if (value != null && value != widget.activeIndex) widget.onSelected(value);
  }

  /// 子密钥地址说明：独立地址显示主机名（无协议），未配置回退「默认地址」
  String _endpointText(BuildContext context, KeyEntry entry) =>
      entry.endpointHost ?? (AppLocalizations.of(context)?.tr('key_endpoint_default_short', '默认地址') ?? '默认地址');

  @override
  Widget build(BuildContext context) {
    if (!widget.aiKey.hasMultipleKeys) return const SizedBox.shrink();
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final index = widget.activeIndex.clamp(0, widget.aiKey.keyEntries.length - 1);
    final entry = widget.aiKey.keyEntries[index];
    final label = entry.displayLabel(index);
    final endpoint = _endpointText(context, entry);
    final fg = _hovering ? kc.actionText : cs.mutedForeground;

    return Tooltip(
      message: '$label · $endpoint',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          key: _anchorKey,
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: Container(
            key: const ValueKey('keyEntryPicker.trigger'),
            // 与头部第二行 caption 文本同高，避免 36px 头部溢出
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: _hovering ? kc.subtle : null,
              borderRadius: BorderRadius.circular(KcRadius.control),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: label, style: KcType.caption.copyWith(color: fg, height: 1.25)),
                    TextSpan(text: ' · ', style: KcType.caption.copyWith(color: cs.mutedForeground.withValues(alpha: 0.5), height: 1.25)),
                    TextSpan(text: endpoint, style: KcType.caption.copyWith(color: fg.withValues(alpha: 0.72), height: 1.25)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more, size: 14, color: fg),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 子密钥校验状态点（ok / 未校验灰）
class _ValidationDot extends StatelessWidget {
  const _ValidationDot({required this.validated});

  final bool validated;

  @override
  Widget build(BuildContext context) {
    final kc = context.kc;
    final cs = ShadTheme.of(context).colorScheme;
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: validated ? kc.ok : cs.mutedForeground.withValues(alpha: 0.4),
      ),
    );
  }
}
