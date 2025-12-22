#!/bin/bash

# 确保 dSYM 文件被正确包含在 Archive 中
# 这个脚本应该在 Archive 后运行，或者在 Xcode 的 Archive Post-Actions 中运行

set -e

ARCHIVE_PATH="${ARCHIVE_PATH:-$1}"

if [ -z "$ARCHIVE_PATH" ]; then
    echo "错误: 请提供 Archive 路径"
    echo "用法: $0 <archive_path>"
    exit 1
fi

DSYMS_DIR="$ARCHIVE_PATH/dSYMs"
APP_PATH="$ARCHIVE_PATH/Products/Applications/密枢.app"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"

echo "检查 dSYM 文件..."
echo "Archive 路径: $ARCHIVE_PATH"
echo "dSYMs 目录: $DSYMS_DIR"
echo "应用路径: $APP_PATH"

# 确保 dSYMs 目录存在
mkdir -p "$DSYMS_DIR"

# 检查主应用的 dSYM
APP_DSYM="$DSYMS_DIR/密枢.app.dSYM"
if [ ! -d "$APP_DSYM" ]; then
    echo "警告: 主应用的 dSYM 不存在: $APP_DSYM"
    echo "请确保在 Xcode Build Settings 中设置了 DEBUG_INFORMATION_FORMAT = dwarf-with-dsym"
else
    echo "✓ 主应用的 dSYM 存在: $APP_DSYM"
fi

# 检查 Flutter 框架的 dSYM
if [ -d "$FRAMEWORKS_DIR" ]; then
    echo ""
    echo "检查 Flutter 框架的 dSYM..."
    
    for framework in "$FRAMEWORKS_DIR"/*.framework; do
        if [ -d "$framework" ]; then
            framework_name=$(basename "$framework" .framework)
            framework_dsym="$DSYMS_DIR/${framework_name}.framework.dSYM"
            
            if [ ! -d "$framework_dsym" ]; then
                echo "警告: 框架 $framework_name 的 dSYM 不存在: $framework_dsym"
                
                # 尝试从 Flutter SDK 复制 dSYM
                if [ -n "$FLUTTER_ROOT" ] && [ -d "$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64" ]; then
                    flutter_dsym="$FLUTTER_ROOT/bin/cache/artifacts/engine/darwin-x64/${framework_name}.framework.dSYM"
                    if [ -d "$flutter_dsym" ]; then
                        echo "从 Flutter SDK 复制 dSYM: $flutter_dsym -> $framework_dsym"
                        cp -R "$flutter_dsym" "$DSYMS_DIR/"
                        echo "✓ 已复制 $framework_name 的 dSYM"
                    fi
                fi
            else
                echo "✓ 框架 $framework_name 的 dSYM 存在: $framework_dsym"
            fi
        fi
    done
fi

echo ""
echo "dSYM 检查完成！"
echo ""
echo "要验证 dSYM 文件，请运行:"
echo "  dwarfdump --uuid $DSYMS_DIR/*.dSYM"





