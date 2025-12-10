import 'package:flutter/services.dart';

/// 输入法友好的文本输入格式化器
///
/// 用于解决 macOS 输入法卡顿问题
/// 主要问题：在使用中文输入法等 IME 时，如果在 composing 状态下修改文本，
/// 会导致输入法卡住，只能输入首字母
///
/// 解决方案：当检测到输入法正在组合文字时（composing.isValid），
/// 直接返回新值，不进行任何处理
class ImeFriendlyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 如果正在使用输入法输入（composing），直接返回新值，不进行任何处理
    // 这样可以避免在输入法输入过程中触发构建或修改文本，导致输入法卡住
    if (newValue.composing.isValid) {
      return newValue;
    }

    // 非输入法输入时，返回新值（可以在这里添加其他格式化逻辑）
    return newValue;
  }
}
