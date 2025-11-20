import 'package:flutter/material.dart';
import 'dart:ui';

/// macOS 26 Liquid Glass（液态玻璃）设计风格装饰工具
class LiquidGlassDecoration {
  /// 创建液态玻璃风格的输入框装饰
  static InputDecoration buildInputDecoration({
    required String? labelText,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool isDark = false,
    int? maxLength,
    int? currentLength,
  }) {
    // 如果有字符限制，将计数添加到suffixIcon
    Widget? finalSuffixIcon = suffixIcon;
    if (maxLength != null) {
      final counterText = currentLength != null 
          ? '$currentLength/$maxLength' 
          : '0/$maxLength';
      final counterWidget = Padding(
        padding: EdgeInsets.only(right: suffixIcon != null ? 8 : 12),
        child: Text(
          counterText,
          style: TextStyle(
            fontSize: 11,
            color: isDark 
                ? Colors.white.withOpacity(0.4) 
                : Colors.black.withOpacity(0.4),
          ),
        ),
      );
      
      if (suffixIcon != null) {
        // 如果已有suffixIcon，使用Row组合，字符计数在左侧
        finalSuffixIcon = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            counterWidget,
            suffixIcon,
          ],
        );
      } else {
        finalSuffixIcon = counterWidget;
      }
    }
    final borderColor = isDark 
        ? Colors.white.withOpacity(0.15) 
        : Colors.black.withOpacity(0.1);
    final focusedBorderColor = isDark 
        ? Colors.blue.withOpacity(0.6) 
        : Colors.blue.withOpacity(0.8);
    final fillColor = isDark 
        ? Colors.white.withOpacity(0.08) 
        : Colors.white.withOpacity(0.6);
    
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: finalSuffixIcon,
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      counterText: '', // 隐藏默认的字符计数
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      floatingLabelAlignment: FloatingLabelAlignment.start,
      floatingLabelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.8),
      ),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: isDark ? Colors.white.withOpacity(0.7) : Colors.black.withOpacity(0.6),
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: borderColor,
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: borderColor,
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: focusedBorderColor,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: Colors.red.withOpacity(0.6),
          width: 1,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: Colors.red.withOpacity(0.8),
          width: 1.5,
        ),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
    );
  }

  /// 创建液态玻璃风格的容器装饰
  static BoxDecoration buildContainerDecoration({
    bool isDark = false,
    double borderRadius = 12,
    bool withShadow = true,
  }) {
    final backgroundColor = isDark 
        ? Colors.white.withOpacity(0.06) 
        : Colors.white.withOpacity(0.7);
    
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isDark 
            ? Colors.white.withOpacity(0.1) 
            : Colors.black.withOpacity(0.08),
        width: 0.5,
      ),
      boxShadow: withShadow ? [
        BoxShadow(
          color: isDark 
              ? Colors.black.withOpacity(0.3) 
              : Colors.black.withOpacity(0.08),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: isDark 
              ? Colors.black.withOpacity(0.2) 
              : Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ] : null,
    );
  }

  /// 创建液态玻璃风格的按钮样式
  static ButtonStyle buildButtonStyle({
    required Color backgroundColor,
    required Color foregroundColor,
    bool isDark = false,
  }) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.all(backgroundColor),
      foregroundColor: WidgetStateProperty.all(foregroundColor),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      elevation: WidgetStateProperty.all(0),
      shadowColor: WidgetStateProperty.all(Colors.transparent),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return foregroundColor.withOpacity(0.1);
        }
        if (states.contains(WidgetState.hovered)) {
          return foregroundColor.withOpacity(0.05);
        }
        return Colors.transparent;
      }),
    );
  }

  /// 创建模糊背景效果
  /// 使用Stack分离背景和输入框，避免ClipRRect裁剪浮动的label
  static Widget buildBlurBackground({
    required Widget child,
    double sigmaX = 10,
    double sigmaY = 10,
  }) {
    return Stack(
      clipBehavior: Clip.none, // 关键：允许label超出Stack边界显示
      children: [
        // 模糊背景层（只裁剪背景，不裁剪label）
        Positioned(
          top: 12, // 与输入框对齐
          left: 0,
          right: 0,
          bottom: 0,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        // 输入框层（可以超出边界，label不会被裁剪）
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: child,
        ),
      ],
    );
  }
}

