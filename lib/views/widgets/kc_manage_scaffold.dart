// 管理 / 排序模式：零布局位移（form_v3.md §13）。
//
// 原则：同一套布局，只换内容不换几何。
// - 标题不变；副标题在原位置交叉淡入（不改变尺寸）；
// - 主按钮槽位定宽（普通「+ 添加」/ 管理「✓ 完成」）；
// - 不要横幅；批量操作在底部悬浮栏（Overlay，不参与布局）；
// - 卡片复选框绝对定位在右上角，不占流式布局。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';

/// 底部悬浮栏的高度 + 边距；网格底部需要预留这么多 padding，避免最后一行被遮住。
const double kcFloatingBarReserve = 72;

/// 页头副标题：普通 / 管理两种文案在同一槽位交叉淡入。
class KcManageSubtitle extends StatelessWidget {
  const KcManageSubtitle({super.key, required this.manage, required this.normal, required this.manageText});

  final bool manage;
  final String normal;
  final String manageText;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final text = manage ? manageText : normal;
    return AnimatedSwitcher(
      duration: KcMotion.of(context),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
      child: Text(
        text,
        key: ValueKey(manage),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: KcType.caption.copyWith(color: manage ? kc.actionText : cs.mutedForeground, fontFeatures: KcType.tabular),
      ),
    );
  }
}

/// 定宽主按钮槽：两种模式下宽度一致，左侧控件不会横向移动。
class KcPrimarySlot extends StatelessWidget {
  const KcPrimarySlot({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: width, height: KcSize.control, child: child);
}

/// 批量操作按钮。
class KcBatchAction {
  const KcBatchAction({required this.icon, required this.label, required this.onPressed, this.danger = false, this.key});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final Key? key;
}

/// 底部悬浮批量操作栏（form_v3.md §13.2）：高 44，圆角 12，深色，水平居中，距底 16。
/// 未选中时只保留「完成 Esc」。
class KcFloatingSelectionBar extends StatelessWidget {
  const KcFloatingSelectionBar({
    super.key,
    required this.selectedCount,
    required this.actions,
    required this.onDone,
    this.onSelectAll,
    this.allSelected = false,
  });

  final int selectedCount;
  final List<KcBatchAction> actions;
  final VoidCallback onDone;
  final VoidCallback? onSelectAll;
  final bool allSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xF23A3A3E) : const Color(0xEB1E1E20);
    const fg = Color(0xFFF2F2F4);
    final sep = Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.16), margin: const EdgeInsets.symmetric(horizontal: 6));

    Widget btn(KcBatchAction a) => TextButton.icon(
          key: a.key,
          onPressed: a.onPressed,
          style: TextButton.styleFrom(
            foregroundColor: a.danger ? const Color(0xFFFF6961) : fg,
            disabledForegroundColor: fg.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            textStyle: KcType.caption.copyWith(fontWeight: FontWeight.w500),
          ),
          icon: Icon(a.icon, size: 15),
          label: Text(a.label),
        );

    return Material(
      key: const ValueKey('kcFloatingSelectionBar'),
      color: Colors.transparent,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 30, offset: Offset(0, 10))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedCount > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  l10n?.tr('n_selected', '{n} 个已选').replaceAll('{n}', '$selectedCount') ?? '$selectedCount 个已选',
                  key: const ValueKey('kcFloatingSelectionBar.count'),
                  style: KcType.caption.copyWith(color: fg, fontWeight: FontWeight.w600, fontFeatures: KcType.tabular),
                ),
              ),
              sep,
              ...actions.map(btn),
              sep,
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(l10n?.tr('manage_select_hint', '勾选卡片进行批量操作') ?? '勾选卡片进行批量操作',
                    style: KcType.caption.copyWith(color: fg.withValues(alpha: 0.7))),
              ),
            if (onSelectAll != null)
              btn(KcBatchAction(
                key: const ValueKey('kcFloatingSelectionBar.selectAll'),
                icon: allSelected ? Icons.deselect : Icons.select_all,
                label: allSelected ? (l10n?.tr('deselect_all', '取消全选') ?? '取消全选') : (l10n?.tr('select_all', '全选') ?? '全选'),
                onPressed: onSelectAll,
              )),
            const SizedBox(width: 4),
            ShadButton(
              key: const ValueKey('kcFloatingSelectionBar.done'),
              height: 30,
              onPressed: onDone,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(l10n?.done ?? '完成'),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(4)),
                  child: const Text('Esc', style: TextStyle(fontSize: 10, color: Colors.white)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片右上角的选择框（绝对定位，不占布局）。
class KcSelectCheck extends StatelessWidget {
  const KcSelectCheck({super.key, required this.selected, required this.onChanged});

  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!selected),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.background,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: selected ? cs.primary : cs.border, width: 1.5),
          ),
          child: selected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
        ),
      ),
    );
  }
}

/// 把卡片包一层：管理模式下右上角放选择框，选中时叠加描边；几何与普通模式完全一致。
class KcSelectableCard extends StatelessWidget {
  const KcSelectableCard({super.key, required this.manage, required this.selected, required this.onSelect, required this.child, this.checkKey});

  final bool manage;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final Widget child;
  final Key? checkKey;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 光晕在卡片下方，描边在卡片上方；两者都不改变尺寸
        if (manage && selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(KcRadius.panel),
                  boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.22), spreadRadius: 3)],
                ),
              ),
            ),
          ),
        Positioned.fill(child: child),
        if (manage && selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(KcRadius.panel),
                  border: Border.all(color: cs.primary, width: 1.5),
                ),
              ),
            ),
          ),
        if (manage)
          Positioned(top: 10, right: 10, child: KcSelectCheck(key: checkKey, selected: selected, onChanged: onSelect)),
      ],
    );
  }
}
