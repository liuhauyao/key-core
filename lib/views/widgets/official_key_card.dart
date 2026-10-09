// 官方配置卡片（ui_redesign_plan §5.5）：与新 KeyCard 同一套骨架——140 高、36 顶部、20 说明行、34 底栏。
// 去掉了流光渐变、噪点和实心「激活」标签；生效时与 lens 卡片一致：ok soft 底 + ok 描边 +「● 生效中」。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import 'kc_logo.dart';

/// 官方配置卡片组件（保持与 KeyCard 一致的视觉风格）
class OfficialKeyCard extends StatefulWidget {
  final bool isCurrent;
  final Widget icon;
  final String title;
  final String subtitle;
  final String description;
  final List<Widget> actions;
  final VoidCallback? onTap;

  const OfficialKeyCard({
    super.key,
    required this.isCurrent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.actions,
    this.onTap,
  });

  @override
  State<OfficialKeyCard> createState() => _OfficialKeyCardState();
}

class _OfficialKeyCardState extends State<OfficialKeyCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final current = widget.isCurrent;

    return Semantics(
      container: true,
      label: widget.title,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          key: const ValueKey('officialCard'),
          duration: KcMotion.of(context),
          curve: KcMotion.curve,
          decoration: BoxDecoration(
            color: current ? Color.alphaBlend(kc.okSoft, cs.card) : cs.card,
            borderRadius: BorderRadius.circular(KcRadius.panel),
            border: Border.all(color: current ? kc.ok : (_isHovering ? cs.input : cs.border)),
            boxShadow: _isHovering ? kc.shadowMd : kc.shadowSm,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KcRadius.panel),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(KcSpace.x3, KcSpace.x2 + 2, KcSpace.x3, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 36,
                        child: Row(
                          children: [
                            KcLogoBox(child: SizedBox(width: 22, height: 22, child: FittedBox(child: widget.icon))),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(widget.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KcType.strong.copyWith(color: cs.foreground)),
                                  Text(widget.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KcType.caption.copyWith(color: cs.mutedForeground, height: 1.25)),
                                ],
                              ),
                            ),
                            if (current) ...[
                              const SizedBox(width: KcSpace.x1_5),
                              Container(
                                key: const ValueKey('officialCard.active'),
                                height: 20,
                                padding: const EdgeInsets.symmetric(horizontal: 7),
                                decoration: BoxDecoration(color: kc.okSoft, borderRadius: BorderRadius.circular(999)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(
                                      width: 6, height: 6, decoration: BoxDecoration(color: kc.ok, shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  Text(l?.statusActive ?? '生效中', style: KcType.badge.copyWith(color: kc.okText)),
                                ]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: KcSpace.x2),
                      SizedBox(
                        height: 20,
                        width: double.infinity,
                        child: Text(
                          widget.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KcType.caption.copyWith(color: kc.text2, height: 1.4),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 34,
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.border))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: widget.actions,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
