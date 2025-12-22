#!/bin/bash

# macOS GitHub Release 构建脚本
# 构建 macOS Release 版本并打包为 DMG（用于 GitHub Releases）
# 
# 使用方法：
#   ./scripts/build_macos_github.sh

set -e

# 切换到脚本所在目录的父目录（项目根目录）
cd "$(dirname "$0")/.."

echo "=========================================="
echo "构建 macOS Release 版本（GitHub Release）"
echo "=========================================="

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "错误: Flutter 未安装或未添加到 PATH"
    exit 1
fi

# 配置 GitHub 代理（如果未设置代理，尝试使用镜像）
if [ -z "$GITHUB_PROXY" ] && [ -z "$HTTP_PROXY" ] && [ -z "$HTTPS_PROXY" ]; then
    echo "检测到未设置代理，尝试使用 GitHub 镜像..."
    export GITHUB_PROXY=https://ghproxy.com
    echo "已设置 GITHUB_PROXY=${GITHUB_PROXY}"
fi

# 获取版本号
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
APP_DISPLAY_NAME="密枢"
DMG_NAME="${APP_DISPLAY_NAME}-${VERSION}"

echo "版本号: ${VERSION}"
echo ""

# 清理构建
echo "清理构建..."
flutter clean

# 清理 sqlite3 构建缓存（避免网络问题）
echo "清理 sqlite3 构建缓存..."
rm -rf ~/.pub-cache/hosted/pub.flutter-io.cn/sqlite3-*/.dart_tool 2>/dev/null || true
rm -rf .dart_tool/hooks_runner/sqlite3 2>/dev/null || true

# 生成图标列表配置文件
echo "生成图标列表配置文件..."
dart scripts/generate_icon_list.dart

# 获取依赖
echo "获取依赖..."
flutter pub get

# 构建 Release 版本（带重试机制）
echo "构建 macOS Release 版本..."
MAX_RETRIES=3
RETRY_COUNT=0
BUILD_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$BUILD_SUCCESS" = false ]; do
    echo "尝试构建 ($((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    
    # 执行构建并捕获输出
    if flutter build macos --release > /tmp/flutter_build.log 2>&1; then
        BUILD_SUCCESS=true
        echo "构建成功！"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        
        # 检查是否是 sqlite3 网络超时问题
        if grep -q "sqlite3.*timeout\|Operation timed out.*github.com" /tmp/flutter_build.log; then
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "检测到 sqlite3 网络超时，清理缓存后重试..."
                rm -rf ~/.pub-cache/hosted/pub.flutter-io.cn/sqlite3-*/.dart_tool 2>/dev/null || true
                rm -rf .dart_tool/hooks_runner/sqlite3 2>/dev/null || true
                sleep 3
            else
                echo ""
                echo "=========================================="
                echo "错误: sqlite3 下载失败，已重试 $MAX_RETRIES 次"
                echo "=========================================="
                echo "建议解决方案："
                echo "1. 检查网络连接"
                echo "2. 设置代理: export HTTP_PROXY=http://your-proxy:port"
                echo "3. 或使用 GitHub 镜像: export GITHUB_PROXY=https://ghproxy.com"
                echo "4. 然后重新运行构建脚本"
                echo ""
                cat /tmp/flutter_build.log | tail -20
                exit 1
            fi
        else
            echo ""
            echo "=========================================="
            echo "构建失败（非网络问题）"
            echo "=========================================="
            cat /tmp/flutter_build.log | tail -30
            exit 1
        fi
    fi
done

if [ "$BUILD_SUCCESS" = false ]; then
    echo "构建失败"
    exit 1
fi

# 检查构建产物
APP_PATH="build/macos/Build/Products/Release/${APP_DISPLAY_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    APP_PATH=$(find build/macos/Build/Products/Release -name "*.app" -type d | head -1)
    if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
        echo "错误: 构建失败，应用文件不存在"
        exit 1
    fi
fi

echo "构建成功！应用位置: ${APP_PATH}"

# 修复应用权限
echo "修复应用权限..."
xattr -cr "$APP_PATH" || true

# 创建 DMG
echo "创建 DMG 文件..."
DMG_DIR="build/dmg"
mkdir -p "$DMG_DIR/temp"
cp -R "$APP_PATH" "$DMG_DIR/temp/"
ln -s /Applications "$DMG_DIR/temp/Applications"

DMG_FILE="$DMG_DIR/${DMG_NAME}.dmg"
hdiutil create -volname "$APP_DISPLAY_NAME" \
    -srcfolder "$DMG_DIR/temp" \
    -ov -format UDZO \
    "$DMG_FILE"

rm -rf "$DMG_DIR/temp"

echo "=========================================="
echo "构建完成！"
echo "=========================================="
echo "应用: ${APP_PATH}"
echo "DMG: ${DMG_FILE}"
echo "=========================================="
























