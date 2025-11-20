/// 应用常量定义
class AppConstants {
  /// 应用名称
  static const String appName = 'Key Core';

  /// 应用版本
  static const String appVersion = '1.0.0';

  /// 数据库文件名
  static const String databaseName = 'key_core.db';

  /// 默认自动锁定时间（分钟）
  static const int defaultAutoLockMinutes = 30;

  /// 默认剪贴板自动清空时间（秒）
  static const int defaultClipboardClearSeconds = 30;

  /// 加密迭代次数
  static const int encryptionIterations = 10000;

  /// 加密密钥长度（AES-256）
  static const int encryptionKeySize = 32;

  /// 加密盐值
  static const String encryptionSalt = 'matrees-ai-key-salt-2024';

  /// 密钥大小限制（字符）
  static const int maxKeyValueLength = 2048;

  /// 名称最大长度
  static const int maxNameLength = 100;

  /// 备注最大长度
  static const int maxNotesLength = 500;

  /// 标签最大数量
  static const int maxTagsCount = 10;

  /// 每次密码验证最大尝试次数
  static const int maxPasswordAttempts = 5;

  /// 默认分页大小
  static const int defaultPageSize = 50;

  /// 图标最大大小（字节）
  static const int maxIconSizeBytes = 1024 * 1024; // 1MB
}
