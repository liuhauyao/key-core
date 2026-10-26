import '../models/ai_key.dart';

/// 密钥掩码预览（只含前缀与后 4 位，非机密）。
///
/// 设置主密码后，数据库里的 key_value 是加密后的 JSON（以 `{` 开头，nonce 在 JSON 内，keyNonce 列为空）。
/// 旧实现直接取存储值的后 4 位，显示成密文尾巴（如 `····=="}`）。
/// 现在：加密值只用 [KeyMaskCache] 里由解密结果算出的掩码；拿不到就只显示圆点，绝不显示密文片段。
class KeyMaskCache {
  KeyMaskCache._();

  /// 键为 `id#entryIndex`：同一卡片的多把子密钥各自缓存掩码
  static final Map<String, String> _byId = {};

  static String _k(int id, int entryIndex) => '$id#$entryIndex';

  static void put(int id, int entryIndex, String plain) =>
      _byId[_k(id, entryIndex)] = maskPlain(plain);

  static String? get(int id, int entryIndex) => _byId[_k(id, entryIndex)];

  static void clear() => _byId.clear();
}

const _dots = '••••';

/// 单个密钥值是否以密文形态存储（密文 JSON 以 `{` 开头，nonce 在 JSON 内）
bool isEncryptedValue(String value) => value.trimLeft().startsWith('{');

bool isEncryptedKeyValue(AIKey key) =>
    key.keyNonce != null || isEncryptedValue(key.keyValue);

/// 由明文算掩码：`sk-••••abcd`
String maskPlain(String plain) {
  final v = plain.trim();
  if (v.length < 8) return '$_dots$_dots';
  final dash = v.indexOf('-');
  final prefix = (dash > 0 && dash <= 6) ? v.substring(0, dash + 1) : '';
  return '$prefix$_dots${v.substring(v.length - 4)}';
}

/// 指定子密钥的掩码（[entryIndex] 缺省取卡片当前密钥）。
///
/// 加密值只用缓存里由解密结果算出的掩码；拿不到就只显示圆点。
String maskKeyForKey(AIKey key, [int? entryIndex]) {
  final idx = entryIndex ?? key.normalizedActiveIndex;
  final entries = key.keyEntries;
  final safeIdx = idx.clamp(0, entries.length - 1);
  final value = entries[safeIdx].value;
  if (isEncryptedKeyValue(key) || isEncryptedValue(value)) {
    return (key.id != null ? KeyMaskCache.get(key.id!, safeIdx) : null) ??
        '$_dots$_dots';
  }
  return maskPlain(value);
}

/// 卡片 / 工具页 / 菜单使用的掩码（默认取当前密钥）
String maskKeyForCard(AIKey key) => maskKeyForKey(key);
