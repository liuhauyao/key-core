// 开源版专用的 UI 链接常量（form_v3.md §10）。
//
// ⚠️ 只能在 `if (Edition.isOss)` 分支里引用：Edition.isAppStore 是编译期常量，
// App Store 构建会把这些分支连同字符串一起 tree-shake 掉；
// scripts/build_macos_appstore.sh 会在产物里 grep 这些地址，残留即构建失败。
class OssLinks {
  OssLinks._();

  static const String repoSlug = 'liuhauyao/key-core';
  static const String repoUrl = 'https://github.com/$repoSlug';
  static const String releasesUrl = '$repoUrl/releases';
  static const String licenseUrl = '$repoUrl/blob/main/LICENSE';
  static const String issuesUrl = '$repoUrl/issues';
  static const String latestReleaseApi = 'https://api.github.com/repos/$repoSlug/releases/latest';
}
