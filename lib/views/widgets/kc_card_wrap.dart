import 'package:flutter/material.dart';

/// 卡片网格（Wrap 版）：始终撑满可用宽度并从左上角排列。
///
/// 旧实现把 Wrap 直接放进滚动视图 / Column：Wrap 收缩到内容宽度后被父级居中，
/// 只有一张卡片时它跑到中间（v4 第 2 项）。
class KcCardWrap extends StatelessWidget {
  const KcCardWrap({super.key, required this.children, this.spacing = 10, this.runSpacing = 10});
  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: Wrap(spacing: spacing, runSpacing: runSpacing, alignment: WrapAlignment.start, children: children),
      );
}
