#!/bin/bash

# macOS App Store 构建准备脚本
# 准备 Xcode Archive 环境，用于构建 App Store 版本
# 
# 使用方法：
#   1. 运行此脚本准备环境
#   2. 在 Xcode 中打开项目并选择 AppStore 配置
#   3. Product → Archive

set -e

cd "$(dirname "$0")/.."

echo "=========================================="
echo "准备 Xcode Archive 环境（App Store）"
echo "=========================================="

# 设置 GitHub 代理
export GITHUB_PROXY=https://ghproxy.com
echo "已设置 GITHUB_PROXY=${GITHUB_PROXY}"

# 1. 生成图标列表配置文件
echo "1. 生成图标列表配置文件..."
dart scripts/generate_icon_list.dart > /dev/null 2>&1

# 2. 获取 Flutter 依赖
echo "2. 获取 Flutter 依赖..."
flutter pub get > /dev/null 2>&1

# 3. 初始化 SQLite 缓存
echo "3. 初始化 SQLite 原生库缓存..."
# shellcheck source=setup_sqlite_cache.sh
source "$(dirname "$0")/setup_sqlite_cache.sh" > /dev/null 2>&1 || true

# 4. 清理 sqlite3 构建缓存
echo "4. 清理 sqlite3 构建缓存..."
rm -rf ~/.pub-cache/hosted/pub.flutter-io.cn/sqlite3-*/.dart_tool 2>/dev/null || true
rm -rf ~/.pub-cache/hosted/pub.dev/sqlite3-*/.dart_tool 2>/dev/null || true
rm -rf .dart_tool/hooks_runner/sqlite3 2>/dev/null || true

# 5. 先运行 Flutter 构建来生成必要的文件（这会生成 Flutter-Generated.xcconfig 等）
#    KC_EDITION=appstore 是编译期常量（lib/config/edition.dart）；flutter build 会把 dart-define
#    写进 Flutter-Generated.xcconfig 的 DART_DEFINES，随后 Xcode Archive 沿用同一份配置。
#    KC_APPSTORE_ID：默认 6755545736（代码内置）；如需覆盖可设置环境变量。
echo "5. 预构建 Flutter 文件（KC_EDITION=appstore）..."
DEFINES=(--dart-define=KC_EDITION=appstore)
if [ -n "${KC_APPSTORE_ID:-}" ]; then
    DEFINES+=("--dart-define=KC_APPSTORE_ID=${KC_APPSTORE_ID}")
else
    echo "使用默认 App Store ID 6755545736"
fi
flutter build macos --release "${DEFINES[@]}" > /tmp/flutter_build.log 2>&1 || {
    echo "错误: Flutter 构建失败"
    tail -20 /tmp/flutter_build.log
    exit 1
}

# 5.1 校验 edition 已写入 Xcode 配置（Archive 依赖它）
echo "5.1 校验 KC_EDITION 已写入 Flutter-Generated.xcconfig..."
XC=macos/Flutter/ephemeral/Flutter-Generated.xcconfig
EXPECTED_DEFINE=$(printf 'KC_EDITION=appstore' | base64)
if ! grep -q "DART_DEFINES=.*${EXPECTED_DEFINE}" "$XC" 2>/dev/null; then
    echo "✗ 错误: $XC 中没有 KC_EDITION=appstore（DART_DEFINES），Archive 会构建成开源版"
    exit 1
fi
echo "✓ KC_EDITION=appstore"

# 5.2 产物检查：App Store 版的 Dart 产物里不能残留仓库 / 许可证 / GitHub Releases 链接常量
#     （lib/config/oss_links.dart 只在 Edition.isOss 分支引用，应被 tree-shake 掉）
echo "5.2 检查产物中是否残留开源仓库地址..."
APP_BIN=$(find build/macos/Build/Products/Release -path '*App.framework/Versions/A/App' -type f | head -1)
if [ -z "$APP_BIN" ]; then
    echo "✗ 错误: 找不到 App.framework 产物"
    exit 1
fi
#     注意：配置模板 / 语言包的远程数据地址（raw.githubusercontent.com、api.github.com/repos/…/contents、gitee）
#     两个版本都允许，不在检查范围；这里只检查 UI 链接常量（仓库主页 / 许可证 / issues / releases）。
LEAKS=$(LC_ALL=C grep -a -o -E '(https://)?github\.com/liuhauyao/key-core(/(releases|blob|issues)[^"[:space:]]{0,40})?' "$APP_BIN" | sort -u || true)
if [ -n "$LEAKS" ]; then
    echo "✗ 错误: App Store 产物中发现开源仓库链接："
    echo "$LEAKS"
    exit 1
fi
echo "✓ 产物中没有仓库 / Releases 链接"

# 5. 确保 ephemeral 目录存在
echo "5. 确保 Flutter ephemeral 文件存在..."
mkdir -p macos/Flutter/ephemeral
if [ ! -f "macos/Flutter/ephemeral/FlutterInputs.xcfilelist" ]; then
    touch macos/Flutter/ephemeral/FlutterInputs.xcfilelist
fi
if [ ! -f "macos/Flutter/ephemeral/FlutterOutputs.xcfilelist" ]; then
    touch macos/Flutter/ephemeral/FlutterOutputs.xcfilelist
fi

# 6. 验证文件
echo "6. 验证文件..."
if [ -f "macos/Flutter/ephemeral/FlutterInputs.xcfilelist" ] && [ -f "macos/Flutter/ephemeral/FlutterOutputs.xcfilelist" ]; then
    echo "✓ Flutter ephemeral 文件已生成"
else
    echo "✗ 警告: Flutter ephemeral 文件可能未正确生成"
fi

echo ""
echo "=========================================="
echo "准备完成！"
echo "=========================================="
echo ""
echo "现在可以在 Xcode 中："
echo "1. 打开项目: open macos/Runner.xcworkspace"
echo "2. Product → Clean Build Folder (⇧⌘K)"
echo "3. 选择 AppStore 配置（Scheme → Edit Scheme → Run/Archive → Build Configuration → AppStore）"
echo "4. Product → Archive"
echo ""
echo "⚠️  重要提示："
echo "如果 Archive 时遇到 sqlite3 网络超时，请在 Xcode Scheme 中设置环境变量："
echo "  Product → Scheme → Edit Scheme → Archive → Arguments → Environment Variables"
echo "  添加: GITHUB_PROXY = https://ghproxy.com"
echo "=========================================="



