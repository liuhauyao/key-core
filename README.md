# Key Core (密枢)

一款跨平台的 AI 密钥管理应用，支持 macOS、Windows 和 Linux，帮助您安全、便捷地管理各类 AI 服务的 API 密钥。

## ✨ 特性

- 🔒 **安全加密**: AES-256-GCM 加密，PBKDF2 密钥派生（10000 次迭代）
- 🏠 **本地存储**: 完全离线运行，数据不离开您的设备
- 🎨 **原生体验**: 遵循 macOS 设计规范，支持深色模式
- 🔑 **快速操作**: 一键复制密钥、打开管理地址
- ⏰ **过期提醒**: 自动提醒即将过期的密钥（7天内）
- 🏷️ **智能分类**: 平台分组、标签管理、收藏功能
- 🔍 **快速搜索**: 实时搜索和筛选（支持名称、平台、标签、备注）
- 💾 **导入导出**: 加密导出和批量导入
- 🌐 **国际化**: 支持中文和英文
- 📊 **统计信息**: 密钥统计和状态监控
- 🎯 **剪贴板保护**: 自动清空剪贴板（30秒后）

## ⚠️ 平台支持状态

- ✅ **macOS**: 完全支持，已测试
- ⚠️ **Windows**: 代码已实现，但**未在实际环境中测试**
- ⚠️ **Linux**: 代码已实现，但**未在实际环境中测试**

> **注意**: Windows 和 Linux 版本已实现跨平台支持代码，包括：
> - 跨平台托盘菜单管理
> - 配置文件路径自动适配
> - 窗口管理功能
> 
> 但由于缺少对应测试环境，尚未进行实际测试。欢迎有条件的用户进行测试并提供反馈。
> 
> 相关文档：
> - Windows/Linux: `docs/cross_platform.md`
> - Linux: 参考 Windows 文档（构建命令使用 `flutter build linux`）

## 📋 支持的平台

### 国际平台
- OpenAI
- Anthropic (Claude)
- Google AI
- Azure OpenAI
- AWS

### 国产平台
- MiniMax
- DeepSeek
- SiliconFlow
- 智谱AI
- 百炼云
- 百度千问
- 通义千问
- 自定义平台

## 🏗️ 项目结构

```
lib/
├── main.dart                      # 应用入口
├── constants/                     # 常量定义
│   └── app_constants.dart
├── models/                        # 数据模型
│   ├── ai_key.dart               # 密钥数据模型
│   └── platform_type.dart        # 平台类型枚举
├── services/                      # 服务层
│   ├── auth_service.dart         # 认证服务（主密码管理）
│   ├── crypt_service.dart        # 加密服务（AES-256-GCM）
│   ├── database_service.dart     # 数据库服务（SQLite）
│   ├── secure_storage_service.dart # 安全存储（macOS Keychain）
│   ├── clipboard_service.dart   # 剪贴板服务（自动清空）
│   ├── url_launcher_service.dart # URL 启动服务
│   ├── export_service.dart      # 导出服务（加密导出）
│   ├── import_service.dart      # 导入服务（批量导入）
│   ├── settings_service.dart    # 设置服务
│   └── macos_preferences_bridge.dart # macOS 原生桥接
├── viewmodels/                   # 业务逻辑层
│   ├── base_viewmodel.dart      # ViewModel 基类
│   ├── key_manager_viewmodel.dart # 密钥管理 ViewModel
│   └── settings_viewmodel.dart  # 设置 ViewModel
├── views/                        # UI 层
│   ├── screens/
│   │   ├── main_screen.dart     # 主界面
│   │   └── key_form_page.dart   # 密钥表单页面
│   └── widgets/
│       ├── key_card.dart        # 密钥卡片组件
│       ├── key_form_dialog.dart # 密钥表单对话框
│       ├── search_bar.dart      # 搜索栏组件
│       ├── platform_filter.dart # 平台筛选组件
│       ├── loading_overlay.dart # 加载遮罩组件
│       ├── master_password_dialog.dart # 主密码对话框
│       └── settings_dialog.dart # 设置对话框
└── utils/                        # 工具类
    ├── app_localizations.dart   # 国际化工具
    ├── password_generator.dart  # 密码生成器
    └── platform_presets.dart    # 平台预设信息
```

## 🚀 快速开始

### 环境要求

- Flutter 3.19+
- Dart 3.0+
- **macOS**: macOS 13.0+
- **Windows**: Windows 10+ (需要 Visual Studio 2022)
- **Linux**: 支持系统托盘的桌面环境 (GNOME/KDE/XFCE)

### 安装依赖

```bash
flutter pub get
```

### 运行应用

**macOS**:
```bash
flutter run -d macos
```

**Windows**:
```powershell
flutter run -d windows
```

**Linux**:
```bash
flutter run -d linux
```

### 构建应用

**macOS**:
```bash
flutter build macos --release
```
构建产物位置：`build/macos/Build/Products/Release/key_core.app`

**Windows** (⚠️ 未测试):
```powershell
# 方法 1: 使用 PowerShell 脚本
.\scripts\build_windows.ps1

# 方法 2: 手动构建
flutter config --enable-windows-desktop
flutter build windows --release
```
构建产物位置：`build/windows/runner/Release/key_core.exe`

**Linux** (⚠️ 未测试):
```bash
flutter build linux --release
```
构建产物位置：`build/linux/x64/release/bundle/`

> **注意**: Windows 和 Linux 版本已实现跨平台支持代码，但尚未在实际环境中测试。如需使用，请参考 `docs/cross_platform.md` 进行构建和测试。

## 📦 依赖项

### 主要依赖

- **provider** (^6.1.1): 状态管理
- **flutter_secure_storage** (^9.0.0): 安全存储 (macOS Keychain)
- **sqflite_common_ffi** (^2.3.0): SQLite 数据库
- **encrypt** (^5.0.3): 数据加密 (AES-256-GCM)
- **crypto** (^3.0.3): 加密算法 (SHA-256, PBKDF2)
- **url_launcher** (^6.2.2): 打开 URL
- **intl** (^0.20.2): 国际化支持
- **clipboard_watcher** (^0.1.0): 剪贴板监控
- **permission_handler** (^11.0.1): 权限管理
- **archive** (^3.4.0): 文件压缩（导入导出）
- **equatable** (^2.0.5): 对象比较
- **logger** (^2.0.2): 日志记录
- **shared_preferences** (^2.2.2): 本地偏好设置

### 开发依赖

- **flutter_lints** (^3.0.0): 代码检查
- **build_runner** (^2.4.7): 代码生成
- **mockito** (^5.4.3): 单元测试
- **json_serializable** (^6.7.1): JSON 序列化

## 🔐 安全特性

### 加密方案

1. **主密码**: 用户设置的主密码（可选，支持无密码模式）
2. **密钥派生**: 使用 PBKDF2 (SHA-256, 10000 iterations) 从主密码生成 AES-256 密钥
3. **数据加密**: 使用 AES-256-GCM 加密所有敏感数据
4. **安全存储**: 加密密钥存储在 macOS Keychain
5. **IV 随机化**: 每次加密使用随机 IV，确保相同明文产生不同密文

### 数据保护

- ✅ 密钥值加密存储（可选）
- ✅ API 地址加密存储
- ✅ 管理地址加密存储
- ✅ 剪贴板自动清空（30秒）
- ✅ 内存安全清零
- ✅ 安全删除（覆写后删除）
- ✅ 主密码强度验证
- ✅ 密码哈希存储（SHA-256）

### 密码要求

- 至少 8 位字符
- 包含小写字母
- 包含大写字母
- 包含数字
- 包含特殊字符

## 🎨 设计规范

### 颜色方案

- **主色**: #007AFF (macOS Blue)
- **成功**: #34C759 (macOS Green)
- **警告**: #FF9500 (macOS Orange)
- **错误**: #FF3B30 (macOS Red)
- **背景**: #FAFAFA (Light) / #1C1C1E (Dark)

### 组件规范

- 使用 Material 3 设计语言
- 遵循 macOS Human Interface Guidelines
- 响应式布局
- 无障碍支持
- 深色模式支持
- 系统主题跟随

## 📖 使用说明

### 首次启动

1. 启动应用后，可以选择设置主密码（可选）
2. 如果设置主密码，密码必须至少 8 位，包含大小写字母、数字和特殊字符
3. 设置完成后，所有数据将使用该密码加密
4. 如果不设置主密码，数据将以明文形式存储（不推荐）

### 添加密钥

1. 点击右下角的 `+` 按钮
2. 填写密钥信息：
   - 密钥名称
   - 平台类型（自动填充管理地址和 API 地址）
   - 管理地址（可选，自动填充）
   - API 地址（可选，自动填充）
   - 密钥值
   - 过期日期（可选）
   - 标签（可选，多个标签用逗号分隔）
   - 备注（可选）
3. 点击保存

### 复制密钥

1. 在密钥卡片上点击复制图标
2. 密钥会自动复制到剪贴板
3. 30 秒后剪贴板会自动清空

### 打开管理地址

1. 在密钥详情中点击管理地址链接
2. 系统会在默认浏览器中打开

### 搜索和筛选

- 在搜索框中输入关键词（支持名称、平台、标签、备注）
- 使用平台下拉菜单筛选特定平台
- 清除搜索或筛选以显示全部

### 收藏和激活状态

- 点击密钥卡片的收藏图标可以收藏/取消收藏
- 点击激活状态可以启用/禁用密钥
- 收藏的密钥会优先显示

### 导入/导出

#### 导出密钥

1. 在菜单中选择导出
2. 设置导出密码
3. 选择保存位置
4. 导出的文件已加密（ZIP 格式）

#### 导入密钥

1. 在菜单中选择导入
2. 选择之前导出的文件
3. 输入导出时设置的密码
4. 确认导入
5. 导入结果会显示成功和失败的数量

### 设置

- **语言**: 切换中文/英文
- **主题**: 浅色/深色/跟随系统
- **最小化到托盘**: 关闭窗口时最小化到系统托盘（macOS）

## 🧪 测试

### 运行单元测试

```bash
flutter test
```

### 代码覆盖率

```bash
flutter test --coverage
```

## 📋 功能特性详情

### 密钥管理

- ✅ 添加、编辑、删除密钥
- ✅ 密钥状态管理（激活/禁用）
- ✅ 收藏功能
- ✅ 过期提醒（7天内）
- ✅ 最后使用时间记录
- ✅ 创建和更新时间记录

### 搜索和筛选

- ✅ 实时搜索（名称、平台、标签、备注）
- ✅ 平台筛选
- ✅ 搜索结果高亮

### 数据统计

- ✅ 总密钥数
- ✅ 激活/禁用数量
- ✅ 即将过期数量
- ✅ 已过期数量
- ✅ 收藏数量

### 安全功能

- ✅ 主密码保护（可选）
- ✅ AES-256-GCM 加密
- ✅ PBKDF2 密钥派生
- ✅ macOS Keychain 存储
- ✅ 剪贴板自动清空
- ✅ 安全删除

### 导入导出

- ✅ 加密导出（ZIP 格式）
- ✅ 批量导入
- ✅ 导入结果统计
- ✅ 数据验证

## 📋 TODO / 计划功能

- [ ] 批量操作（批量编辑、删除）
- [ ] 标签管理界面
- [ ] 快捷键支持
- [ ] 生物认证（Touch ID / Face ID）
- [ ] 自动备份
- [ ] 团队协作
- [ ] 使用统计
- [ ] API 监控
- [ ] 插件系统
- [ ] 密钥生成器
- [ ] 密码强度检测
- [ ] 自动锁定功能

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 开发指南

1. Fork 本项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

### 代码规范

- 遵循 Flutter/Dart 代码规范
- 使用 `flutter_lints` 进行代码检查
- 编写单元测试
- 添加必要的注释和文档

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 📞 联系方式

如有问题或建议，请通过以下方式联系：

- GitHub Issues: https://github.com/yourusername/ai-key-manager/issues

## 🙏 致谢

感谢以下开源项目：

- Flutter
- Dart
- flutter_secure_storage
- sqflite
- encrypt
- provider

---

**⚠️ 重要提示**: 

1. 请务必保护好您的主密码，忘记主密码将无法恢复加密的数据！
2. 建议定期导出备份您的密钥数据
3. 主密码是可选的，但强烈建议设置以提高安全性
4. 剪贴板会在 30 秒后自动清空，请及时使用复制的密钥

