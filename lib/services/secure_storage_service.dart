import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: const AndroidOptions(encryptedSharedPreferences: true),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'Key Core',
    ),
    wOptions: const WindowsOptions(useBackwardCompatibility: false),
    lOptions: const LinuxOptions(),
    mOptions: const MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// 处理 Keychain 错误，提供友好的错误信息
  String _handleKeychainError(dynamic error) {
    final errorString = error.toString();
    if (errorString.contains('-34018') || 
        errorString.contains('entitlement') ||
        errorString.contains('signing')) {
      return 'Keychain 访问需要代码签名。请在 Xcode 中配置签名：\n'
          '1. 打开 macos/Runner.xcworkspace\n'
          '2. 选择 Runner target → Signing & Capabilities\n'
          '3. 勾选 "Automatically manage signing"\n'
          '4. 选择你的开发团队（可使用免费 Apple ID）\n\n'
          '或者暂时移除 keychain-access-groups 权限（不推荐）';
    }
    return errorString;
  }

  Future<void> storeMasterPasswordHash(String hash) async {
    try {
      await _storage.write(key: 'master_password_hash', value: hash);
    } catch (e) {
      if (Platform.isMacOS) {
        throw Exception(_handleKeychainError(e));
      }
      rethrow;
    }
  }

  Future<String?> getMasterPasswordHash() async {
    return await _storage.read(key: 'master_password_hash');
  }

  Future<bool> hasMasterPassword() async {
    return await _storage.containsKey(key: 'master_password_hash');
  }

  Future<void> deleteMasterPassword() async {
    await _storage.delete(key: 'master_password_hash');
  }

  Future<void> storeEncryptionKey(String encryptionKey) async {
    try {
      await _storage.write(key: 'encryption_key', value: encryptionKey);
    } catch (e) {
      if (Platform.isMacOS) {
        throw Exception(_handleKeychainError(e));
      }
      rethrow;
    }
  }

  Future<String?> getEncryptionKey() async {
    return await _storage.read(key: 'encryption_key');
  }

  Future<void> deleteEncryptionKey() async {
    await _storage.delete(key: 'encryption_key');
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
