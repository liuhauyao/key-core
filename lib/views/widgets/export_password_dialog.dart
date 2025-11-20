import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../utils/app_localizations.dart';

/// 导出密码输入对话框
/// 用于导入时输入导出密码，或导出时设置导出密码
class ExportPasswordDialog extends StatefulWidget {
  /// 是否为导入模式（true：导入时需要输入密码，false：导出时需要设置密码）
  final bool isImportMode;

  const ExportPasswordDialog({
    super.key,
    this.isImportMode = false,
  });

  @override
  State<ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<ExportPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)?.exportPasswordRequired ?? '密码不能为空';
      });
      return;
    }

    Navigator.pop(context, password);
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 450,
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: shadTheme.colorScheme.border,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.isImportMode ? Icons.lock_open : Icons.lock,
                      size: 20,
                      color: shadTheme.colorScheme.foreground,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.isImportMode
                            ? (localizations?.importPasswordTitle ?? '输入导出密码')
                            : (localizations?.exportPasswordTitle ?? '设置导出密码'),
                        style: shadTheme.textTheme.h4.copyWith(
                          color: shadTheme.colorScheme.foreground,
                        ),
                      ),
                    ),
                    ShadButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // 内容区域
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 说明文字
                    Text(
                      widget.isImportMode
                          ? (localizations?.importPasswordDesc ?? '请输入导出时设置的密码以解密文件')
                          : (localizations?.exportPasswordDesc ?? '设置密码用于加密导出文件，导入时需要此密码'),
                      style: shadTheme.textTheme.small.copyWith(
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // 错误信息
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, size: 20, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: shadTheme.textTheme.small.copyWith(
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // 密码输入框
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: localizations?.exportPasswordLabel ?? '密码',
                        hintText: localizations?.exportPasswordHint ?? '请输入密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return localizations?.exportPasswordRequired ?? '密码不能为空';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                ),
              ),
              // 底部按钮
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: shadTheme.colorScheme.border,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text(localizations?.cancel ?? '取消'),
                    ),
                    const SizedBox(width: 12),
                    ShadButton(
                      onPressed: _isLoading ? null : _submit,
                      leading: _isLoading
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              widget.isImportMode ? Icons.check : Icons.lock,
                              size: 18,
                            ),
                      child: Text(
                        widget.isImportMode
                            ? (localizations?.confirm ?? '确认')
                            : (localizations?.set ?? '设置'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

