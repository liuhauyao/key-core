import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/ime_friendly_formatter.dart';

/// macOS 输入法安全的文本输入框
///
/// 这个组件专门为解决 macOS 上的输入法问题而设计
/// 移除了所有可能导致输入法卡顿的因素
class ImeSafeTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final String? Function(String?)? validator;
  final bool isDark;

  const ImeSafeTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.maxLengthEnforcement,
    this.validator,
    this.isDark = false,
  });

  @override
  State<ImeSafeTextField> createState() => _ImeSafeTextFieldState();
}

class _ImeSafeTextFieldState extends State<ImeSafeTextField> {
  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isDark ? Colors.grey[700]! : Colors.grey[400]!;
    final focusedBorderColor = widget.isDark ? Colors.blue[400]! : Colors.blue[600]!;
    final fillColor = widget.isDark ? const Color(0xFF1E1E1E) : Colors.white;

    // ⚠️ 使用纯 TextField 而非 TextFormField，避免 validator 导致的重建
    return TextField(
      controller: widget.controller,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      // 使用 ImeFriendlyFormatter 避免在输入法组合过程中打断 IME
      inputFormatters: [ImeFriendlyFormatter()],
      // 完全移除所有可能导致重建的功能
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      style: TextStyle(
        fontSize: 14,
        height: 1.2, // 减小行高以匹配 ShadInputFormField
      ),
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: widget.prefixIcon,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          maxWidth: 32,
          minHeight: 32,
          maxHeight: 32,
        ),
        suffixIcon: widget.suffixIcon,
        suffixIconConstraints: widget.suffixIcon != null
            ? const BoxConstraints(
                minWidth: 52, // 为两个图标按钮预留足够空间
                minHeight: 32,
              )
            : null,
        filled: true,
        fillColor: fillColor,
        // 仅通过内边距控制输入框高度
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        floatingLabelAlignment: FloatingLabelAlignment.start,
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: widget.isDark ? Colors.grey[300] : Colors.grey[700],
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          color: widget.isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        hintStyle: TextStyle(
          fontSize: 13,
          color: widget.isDark ? Colors.grey[500] : Colors.grey[400],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: focusedBorderColor,
            width: 1,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Colors.red[400]!,
            width: 0.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Colors.red[500]!,
            width: 1,
          ),
        ),
      ),
    );
  }
}
