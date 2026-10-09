// 分段控件（§4.1：选中用白底块，不用蓝）。高 32，用于钥匙包过滤「全部 / 正在使用 / 未用到工具 / 需处理」。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';

class KcSegmented<T> extends StatelessWidget {
  const KcSegmented({super.key, required this.value, required this.items, required this.onChanged});

  final T value;

  /// (值, 文案, 计数；计数为 null 时不显示)
  final List<(T, String, int?)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    return Container(
      height: KcSize.control,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(KcRadius.control + 2)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label, count) in items)
            Semantics(
              button: true,
              selected: v == value,
              child: GestureDetector(
                key: ValueKey('segment.$v'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: AnimatedContainer(
                    duration: KcMotion.of(context),
                    curve: KcMotion.curve,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: v == value ? cs.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(KcRadius.control),
                      boxShadow: v == value ? kc.shadowSm : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: KcType.body.copyWith(
                            color: v == value ? cs.foreground : kc.text2,
                            fontWeight: v == value ? FontWeight.w500 : FontWeight.w400,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 5),
                          Text('$count', style: KcType.badge.copyWith(color: cs.mutedForeground, fontFeatures: KcType.tabular)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
