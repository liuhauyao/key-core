# 图标管理系统

本目录包含应用程序中使用的所有图标文件。

## 目录结构

```
assets/icons/
├── icon.png              # 应用程序主图标
├── platforms/            # 平台图标目录（278个SVG文件）
│   ├── anthropic.svg     # Anthropic平台图标
│   ├── openai.svg        # OpenAI平台图标
│   ├── coze.svg          # Coze平台图标
│   └── ...               # 其他平台图标
└── README.md            # 本文件
```

## 图标添加流程

### 1. 添加新图标文件
将 SVG 格式的图标文件放置在 `assets/icons/platforms/` 目录下。

### 2. 更新配置文件
运行以下命令更新图标列表配置文件：

```bash
# 方法1：使用专用脚本（推荐）
./scripts/update_icons.sh

# 方法2：直接运行Dart脚本
dart scripts/generate_icon_list.dart
```

### 3. 构建应用
在构建应用时，构建脚本会自动生成最新的图标配置文件。

## 图标命名规范

- 文件格式：`.svg`
- 命名规则：`{platform-name}[-variant].svg`
- 示例：
  - `anthropic.svg` - 基本图标
  - `anthropic-color.svg` - 彩色版本
  - `openai-icon.svg` - 带后缀的图标

## 技术实现

### 构建时生成配置
- 使用 `scripts/generate_icon_list.dart` 脚本扫描 `assets/icons/platforms/` 目录
- 生成 `assets/config/icon_list.json` 配置文件
- 配置文件包含所有可用图标的列表

### 运行时加载
- `IconPicker` 组件从配置文件加载图标列表
- 支持搜索和选择功能
- 自动包含新添加的图标文件

## 构建脚本集成

所有平台构建脚本都已集成图标列表生成：

- `build_macos_github.sh` - macOS GitHub Release
- `build_macos_appstore.sh` - macOS App Store
- `build_windows.sh` - Windows
- `build_linux.sh` - Linux

构建时会自动运行图标列表生成脚本，确保配置文件始终是最新的。





