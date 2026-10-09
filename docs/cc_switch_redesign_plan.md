# Key Core 参照 CC Switch 的改造方案

## 文档版本

- 创建日期：2026-10-09
- Key Core 当前版本：1.0.5
- CC Switch 参考版本：4.0.5
- 改造目标：将 Key Core 升级为类似 CC Switch 的 All-in-One AI 工具配置管理器

## 一、项目概述

### 1.1 Key Core 现状

**技术栈：**
- Flutter 3.19+ / Dart 3.0+
- 跨平台：macOS（已测试）、Windows/Linux（代码已实现但未测试）
- 数据库：SQLite (sqflite_common_ffi)
- 加密：AES-256-GCM + PBKDF2
- 状态管理：Provider
- 存储：flutter_secure_storage (macOS Keychain)

**核心功能：**
1. AI API 密钥管理（增删改查）
2. 密钥加密存储（可选主密码）
3. 平台分类（国际/国产平台）
4. 搜索和筛选
5. 过期提醒
6. 导入导出（加密）
7. 剪贴板保护
8. 多语言支持（中文/英文）

**已有特殊功能：**
- OpenClaw 配置管理（PR #4）
- MCP 服务器管理
- 技能(Skills)管理
- 模型列表管理
- 密钥验证
- 余额查询

### 1.2 CC Switch 核心设计

**技术栈：**
- Tauri 2 (Rust + TypeScript/React)
- 跨平台：Windows、macOS、Linux
- 配置文件格式：TOML、JSON、JSONC、dotenv

**核心设计理念：**
1. **多工具统一管理**：Claude Code、Codex、Gemini CLI、Grok Build、OpenCode、OpenClaw、Hermes Agent、Pi、MiniMax Code 等
2. **Key-Field 写入引擎**：仅修改关键字段，保留用户的其他配置
3. **三种工作模式**：
   - Direct：直接模式，每个工具独立配置
   - Routing：路由模式，通过本地代理路由
   - Aggregation（Stack）：聚合模式，多供应商模型聚合
4. **配置文件保护**：精确修改，保留注释、格式、用户自定义配置
5. **设备本地状态**：live-state.json 记录当前模式和路由

**主要功能模块：**

#### A. 供应商(Provider)管理
- 预设供应商库（100+ 预设）
- 支持自定义供应商
- 按工具分类（Claude Code、Codex等）
- 按区域/计划分组
- API Key 和 Endpoint 配置
- 模型目录管理
- 一键切换供应商

#### B. MCP 服务器管理
- 多工具 MCP 同步（Claude Code、Codex、MiniMax Code、Pi）
- JSON/TOML 导入
- 批量粘贴识别
- 敏感信息遮蔽
- Per-app 重新同步

#### C. 技能(Skills)管理
- 跨工具同步
- 自动更新检测
- 三种同步模式：auto/symlink/copy
- 卸载备份
- 批量操作

#### D. 提示词(Prompts)管理
- 8 个工具的提示词统一管理
- 跨工具复制
- 导入现有文件

#### E. 会话(Sessions)管理
- 多工具会话历史（Claude Code、Codex、Gemini CLI、OpenCode、Grok Build）
- 结构化转录显示
- 搜索和筛选
- Markdown 导出
- 使用统计集成

#### F. 账户与授权
- OAuth 账户管理
- ChatGPT/GitHub Copilot 账户
- 配额显示和刷新
- 重新登录

#### G. 使用统计(Usage)
- 请求日志
- 供应商/模型/定价统计
- 趋势图表（柱状图、热力图）
- 速度和成功率统计
- 成本追踪
- 缓存令牌统计

#### H. 本地路由服务
- 代理服务器
- 故障转移(Failover)
- 请求日志记录
- 协议转换

#### I. 备份与恢复
- 数据库快照
- 配置备份
- 迁移备份
- 技能卸载备份

#### J. 系统集成
- 托盘菜单（按应用分组）
- 快速切换
- 问题提醒
- 应用安装和升级管理

## 二、功能对照表

| 功能模块 | Key Core 当前状态 | CC Switch 功能 | 改造优先级 | 说明 |
|---------|-----------------|---------------|----------|------|
| **密钥管理** | ✅ 完整 | ✅ 作为供应商管理的一部分 | P2 | 保留并增强 |
| **供应商管理** | ⚠️ 简单（平台类型） | ✅ 完整（预设库、分组、切换） | P0 | 核心改造 |
| **多工具配置** | ⚠️ 部分（OpenClaw、Codex等） | ✅ 完整（9+工具） | P0 | 扩展支持 |
| **MCP 管理** | ✅ 基本完整 | ✅ 完整（跨工具同步） | P1 | 增强同步功能 |
| **Skills 管理** | ✅ 基本完整 | ✅ 完整（自动更新、批量操作） | P1 | 增强同步和更新 |
| **Prompts 管理** | ❌ 无 | ✅ 完整 | P1 | 新增 |
| **会话管理** | ❌ 无 | ✅ 完整 | P2 | 新增 |
| **使用统计** | ❌ 无 | ✅ 完整 | P1 | 新增 |
| **配额显示** | ⚠️ 部分（余额查询） | ✅ 完整 | P2 | 增强 |
| **本地路由** | ❌ 无 | ✅ 完整 | P3 | 可选实现 |
| **工作模式** | ❌ 无 | ✅ Direct/Routing/Aggregation | P3 | 可选实现 |
| **备份恢复** | ⚠️ 简单（导入导出） | ✅ 完整（多层备份） | P1 | 增强 |
| **账户管理** | ❌ 无 | ✅ OAuth/ChatGPT/Copilot | P2 | 新增 |
| **托盘菜单** | ✅ 基本 | ✅ 丰富（应用分组、快速切换） | P2 | 增强 |
| **加密存储** | ✅ 完整 | ⚠️ 明文配置文件 | - | Key Core 优势 |
| **离线使用** | ✅ 完整 | ✅ 完整 | - | 都支持 |
| **多语言** | ⚠️ 中英文 | ✅ 中英日德 | P2 | 扩展日语 |

### 优先级说明
- **P0**：核心改造，必须实现
- **P1**：重要功能，应该实现
- **P2**：增强功能，建议实现
- **P3**：高级功能，可选实现

## 三、详细改造方案

### 3.1 架构调整

#### 3.1.1 保持现有技术栈
- 继续使用 Flutter + Dart
- 保持 SQLite 数据库
- 保持 AES-256-GCM 加密
- 保持 Provider 状态管理

#### 3.1.2 新增服务层
```
lib/services/
├── provider_manager_service.dart        # 供应商管理（新增）
├── tool_config_service.dart             # 工具配置管理（增强）
├── usage_tracking_service.dart          # 使用统计（新增）
├── session_manager_service.dart         # 会话管理（新增）
├── prompt_manager_service.dart          # 提示词管理（新增）
├── backup_manager_service.dart          # 备份管理（增强）
└── tool_installer_service.dart          # 工具安装器（新增）
```

#### 3.1.3 数据模型扩展
```
lib/models/
├── provider.dart                        # 供应商模型（新增）
├── provider_preset.dart                 # 预设供应商（新增）
├── tool_config.dart                     # 工具配置（新增）
├── usage_record.dart                    # 使用记录（新增）
├── session.dart                         # 会话模型（新增）
├── prompt.dart                          # 提示词模型（新增）
└── quota.dart                           # 配额模型（新增）
```

### 3.2 数据库模式升级

#### 当前表结构（部分）
```sql
-- ai_keys: 密钥表
-- mcp_servers: MCP 服务器表
-- skills: 技能表
```

#### 新增表结构
```sql
-- providers: 供应商表
CREATE TABLE providers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  provider_type TEXT NOT NULL,  -- 'official', 'relay', 'custom'
  api_endpoint TEXT,
  api_key_encrypted TEXT,
  models TEXT,                   -- JSON array
  supported_tools TEXT,          -- JSON array ['claude_code', 'codex', ...]
  region TEXT,
  plan_type TEXT,
  icon_url TEXT,
  is_active INTEGER DEFAULT 1,
  created_at INTEGER,
  updated_at INTEGER
);

-- tool_configs: 工具配置表（记录每个工具的当前配置）
CREATE TABLE tool_configs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_name TEXT NOT NULL,       -- 'claude_code', 'codex', etc.
  provider_id TEXT,              -- 关联 providers
  mode TEXT DEFAULT 'direct',    -- 'direct', 'routing', 'aggregation'
  config_path TEXT,              -- 配置文件路径
  config_backup TEXT,            -- 配置备份（JSON）
  last_switched_at INTEGER,
  FOREIGN KEY (provider_id) REFERENCES providers(id)
);

-- usage_records: 使用记录表
CREATE TABLE usage_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tool_name TEXT NOT NULL,
  provider_id TEXT,
  model TEXT,
  request_time INTEGER,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_tokens INTEGER,
  cost REAL,
  duration_ms INTEGER,
  first_token_ms INTEGER,
  success INTEGER DEFAULT 1,
  error_message TEXT,
  FOREIGN KEY (provider_id) REFERENCES providers(id)
);

-- sessions: 会话表
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  tool_name TEXT NOT NULL,
  title TEXT,
  project TEXT,
  created_at INTEGER,
  updated_at INTEGER,
  message_count INTEGER,
  total_tokens INTEGER,
  session_file_path TEXT
);

-- prompts: 提示词表
CREATE TABLE prompts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  content TEXT NOT NULL,
  tools TEXT,                    -- JSON array
  tags TEXT,
  created_at INTEGER,
  updated_at INTEGER
);

-- quotas: 配额缓存表
CREATE TABLE quotas (
  provider_id TEXT PRIMARY KEY,
  quota_data TEXT,               -- JSON
  last_updated INTEGER,
  FOREIGN KEY (provider_id) REFERENCES providers(id)
);

-- backups: 备份记录表
CREATE TABLE backups (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  backup_type TEXT NOT NULL,     -- 'database', 'config', 'skill', etc.
  backup_path TEXT NOT NULL,
  size_bytes INTEGER,
  created_at INTEGER,
  description TEXT
);
```

### 3.3 供应商管理系统（P0）

#### 3.3.1 预设供应商库
创建 `assets/config/provider_presets.json`，包含：
- 官方平台：OpenAI、Anthropic、Google、xAI、DeepSeek 等
- 国内平台：智谱、百川、MiniMax、月之暗面、百度、通义等
- 中转服务：主要赞助商的预设（按 CC Switch 的贡献指南标准）

#### 3.3.2 供应商切换流程
1. 用户选择供应商
2. 选择目标工具（Claude Code、Codex 等）
3. 系统读取工具配置文件
4. 仅修改 API Endpoint 和 API Key 字段
5. 保留其他用户配置
6. 原子性写入配置文件
7. 可选：重启提醒

#### 3.3.3 配置文件操作
- 支持 JSON、TOML、JSONC、dotenv 格式
- 保留注释和格式
- 崩溃安全写入
- 自动备份

### 3.4 使用统计系统（P1）

#### 3.4.1 数据收集
- 请求拦截（如果实现本地路由）
- 会话日志导入（Claude Code、Codex、Gemini CLI 等）
- 手动记录

#### 3.4.2 统计维度
- 按供应商统计
- 按模型统计
- 按工具统计
- 按时间统计（小时、天、周、月、全部）

#### 3.4.3 可视化
- 请求日志表格（分页、搜索、筛选）
- 趋势图表（柱状图、热力图）
- 成本统计
- 速度统计（输出速度 = 输出令牌 / 生成时间）
- 成功率统计

### 3.5 会话管理系统（P2）

#### 3.5.1 会话导入
- Claude Code：`~/.claude_code/sessions/`
- Codex：`<config_dir>/state_*.sqlite`
- Gemini CLI：`tmp/<hash>/chats/session-*.jsonl`
- OpenCode：session 数据库
- Grok Build：会话文件

#### 3.5.2 会话展示
- 列表视图（按项目/时间分组）
- 详情视图（结构化转录）
- 支持 Markdown 渲染
- 工具调用展示
- 思考过程展示

#### 3.5.3 会话操作
- 搜索和筛选
- 导出为 Markdown
- 删除会话

### 3.6 提示词管理（P1）

#### 3.6.1 提示词存储
- 本地数据库存储
- 支持分类和标签
- 支持变量替换

#### 3.6.2 跨工具同步
- Claude Code：system prompts
- Codex：system message
- OpenClaw：prompts
- Hermes：SOUL.md
- 其他工具的提示词配置

#### 3.6.3 提示词操作
- 增删改查
- 导入导出
- 模板库

### 3.7 增强 MCP 和 Skills（P1）

#### 3.7.1 MCP 增强
- 支持批量导入（JSON、TOML 混合识别）
- 敏感信息遮蔽
- 跨工具状态同步
- 失败重试机制
- Per-app resync

#### 3.7.2 Skills 增强
- 自动更新检测
- 批量操作（全选、批量启用/禁用）
- 更新通知
- 卸载备份
- 存储管理

### 3.8 备份增强（P1）

#### 3.8.1 多层备份
- 数据库快照（定期、手动）
- 配置文件首次写入备份
- 迁移备份
- 技能卸载备份
- 环境变量清理记录

#### 3.8.2 备份管理
- 列表展示（按类型分类）
- 大小统计
- 恢复功能
- 批量删除
- 自动清理策略

### 3.9 UI/UX 改造（P1）

#### 3.9.1 整体布局
- 侧边栏导航（200px，可折叠为 72px 图标栏）
- 应用列表（带模式标签和提醒点）
- 全局页面（MCP、Skills、Prompts、Sessions、Usage）
- 设置分组（通用、应用配置、本地路由、网络、数据、关于）

#### 3.9.2 供应商页面
- Direct/Routing/Aggregation 模式切换
- 供应商卡片（图标、名称、配额、操作）
- 快速切换
- 配额刷新
- 详细配置表单

#### 3.9.3 使用统计页面
- 筛选栏（时间范围、应用、供应商、模型）
- 指标卡片（总令牌、总成本、请求数、平均速度）
- 趋势图表
- 数据表格（请求日志、供应商、模型、定价）

#### 3.9.4 会话页面
- 会话列表（搜索、筛选、分组）
- 会话详情（结构化转录、Markdown 渲染）
- 使用统计集成

### 3.10 账户管理（P2）

#### 3.10.1 OAuth 集成
- ChatGPT/Codex 账户
- GitHub Copilot 账户
- Google 账户

#### 3.10.2 配额查询
- 实时查询
- 缓存机制
- 剩余量显示
- 重置时间倒计时
- 刷新操作

### 3.11 工具安装器（P2）

#### 3.11.1 工具检测
- 自动检测已安装工具
- 版本检查
- 路径识别

#### 3.11.2 工具管理
- 安装状态显示
- 升级提醒
- 批量升级
- 配置路径管理

### 3.12 高级功能（P3，可选）

#### 3.12.1 本地路由服务
- HTTP 代理服务器
- 请求拦截和日志记录
- 协议转换（Anthropic ↔ OpenAI）
- 故障转移

#### 3.12.2 Aggregation 模式
- 多供应商模型聚合
- 统一模型选择器
- 智能路由

## 四、数据迁移策略

### 4.1 现有数据保留
- `ai_keys` 表保留，作为传统密钥管理
- `mcp_servers` 表保留并扩展
- `skills` 表保留并扩展
- 用户设置保留

### 4.2 数据转换
- 将现有平台类型转换为供应商预设
- 密钥关联到对应供应商
- 配置路径自动检测和填充

### 4.3 兼容模式
- 支持传统密钥管理模式
- 新用户引导选择工作模式
- 逐步迁移提示

## 五、保持兼容的地方

### 5.1 核心功能保持
- 密钥加密存储（Key Core 的核心优势）
- 主密码保护
- 剪贴板保护
- 离线工作
- 跨平台支持

### 5.2 现有用户数据
- 所有现有数据向前兼容
- 数据库自动升级
- 降级保护（新版本数据不破坏旧版本）

### 5.3 API 稳定性
- 服务层接口保持稳定
- 数据库表只增不减（旧表标记为 deprecated）

## 六、技术实施细节

### 6.1 配置文件操作库

#### 6.1.1 TOML 解析
使用 `toml` package (pub.dev)：
```dart
import 'package:toml/toml.dart';

class TomlConfigEditor {
  // 保留格式的 TOML 编辑
  String updateKeyField(String content, String key, String value);
  Map<String, dynamic> parse(String content);
  String stringify(Map<String, dynamic> data);
}
```

#### 6.1.2 JSON/JSONC 解析
使用内置 `dart:convert` + 自定义 JSONC 解析器：
```dart
class JsoncConfigEditor {
  // 保留注释和格式
  String updateKeyField(String content, String key, dynamic value);
  Map<String, dynamic> parse(String content);
  String stringify(Map<String, dynamic> data, {bool preserveComments = true});
}
```

#### 6.1.3 Dotenv 解析
使用 `flutter_dotenv` package：
```dart
class DotenvConfigEditor {
  String updateKeyField(String content, String key, String value);
  Map<String, String> parse(String content);
  String stringify(Map<String, String> data);
}
```

### 6.2 原子性写入

```dart
class AtomicFileWriter {
  Future<void> writeAtomic(String filePath, String content) async {
    // 1. 写入临时文件
    final tempFile = File('$filePath.tmp');
    await tempFile.writeAsString(content);
    
    // 2. 验证内容
    final written = await tempFile.readAsString();
    if (written != content) {
      throw Exception('Write verification failed');
    }
    
    // 3. 原子性重命名
    await tempFile.rename(filePath);
  }
  
  Future<void> writeWithBackup(String filePath, String content) async {
    // 1. 创建备份
    final originalFile = File(filePath);
    if (await originalFile.exists()) {
      final backupPath = await _createBackup(filePath);
      try {
        await writeAtomic(filePath, content);
      } catch (e) {
        // 恢复备份
        await File(backupPath).copy(filePath);
        rethrow;
      }
    } else {
      await writeAtomic(filePath, content);
    }
  }
}
```

### 6.3 会话日志解析

```dart
// Claude Code 会话
class ClaudeCodeSessionParser {
  Future<Session> parseSession(String sessionDir) async {
    final messages = <Message>[];
    // 解析 SQLite 或 JSON 格式
    return Session(messages: messages);
  }
}

// Codex 会话
class CodexSessionParser {
  Future<Session> parseSession(String dbPath) async {
    final db = await openDatabase(dbPath);
    // 查询 state_*.sqlite
    return Session(messages: []);
  }
}

// Gemini CLI 会话
class GeminiSessionParser {
  Future<Session> parseSession(String jsonlPath) async {
    final lines = await File(jsonlPath).readAsLines();
    final messages = <Message>[];
    // 解析 JSONL 格式，处理 $set/$rewindTo
    return Session(messages: messages);
  }
}
```

### 6.4 使用统计聚合

```dart
class UsageAggregator {
  Future<UsageStats> aggregateByProvider(
    String providerId,
    DateTime startTime,
    DateTime endTime,
  ) async {
    final records = await _db.query(
      'usage_records',
      where: 'provider_id = ? AND request_time >= ? AND request_time <= ?',
      whereArgs: [providerId, startTime.millisecondsSinceEpoch, endTime.millisecondsSinceEpoch],
    );
    
    return UsageStats(
      totalRequests: records.length,
      totalTokens: records.fold(0, (sum, r) => sum + (r['input_tokens'] + r['output_tokens'])),
      totalCost: records.fold(0.0, (sum, r) => sum + r['cost']),
      avgSpeed: _calculateAvgSpeed(records),
      successRate: _calculateSuccessRate(records),
    );
  }
}
```

### 6.5 预设供应商数据结构

```dart
class ProviderPreset {
  final String id;
  final String name;
  final String nameZh;  // 中文名
  final String providerType;  // 'official', 'relay', 'custom'
  final String? apiEndpoint;
  final String? websiteUrl;
  final String? apiKeyUrl;
  final List<String> supportedTools;  // ['claude_code', 'codex', ...]
  final List<ModelPreset> models;
  final String? iconUrl;
  final String? family;  // 分组：同一供应商的不同区域/计划
  final String? region;
  final String? planKey;
  final String? description;
  final bool isSponsored;
  
  factory ProviderPreset.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}

class ModelPreset {
  final String id;
  final String displayName;
  final int? contextWindow;
  final int? maxOutputTokens;
  final List<String>? reasoningLevels;  // ['low', 'medium', 'high', ...]
  final bool supportsImages;
  final bool supportsThinking;
  final double? inputPricePerMToken;
  final double? outputPricePerMToken;
  
  factory ModelPreset.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

## 七、实施步骤

### 第一阶段：基础架构（1-2周）

1. ✅ 数据库模式设计和迁移脚本
2. ✅ 新增服务层骨架
3. ✅ 预设供应商数据准备
4. ✅ 配置文件操作库
5. ✅ 原子性写入机制

### 第二阶段：核心功能（2-3周）

6. ✅ 供应商管理系统
7. ✅ 工具配置切换
8. ✅ 使用统计基础
9. ✅ UI 改造（侧边栏布局）
10. ✅ 供应商页面

### 第三阶段：扩展功能（2-3周）

11. ✅ 会话管理系统
12. ✅ 提示词管理
13. ✅ MCP/Skills 增强
14. ✅ 备份管理增强
15. ✅ 使用统计可视化

### 第四阶段：优化和测试（1-2周）

16. ✅ 多语言扩展（日语）
17. ✅ 账户管理
18. ✅ 工具安装器
19. ✅ 性能优化
20. ✅ 全面测试

### 第五阶段：高级功能（可选，2-3周）

21. ⚠️ 本地路由服务
22. ⚠️ Aggregation 模式
23. ⚠️ 故障转移

## 八、测试策略

### 8.1 单元测试
- 配置文件解析和写入
- 数据库操作
- 加密解密
- 数据转换
- 统计计算

### 8.2 集成测试
- 供应商切换流程
- 会话导入
- 使用统计收集
- 备份恢复

### 8.3 E2E 测试
- 完整的用户流程
- 跨工具配置
- 数据迁移

### 8.4 性能测试
- 大量数据加载
- 会话解析性能
- UI 响应性

## 九、风险和挑战

### 9.1 技术风险

| 风险 | 影响 | 缓解措施 |
|-----|-----|---------|
| 配置文件格式多样 | 高 | 使用成熟的解析库，充分测试 |
| 原子性写入失败 | 高 | 多层备份，崩溃恢复机制 |
| 跨平台路径处理 | 中 | 使用 Dart path 库，分平台测试 |
| 性能问题（大量数据） | 中 | 分页、虚拟滚动、数据库索引 |
| 会话格式变化 | 中 | 版本检测，向前兼容 |

### 9.2 用户体验风险

| 风险 | 影响 | 缓解措施 |
|-----|-----|---------|
| 功能复杂度增加 | 中 | 分模式引导，默认简单模式 |
| 数据迁移问题 | 高 | 完整的迁移测试，回滚机制 |
| 配置丢失 | 高 | 多层备份，首次写入备份 |
| 学习曲线 | 低 | 详细文档，视频教程 |

### 9.3 开发风险

| 风险 | 影响 | 缓解措施 |
|-----|-----|---------|
| 工作量估算偏差 | 中 | 分阶段实施，优先级管理 |
| 依赖库问题 | 低 | 选择成熟库，准备备选方案 |
| 跨平台测试不足 | 中 | CI/CD 集成，社区测试 |

## 十、不复制 CC Switch 的理由

### 10.1 技术栈差异
- CC Switch 使用 Tauri + Rust，Key Core 使用 Flutter
- 直接移植代码不可行
- Flutter 生态有自己的最佳实践

### 10.2 保持 Key Core 优势
- 更强的加密和安全特性
- 更好的跨平台 UI 一致性
- Flutter 的热重载开发体验

### 10.3 许可证考虑
- CC Switch 的具体许可证需要遵守
- 独立实现避免许可证问题
- 学习设计理念，而非复制代码

### 10.4 产品定位差异
- Key Core：个人密钥管理 + 工具配置
- CC Switch：企业级工具配置管理器
- Key Core 可以保持更轻量的实现

## 十一、成功标准

### 11.1 功能完整性
- ✅ 支持至少 5 个 AI 工具配置（Claude Code、Codex、OpenClaw、Gemini CLI、MiniMax Code）
- ✅ 预设供应商库至少 50 个
- ✅ MCP/Skills 跨工具同步正常
- ✅ 使用统计完整可用
- ✅ 会话导入至少支持 3 个工具

### 11.2 性能指标
- ⚠️ 应用启动时间 < 2秒
- ✅ 供应商切换时间 < 1秒
- ✅ 会话列表加载（1000条）< 2秒
- ✅ 使用统计图表渲染 < 500ms

### 11.3 稳定性
- ✅ 配置文件写入成功率 > 99.9%
- ✅ 数据库操作成功率 > 99.99%
- ✅ 崩溃恢复成功率 100%
- ✅ 数据迁移成功率 100%

### 11.4 用户体验
- ✅ 新用户上手时间 < 5分钟
- ✅ 核心操作步骤 ≤ 3步
- ⚠️ 错误信息清晰可操作
- ✅ 支持快捷键操作

## 十二、后续维护

### 12.1 版本规划
- 2.0.0：核心改造完成
- 2.1.0：高级功能（本地路由）
- 2.2.0：UI/UX 优化
- 2.3.0：性能优化和 bug 修复

### 12.2 文档计划
- 用户手册（中英文）
- API 文档
- 开发者指南
- 视频教程

### 12.3 社区支持
- GitHub Issues
- 用户反馈收集
- 功能投票
- 贡献者指南

## 十三、参考资料

### 13.1 CC Switch
- GitHub: https://github.com/farion1231/cc-switch
- 最新版本: v4.0.5
- CHANGELOG: 详细的版本变更记录
- 用户手册: docs/user-manual/

### 13.2 相关工具文档
- Claude Code: Anthropic 官方文档
- Codex: OpenAI 官方文档
- OpenClaw: GitHub 仓库
- Gemini CLI: Google 官方文档
- MCP 协议: Anthropic MCP 文档

### 13.3 技术参考
- Flutter 官方文档
- Dart 语言规范
- SQLite 文档
- TOML 规范
- JSON5 规范

---

## 附录：术语表

| 术语 | 说明 |
|-----|------|
| Provider | 供应商，提供 AI API 服务的平台 |
| Tool | 工具，如 Claude Code、Codex 等 AI 编程助手 |
| MCP | Model Context Protocol，模型上下文协议 |
| Skills | 技能，AI 工具的扩展功能 |
| Session | 会话，用户与 AI 工具的对话记录 |
| Prompt | 提示词，AI 工具的系统提示 |
| Direct Mode | 直接模式，每个工具独立配置 |
| Routing Mode | 路由模式，通过本地代理统一路由 |
| Aggregation Mode | 聚合模式，多供应商模型聚合 |
| Quota | 配额，API 使用限额 |
| Key-Field | 关键字段，配置文件中需要修改的核心字段 |
| Atomic Write | 原子性写入，保证写入操作的完整性 |

---

**文档状态：** 待审核  
**最后更新：** 2026-10-09  
**维护者：** Cursor Cloud Agent
