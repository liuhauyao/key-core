// 统一反馈（ui_redesign_plan.md §5.7）：ShadToaster 白卡 + 彩色图标，底部居中。
//
// - 成功写结果：「已切换到 DeepSeek 主力。新开的会话会读取新配置。」，2 秒
// - 失败写原因和下一步：「没能切换到 X：<原因>」，6 秒，可带「重试」
// - 可选「撤销」动作（工具 chip 一键切换后使用）
//
// 树上没有 ShadToaster 时（例如单独 push 的页面或测试）退回到 SnackBar，保证消息不丢。
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../theme/kc_tokens.dart';
import '../../utils/app_localizations.dart';

enum KcToastKind { success, error, warning, info }

/// 去掉 `Exception: ` 等前缀，得到给用户看的原因。
String humanizeError(Object? error) {
  if (error == null) return '';
  var s = error.toString().trim();
  for (final prefix in const ['Exception: ', 'Exception:', 'Bad state: ', 'FormatException: ']) {
    if (s.startsWith(prefix)) s = s.substring(prefix.length).trim();
  }
  return s;
}

void showKcToast(
  BuildContext context,
  String message, {
  KcToastKind kind = KcToastKind.success,
  String? title,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final effectiveDuration = duration ??
      (kind == KcToastKind.error || kind == KcToastKind.warning
          ? const Duration(seconds: 6)
          : const Duration(seconds: 2));
  final kc = context.kc;
  final (IconData icon, Color color) = switch (kind) {
    KcToastKind.success => (Icons.check_circle_rounded, kc.ok),
    KcToastKind.error => (Icons.error_rounded, kc.danger),
    KcToastKind.warning => (Icons.warning_rounded, kc.warn),
    KcToastKind.info => (Icons.info_rounded, ShadTheme.of(context).colorScheme.primary),
  };

  final toaster = ShadToaster.maybeOf(context);
  if (toaster != null) {
    final theme = ShadTheme.of(context);
    final hasTitle = title != null && title.isNotEmpty;
    toaster.show(ShadToast(
      alignment: Alignment.bottomCenter,
      duration: effectiveDuration,
      radius: BorderRadius.circular(KcRadius.panel),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 16, color: color, semanticLabel: kind.name),
          ),
          const SizedBox(width: KcSpace.x2),
          Flexible(
            child: Text(
              hasTitle ? title : message,
              style: (hasTitle ? KcType.strong : KcType.body).copyWith(color: theme.colorScheme.foreground),
            ),
          ),
        ],
      ),
      description: hasTitle
          ? Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(message, style: KcType.caption.copyWith(color: kc.text2)),
            )
          : null,
      action: (actionLabel != null && onAction != null)
          ? ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () {
                toaster.hide();
                onAction();
              },
              child: Text(actionLabel),
            )
          : null,
    ));
    return;
  }

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: effectiveDuration,
      content: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: KcSpace.x2),
        Expanded(child: Text(title == null || title.isEmpty ? message : '$title\n$message')),
      ]),
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(label: actionLabel, onPressed: onAction)
          : null,
    ));
}

/// 工具切换结果（四个工具页 + 钥匙包工具 chip 共用）。
///
/// [targetName] 为密钥名或「官方配置」；失败时 [error] 一般是 `KeyManagerViewModel.errorMessage`。
void showSwitchResult(
  BuildContext context, {
  required bool success,
  required String targetName,
  String? toolName,
  Object? error,
  VoidCallback? onRetry,
  VoidCallback? onUndo,
}) {
  final l = AppLocalizations.of(context);
  if (success) {
    final msg = l?.switchedToTarget(targetName, toolName) ??
        '已切换到 $targetName。新开的会话会读取新配置。';
    showKcToast(
      context,
      msg,
      kind: KcToastKind.success,
      actionLabel: onUndo != null ? (l?.undo ?? '撤销') : null,
      onAction: onUndo,
      duration: onUndo != null ? const Duration(seconds: 5) : null,
    );
    return;
  }
  final reason = humanizeError(error);
  final msg = l?.switchFailedWithReason(
          targetName, reason.isEmpty ? l.switchFailedUnknownReason : reason) ??
      '没能切换到 $targetName：${reason.isEmpty ? '写入配置文件失败，详见日志' : reason}';
  showKcToast(
    context,
    msg,
    kind: KcToastKind.error,
    actionLabel: onRetry != null ? (l?.retry ?? '重试') : null,
    onAction: onRetry,
  );
}
