# 环境配置指南

## ✅ 已完成的配置

1. ✅ **Flutter SDK** - 已安装 (v3.38.1)
2. ✅ **Dart SDK** - 已安装 (v3.10.0)
3. ✅ **macOS桌面支持** - 已启用
4. ✅ **项目依赖** - 已安装 (`flutter pub get`)

## ⚠️ 需要手动完成的配置

### 1. 安装完整版Xcode（必需）

**原因**: macOS应用开发需要完整的Xcode，不仅仅是命令行工具。

**步骤**:
1. 打开 App Store
2. 搜索 "Xcode"
3. 点击"获取"或"安装"（大约10-15GB，需要一些时间）
4. 安装完成后，在终端执行：

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

**验证**:
```bash
xcode-select -p
# 应该显示: /Applications/Xcode.app/Contents/Developer
```

### 2. 安装CocoaPods（必需）

**原因**: macOS/iOS插件依赖CocoaPods进行管理。

**步骤**:
```bash
sudo gem install cocoapods
```

**验证**:
```bash
pod --version
# 应该显示版本号，例如: 1.15.2
```

### 3. 接受Xcode许可协议

安装Xcode后，需要接受许可协议：

```bash
sudo xcodebuild -license accept
```

## 🚀 快速启动（配置完成后）

配置完成后，运行以下命令启动应用：

```bash
cd /Users/liuhuayao/dev/key-package/ai_key_manager

# 检查环境
flutter doctor

# 运行应用
flutter run -d macos
```

## 📋 环境检查清单

运行 `flutter doctor` 后，应该看到：

- [✓] Flutter
- [✓] Xcode (需要完整安装)
- [✓] CocoaPods (需要安装)
- [✓] Connected device (macOS)

Android工具链可以忽略（我们只需要macOS支持）。

## 🔧 故障排除

### 问题1: Xcode未找到
```bash
# 检查Xcode是否安装
ls /Applications/ | grep -i xcode

# 如果已安装但路径不对，切换路径
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### 问题2: CocoaPods安装失败
```bash
# 如果gem安装失败，尝试使用Homebrew
brew install cocoapods
```

### 问题3: 权限问题
```bash
# 确保有管理员权限
sudo -v

# 如果sudo不可用，可能需要配置askpass
```

## 📝 当前状态

**已安装**:
- Flutter 3.38.1 ✅
- Dart 3.10.0 ✅
- 项目依赖 ✅

**待安装**:
- Xcode完整版 ⚠️
- CocoaPods ⚠️

## 🎯 下一步

1. 安装Xcode（从App Store）
2. 安装CocoaPods (`sudo gem install cocoapods`)
3. 运行 `flutter doctor` 验证
4. 运行 `flutter run -d macos` 启动应用

