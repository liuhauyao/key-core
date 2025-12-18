#!/bin/bash

# Key Core 应用数据清理脚本
# 用于清理应用数据，恢复到首次安装状态，便于测试工具目录权限授权流程

# 不使用 set -e，因为某些文件可能不存在，这是正常的
set -u  # 只检查未定义的变量

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Bundle Identifier
BUNDLE_ID="cn.dlrow.keycore"
APP_NAME="Key Core"

# 获取用户主目录
HOME_DIR="$HOME"

# 应用数据目录路径（Flutter 在 macOS 上可能使用不同的目录名）
# getApplicationDocumentsDirectory() 在 macOS 上通常返回：
# ~/Library/Application Support/[app_name] 或
# ~/Library/Containers/[bundle_id]/Data/Library/Application Support/[app_name]
APP_SUPPORT_BASE="$HOME_DIR/Library/Application Support"
APP_DOCUMENTS_DIR="$APP_SUPPORT_BASE/key_core"
APP_DOCUMENTS_DIR_ALT="$APP_SUPPORT_BASE/key-core"

# 沙盒环境下的可能路径
CONTAINER_DIR="$HOME_DIR/Library/Containers/$BUNDLE_ID/Data/Library/Application Support"
CONTAINER_DOCUMENTS_DIR="$CONTAINER_DIR/key_core"
CONTAINER_DOCUMENTS_DIR_ALT="$CONTAINER_DIR/key-core"

PREFERENCES_DIR="$HOME_DIR/Library/Preferences"
PREFS_FILE="$PREFERENCES_DIR/$BUNDLE_ID.plist"

# 数据库文件名
DB_NAME="key_core.db"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Key Core 应用数据清理脚本${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# 确认操作
echo -e "${RED}警告：此操作将删除以下数据：${NC}"
echo "  - 数据库文件（所有密钥数据）"
echo "  - SharedPreferences（所有设置）"
echo "  - UserDefaults（macOS 设置）"
echo "  - 工具目录配置"
echo "  - 首次启动标记"
echo ""
read -p "确认清理所有应用数据？(y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}操作已取消${NC}"
    exit 0
fi

echo ""
echo -e "${GREEN}开始清理应用数据...${NC}"
echo ""

# 1. 清理数据库文件
echo "1. 清理数据库文件..."
DB_PATHS=(
    "$APP_DOCUMENTS_DIR/$DB_NAME"
    "$APP_DOCUMENTS_DIR_ALT/$DB_NAME"
    "$CONTAINER_DOCUMENTS_DIR/$DB_NAME"
    "$CONTAINER_DOCUMENTS_DIR_ALT/$DB_NAME"
)

FOUND_DB=false
for db_path in "${DB_PATHS[@]}"; do
    if [ -f "$db_path" ]; then
        rm -f "$db_path"
        echo -e "   ${GREEN}✓${NC} 已删除: $db_path"
        FOUND_DB=true
    fi
done

if [ "$FOUND_DB" = false ]; then
    echo -e "   ${YELLOW}⚠${NC} 未找到数据库文件（可能已被清理或不存在）"
fi

# 2. 清理 SharedPreferences/UserDefaults
echo "2. 清理 SharedPreferences/UserDefaults..."

# 使用 defaults 命令清理 NSUserDefaults（这是最彻底的方法）
echo "   使用 defaults 命令清理 NSUserDefaults..."
# 先尝试读取，如果存在则删除
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    defaults delete "$BUNDLE_ID" 2>/dev/null
    echo -e "   ${GREEN}✓${NC} 已清理 NSUserDefaults: $BUNDLE_ID"
else
    echo -e "   ${YELLOW}⚠${NC} NSUserDefaults 中无数据或已清理"
fi

# 清理 Flutter 相关的 NSUserDefaults（如果存在）
FLUTTER_DOMAINS=(
    "flutter.$BUNDLE_ID"
    "com.google.Flutter.$BUNDLE_ID"
)

for domain in "${FLUTTER_DOMAINS[@]}"; do
    if defaults read "$domain" >/dev/null 2>&1; then
        defaults delete "$domain" 2>/dev/null
        echo -e "   ${GREEN}✓${NC} 已清理 NSUserDefaults: $domain"
    fi
done

# 删除 Debug 构建的 Preferences 文件
DEBUG_PREFS_FILES=(
    "$PREFERENCES_DIR/$BUNDLE_ID.plist"
    "$PREFERENCES_DIR/flutter.$BUNDLE_ID.plist"
    "$PREFERENCES_DIR/com.google.Flutter.$BUNDLE_ID.plist"
)

FOUND_PREFS=false
for prefs_file in "${DEBUG_PREFS_FILES[@]}"; do
    if [ -f "$prefs_file" ]; then
        rm -f "$prefs_file"
        echo -e "   ${GREEN}✓${NC} 已删除: $prefs_file"
        FOUND_PREFS=true
    fi
done

# 删除 Release/沙盒构建的 Preferences 文件
RELEASE_PREFS_DIR="$CONTAINER_DIR/../Preferences"
RELEASE_PREFS_FILES=(
    "$RELEASE_PREFS_DIR/$BUNDLE_ID.plist"
    "$RELEASE_PREFS_DIR/flutter.$BUNDLE_ID.plist"
    "$RELEASE_PREFS_DIR/com.google.Flutter.$BUNDLE_ID.plist"
)

for prefs_file in "${RELEASE_PREFS_FILES[@]}"; do
    if [ -f "$prefs_file" ]; then
        rm -f "$prefs_file"
        echo -e "   ${GREEN}✓${NC} 已删除: $prefs_file"
        FOUND_PREFS=true
    fi
done

if [ "$FOUND_PREFS" = false ]; then
    echo -e "   ${YELLOW}⚠${NC} 未找到 Preferences 文件（可能已被清理或不存在）"
fi

# 清理所有可能的 NSUserDefaults 相关文件（包括 ByHost）
echo "   清理 NSUserDefaults ByHost 文件..."
BYHOST_PATTERN="$PREFERENCES_DIR/ByHost/$BUNDLE_ID"*
shopt -s nullglob
BYHOST_FILES=($BYHOST_PATTERN)
if [ ${#BYHOST_FILES[@]} -gt 0 ]; then
    rm -f "${BYHOST_FILES[@]}"
    echo -e "   ${GREEN}✓${NC} 已清理 ByHost 文件"
fi
shopt -u nullglob

# 4. 清理应用支持目录中的其他数据（保留目录结构）
echo "3. 清理应用支持目录..."
APP_DIRS=(
    "$APP_DOCUMENTS_DIR"
    "$APP_DOCUMENTS_DIR_ALT"
    "$CONTAINER_DOCUMENTS_DIR"
    "$CONTAINER_DOCUMENTS_DIR_ALT"
)

FOUND_DIR=false
for app_dir in "${APP_DIRS[@]}"; do
    if [ -d "$app_dir" ]; then
        # 删除目录中的所有文件，但保留目录结构
        find "$app_dir" -type f -delete 2>/dev/null || true
        echo -e "   ${GREEN}✓${NC} 已清理: $app_dir"
        FOUND_DIR=true
    fi
done

if [ "$FOUND_DIR" = false ]; then
    echo -e "   ${YELLOW}⚠${NC} 未找到应用支持目录（可能已被清理或不存在）"
fi

# 5. 清理可能的缓存目录
echo "4. 清理缓存目录..."
CACHE_DIR="$HOME_DIR/Library/Caches/$BUNDLE_ID"
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo -e "   ${GREEN}✓${NC} 已删除: $CACHE_DIR"
else
    echo -e "   ${YELLOW}⚠${NC} 缓存目录不存在: $CACHE_DIR"
fi

# 6. 清理可能的临时文件
echo "5. 清理临时文件..."
TEMP_PATTERN="/tmp/$BUNDLE_ID"*
# 使用 shopt 来处理 glob 扩展
shopt -s nullglob
TEMP_FILES=($TEMP_PATTERN)
if [ ${#TEMP_FILES[@]} -gt 0 ]; then
    rm -rf "${TEMP_FILES[@]}"
    echo -e "   ${GREEN}✓${NC} 已清理临时文件"
else
    echo -e "   ${YELLOW}⚠${NC} 无临时文件需要清理"
fi
shopt -u nullglob

# 7. 清理可能的日志文件
echo "6. 清理日志文件..."
LOG_DIRS=(
    "$HOME_DIR/Library/Logs/$BUNDLE_ID"
    "$CONTAINER_DIR/../Logs"
)

FOUND_LOGS=false
for log_dir in "${LOG_DIRS[@]}"; do
    if [ -d "$log_dir" ]; then
        rm -rf "$log_dir"
        echo -e "   ${GREEN}✓${NC} 已删除: $log_dir"
        FOUND_LOGS=true
    fi
done

if [ "$FOUND_LOGS" = false ]; then
    echo -e "   ${YELLOW}⚠${NC} 未找到日志目录"
fi

# 8. 清理 Saved Application State（如果存在）
echo "7. 清理应用状态..."
SAVED_STATE_DIR="$HOME_DIR/Library/Saved Application State/$BUNDLE_ID.savedState"
if [ -d "$SAVED_STATE_DIR" ]; then
    rm -rf "$SAVED_STATE_DIR"
    echo -e "   ${GREEN}✓${NC} 已删除: $SAVED_STATE_DIR"
else
    echo -e "   ${YELLOW}⚠${NC} 应用状态目录不存在"
fi

# 9. 清理 Keychain 中的安全存储（flutter_secure_storage）
echo "8. 清理 Keychain 安全存储..."
# flutter_secure_storage 在 macOS 上使用 Keychain
# 使用 security 命令查找并删除相关条目
KEYCHAIN_ENTRIES=$(security find-generic-password -s "$BUNDLE_ID" 2>/dev/null | grep "keychain:" | head -1 | cut -d'"' -f2)
if [ -n "$KEYCHAIN_ENTRIES" ]; then
    # 尝试删除所有相关的 Keychain 条目
    security delete-generic-password -s "$BUNDLE_ID" 2>/dev/null && echo -e "   ${GREEN}✓${NC} 已清理 Keychain 条目" || echo -e "   ${YELLOW}⚠${NC} Keychain 条目可能不存在或需要用户确认"
else
    echo -e "   ${YELLOW}⚠${NC} 未找到 Keychain 条目（可能不存在）"
fi

# 10. 清理可能的 WebKit 数据（如果应用使用了 WebView）
echo "9. 清理 WebKit 数据..."
WEBKIT_DIRS=(
    "$HOME_DIR/Library/WebKit/$BUNDLE_ID"
    "$CONTAINER_DIR/../WebKit"
)

FOUND_WEBKIT=false
for webkit_dir in "${WEBKIT_DIRS[@]}"; do
    if [ -d "$webkit_dir" ]; then
        rm -rf "$webkit_dir"
        echo -e "   ${GREEN}✓${NC} 已删除: $webkit_dir"
        FOUND_WEBKIT=true
    fi
done

if [ "$FOUND_WEBKIT" = false ]; then
    echo -e "   ${YELLOW}⚠${NC} 未找到 WebKit 目录"
fi

# 11. 强制刷新 NSUserDefaults 缓存
echo "10. 刷新 NSUserDefaults 缓存..."
# 使用 killall 来重启 cfprefsd（这会刷新所有应用的 Preferences 缓存）
killall cfprefsd 2>/dev/null && echo -e "   ${GREEN}✓${NC} 已刷新 Preferences 缓存" || echo -e "   ${YELLOW}⚠${NC} 无法刷新缓存（可能需要管理员权限）"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}清理完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 验证清理结果
echo -e "${YELLOW}验证清理结果...${NC}"
VERIFY_FAILED=false

# 检查数据库文件
DB_FOUND=false
for db_path in "${DB_PATHS[@]}"; do
    if [ -f "$db_path" ]; then
        echo -e "   ${RED}✗${NC} 数据库文件仍存在: $db_path"
        DB_FOUND=true
        VERIFY_FAILED=true
    fi
done

# 检查 NSUserDefaults
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
    echo -e "   ${RED}✗${NC} NSUserDefaults 仍有数据"
    VERIFY_FAILED=true
fi

# 检查 Preferences 文件
PREFS_FOUND=false
for prefs_file in "${DEBUG_PREFS_FILES[@]}" "${RELEASE_PREFS_FILES[@]}"; do
    if [ -f "$prefs_file" ]; then
        echo -e "   ${RED}✗${NC} Preferences 文件仍存在: $prefs_file"
        PREFS_FOUND=true
        VERIFY_FAILED=true
    fi
done

if [ "$VERIFY_FAILED" = false ]; then
    echo -e "   ${GREEN}✓${NC} 所有数据已成功清理"
fi

echo ""
echo "应用数据已全部清理，下次启动时将："
echo "  - 显示首次启动提示"
echo "  - 需要重新选择工具配置目录"
echo "  - 需要重新授权目录访问权限"
echo "  - 所有设置恢复为默认值"
echo ""
echo -e "${YELLOW}提示：如果应用正在运行，请先退出应用后再启动，以确保清理生效。${NC}"
echo ""

