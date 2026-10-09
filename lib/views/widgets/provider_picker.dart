// 供应商选择器（form_v3.md §1）：锚定在供应商字段下方的 600×452 弹层。
// 顶部搜索（高 44）/ 分类分段（按内容自适应宽度，溢出横向滚动，不截字）/ 3 列卡片（logo + 名称 + 域名）/
// 底栏键盘提示 +「自定义供应商」。宽度、位置按窗口夹紧，任何窗口尺寸下都不会被裁切。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/platform_category.dart';
import '../../models/platform_type.dart';
import '../../services/platform_registry.dart';
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_presets.dart';
import 'kc_logo.dart';

/// 供应商的展示域名（取预设的请求地址或管理地址）
String providerDomain(PlatformType p) {
  final preset = PlatformPresets.getPreset(p);
  final url = preset?.apiEndpoint ?? preset?.managementUrl;
  if (url == null || url.isEmpty) return '';
  return Uri.tryParse(url)?.host ?? '';
}

/// 打开选择器。[anchor] 是供应商字段的全局矩形；返回选中的平台（取消为 null）。
Future<PlatformType?> showProviderPicker({
  required BuildContext context,
  required Rect anchor,
  required List<PlatformCategory> categories,
  required List<PlatformType> Function(PlatformCategory) platformsOf,
  PlatformType? selected,
}) {
  return showGeneralDialog<PlatformType>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'provider-picker',
    barrierColor: Colors.transparent, // 弹出面板不压暗整窗
    transitionDuration: KcMotion.of(context),
    pageBuilder: (ctx, _, __) {
      final screen = MediaQuery.sizeOf(ctx);
      const margin = 12.0;
      final w = (screen.width - margin * 2).clamp(320.0, 600.0);
      final h = (screen.height - margin * 2).clamp(260.0, 452.0);
      var left = anchor.left.clamp(margin, screen.width - w - margin);
      var top = anchor.bottom + 6;
      if (top + h > screen.height - margin) {
        // 下方放不下：放到字段上方；再放不下就贴着窗口底部
        top = anchor.top - 6 - h;
        if (top < margin) top = screen.height - h - margin;
      }
      return Stack(children: [
        Positioned(
          left: left,
          top: top,
          width: w,
          height: h,
          child: ProviderPickerPanel(categories: categories, platformsOf: platformsOf, selected: selected),
        ),
      ]);
    },
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: child),
  );
}

class ProviderPickerPanel extends StatefulWidget {
  const ProviderPickerPanel({super.key, required this.categories, required this.platformsOf, this.selected});

  final List<PlatformCategory> categories;
  final List<PlatformType> Function(PlatformCategory) platformsOf;
  final PlatformType? selected;

  @override
  State<ProviderPickerPanel> createState() => _ProviderPickerPanelState();
}

class _ProviderPickerPanelState extends State<ProviderPickerPanel> {
  final _search = TextEditingController();
  PlatformCategory? _cat; // null = 全部

  List<PlatformType> get _all {
    final seen = <String>{};
    final out = <PlatformType>[];
    for (final c in widget.categories) {
      for (final p in widget.platformsOf(c)) {
        if (p != PlatformType.custom && seen.add(p.id)) out.add(p);
      }
    }
    // 「全部」= 分类之外的已注册平台也要能搜到（内置平台未必都有分类标签）
    for (final p in PlatformRegistry.getFilteredPlatformsSync()) {
      if (p != PlatformType.custom && seen.add(p.id)) out.add(p);
    }
    return out;
  }

  List<PlatformType> get _visible {
    final base = _cat == null ? _all : widget.platformsOf(_cat!).where((p) => p != PlatformType.custom).toList();
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base
        .where((p) => p.value.toLowerCase().contains(q) || p.id.toLowerCase().contains(q) || providerDomain(p).contains(q))
        .toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final items = _visible;

    Widget seg(PlatformCategory? c, String label, int n) {
      final on = c == _cat;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          key: ValueKey('providerPicker.cat.${c?.name ?? 'all'}'),
          borderRadius: BorderRadius.circular(KcRadius.control),
          onTap: () => setState(() => _cat = c),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? cs.background : Colors.transparent,
              borderRadius: BorderRadius.circular(KcRadius.control),
              boxShadow: on ? kc.shadowSm : null,
            ),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label),
                TextSpan(text: ' $n', style: TextStyle(color: cs.mutedForeground, fontFeatures: KcType.tabular)),
              ]),
              softWrap: false,
              style: KcType.caption.copyWith(color: on ? cs.foreground : kc.text2, fontWeight: on ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (items.isNotEmpty) Navigator.of(context).pop(items.first);
        },
      },
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(KcRadius.dialog), boxShadow: kc.shadowLg),
        child: Material(
        key: const ValueKey('providerPicker'),
        color: cs.popover,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KcRadius.dialog), side: BorderSide(color: cs.border)),
        clipBehavior: Clip.antiAlias,
        shadowColor: Colors.black26,
        // 实色面板：阴影不再画在无填充色的盒子里（否则整块面板发灰）
        child: DecoratedBox(
          decoration: BoxDecoration(color: cs.popover),
          child: Column(children: [
            SizedBox(
              height: 44,
              child: Row(children: [
                const SizedBox(width: 14),
                Icon(Icons.search, size: 16, color: cs.mutedForeground),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: const ValueKey('providerPicker.search'),
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    style: KcType.body.copyWith(color: cs.foreground),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: l?.tr('provider_search_hint', '搜索供应商、域名…') ?? '搜索供应商、域名…',
                      hintStyle: KcType.body.copyWith(color: cs.mutedForeground),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('Esc', style: KcType.badge.copyWith(color: cs.mutedForeground)),
                ),
              ]),
            ),
            Divider(height: 1, color: cs.border),
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(children: [
                  seg(null, l?.tr('all', '全部') ?? '全部', _all.length),
                  for (final c in widget.categories)
                    if (c != PlatformCategory.custom) seg(c, c.getValue(context), widget.platformsOf(c).where((p) => p != PlatformType.custom).length),
                ]),
              ),
            ),
            Divider(height: 1, color: cs.border),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(l?.tr('provider_none', '没有匹配的供应商') ?? '没有匹配的供应商', style: KcType.body.copyWith(color: cs.mutedForeground)))
                  : LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth >= 480 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols, mainAxisExtent: 50, crossAxisSpacing: 6, mainAxisSpacing: 6),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final p = items[i];
                          final on = p == widget.selected;
                          final domain = providerDomain(p);
                          return InkWell(
                            key: ValueKey('providerPicker.item.${p.id}'),
                            borderRadius: BorderRadius.circular(KcRadius.control + 2),
                            onTap: () => Navigator.of(context).pop(p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: on ? kc.actionSoft : null,
                                borderRadius: BorderRadius.circular(KcRadius.control + 2),
                                border: Border.all(color: on ? cs.primary : cs.border),
                              ),
                              child: Row(children: [
                                KcPlatformLogo(platform: p, size: 28, logoSize: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: KcType.body.copyWith(color: cs.foreground, fontWeight: FontWeight.w500, height: 1.2)),
                                      if (domain.isNotEmpty)
                                        Text(domain,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: KcType.mono.copyWith(fontSize: 10.5, color: cs.mutedForeground, height: 1.3)),
                                    ],
                                  ),
                                ),
                              ]),
                            ),
                          );
                        },
                      );
                    }),
            ),
            Divider(height: 1, color: cs.border),
            SizedBox(
              height: 40,
              child: Row(children: [
                const SizedBox(width: 14),
                Expanded(
                  child: Text(l?.tr('provider_picker_keys', '↑↓ 选择 · Enter 确认 · Esc 关闭') ?? '↑↓ 选择 · Enter 确认 · Esc 关闭',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.caption.copyWith(color: cs.mutedForeground)),
                ),
                TextButton.icon(
                  key: const ValueKey('providerPicker.custom'),
                  onPressed: () => Navigator.of(context).pop(PlatformType.custom),
                  icon: const Icon(Icons.add, size: 15),
                  label: Text(l?.tr('custom_provider', '自定义供应商') ?? '自定义供应商'),
                ),
                const SizedBox(width: 8),
              ]),
            ),
          ]),
        ),
      ),
      ),
    );
  }
}
