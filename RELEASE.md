# 发布指南

## 📦 构建 Release 版本

### ⚠️ 重要提示

如果遇到以下问题：
- **应用无法运行**（提示"已损坏或不完整"）
- **应用没有图标**
- **构建失败**（内存不足错误）

请使用 Xcode 构建（方法 2），然后运行权限修复脚本。

### 方法 1: 使用 Flutter 命令行（推荐）

```bash
# 清理构建缓存
flutter clean

# 构建 Release 版本
flutter build macos --release

# 如果构建成功，修复应用权限
./scripts/fix_app_permissions.sh
```

### 方法 2: 使用 Xcode（如果命令行构建失败）

1. 打开 Xcode 项目：
```bash
open macos/Runner.xcworkspace
```

2. 在 Xcode 中：
   - 选择 **Product > Scheme > Runner**
   - 选择 **Product > Destination > My Mac**
   - 选择 **Product > Build Configuration > Release**
   - 按 `Cmd + B` 构建

3. 构建完成后，应用位于：
   `build/macos/Build/Products/Release/密枢.app`

4. **重要：修复应用权限**（允许运行未签名的应用）：
```bash
./scripts/fix_app_permissions.sh
```

或者手动执行：
```bash
xattr -cr build/macos/Build/Products/Release/密枢.app
```

5. 如果仍然无法运行，请：
   - 右键点击应用 > **打开**
   - 或在 **系统设置 > 隐私与安全性** 中允许运行

## 📦 打包 DMG 文件

### 使用脚本（推荐）

```bash
# 确保应用已构建（使用 Xcode 或 Flutter）
# 确保已修复应用权限
./scripts/fix_app_permissions.sh

# 运行打包脚本
./scripts/build_dmg.sh
```

DMG 文件将生成在 `build/dmg/密枢-1.0.0.dmg`

### ⚠️ DMG 中的应用权限问题

DMG 中的应用也需要修复权限。用户安装后可能需要：
1. 右键点击应用 > **打开**
2. 或在终端运行：`xattr -cr /Applications/密枢.app`

### 手动打包 DMG

1. 创建临时目录：
```bash
mkdir -p build/dmg/temp
```

2. 复制应用到临时目录：
```bash
cp -R build/macos/Build/Products/Release/密枢.app build/dmg/temp/
```

3. 创建 Applications 链接：
```bash
ln -s /Applications build/dmg/temp/Applications
```

4. 创建 DMG：
```bash
hdiutil create -volname "密枢" \
    -srcfolder build/dmg/temp \
    -ov -format UDZO \
    build/dmg/密枢-1.0.0.dmg
```

5. 清理临时文件：
```bash
rm -rf build/dmg/temp
```

## 🚀 创建 GitHub Release

### 1. 创建 Git Tag

```bash
# 创建标签
git tag -a v1.0.0 -m "Release version 1.0.0"

# 推送标签到 GitHub
git push ai-key-manager v1.0.0
```

### 2. 在 GitHub 上创建 Release

1. 访问：https://github.com/liuhauyao/ai-key-manager/releases/new
2. 选择标签：`v1.0.0`
3. 标题：`v1.0.0 - 密枢`
4. 描述：

```markdown
## 🎉 版本 1.0.0

### ✨ 新功能
- 🔖 密钥列表标签展示功能
- 🎨 窗口主题同步（深色/浅色/跟随系统）
- ⚙️ 设置管理优化

### 🐛 修复
- 修复 MethodChannel 注册时机问题
- 修复 NSUserDefaults 警告
- 优化应用激活逻辑

### 📦 下载
- [密枢-1.0.0.dmg](下载链接)

### 📋 系统要求
- macOS 13.0 或更高版本
```

5. 上传 DMG 文件
6. 点击 "Publish release"

## 📝 Release Notes 模板

```markdown
## 🎉 版本 1.0.0

### ✨ 新功能
- 🔖 密钥列表标签展示功能（中间位置，垂直排列）
- 🎨 窗口标题栏主题同步（深色/浅色/跟随系统）
- ⚙️ 设置管理优化

### 🐛 修复
- 修复 MethodChannel 注册时机问题
- 修复 NSUserDefaults suite name 警告
- 优化应用激活逻辑
- 修复应用启动时的异常处理

### 🔧 改进
- 改进错误处理机制
- 优化应用启动性能
- 更新项目文档

### 📦 安装说明
1. 下载 DMG 文件
2. 双击打开 DMG
3. 将应用拖拽到 Applications 文件夹
4. 在 Applications 中启动应用

### 📋 系统要求
- macOS 13.0 或更高版本
- 至少 100MB 可用磁盘空间

### 🙏 致谢
感谢所有贡献者和用户的支持！
```

## 🔄 自动化发布（可选）

可以使用 GitHub Actions 自动构建和发布。创建 `.github/workflows/release.yml`：

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
      - run: flutter pub get
      - run: flutter build macos --release
      - run: ./scripts/build_dmg.sh
      - uses: softprops/action-gh-release@v1
        with:
          files: build/dmg/*.dmg
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

