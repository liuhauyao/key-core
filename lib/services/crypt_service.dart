import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class CryptService {
  static const int _iterations = 10000;
  static const int _keySize = 32;
  static const String _salt = 'matrees-ai-key-salt-2024';

  Future<String> generateEncryptionKey(String masterPassword) async {
    // 使用 PBKDF2 算法生成密钥
    var key = Uint8List.fromList(utf8.encode(masterPassword + _salt));
    for (int i = 0; i < _iterations; i++) {
      final digest = sha256.convert(key);
      key = Uint8List.fromList(digest.bytes);
    }
    
    // 截取前32字节作为AES-256密钥
    final keyBytes = key.take(_keySize).toList();
    return base64Encode(keyBytes);
  }

  Future<String> encrypt(String data, String encryptionKey) async {
    final key = Key.fromBase64(encryptionKey);
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    final encrypted = encrypter.encrypt(data, iv: iv);
    return jsonEncode({
      'data': encrypted.base64,
      'iv': iv.base64,
    });
  }

  Future<String> decrypt(String encryptedData, String encryptionKey) async {
    final key = Key.fromBase64(encryptionKey);
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));

    final payload = jsonDecode(encryptedData);
    final iv = IV.fromBase64(payload['iv']);
    final data = Encrypted.fromBase64(payload['data']);

    return encrypter.decrypt(data, iv: iv);
  }

  Future<String> hashPassword(String password) async {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<bool> verifyPassword(String password, String hash) async {
    final inputHash = await hashPassword(password);
    return inputHash == hash;
  }

  bool validatePasswordStrength(String password) {
    if (password.length < 8) return false;
    if (!password.contains(RegExp(r'[a-z]'))) return false;
    if (!password.contains(RegExp(r'[A-Z]'))) return false;
    if (!password.contains(RegExp(r'[0-9]'))) return false;
    if (!password.contains(RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]'))) {
      return false;
    }
    return true;
  }

  int getPasswordStrengthScore(String password) {
    int score = 0;
    if (password.length >= 8) score += 20;
    if (password.length >= 12) score += 10;
    if (password.length >= 16) score += 10;
    if (password.contains(RegExp(r'[a-z]'))) score += 15;
    if (password.contains(RegExp(r'[A-Z]'))) score += 15;
    if (password.contains(RegExp(r'[0-9]'))) score += 15;
    if (password.contains(RegExp(r'[!@#\$%^&*()_+\-=\[\]{}|;:,.<>?]'))) {
      score += 15;
    }
    return score.clamp(0, 100);
  }

  IV generateIV() {
    return IV.fromSecureRandom(16);
  }
}
