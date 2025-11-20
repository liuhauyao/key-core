#!/bin/bash

# 修复应用权限脚本
# 用于移除 macOS 隔离属性，允许运行未签名的应用

set -e

APP_NAME="密枢"
APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
    # 默认使用构建目录中的应用
    APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ 错误: 应用不存在: $APP_PATH"
    echo "用法: $0 [应用路径]"
    exit 1
fi

echo "🔓 移除隔离属性..."
xattr -cr "$APP_PATH"

echo "✅ 完成！现在可以运行应用了"
echo ""
echo "如果仍然无法运行，请尝试："
echo "1. 右键点击应用 > 打开"
echo "2. 或者在系统设置 > 隐私与安全性 中允许运行"

