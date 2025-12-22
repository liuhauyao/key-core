#!/bin/bash

# 修复框架结构脚本（Xcode Build Phase 版本）
# 用于修复 macOS 框架的符号链接结构，符合 App Store 要求
# 解决 ITMS-90291: Malformed Framework 错误
# 此脚本在 Xcode Build Phase 中自动运行

set -e

# 使用 Xcode 环境变量获取应用路径
APP_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "⚠️  警告: 应用不存在: $APP_PATH"
    exit 0
fi

FRAMEWORKS_DIR="${APP_PATH}/Contents/Frameworks"

if [ ! -d "$FRAMEWORKS_DIR" ]; then
    # 如果没有框架，直接退出
    exit 0
fi

# 修复所有框架
for FRAMEWORK in "$FRAMEWORKS_DIR"/*.framework; do
    if [ ! -d "$FRAMEWORK" ]; then
        continue
    fi
    
    FRAMEWORK_NAME=$(basename "$FRAMEWORK" .framework)
    
    # 检查 Versions 目录是否存在
    VERSIONS_DIR="${FRAMEWORK}/Versions"
    if [ ! -d "$VERSIONS_DIR" ]; then
        continue
    fi
    
    # 查找 Current 版本
    CURRENT_VERSION=""
    if [ -L "${VERSIONS_DIR}/Current" ]; then
        CURRENT_VERSION=$(readlink "${VERSIONS_DIR}/Current")
        CURRENT_VERSION=$(basename "$CURRENT_VERSION")
    else
        # 如果没有 Current 符号链接，查找第一个版本目录
        for VERSION in "$VERSIONS_DIR"/*; do
            if [ -d "$VERSION" ] && [ ! -L "$VERSION" ]; then
                CURRENT_VERSION=$(basename "$VERSION")
                break
            fi
        done
    fi
    
    if [ -z "$CURRENT_VERSION" ]; then
        continue
    fi
    
    CURRENT_VERSION_DIR="${VERSIONS_DIR}/${CURRENT_VERSION}"
    
    # 创建或修复 Versions/Current 符号链接
    if [ ! -L "${VERSIONS_DIR}/Current" ]; then
        (cd "$VERSIONS_DIR" && ln -sf "$CURRENT_VERSION" Current)
    fi
    
    # 检查 Resources 目录是否存在
    RESOURCES_DIR="${CURRENT_VERSION_DIR}/Resources"
    if [ ! -d "$RESOURCES_DIR" ]; then
        mkdir -p "$RESOURCES_DIR"
    fi
    
    # 创建或修复 Resources 符号链接
    FRAMEWORK_RESOURCES="${FRAMEWORK}/Resources"
    if [ ! -L "$FRAMEWORK_RESOURCES" ]; then
        if [ -e "$FRAMEWORK_RESOURCES" ]; then
            rm -rf "$FRAMEWORK_RESOURCES"
        fi
        (cd "$FRAMEWORK" && ln -sf "Versions/Current/Resources" Resources)
    else
        # 验证符号链接是否正确
        LINK_TARGET=$(readlink "$FRAMEWORK_RESOURCES")
        if [ "$LINK_TARGET" != "Versions/Current/Resources" ]; then
            rm "$FRAMEWORK_RESOURCES"
            (cd "$FRAMEWORK" && ln -sf "Versions/Current/Resources" Resources)
        fi
    fi
    
    # 创建或修复主可执行文件符号链接
    FRAMEWORK_BINARY="${FRAMEWORK}/${FRAMEWORK_NAME}"
    if [ ! -L "$FRAMEWORK_BINARY" ] && [ ! -f "$FRAMEWORK_BINARY" ]; then
        (cd "$FRAMEWORK" && ln -sf "Versions/Current/${FRAMEWORK_NAME}" "$FRAMEWORK_NAME")
    fi
done
























