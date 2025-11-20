#!/bin/bash

# 清除 Key Core 应用的所有数据
# 包括：数据库、Keychain 数据、SharedPreferences

echo "正在清除 Key Core 应用数据..."

# 获取应用数据目录
APP_DATA_DIR="$HOME/Library/Application Support/key_core"
APP_DOCS_DIR="$HOME/Library/Containers/com.example.keyCore/Data/Documents"

# 清除数据库文件
if [ -d "$APP_DATA_DIR" ]; then
    echo "清除数据库目录: $APP_DATA_DIR"
    rm -rf "$APP_DATA_DIR"
fi

if [ -d "$APP_DOCS_DIR" ]; then
    echo "清除文档目录: $APP_DOCS_DIR"
    rm -rf "$APP_DOCS_DIR"
fi

# 清除 SharedPreferences (macOS 使用 UserDefaults)
PREFERENCES_FILE="$HOME/Library/Preferences/com.example.keyCore.plist"
if [ -f "$PREFERENCES_FILE" ]; then
    echo "清除偏好设置文件: $PREFERENCES_FILE"
    rm -f "$PREFERENCES_FILE"
fi

# 清除 Keychain 数据
# 注意：Keychain 数据需要通过 security 命令清除，或者让应用自己清除
echo ""
echo "Keychain 数据需要手动清除："
echo "1. 打开 '钥匙串访问' 应用"
echo "2. 搜索 'Key Core' 或 'flutter_secure_storage'"
echo "3. 删除相关的钥匙串项目"
echo ""
echo "或者运行以下命令清除（需要输入密码）："
echo "security delete-generic-password -a 'Key Core' 2>/dev/null || true"

# 尝试清除 Keychain（可能失败，但不影响其他清理）
security delete-generic-password -a 'Key Core' 2>/dev/null || true

echo ""
echo "✅ 应用数据清除完成！"
echo ""
echo "已清除："
echo "  - 数据库文件"
echo "  - 应用文档目录"
echo "  - 偏好设置文件"
echo ""
echo "请手动检查并清除 Keychain 中的数据（如果存在）"

