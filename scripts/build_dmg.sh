#!/bin/bash

# DMG 打包脚本
# 用于将 macOS 应用打包成 DMG 文件

set -e

APP_NAME="密枢"
APP_VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
BUILD_DIR="build/macos/Build/Products/Release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="build/dmg"
DMG_TEMP_DIR="${DMG_DIR}/temp"

# 检查应用是否存在，如果不存在，尝试从 DerivedData 复制
if [ ! -d "$APP_PATH" ] || [ ! -f "$APP_PATH/Contents/MacOS/Runner" ]; then
    echo "⚠️  应用不存在或为空，尝试从 Xcode DerivedData 查找..."
    
    # 查找 DerivedData 中的应用
    DERIVED_DATA_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "${APP_NAME}.app" -path "*/Build/Products/Release/*" -type d 2>/dev/null | head -1)
    
    if [ -n "$DERIVED_DATA_APP" ] && [ -f "$DERIVED_DATA_APP/Contents/MacOS/Runner" ]; then
        echo "✅ 在 DerivedData 中找到应用: $DERIVED_DATA_APP"
        echo "📦 复制应用到项目目录..."
        mkdir -p "$BUILD_DIR"
        cp -R "$DERIVED_DATA_APP" "$APP_PATH"
        echo "✅ 应用已复制"
    else
        echo "❌ 错误: 应用文件不存在"
        echo "请先运行: flutter build macos --release"
        echo "或者在 Xcode 中构建 Release 版本"
        exit 1
    fi
fi

# 验证应用完整性
if [ ! -f "$APP_PATH/Contents/MacOS/Runner" ]; then
    echo "❌ 错误: 应用可执行文件不存在"
    exit 1
fi

# 清理旧的 DMG 目录
rm -rf "$DMG_DIR"
mkdir -p "$DMG_TEMP_DIR"

# 复制应用到临时目录
cp -R "$APP_PATH" "$DMG_TEMP_DIR/"

# 创建 Applications 链接
ln -s /Applications "$DMG_TEMP_DIR/Applications"

# 创建 DMG
echo "正在创建 DMG 文件..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP_DIR" \
    -ov -format UDZO \
    "$DMG_DIR/$DMG_NAME"

# 清理临时目录
rm -rf "$DMG_TEMP_DIR"

echo "✅ DMG 文件已创建: $DMG_DIR/$DMG_NAME"

