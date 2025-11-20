import 'package:flutter/cupertino.dart';
import '../../utils/app_localizations.dart';

/// 统一的确认对话框组件
/// 使用 Flutter 内置的 CupertinoAlertDialog iOS 风格对话框
class ConfirmDialog extends StatelessWidget {
  /// 对话框标题
  final String title;
  
  /// 对话框消息内容
  final String message;
  
  /// 取消按钮文本，默认为 "取消"
  final String? cancelText;
  
  /// 确认按钮文本，默认为 "确定"
  final String? confirmText;
  
  /// 是否为危险操作（删除等），已废弃，保留以兼容旧代码
  @Deprecated('不再使用，按钮统一为蓝色')
  final bool isDangerous;

  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.cancelText,
    this.confirmText,
    @Deprecated('不再使用') this.isDangerous = false,
  });

  /// 显示确认对话框的静态方法
  /// 返回 true: 确认，false: 取消，null: 关闭对话框
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String? cancelText,
    String? confirmText,
    @Deprecated('不再使用') bool isDangerous = false,
  }) {
    final localizations = AppLocalizations.of(context);
    
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfirmDialog(
        title: title,
        message: message,
        cancelText: cancelText ?? localizations?.cancel ?? '取消',
        confirmText: confirmText ?? localizations?.confirm ?? '确认',
      ),
    );
  }

  /// 显示未保存变更确认对话框（三个按钮）
  /// 返回 true: 保存，false: 放弃，null: 取消
  static Future<bool?> showUnsavedChanges({
    required BuildContext context,
    required String title,
    required String message,
    String? cancelText,
    String? discardText,
    String? saveText,
  }) {
    final localizations = AppLocalizations.of(context);
    
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Text(message),
        ),
        actions: [
          // 取消按钮 - 蓝色，字体较小，垂直居中
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, null),
            child: Text(
              cancelText ?? localizations?.cancel ?? '取消',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.0,
                color: CupertinoColors.systemBlue.resolveFrom(context),
              ),
            ),
          ),
          // 放弃按钮 - 蓝色，字体较小，垂直居中
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              discardText ?? localizations?.mcpDiscard ?? '放弃',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.0,
                color: CupertinoColors.systemBlue.resolveFrom(context),
              ),
            ),
          ),
          // 保存按钮 - 蓝色，字体较小，垂直居中
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              saveText ?? localizations?.mcpSave ?? '保存',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.0,
                color: CupertinoColors.systemBlue.resolveFrom(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    
    return CupertinoAlertDialog(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Padding(
        padding: const EdgeInsets.only(top: 12.0),
        child: Text(message),
      ),
      actions: [
        // 取消按钮 - 蓝色，字体较小，垂直居中
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            cancelText ?? localizations?.cancel ?? '取消',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.0,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
          ),
        ),
        // 确认按钮 - 蓝色，字体较小，垂直居中
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            confirmText ?? localizations?.confirm ?? '确认',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.0,
              color: CupertinoColors.systemBlue.resolveFrom(context),
            ),
          ),
        ),
      ],
    );
  }
}

