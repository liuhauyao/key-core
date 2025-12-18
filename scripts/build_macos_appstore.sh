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

# 1. 清理构建
echo "1. 清理构建..."
flutter clean > /dev/null 2>&1 || true
rm -rf macos/build 2>/dev/null || true

# 2. 生成图标列表配置文件
echo "2. 生成图标列表配置文件..."
dart scripts/generate_icon_list.dart > /dev/null 2>&1

# 3. 获取依赖
echo "3. 获取 Flutter 依赖..."
flutter pub get > /dev/null 2>&1

# 4. 清理 sqlite3 缓存
echo "4. 清理 sqlite3 构建缓存..."
rm -rf ~/.pub-cache/hosted/pub.flutter-io.cn/sqlite3-*/.dart_tool 2>/dev/null || true
rm -rf ~/.pub-cache/hosted/pub.dev/sqlite3-*/.dart_tool 2>/dev/null || true
rm -rf .dart_tool/hooks_runner/sqlite3 2>/dev/null || true

# 5. 先运行 Flutter 构建来生成必要的文件（这会生成 Flutter-Generated.xcconfig 等）
echo "5. 预构建 Flutter 文件（生成必要的资源文件）..."
flutter build macos --release > /tmp/flutter_build.log 2>&1 || {
    echo "警告: Flutter 构建失败，但继续..."
    cat /tmp/flutter_build.log | tail -20
}

# 6. 确保 ephemeral 目录存在
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



