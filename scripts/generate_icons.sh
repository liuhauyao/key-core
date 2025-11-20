#!/bin/bash

# 图标生成脚本
# 从源图标生成 macOS 应用所需的所有尺寸

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 源图标路径
SOURCE_ICON="assets/icons/icon.png"
ICONSET_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"

# 检查源图标是否存在
if [ ! -f "$SOURCE_ICON" ]; then
    echo -e "${RED}错误: 源图标文件不存在: $SOURCE_ICON${NC}"
    exit 1
fi

# 检查 iconset 目录是否存在
if [ ! -d "$ICONSET_DIR" ]; then
    echo -e "${RED}错误: 图标目录不存在: $ICONSET_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}开始生成应用图标...${NC}"

# 检查是否安装了 sips (macOS 内置工具)
if ! command -v sips &> /dev/null; then
    echo -e "${RED}错误: 未找到 sips 工具（macOS 内置工具）${NC}"
    exit 1
fi

# 定义需要生成的图标尺寸 (格式: 文件名:尺寸)
ICON_CONFIGS=(
    "app_icon_16.png:16"
    "app_icon_32.png:32"
    "app_icon_64.png:64"
    "app_icon_128.png:128"
    "app_icon_256.png:256"
    "app_icon_512.png:512"
    "app_icon_1024.png:1024"
)

# 生成所有尺寸的图标
for config in "${ICON_CONFIGS[@]}"; do
    filename="${config%%:*}"
    size="${config##*:}"
    output_path="$ICONSET_DIR/$filename"
    
    echo -e "${YELLOW}生成 ${size}x${size} -> $filename${NC}"
    
    # 使用 sips 调整图标尺寸
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$output_path" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ 成功生成 $filename${NC}"
    else
        echo -e "${RED}✗ 生成失败 $filename${NC}"
        exit 1
    fi
done

echo -e "${GREEN}所有图标生成完成！${NC}"
echo -e "${YELLOW}提示: 如果图标显示不正确，请清理构建缓存后重新构建应用${NC}"
echo -e "${YELLOW}清理命令: flutter clean && flutter pub get${NC}"

