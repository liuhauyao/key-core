// 工具页（lens）共用部件（ui_redesign_plan §5.5 / mockup 05、06）：
// - KcToolPageTitle：工具 logo + 名称 +「当前：X · 写入 路径」
// - KcNoticeBar：页内常驻提示条（配置文件缺失、需要环境变量等），取代一闪而过的橙色 SnackBar
// - KcUnenabledSection：「未启用到 X 的密钥」紧凑区，每行一个「启用」
// - enableKeyForTool：启用逻辑（缺请求地址 / 模型时转去编辑页补全）
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/ai_key.dart';
import '../../models/mcp_server.dart' show AiToolType;
import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import 'kc_logo.dart';
import 'kc_toast.dart';
import 'key_card.dart' show toolConfigPathHint, enabledToolsOf;
import 'key_details_dialog.dart' show toolNeedsSetup, withToolEnabled;

/// 页头左侧：工具 logo + 名称 +「当前：X · 写入 路径」
class KcToolPageTitle extends StatelessWidget {
  const KcToolPageTitle({super.key, required this.tool, this.currentLabel, this.subtitle, this.trailing});

  final AiToolType tool;

  /// 当前生效的密钥名 /「官方配置」；null 表示还没读到
  final String? currentLabel;

  /// 覆盖默认副标题（例如 OpenClaw 的「n 个已启用」）
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final path = toolConfigPathHint(tool);
    final sub = subtitle ??
        (currentLabel == null
            ? path
            : (l?.toolPageCurrent(currentLabel!, path) ?? '当前：$currentLabel  ·  写入 $path'));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KcToolLogo(tool: tool, size: 32, logoSize: 20),
        const SizedBox(width: KcSpace.x3),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(kcToolName(tool), key: const ValueKey('toolPage.title'), style: KcType.page.copyWith(color: cs.foreground)),
                if (trailing != null) ...[const SizedBox(width: KcSpace.x3), trailing!],
              ]),
              Text(sub,
                  key: const ValueKey('toolPage.subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KcType.caption.copyWith(color: kc.text2)),
            ],
          ),
        ),
      ],
    );
  }
}

enum KcNoticeKind { info, warning, danger }

/// 页内常驻提示条
class KcNoticeBar extends StatelessWidget {
  const KcNoticeBar({super.key, required this.message, this.kind = KcNoticeKind.warning, this.actionLabel, this.onAction});

  final String message;
  final KcNoticeKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final kc = context.kc;
    final cs = ShadTheme.of(context).colorScheme;
    final (Color fg, Color bg, IconData icon) = switch (kind) {
      KcNoticeKind.info => (kc.actionText, kc.actionSoft, Icons.info_outline_rounded),
      KcNoticeKind.warning => (kc.warnText, kc.warnSoft, Icons.warning_amber_rounded),
      KcNoticeKind.danger => (kc.dangerText, kc.dangerSoft, Icons.error_outline_rounded),
    };
    return Container(
      key: const ValueKey('toolPage.notice'),
      margin: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x3, KcSpace.page, 0),
      padding: const EdgeInsets.symmetric(horizontal: KcSpace.x3, vertical: KcSpace.x2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(KcRadius.panel)),
      child: Row(
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: KcSpace.x2),
          Expanded(child: Text(message, style: KcType.body.copyWith(color: fg))),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: KcSpace.x2),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              foregroundColor: cs.foreground,
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// 「未启用到 X 的密钥」紧凑区：默认折叠，展开后每行 logo + 名称 + 平台 +「启用」
class KcUnenabledSection extends StatefulWidget {
  const KcUnenabledSection({super.key, required this.tool, required this.keys, required this.onEnable});

  final AiToolType tool;
  final List<AIKey> keys;
  final ValueChanged<AIKey> onEnable;

  @override
  State<KcUnenabledSection> createState() => _KcUnenabledSectionState();
}

class _KcUnenabledSectionState extends State<KcUnenabledSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.keys.isEmpty) return const SizedBox.shrink();
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final name = kcToolName(widget.tool);
    return Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x2, KcSpace.page, KcSpace.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('unenabled.toggle'),
            borderRadius: BorderRadius.circular(KcRadius.control),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: KcSpace.x2),
              child: Row(children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 18, color: kc.text2),
                const SizedBox(width: 4),
                Text(l?.notEnabledForTool(name) ?? '未启用到 $name 的密钥',
                    style: KcType.section.copyWith(color: cs.foreground)),
                const SizedBox(width: KcSpace.x2),
                Text('${widget.keys.length}', style: KcType.caption.copyWith(color: cs.mutedForeground)),
                const SizedBox(width: KcSpace.x3),
                Flexible(
                  child: Text(l?.notEnabledForToolHint ?? '启用后才会出现在上面的候选列表里',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KcType.caption.copyWith(color: cs.mutedForeground)),
                ),
              ]),
            ),
          ),
          if (_open)
            Container(
              decoration: BoxDecoration(
                color: cs.card,
                border: Border.all(color: cs.border),
                borderRadius: BorderRadius.circular(KcRadius.panel),
              ),
              child: Column(children: [
                for (final (i, k) in widget.keys.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: cs.border),
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KcSpace.x3),
                      child: Row(children: [
                        KcPlatformLogo(platform: k.platformType, customIconFileName: k.icon, name: k.name, size: 26, logoSize: 16),
                        const SizedBox(width: KcSpace.x2),
                        Flexible(
                          child: Text(k.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.body.copyWith(color: cs.foreground)),
                        ),
                        const SizedBox(width: KcSpace.x2),
                        Text(k.platform, style: KcType.caption.copyWith(color: cs.mutedForeground)),
                        const SizedBox(width: KcSpace.x2),
                        for (final t in enabledToolsOf(k).take(4))
                          Padding(padding: const EdgeInsets.only(left: 2), child: KcToolLogo(tool: t, size: 14)),
                        const Spacer(),
                        ShadButton.outline(
                          key: ValueKey('unenabled.enable.${k.id}'),
                          size: ShadButtonSize.sm,
                          foregroundColor: kc.actionText,
                          onPressed: () => widget.onEnable(k),
                          child: Text(l?.enableShort ?? '启用'),
                        ),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

/// 把 [key] 启用到 [tool]：只改 enableXxx，不写配置文件。缺请求地址 / 模型时调用 [openEditor] 去编辑页补全。
/// 返回是否已保存。
Future<bool> enableKeyForTool(
  BuildContext context,
  AIKey key,
  AiToolType tool, {
  required void Function(AIKey decrypted) openEditor,
}) async {
  if (key.id == null) return false;
  final vm = context.read<KeyManagerViewModel>();
  final l = AppLocalizations.of(context);
  final name = kcToolName(tool);
  final decrypted = await vm.getDecryptedKey(key.id!);
  if (!context.mounted) return false;
  if (decrypted == null) {
    showKcToast(context, l?.cannotDecryptKey ?? '无法解密密钥', kind: KcToastKind.error);
    return false;
  }
  if (toolNeedsSetup(decrypted, tool)) {
    showKcToast(context, l?.toolModelMissing(name) ?? '$name 还缺少请求地址或模型，请先在编辑页补全',
        kind: KcToastKind.warning);
    openEditor(decrypted);
    return false;
  }
  final ok = await vm.updateKey(withToolEnabled(decrypted, tool, true));
  if (!context.mounted) return ok;
  if (ok) {
    showKcToast(context, l?.toolEnabledFor(name) ?? '已启用到 $name');
  } else {
    showKcToast(context, vm.errorMessage ?? (l?.updateFailed ?? '更新失败'), kind: KcToastKind.error);
  }
  return ok;
}
