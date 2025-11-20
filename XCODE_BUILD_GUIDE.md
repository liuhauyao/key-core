# Xcode 构建指南

## 📦 在 Xcode 中构建 Release 版本

### 方法 1: 通过 Scheme 设置（推荐）

1. **打开 Scheme 编辑器**：
   - 点击 Xcode 顶部工具栏中的 **Scheme 选择器**（显示 "Runner" 的地方，通常在播放按钮旁边）
   - 选择 **Edit Scheme...**（或直接点击 Scheme 名称）

2. **设置 Build Configuration**：
   - 在左侧选择 **Run**（第一个选项）
   - 在右侧的 **Info** 标签页中
   - 找到 **Build Configuration** 下拉菜单
   - 选择 **Release**
   - 点击 **Close** 关闭对话框

3. **构建应用**：
   - 按 **`Cmd + B`** 构建
   - 或者选择 **Product > Build**（从菜单栏）

### 方法 2: 直接选择 Release Scheme

1. **选择 Release Scheme**：
   - 点击 Xcode 顶部工具栏中的 **Scheme 选择器**
   - 如果看到多个配置，选择 **Runner > Release**
   - 如果没有，先使用方法 1

2. **构建应用**：
   - 按 **`Cmd + B`** 构建

### 方法 3: 使用命令行构建（如果 Xcode UI 有问题）

```bash
cd /Users/liuhuayao/dev/ai-key-manager/macos
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath ../build/macos/Build
```

## ✅ 验证构建结果

构建完成后，检查应用：

```bash
cd /Users/liuhuayao/dev/ai-key-manager
ls -lh build/macos/Build/Products/Release/密枢.app/Contents/MacOS/
```

应该能看到 `Runner` 可执行文件。

## 🔧 如果构建失败

1. **清理构建**：
   - 在 Xcode 中：**Product > Clean Build Folder** (`Shift + Cmd + K`)

2. **检查错误**：
   - 查看 Xcode 底部的 **Issue Navigator**（左侧边栏）
   - 查看构建日志中的错误信息

3. **重新构建**：
   - 按 **`Cmd + B`** 重新构建

