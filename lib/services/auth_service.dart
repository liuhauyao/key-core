import 'dart:async';
import 'secure_storage_service.dart';
import 'crypt_service.dart';

class AuthService {
  final SecureStorageService _storage = SecureStorageService();
  final CryptService _crypt = CryptService();

  int _failedAttempts = 0;
  bool _isLocked = false;
  static const int _maxAttempts = 5;

  Future<bool> hasMasterPassword() async {
    return await _storage.hasMasterPassword();
  }

  Future<bool> setMasterPassword(String password, {bool skipValidation = false}) async {
    // 如果密码为空，清除主密码设置
    if (password.isEmpty) {
      await clearAuthData();
      return true;
    }

    // 可选：验证密码强度（如果启用）
    if (!skipValidation && !_crypt.validatePasswordStrength(password)) {
      throw AuthException('密码强度不足，建议包含大小写字母、数字和特殊字符');
    }

    final passwordHash = await _crypt.hashPassword(password);
    await _storage.storeMasterPasswordHash(passwordHash);

    final encryptionKey = await _crypt.generateEncryptionKey(password);
    await _storage.storeEncryptionKey(encryptionKey);

    return true;
  }

  Future<AuthResult> verifyPassword(String password) async {
    if (_isLocked) {
      return AuthResult(
        success: false,
        message: '账户已锁定',
        isLocked: true,
      );
    }

    final storedHash = await _storage.getMasterPasswordHash();
    if (storedHash == null) {
      return AuthResult(
        success: false,
        message: '未设置主密码',
      );
    }

    final isValid = await _crypt.verifyPassword(password, storedHash);
    if (isValid) {
      _failedAttempts = 0;
      return AuthResult(success: true, message: '验证成功');
    } else {
      _failedAttempts++;
      final remainingAttempts = _maxAttempts - _failedAttempts;

      if (_failedAttempts >= _maxAttempts) {
        _isLocked = true;
        return AuthResult(
          success: false,
          message: '验证失败次数过多',
          isLocked: true,
        );
      }

      return AuthResult(
        success: false,
        message: '验证失败，剩余尝试次数：$remainingAttempts',
      );
    }
  }

  Future<String?> getEncryptionKey() async {
    return await _storage.getEncryptionKey();
  }

  void lock() {
    _isLocked = true;
  }

  void unlock() {
    _isLocked = false;
    _failedAttempts = 0;
  }

  bool get isLocked => _isLocked;
  int get failedAttempts => _failedAttempts;
  void resetFailedAttempts() => _failedAttempts = 0;

  Future<void> clearAuthData() async {
    await _storage.deleteMasterPassword();
    await _storage.deleteEncryptionKey();
    _failedAttempts = 0;
    _isLocked = false;
  }

  /// 清除所有认证数据（包括 Keychain）
  Future<void> clearAllAuthData() async {
    await _storage.clearAll();
    _failedAttempts = 0;
    _isLocked = false;
  }
}

class AuthResult {
  final bool success;
  final String message;
  final bool isLocked;

  const AuthResult({
    required this.success,
    required this.message,
    this.isLocked = false,
  });
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
