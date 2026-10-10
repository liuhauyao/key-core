// 发行版本（form_v3.md §10）：编译期常量，由构建脚本通过
//   --dart-define=KC_EDITION=appstore|oss
// 传入；未传时为 oss（开发 / 开源构建）。
//
// 取代原先在 main.dart 与 settings_screen.dart 里重复的运行时 `_MASReceipt/receipt` 探测：
// 本地调试的 App Store 构建没有 receipt，旧逻辑会误判；编译期常量也能让 tree-shaking
// 把 App Store 包里与 GitHub 相关的 UI 常量整段剔除。
enum KcEdition { appstore, oss }

class Edition {
  Edition._();

  static const String raw = String.fromEnvironment('KC_EDITION', defaultValue: 'oss');

  static const bool isAppStore = raw == 'appstore';
  static const bool isOss = !isAppStore;

  static KcEdition get current => isAppStore ? KcEdition.appstore : KcEdition.oss;

  /// App Store 商品 ID（Apple ID 6755545736，Bundle ID cn.dlrow.keycore，SKU keycore-mac-1.0）。
  /// 可通过 --dart-define=KC_APPSTORE_ID 覆盖。
  static const String appStoreId = String.fromEnvironment('KC_APPSTORE_ID', defaultValue: '6755545736');

  /// 在 App Store 中打开本应用的地址（仅 App Store 版使用）
  static String get appStoreUrl => 'https://apps.apple.com/app/id$appStoreId';
}
