# 跨平台支持说明

## 平台支持状态

### ✅ macOS
- **状态**: 完全支持，已测试
- **构建命令**: `flutter build macos --release`
- **构建脚本**: `./scripts/build_macos.sh`
- **打包格式**: DMG 文件
- **构建产物**: `build/macos/Build/Products/Release/key_core.app` 和 `build/dmg/密枢-{VERSION}.dmg`

### ⚠️ Windows
- **状态**: 代码已实现，**未在实际环境中测试**
- **构建命令**: `flutter build windows --release`
- **构建脚本**: `./scripts/build_windows.sh`
- **打包格式**: 可执行文件 + DLL
- **构建产物**: `build/windows/runner/Release/key_core.exe`

### ⚠️ Linux
- **状态**: 代码已实现，**未在实际环境中测试**
- **构建命令**: `flutter build linux --release`
- **构建脚本**: `./scripts/build_linux.sh`
- **打包格式**: Bundle 目录
- **构建产物**: `build/linux/x64/release/bundle/`

## 环境配置

### macOS

**前置要求**:
- Flutter 3.19+ 已安装
- Xcode 已安装
- macOS 13.0+

**配置步骤**:
```bash
# 验证环境
flutter doctor

# 构建
./scripts/build_macos.sh
```

### Windows

**前置要求**:
- Flutter 3.19+ 已安装并添加到 PATH
- Visual Studio 2022（包含"使用 C++ 的桌面开发"工作负载）
- Windows 10+

**配置步骤**:

1. **添加 Flutter 到 PATH**（如果命令未找到）:
   - 找到 Flutter 安装目录（例如：`C:\src\flutter`）
   - 将 `flutter\bin` 目录添加到系统 PATH 环境变量
   - 重新打开 PowerShell 窗口
   - 验证：`flutter --version`

2. **启用 Windows 桌面支持**:
   ```powershell
   flutter config --enable-windows-desktop
   flutter doctor
   ```

3. **构建**:
   ```powershell
   # 使用脚本（推荐）
   ./scripts/build_windows.sh
   
   # 或手动构建
   flutter build windows --release
   ```

**故障排除**:
- 如果 `flutter` 命令未找到，参考上面的 PATH 配置
- 如果 Visual Studio 未检测到，确保安装了 C++ 桌面开发工具
- 如果构建失败，运行 `flutter clean` 后重试

### Linux

**前置要求**:
- Flutter 3.19+ 已安装
- 支持系统托盘的桌面环境（GNOME/KDE/XFCE）
- Linux 发行版支持 Flutter Desktop

**配置步骤**:

1. **启用 Linux 桌面支持**:
   ```bash
   flutter config --enable-linux-desktop
   flutter doctor
   ```

2. **构建**:
   ```bash
   # 使用脚本（推荐）
   ./scripts/build_linux.sh
   
   # 或手动构建
   flutter build linux --release
   ```

## 已实现的功能

### 跨平台托盘菜单
- ✅ 平台抽象接口 (`PlatformTrayService`)
- ✅ macOS 实现（保留现有 MethodChannel，向后兼容）
- ✅ Windows 实现（使用 `tray_manager` 插件）
- ✅ Linux 实现（使用 `tray_manager` 插件）
- ✅ 统一托盘菜单桥接 (`TrayMenuBridge`)

### 配置路径适配
- ✅ 统一配置路径服务 (`PlatformConfigPathService`)
- ✅ macOS: `~/.claude`, `~/.codex`, `~/.gemini`
- ✅ Windows: `%APPDATA%\.claude`, `%APPDATA%\.codex`, `%APPDATA%\.gemini`
- ✅ Linux: `~/.claude`, `~/.codex`, `~/.gemini`

### 窗口管理
- ✅ 集成 `window_manager` 插件
- ✅ 窗口显示/隐藏功能
- ✅ 最小化到托盘功能

## 已知限制

### tray_manager 0.5.2 API 限制
- ❌ 不支持 `enabled` 参数（菜单项始终可用）
- ❌ 不支持 `checked` 参数（无法显示选中状态）
- ❌ 不支持子菜单（使用扁平化菜单结构）

**解决方案**: 已适配为扁平化菜单结构，菜单项始终可用。

### 图标格式要求
- **macOS**: `.png` 或 `.icns`
- **Windows**: `.ico`（需要准备 `assets/icons/app_icon.ico`）
- **Linux**: `.png`

### 测试状态
- **macOS**: ✅ 已测试
- **Windows**: ⚠️ 未测试（需要 Windows 环境）
- **Linux**: ⚠️ 未测试（需要 Linux 环境）

## 构建脚本

所有平台都提供了简单的构建脚本，位于 `scripts/` 目录：

```bash
# macOS
./scripts/build_macos.sh

# Windows
./scripts/build_windows.sh

# Linux
./scripts/build_linux.sh
```

脚本会自动：
- 切换到项目根目录
- 清理之前的构建
- 获取依赖
- 构建 Release 版本
- 显示构建产物位置

## 故障排除

### sqlite3 下载超时（macOS/Linux）

**问题**: 构建时出现 `sqlite3` 下载超时错误

**解决方案**:

1. **配置代理**（如果使用代理）:
   ```bash
   export http_proxy=http://your-proxy:port
   export https_proxy=http://your-proxy:port
   flutter build macos --release
   ```

2. **使用镜像源**（中国用户）:
   ```bash
   export PUB_HOSTED_URL=https://pub.flutter-io.cn
   export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
   flutter build macos --release
   ```

3. **清理缓存后重试**:
   ```bash
   flutter clean
   rm -rf ~/.pub-cache/hosted/pub.flutter-io.cn/sqlite3-*/
   flutter pub get
   flutter build macos --release
   ```

### Windows 构建失败

1. **检查 Visual Studio**:
   - 确保安装了 Visual Studio 2022
   - 确保安装了"使用 C++ 的桌面开发"工作负载
   - 运行 `flutter doctor -v` 查看详细信息

2. **清理重建**:
   ```powershell
   flutter clean
   flutter pub get
   flutter build windows --release
   ```

### 应用权限问题（macOS）

如果应用无法运行：
```bash
xattr -cr build/macos/Build/Products/Release/key_core.app
```

### 托盘图标不显示

1. **检查图标文件**:
   - macOS: `assets/icons/app_icon.png`
   - Windows: `assets/icons/app_icon.ico`（需要准备）
   - Linux: `assets/icons/app_icon.png`

2. **检查 tray_manager 初始化**:
   - 查看控制台是否有错误
   - 确认 `TrayMenuBridge.init()` 已调用

## 测试建议

### Windows 测试清单

- [ ] 应用启动正常
- [ ] 托盘图标显示正常
- [ ] 托盘菜单显示正常
- [ ] 配置路径正确（`%APPDATA%\.claude` 等）
- [ ] 密钥切换功能正常
- [ ] 窗口管理功能正常

### Linux 测试清单

- [ ] 应用启动正常
- [ ] 托盘图标显示正常（需要桌面环境支持）
- [ ] 托盘菜单显示正常
- [ ] 配置路径正确（`~/.claude` 等）
- [ ] 密钥切换功能正常
- [ ] 窗口管理功能正常

## 贡献

欢迎有条件的用户进行测试并提供反馈：
- 提交 Issue 报告问题
- 提交 Pull Request 改进代码
- 分享测试结果和使用体验

## 相关文件

### 代码文件
- `lib/services/platform/platform_tray_service.dart` - 平台抽象接口
- `lib/services/platform/macos_tray_service.dart` - macOS 实现
- `lib/services/platform/windows_tray_service.dart` - Windows 实现
- `lib/services/platform/linux_tray_service.dart` - Linux 实现
- `lib/services/platform_config_path_service.dart` - 配置路径服务
- `lib/services/tray_menu_bridge.dart` - 托盘菜单桥接

### 构建脚本
- `scripts/build_macos.sh` - macOS 构建脚本
- `scripts/build_windows.sh` - Windows 构建脚本
- `scripts/build_linux.sh` - Linux 构建脚本

## 快速参考

### 构建命令

```bash
# macOS
./scripts/build_macos.sh
# 或
flutter build macos --release

# Windows
./scripts/build_windows.sh
# 或
flutter build windows --release

# Linux
./scripts/build_linux.sh
# 或
flutter build linux --release
```

### 开发模式运行

```bash
# macOS
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

### 环境验证

```bash
# 检查 Flutter 环境
flutter doctor

# 检查可用设备
flutter devices
```

