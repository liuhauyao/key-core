# 配置同步更新机制

## 概述

本文档说明密枢（Key Core）项目的配置云端同步更新机制，包括架构设计、实现细节和操作流程。

## 架构设计

### 仓库策略

- **key-core**: 开源主仓库，存储核心代码、应用逻辑和配置文件
- **GitHub**: 主仓库地址，https://github.com/liuhauyao/key-core
- **Gitee**: GitHub 镜像库，自动同步主仓库内容（国内用户访问）

**优势**：
1. **统一管理**: 配置文件和代码在同一仓库，便于版本同步
2. **灵活性**: 配置更新无需重新编译和发布应用
3. **可维护性**: 单一仓库管理，减少同步步骤
4. **镜像同步**: Gitee 自动镜像 GitHub，国内用户访问更快

### 配置更新流程

1. **开发阶段**: 在 key-core 项目中修改 `assets/config/app_config.json`
2. **更新版本**: 更新配置文件的 `version` 和 `lastUpdated` 字段
3. **提交更新**: 在主仓库中提交并推送到 GitHub
4. **自动镜像**: Gitee 自动从 GitHub 同步更新（无需手动操作）
5. **用户更新**: 用户端应用自动检测并下载最新配置

## 配置加载优先级

应用按以下优先级加载配置：

1. **内存缓存** - 应用运行时的内存缓存（最快）
2. **本地缓存** - 应用文档目录下的 `cloud_config.json`（快速）
3. **云端配置** - 从 key-core 主仓库获取（需要网络）
4. **默认配置** - 应用内置的 `assets/config/app_config.json`（离线可用）

### 加载流程

```
应用启动
  ↓
检查内存缓存
  ↓ (不存在)
检查本地文件缓存 (cloud_config.json)
  ↓ (不存在)
尝试从云端获取配置
  ↓ (失败)
使用默认配置 (assets/config/app_config.json)
```

## 自动更新机制

### 更新检查时机

应用会在以下情况自动检查更新：

- **应用启动时**: 异步检查，不阻塞应用启动
- **定期检查**: 距离上次检查超过 24 小时
- **手动触发**: 用户可以在设置中手动触发更新检查

### 更新检查流程

```
检查是否需要更新
  ↓ (需要)
从云端获取最新配置
  ↓
比较版本号
  ↓ (云端版本 > 本地版本)
下载并保存到本地缓存
  ↓
清除内存缓存
  ↓
重新初始化配置模块
```

### 版本比较逻辑

- 如果云端版本 > 本地版本，则更新
- 如果版本相同，则跳过更新
- 如果本地版本 > 云端版本（开发环境），则使用本地版本

版本比较使用语义化版本规范（Semantic Versioning）：
- 主版本号 > 次版本号 > 修订号
- 例如：`2.1.0` > `2.0.9` > `2.0.1`

## 实现细节

### CloudConfigService

`CloudConfigService` 是配置管理的核心服务，位于 `lib/services/cloud_config_service.dart`。

#### 主要功能

1. **配置加载**: 按优先级加载配置
2. **版本管理**: 比较本地和云端版本，决定是否需要更新
3. **缓存管理**: 管理内存缓存和本地文件缓存
4. **更新检查**: 定期检查云端配置更新

#### 配置 URL

默认配置 URL（GitHub）:
```dart
https://raw.githubusercontent.com/liuhauyao/key-core/main/assets/config/app_config.json
```

备选配置 URL（Gitee，国内用户）:
```dart
https://gitee.com/liuhauyao/key-core/raw/main/assets/config/app_config.json
```

应用会优先尝试 GitHub，失败时自动切换到 Gitee。

#### 关键方法

- `init()`: 初始化服务
- `getConfigData()`: 获取配置数据（按优先级）
- `checkForUpdates()`: 检查更新
- `fetchConfigFromCloud()`: 从云端获取配置
- `saveConfigToCache()`: 保存配置到本地缓存
- `loadLocalCachedConfig()`: 加载本地缓存配置
- `loadLocalDefaultConfig()`: 加载默认配置（assets）
- `getLocalConfigDate()`: 获取本地配置日期

### 配置使用模块

配置被以下模块使用：

1. **ProviderConfig** (`lib/config/provider_config.dart`)
   - 加载供应商配置（密钥模板）
   - 提供 ClaudeCode 和 Codex 供应商列表

2. **McpServerPresets** (`lib/utils/mcp_server_presets.dart`)
   - 加载 MCP 服务器模板
   - 提供 MCP 服务器模板列表

3. **PlatformPresets** (`lib/utils/platform_presets.dart`)
   - 加载平台预设信息
   - 提供平台预设列表

## 配置更新操作流程

### 开发者操作步骤

1. **修改配置**
   - 在 key-core 项目中编辑 `assets/config/app_config.json`
   - 参考 `docs/config_format.md` 了解配置格式

2. **更新版本信息**
   - 更新 `version` 字段（遵循语义化版本规范）
   - 更新 `lastUpdated` 字段为当前时间（ISO 8601 格式）
   - 如有架构变更，更新 `schemaVersion`

3. **提交并推送**
   ```bash
   cd /Users/liuhuayao/dev/key-core
   
   # 添加配置文件
   git add assets/config/app_config.json
   
   # 获取版本号（可选，用于提交信息）
   VERSION=$(jq -r '.version' assets/config/app_config.json)
   
   # 提交
   git commit -m "Update config: version $VERSION"
   
   # 推送到 GitHub 主仓库
   git push origin main
   ```

4. **自动镜像同步**
   - Gitee 会自动从 GitHub 同步更新（通常几分钟内完成）
   - 无需手动推送到 Gitee

5. **验证更新**
   - 等待几分钟让 CDN 更新
   - 在应用中手动触发配置更新检查
   - 验证新配置是否正确加载

## 仓库配置

### 主仓库地址

- **GitHub（主仓库）**: https://github.com/liuhauyao/key-core
- **Gitee（镜像库）**: https://gitee.com/liuhauyao/key-core

### 镜像同步说明

Gitee 仓库已配置为 GitHub 的镜像库，会自动同步主仓库的所有更新：

- **同步方式**: Gitee 自动从 GitHub 拉取更新（通常几分钟内完成）
- **同步内容**: 包括代码、配置文件和所有提交历史
- **无需手动操作**: 推送到 GitHub 后，Gitee 会自动同步

### 本地仓库配置

**位置**: `/Users/liuhuayao/dev/key-core`

**远程仓库配置**:
```bash
origin   https://github.com/liuhauyao/key-core.git
```

**推送命令**:
```bash
# 推送到 GitHub 主仓库
git push origin main

# Gitee 会自动同步，无需手动推送
```

## 错误处理

### 网络错误

- 如果无法连接云端，使用本地缓存或默认配置
- 不会阻塞应用启动
- 错误信息记录到日志
- 支持 GitHub 和 Gitee 两个源，GitHub 失败时自动尝试 Gitee
- Gitee 作为镜像库，为国内用户提供更快的访问速度

### 配置格式错误

- JSON 解析失败时，使用本地缓存或默认配置
- 错误信息记录到日志
- 不会导致应用崩溃

### 版本兼容性

- 通过 `schemaVersion` 检查兼容性
- 如果架构版本不兼容，使用本地缓存或默认配置
- 版本号格式错误时，使用本地缓存或默认配置

### 超时处理

- 网络请求设置 10 秒超时
- 超时后使用本地缓存或默认配置
- 不会阻塞应用启动

## 安全考虑

1. **HTTPS 要求**: 所有配置 URL 必须使用 HTTPS
2. **URL 验证**: 验证 URL 格式，拒绝非 HTTPS 连接
3. **超时控制**: 网络请求设置 10 秒超时
4. **错误处理**: 网络错误不会影响应用正常运行
5. **缓存验证**: 本地缓存文件损坏时自动回退到默认配置

## 性能优化

1. **缓存机制**: 多级缓存（内存、本地文件）
2. **异步加载**: 配置更新不阻塞应用启动
3. **按需更新**: 24 小时检查间隔，避免频繁请求
4. **超时控制**: 避免长时间等待网络响应
5. **失败回退**: 快速回退到本地缓存或默认配置

## 用户端体验

用户无需任何操作，应用会自动：

1. 在启动时检查更新（异步）
2. 每 24 小时自动检查一次
3. 发现新版本时自动下载并应用
4. 网络失败时使用本地缓存，不影响使用

用户也可以在设置中手动触发更新检查。

## 相关文件

### key-core 项目

- `lib/services/cloud_config_service.dart`: 配置服务实现
- `lib/models/cloud_config.dart`: 配置结构定义
- `lib/config/provider_config.dart`: 供应商配置管理
- `lib/utils/mcp_server_presets.dart`: MCP 模板管理
- `lib/utils/platform_presets.dart`: 平台预设管理
- `lib/main.dart`: 应用入口，初始化配置服务
- `assets/config/app_config.json`: 默认配置文件（同时也是云端配置文件）

## 相关文档

- `docs/config_format.md` - 配置文件格式详细说明
