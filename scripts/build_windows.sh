#!/bin/bash

# Windows 构建脚本
# 构建 Windows Release 版本

set -e

# 切换到脚本所在目录的父目录（项目根目录）
cd "$(dirname "$0")/.."

echo "=========================================="
echo "构建 Windows Release 版本"
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

# 启用 Windows 桌面支持
echo "启用 Windows 桌面支持..."
flutter config --enable-windows-desktop

# 清理构建
echo "清理构建..."
flutter clean

# 获取依赖
echo "获取依赖..."
flutter pub get

# 构建 Release 版本
echo "构建 Windows Release 版本..."
flutter build windows --release

# 检查构建产物
EXE_PATH="build/windows/runner/Release/key_core.exe"
if [ ! -f "$EXE_PATH" ]; then
    echo "错误: 构建失败，可执行文件不存在"
    exit 1
fi

echo "=========================================="
echo "构建完成！"
echo "=========================================="
echo "可执行文件: ${EXE_PATH}"
echo "完整目录: build/windows/runner/Release/"
echo "=========================================="
echo ""
echo "注意: Windows 版本已实现但未测试"
echo "参考文档: docs/cross_platform.md"
