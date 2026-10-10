#!/bin/bash
# macOS GitHub Release 构建脚本
# 构建 macOS Release → branded DMG → 可选替换 /Applications 并启动
# 用法: ./scripts/build_macos_github.sh
#       NO_REPLACE=1 ./scripts/build_macos_github.sh    # 跳过本地替换

set -e
cd -P "$(dirname "$0")/.."

# Xcode 在带空格的外置磁盘路径上时，Flutter 会截断 clang 路径；
# Xcode 27 的 lipo 也不能一次校验多个架构。这两个包装脚本只影响本次构建。
export PATH="$(cd "$(dirname "$0")" && pwd)/macos-toolchain:${PATH}"

echo "━━━ macOS GitHub Release ━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查 Flutter
command -v flutter &> /dev/null || { echo "错误: Flutter 未安装"; exit 1; }

# GITHUB_PROXY 用于 sqlite3 缓存脚本中的 curl 下载（不设 HTTPS_PROXY，避免干扰 pub.dev）
if [ -z "${GITHUB_PROXY:-}" ] && [ -z "${HTTP_PROXY:-}" ] && [ -z "${HTTPS_PROXY:-}" ]; then
    export GITHUB_PROXY=https://ghproxy.com
fi

VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
APP_DISPLAY_NAME="Key Core"
DMG_NAME="${APP_DISPLAY_NAME}-${VERSION}"

# 1. SQLite 缓存
echo "  • 初始化 SQLite 缓存"
source "$(dirname "$0")/setup_sqlite_cache.sh" > /dev/null 2>&1 || true
# 该脚本被 source 时会打开 set -u 和 pipefail，恢复为本脚本的 set -e
set +u
set +o pipefail
set -e

# 2. 图标配置
echo "  • 生成图标配置"
dart scripts/generate_icon_list.dart > /dev/null 2>&1

# 3. 依赖检查
echo "  • 检查依赖"
flutter pub get > /dev/null 2>&1

# 4. 构建（重试 3 次）
echo "  • 构建应用"
MAX_RETRIES=3
RETRY_COUNT=0
BUILD_SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$BUILD_SUCCESS" = false ]; do
    echo "    尝试 $((RETRY_COUNT + 1))/$MAX_RETRIES..."
    # 开源版：KC_EDITION=oss（GitHub Releases 应用内更新，lib/config/edition.dart）
    if flutter build macos --release --dart-define=KC_EDITION=oss > /tmp/flutter_build.log 2>&1; then
        BUILD_SUCCESS=true
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if grep -q "sqlite3.*timeout\|sqlite3.*HandshakeException\|sqlite3.*Connection terminated\|Operation timed out.*github.com\|HandshakeException" /tmp/flutter_build.log; then
            [ $RETRY_COUNT -lt $MAX_RETRIES ] && {
                echo "    网络超时，清理缓存重试..."
                rm -rf .dart_tool/hooks_runner/sqlite3 2>/dev/null || true
                sleep 3
                continue
            }
            echo "错误: sqlite3 下载失败，请检查网络或设置代理后重试"
            exit 1
        else
            echo ""
            echo "构建失败："
            grep -E "contains errors|must be an absolute path|does not exist|failed:|Failed to package|PhaseScriptExecution failed|BUILD FAILED" /tmp/flutter_build.log | grep -v "Stale file" | head -30
            echo ""
            echo "日志末尾："
            tail -15 /tmp/flutter_build.log
            exit 1
        fi
    fi
done

# 检查产物
APP_PATH="build/macos/Build/Products/Release/${APP_DISPLAY_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
    APP_PATH=$(find build/macos/Build/Products/Release -name "*.app" -type d | head -1)
fi
if [ ! -d "$APP_PATH" ]; then
    echo "错误: 构建产物不存在"
    exit 1
fi

echo "  ✓ 构建完成: ${APP_PATH}"

# 5. 创建 branded DMG（create-dmg: 背景、图标布局、Applications 拖拽链接）
echo "  • 创建 DMG"
DMG_DIR="build/macos-github"
mkdir -p "$DMG_DIR/temp"
cp -R "$APP_PATH" "$DMG_DIR/temp/"
xattr -cr "$APP_PATH" || true

DMG_FILE="$DMG_DIR/${DMG_NAME}.dmg"

source "$(dirname "$0")/lib/release-lib.sh"
create_branded_dmg "$DMG_DIR/temp" "$DMG_FILE" "$APP_DISPLAY_NAME" || {
    # 回退：手动补 Applications 后 hdiutil
    ln -sf /Applications "$DMG_DIR/temp/Applications"
    hdiutil create -volname "$APP_DISPLAY_NAME" \
        -srcfolder "$DMG_DIR/temp" \
        -ov -format UDZO "$DMG_FILE" > /dev/null 2>&1
}
echo "  ✓ DMG: ${DMG_FILE}"

# create-dmg AppleScript 可能打开 Finder 窗口，关掉它
osascript -e 'tell application "Finder" to close (every window whose name contains "Key Core" or name contains "dmg.")' 2>/dev/null || true

rm -rf "$DMG_DIR/temp"

# ── 本地替换 ──
if [[ "$(uname -s)" != "Darwin" ]] || [[ -n "${NO_REPLACE:-}" ]]; then
    exit 0
fi

source "$(dirname "$0")/lib/release-lib.sh"
if ! is_keycore_running; then
    exit 0
fi

echo "  • 替换本地应用"
stop_keycore_graceful || { print_error "无法终止 Key Core"; exit 1; }

if package_and_replace "$DMG_FILE" > /dev/null 2>&1; then
    print_info "应用已更新，启动 Key Core..."
    open -a "/Applications/${APP_DISPLAY_NAME}.app"
else
    print_error "应用替换失败"
    exit 1
fi
