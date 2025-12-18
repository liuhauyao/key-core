import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/validation_result.dart';

/// 校验按钮状态
enum ValidationState {
  idle,
  validating,
  success,
  failure,
}

/// 密钥校验按钮组件
class KeyValidationButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final ValidationState state;
  final String? errorMessage;

  const KeyValidationButton({
    super.key,
    this.onPressed,
    this.state = ValidationState.idle,
    this.errorMessage,
  });

  @override
  State<KeyValidationButton> createState() => _KeyValidationButtonState();
}

class _KeyValidationButtonState extends State<KeyValidationButton> {
  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);

    IconData icon;
    Color? color;
    String tooltip;

    switch (widget.state) {
      case ValidationState.validating:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              shadTheme.colorScheme.primary,
            ),
          ),
        );
      case ValidationState.success:
        icon = Icons.check_circle;
        color = Colors.green;
        tooltip = '密钥有效';
        break;
      case ValidationState.failure:
        icon = Icons.error;
        color = Colors.red;
        tooltip = widget.errorMessage ?? '密钥无效';
        break;
      case ValidationState.idle:
      default:
        icon = Icons.verified_outlined;
        color = shadTheme.colorScheme.mutedForeground;
        tooltip = '校验密钥';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: color),
        onPressed: widget.state == ValidationState.validating
            ? null
            : widget.onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    );
  }
}





