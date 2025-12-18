#!/bin/bash

# Linux 构建脚本
# 构建 Linux Release 版本

set -e

# 切换到脚本所在目录的父目录（项目根目录）
cd "$(dirname "$0")/.."

echo "=========================================="
echo "构建 Linux Release 版本"
echo "=========================================="

# 检查 Flutter
if ! command -v flutter &> /dev/null; then
    echo "错误: Flutter 未安装或未添加到 PATH"
    exit 1
fi

# 获取版本号
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
echo "版本号: ${VERSION}"
echo ""

# 启用 Linux 桌面支持
echo "启用 Linux 桌面支持..."
flutter config --enable-linux-desktop

# 清理构建
echo "清理构建..."
flutter clean

# 生成图标列表配置文件
echo "生成图标列表配置文件..."
dart scripts/generate_icon_list.dart

# 获取依赖
echo "获取依赖..."
flutter pub get

# 构建 Release 版本
echo "构建 Linux Release 版本..."
flutter build linux --release

# 检查构建产物
BUNDLE_DIR="build/linux/x64/release/bundle"
if [ ! -d "$BUNDLE_DIR" ]; then
    echo "错误: 构建失败，bundle 目录不存在"
    exit 1
fi

echo "=========================================="
echo "构建完成！"
echo "=========================================="
echo "Bundle 目录: ${BUNDLE_DIR}"
echo "=========================================="
echo ""
echo "注意: Linux 版本已实现但未测试"
echo "需要桌面环境支持系统托盘 (GNOME/KDE/XFCE)"

