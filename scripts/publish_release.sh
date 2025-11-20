#!/bin/bash

# GitHub Release 发布脚本
# 用于创建 GitHub Release 并上传 DMG 文件

set -e

VERSION="v1.0.0"
DMG_FILE="build/dmg/密枢-1.0.0.dmg"
REPO="liuhauyao/ai-key-manager"

echo "🚀 准备发布 GitHub Release: $VERSION"
echo ""

# 检查 DMG 文件是否存在
if [ ! -f "$DMG_FILE" ]; then
    echo "❌ 错误: DMG 文件不存在: $DMG_FILE"
    echo "请先运行: ./scripts/build_dmg.sh"
    exit 1
fi

echo "✅ DMG 文件存在: $DMG_FILE"
echo "📦 文件大小: $(ls -lh "$DMG_FILE" | awk '{print $5}')"
echo ""

# 检查 GitHub CLI
if command -v gh &> /dev/null; then
    echo "✅ 检测到 GitHub CLI，使用 CLI 发布..."
    echo ""
    
    # 检查是否已登录
    if ! gh auth status &> /dev/null; then
        echo "⚠️  未登录 GitHub CLI，请先登录："
        echo "   gh auth login"
        exit 1
    fi
    
    # 创建 Release
    echo "📝 创建 Release..."
    gh release create "$VERSION" \
        --title "v1.0.0 - 密枢" \
        --notes-file RELEASE_NOTES_v1.0.0.md \
        "$DMG_FILE"
    
    echo ""
    echo "✅ Release 已创建！"
    echo "🔗 访问: https://github.com/$REPO/releases/tag/$VERSION"
    
else
    echo "⚠️  GitHub CLI 未安装，请手动发布："
    echo ""
    echo "1. 访问: https://github.com/$REPO/releases/new"
    echo "2. 选择标签: $VERSION"
    echo "3. 标题: v1.0.0 - 密枢"
    echo "4. 描述: 复制 RELEASE_NOTES_v1.0.0.md 的内容"
    echo "5. 上传文件: $DMG_FILE"
    echo "6. 点击 'Publish release'"
    echo ""
    echo "或者安装 GitHub CLI:"
    echo "   brew install gh"
    echo "   gh auth login"
    echo ""
    echo "然后重新运行此脚本。"
fi



