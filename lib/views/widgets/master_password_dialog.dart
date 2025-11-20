import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/crypt_service.dart';
import '../../utils/password_generator.dart';
import '../../utils/app_localizations.dart';
import '../../viewmodels/key_manager_viewmodel.dart';

/// 主密码设置对话框
class MasterPasswordDialog extends StatefulWidget {
  const MasterPasswordDialog({super.key});

  @override
  State<MasterPasswordDialog> createState() => _MasterPasswordDialogState();
}

class _MasterPasswordDialogState extends State<MasterPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  final _cryptService = CryptService();
  
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _skipValidation = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
    _passwordController.addListener(() {
      setState(() {});
    });
  }

  Future<void> _checkPasswordStatus() async {
    final hasPassword = await _authService.hasMasterPassword();
    setState(() {
      _hasPassword = hasPassword;
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _generatePassword() {
    final password = PasswordGenerator.generate(
      length: 16,
      includeLowercase: true,
      includeUppercase: true,
      includeNumbers: true,
      includeSymbols: true,
    );
    setState(() {
      _passwordController.text = password;
      _confirmPasswordController.text = password;
      _skipValidation = true; // 生成的密码跳过验证
    });
  }

  void _generateMemorablePassword() {
    final password = PasswordGenerator.generateMemorable(
      wordCount: 4,
      separator: '-',
    );
    setState(() {
      _passwordController.text = password;
      _confirmPasswordController.text = password;
      _skipValidation = true;
    });
  }

  Future<void> _savePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final password = _passwordController.text.trim();
      
      if (password.isEmpty) {
        // 清除主密码
        await _authService.clearAuthData();
        if (mounted) {
          Navigator.pop(context, true);
          final localizations = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations?.masterPasswordCleared ?? '已清除主密码，密钥将以明文存储')),
          );
        }
        return;
      }

      // 检查是否之前已经设置过主密码
      final hadPasswordBefore = await _authService.hasMasterPassword();
      
      // 设置主密码
      await _authService.setMasterPassword(
        password,
        skipValidation: _skipValidation,
      );

      // 如果是首次设置主密码，重新加密所有明文密钥
      if (!hadPasswordBefore && mounted) {
        try {
          final viewModel = context.read<KeyManagerViewModel>();
          await viewModel.reEncryptAllPlaintextKeys();
        } catch (e) {
          print('重新加密已有密钥时出错: $e');
          // 即使重新加密失败，也不影响主密码设置成功
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
        final localizations = AppLocalizations.of(context);
        final message = !hadPasswordBefore
            ? (localizations?.masterPasswordSetSuccess ?? '主密码设置成功，已加密所有密钥')
            : (localizations?.masterPasswordSetSuccess ?? '主密码设置成功');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('AuthException: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Dialog(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  const Icon(Icons.lock_outline, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _hasPassword ? (localizations?.changeMasterPassword ?? '修改主密码') : (localizations?.setMasterPassword ?? '设置主密码'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _hasPassword
                    ? (localizations?.changePasswordDesc ?? '修改主密码后，所有密钥将使用新密码重新加密')
                    : (localizations?.setPasswordDesc ?? '设置主密码后，所有密钥将加密存储。不设置则使用明文存储。'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 24),

              // 错误信息
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),

              // 密码输入
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: localizations?.masterPasswordLabel ?? '主密码',
                  hintText: localizations?.masterPasswordHint ?? '留空则清除主密码（明文存储）',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                      ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (value) {
                          if (value == 'generate') {
                            _generatePassword();
                          } else if (value == 'generate_memorable') {
                            _generateMemorablePassword();
                          }
                        },
                        itemBuilder: (context) {
                          final loc = AppLocalizations.of(context);
                          return [
                            PopupMenuItem(
                              value: 'generate',
                              child: Row(
                                children: [
                                  const Icon(Icons.shuffle, size: 20),
                                  const SizedBox(width: 8),
                                  Text(loc?.generateRandomPassword ?? '生成随机密码'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'generate_memorable',
                              child: Row(
                                children: [
                                  const Icon(Icons.text_fields, size: 20),
                                  const SizedBox(width: 8),
                                  Text(loc?.generateMemorablePassword ?? '生成易记密码'),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                  helperText: _skipValidation
                      ? (localizations?.passwordGeneratedSkip ?? '已生成密码，跳过强度验证')
                      : (localizations?.passwordStrengthHint ?? '建议包含大小写字母、数字和特殊字符'),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null; // 允许为空（清除密码）
                  }
                  if (!_skipValidation && value.length < 8) {
                    return localizations?.passwordMinLength ?? '密码长度至少8位';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 确认密码（仅在设置密码时显示）
              if (_passwordController.text.isNotEmpty)
                Column(
                  children: [
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        labelText: localizations?.confirmPasswordLabel ?? '确认密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirm = !_obscureConfirm;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (_passwordController.text.isEmpty) {
                          return null;
                        }
                        if (value == null || value.isEmpty) {
                          return localizations?.confirmPasswordRequired ?? '请确认密码';
                        }
                        if (value != _passwordController.text) {
                          return localizations?.passwordMismatch ?? '两次输入的密码不一致';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              // 密码强度指示器（仅在设置密码且未跳过验证时显示）
              if (_passwordController.text.isNotEmpty && !_skipValidation)
                Builder(
                  builder: (context) {
                    final score = _cryptService.getPasswordStrengthScore(
                      _passwordController.text,
                    );
                    Color color;
                    String label;
                    if (score < 40) {
                      color = Colors.red;
                      label = localizations?.passwordWeak ?? '弱';
                    } else if (score < 70) {
                      color = Colors.orange;
                      label = localizations?.passwordMedium ?? '中';
                    } else {
                      color = Colors.green;
                      label = localizations?.passwordStrong ?? '强';
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(localizations?.passwordStrength ?? '密码强度: '),
                            Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: score / 100,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ],
                    );
                  },
                ),

              const SizedBox(height: 24),

              // 操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text(localizations?.cancel ?? '取消'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _savePassword,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_hasPassword ? (localizations?.save ?? '保存') : (localizations?.set ?? '设置')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

