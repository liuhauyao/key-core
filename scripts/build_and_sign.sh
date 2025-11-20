#!/bin/bash

# 构建和签名脚本
# 用于构建 macOS 应用并处理代码签名

set -e

APP_NAME="密枢"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "📦 开始构建应用..."

# 方法 1: 尝试使用 Flutter 构建
if flutter build macos --release 2>&1 | grep -q "BUILD SUCCEEDED"; then
    echo "✅ Flutter 构建成功"
else
    echo "⚠️  Flutter 构建失败，尝试使用 Xcode 构建..."
    echo "请手动执行以下步骤："
    echo "1. 打开 Xcode: open macos/Runner.xcworkspace"
    echo "2. 选择 Product > Scheme > Runner"
    echo "3. 选择 Product > Destination > My Mac"
    echo "4. 选择 Product > Build Configuration > Release"
    echo "5. 按 Cmd + B 构建"
    echo ""
    echo "构建完成后，运行此脚本继续..."
    read -p "按 Enter 继续..."
fi

# 检查应用是否存在
if [ ! -d "$APP_PATH" ]; then
    echo "❌ 错误: 应用文件不存在: $APP_PATH"
    echo "请先构建应用"
    exit 1
fi

# 检查应用大小
APP_SIZE=$(du -sh "$APP_PATH" | cut -f1)
echo "📦 应用大小: $APP_SIZE"

# 移除隔离属性（允许运行未签名的应用）
echo "🔓 移除隔离属性..."
xattr -cr "$APP_PATH"

# 尝试代码签名（如果失败则跳过）
echo "✍️  尝试代码签名..."
if codesign --force --deep --sign - "$APP_PATH" 2>/dev/null; then
    echo "✅ 代码签名成功"
else
    echo "⚠️  代码签名失败（这是正常的，如果没有开发者证书）"
    echo "应用仍然可以运行，但用户可能需要右键点击并选择'打开'"
fi

# 验证应用
echo "🔍 验证应用..."
if [ -f "$APP_PATH/Contents/MacOS/Runner" ]; then
    echo "✅ 应用可执行文件存在"
else
    echo "❌ 错误: 应用可执行文件不存在"
    exit 1
fi

echo ""
echo "✅ 构建完成！"
echo "应用位置: $APP_PATH"
echo ""
echo "如果应用无法运行，请尝试："
echo "1. 右键点击应用 > 打开"
echo "2. 或者在终端运行: xattr -cr \"$APP_PATH\""

