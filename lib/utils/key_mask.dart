import '../models/ai_key.dart';

/// 密钥掩码预览（只含前缀与后 4 位，非机密）。
///
/// 设置主密码后，数据库里的 key_value 是加密后的 JSON（以 `{` 开头，nonce 在 JSON 内，keyNonce 列为空）。
/// 旧实现直接取存储值的后 4 位，显示成密文尾巴（如 `····=="}`）。
/// 现在：加密值只用 [KeyMaskCache] 里由解密结果算出的掩码；拿不到就只显示圆点，绝不显示密文片段。
class KeyMaskCache {
  KeyMaskCache._();
  static final Map<int, String> _byId = {};

  static void put(int id, String plain) => _byId[id] = maskPlain(plain);
  static String? get(int id) => _byId[id];
  static void clear() => _byId.clear();
}

const _dots = '••••';

bool isEncryptedKeyValue(AIKey key) => key.keyNonce != null || key.keyValue.trimLeft().startsWith('{');

/// 由明文算掩码：`sk-••••abcd`
String maskPlain(String plain) {
  final v = plain.trim();
  if (v.length < 8) return '$_dots$_dots';
  final dash = v.indexOf('-');
  final prefix = (dash > 0 && dash <= 6) ? v.substring(0, dash + 1) : '';
  return '$prefix$_dots${v.substring(v.length - 4)}';
}

/// 卡片 / 工具页 / 菜单使用的掩码
String maskKeyForCard(AIKey key) {
  if (isEncryptedKeyValue(key)) {
    return (key.id != null ? KeyMaskCache.get(key.id!) : null) ?? '$_dots$_dots';
  }
  return maskPlain(key.keyValue);
}
