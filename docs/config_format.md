# 配置文件格式说明

## 概述

本文档详细说明密枢（Key Core）项目配置文件的格式和结构。

## 顶层结构

配置文件 `app_config.json` 遵循以下顶层结构：

```json
{
  "version": "2.0.0",
  "schemaVersion": 2,
  "lastUpdated": "2025-01-20T00:00:00.000000",
  "config": {
    "providers": [...],
    "mcpServerTemplates": [...],
    "codexAuthConfig": {...}
  }
}
```

### 顶层字段说明

- **version**: 配置版本号（语义化版本，如 "2.0.0"）
- **schemaVersion**: 配置架构版本号（整数，用于兼容性检查）
- **lastUpdated**: 最后更新时间（ISO 8601 格式，如 "2025-01-20T00:00:00.000000"）
- **config**: 配置数据对象，包含所有实际配置内容

## 供应商配置（providers）

供应商配置定义了密钥模板，每个供应商可以支持以下能力：

- **claudeCode**: 支持 ClaudeCode 应用
- **codex**: 支持 Codex 应用
- **platform**: 平台预设（用于密钥管理）

### 供应商配置结构

```json
{
  "id": "anthropic",
  "name": "Claude Official",
  "platformType": "anthropic",
  "categories": ["claudeCode", "popular"],
  "providerCategory": "official",
  "websiteUrl": "https://www.anthropic.com/claude-code",
  "apiKeyUrl": "https://console.anthropic.com/settings/keys",
  "isOfficial": true,
  "isPartner": false,
  "claudeCode": {
    "baseUrl": "https://api.anthropic.com",
    "modelConfig": {
      "mainModel": "",
      "haikuModel": "",
      "sonnetModel": "",
      "opusModel": ""
    },
    "endpointCandidates": []
  },
  "codex": {
    "baseUrl": "https://api.openai.com/v1",
    "model": "gpt-5-codex",
    "endpointCandidates": []
  },
  "platform": {
    "managementUrl": "https://console.anthropic.com/settings/keys",
    "apiEndpoint": "https://api.anthropic.com/v1",
    "defaultName": "Anthropic API Key"
  }
}
```

### 供应商字段说明

#### 基础字段

- **id**: 供应商唯一标识（通常与 platformType 相同，必须唯一）
- **name**: 供应商显示名称
- **platformType**: 平台类型（必须与 PlatformType 枚举值匹配）
- **categories**: 分组数组（如 `["claudeCode", "popular"]`）
  - 常见分组：`claudeCode`、`codex`、`popular`
- **providerCategory**: 供应商分类（字符串枚举）
  - `official`: 官方供应商
  - `cnOfficial`: 国内官方供应商
  - `thirdParty`: 第三方供应商
  - `aggregator`: 聚合平台
- **websiteUrl**: 供应商网站地址（必需，必须使用 HTTPS）
- **apiKeyUrl**: API Key 获取地址（可选）
- **isOfficial**: 是否为官方供应商（布尔值）
- **isPartner**: 是否为合作伙伴（布尔值）

#### ClaudeCode 配置（可选）

如果供应商支持 ClaudeCode，需要包含 `claudeCode` 字段：

- **baseUrl**: API 基础地址（必需，必须使用 HTTPS）
- **modelConfig**: 模型配置对象
  - **mainModel**: 主模型名称（字符串，可为空字符串）
  - **haikuModel**: Haiku 模型名称（可选字符串）
  - **sonnetModel**: Sonnet 模型名称（可选字符串）
  - **opusModel**: Opus 模型名称（可选字符串）
- **endpointCandidates**: 请求地址候选列表（可选数组，用于地址管理/测速）

#### Codex 配置（可选）

如果供应商支持 Codex，需要包含 `codex` 字段：

- **baseUrl**: API 基础地址（必需，必须使用 HTTPS）
- **model**: 模型名称（必需字符串）
- **endpointCandidates**: 请求地址候选列表（可选数组）

#### 平台预设配置（可选）

如果供应商需要平台预设信息，需要包含 `platform` 字段：

- **managementUrl**: 密钥管理页面地址（可选字符串，必须使用 HTTPS）
- **apiEndpoint**: API 端点地址（可选字符串，必须使用 HTTPS）
- **defaultName**: 默认密钥名称（可选字符串）

#### 密钥同步配置（可选）

如果供应商支持密钥同步功能（校验有效性、查询模型列表、查询余额），需要包含 `validation` 字段：

```json
{
  "validation": {
    "type": "anthropic-compatible",
    "endpoint": "/v1/messages",
    "method": "POST",
    "headers": {
      "x-api-key": "{apiKey}",
      "anthropic-version": "2023-06-01",
      "content-type": "application/json"
    },
    "body": {
      "model": "moonshot-v1-8k",
      "max_tokens": 1,
      "messages": [
        {
          "role": "user",
          "content": "test"
        }
      ]
    },
    "successStatus": [200],
    "errorStatus": {
      "401": "密钥无效或已过期",
      "403": "密钥权限不足"
    },
    "baseUrlSource": "claudeCode.baseUrl",
    "fallbackBaseUrl": "https://api.moonshot.cn/anthropic",
    "modelsEndpoint": "/models",
    "modelsMethod": "GET",
    "modelsResponsePath": "data",
    "modelIdField": "id",
    "modelNameField": "id",
    "modelDescriptionField": null,
    "modelsBaseUrlSource": "platform.apiEndpoint",
    "modelsFallbackBaseUrl": "https://api.moonshot.cn/v1",
    "balanceEndpoint": "/users/me/balance",
    "balanceMethod": "GET",
    "balanceBaseUrlSource": "platform.apiEndpoint",
    "balanceFallbackBaseUrl": "https://api.moonshot.cn/v1"
  }
}
```

##### 基础校验配置字段

- **type**: 校验器类型（必需字符串枚举）
  - `openai`: OpenAI 官方 API
  - `openai-compatible`: OpenAI 兼容 API
  - `anthropic`: Anthropic 官方 API
  - `anthropic-compatible`: Anthropic 兼容 API
  - `google`: Google API
  - `custom`: 自定义配置
- **endpoint**: 校验端点路径（可选字符串，相对于 baseUrl，如 `/v1/messages`）
- **method**: HTTP 方法（可选字符串，默认 `GET`，支持 `GET`/`POST`/`PUT`/`DELETE`）
- **headers**: 请求头映射（可选对象，键值对为字符串）
  - 支持 `{apiKey}` 占位符，会被替换为实际密钥值
- **body**: 请求体（可选对象，仅 POST/PUT 使用）
  - 支持 `{apiKey}` 占位符，会被替换为实际密钥值
- **successStatus**: 成功状态码列表（可选整数数组，如 `[200, 201]`）
- **errorStatus**: 错误状态码映射（可选对象，状态码字符串 -> 错误消息）
- **baseUrlSource**: baseUrl 来源字段（可选字符串）
  - 支持路径：`claudeCode.baseUrl`、`codex.baseUrl`、`platform.apiEndpoint`
- **fallbackBaseUrl**: 备用 baseUrl（可选字符串，如果 baseUrlSource 为空时使用）

##### 模型列表查询配置字段

- **modelsEndpoint**: 模型列表查询端点（可选字符串，如 `/v1/models`）
  - 如果为空，则不显示"查看模型列表"功能
- **modelsMethod**: 模型列表查询方法（可选字符串，默认 `GET`）
- **modelsResponsePath**: JSON 响应中模型列表的路径（可选字符串）
  - 如 `"data"` 表示从 `response.data` 中获取模型列表
  - 如为空，则从响应根级别获取
- **modelIdField**: 模型 ID 字段名（可选字符串，默认 `"id"`）
- **modelNameField**: 模型名称字段名（可选字符串，默认 `"name"`）
- **modelDescriptionField**: 模型描述字段名（可选字符串，默认 `null`）
- **modelsBaseUrlSource**: 模型列表查询的 baseUrl 来源（可选字符串）
  - 如果为空，则使用 `baseUrlSource`
- **modelsFallbackBaseUrl**: 模型列表查询的备用 baseUrl（可选字符串）
  - 如果为空，则使用 `fallbackBaseUrl`

##### 余额查询配置字段

- **balanceEndpoint**: 余额查询端点（可选字符串，如 `/users/me/balance`）
  - 如果为空，则不显示"查询余额"功能
- **balanceMethod**: 余额查询方法（可选字符串，默认 `GET`）
- **balanceBody**: 余额查询请求体（可选对象，仅 POST 使用）
  - 支持 `{apiKey}` 占位符
- **balanceBaseUrlSource**: 余额查询的 baseUrl 来源（可选字符串）
  - 如果为空，则使用 `baseUrlSource`
- **balanceFallbackBaseUrl**: 余额查询的备用 baseUrl（可选字符串）
  - 如果为空，则使用 `fallbackBaseUrl`

##### 密钥同步功能说明

密钥同步功能整合了三个操作：
1. **校验有效性**：使用 `endpoint`、`method`、`headers`、`body` 配置进行密钥校验
2. **查询模型列表**：使用 `modelsEndpoint` 等配置查询可用模型
3. **查询余额**：使用 `balanceEndpoint` 等配置查询账户余额

同步功能会依次调用这三个接口，统一返回结果。同步成功后，模型列表和余额数据会被缓存到本地，下次显示时直接使用缓存数据。

## MCP 服务器模板（mcpServerTemplates）

MCP 服务器模板定义了可用的 MCP 服务器配置模板。

### MCP 服务器模板结构

#### stdio 类型示例

```json
{
  "serverId": "context7",
  "name": "Context7",
  "description": "Context7 MCP服务器，提供库文档查询功能",
  "category": "popular",
  "serverType": "stdio",
  "command": "npx",
  "args": ["-y", "@upstash/context7-mcp@latest"],
  "env": {
    "CONTEXT7_API_KEY": ""
  },
  "cwd": null,
  "icon": "mcp.svg",
  "tags": ["documentation", "library"],
  "homepage": "https://context7.com",
  "docs": "https://context7.com/docs"
}
```

#### http/sse 类型示例

```json
{
  "serverId": "custom-http-server",
  "name": "Custom HTTP Server",
  "description": "自定义 HTTP MCP 服务器",
  "category": "custom",
  "serverType": "http",
  "url": "https://api.example.com/mcp",
  "headers": {
    "Authorization": "Bearer {TOKEN}"
  },
  "icon": "mcp.svg",
  "tags": ["custom"],
  "homepage": "https://example.com",
  "docs": "https://example.com/docs"
}
```

### MCP 服务器模板字段说明

#### 基础字段

- **serverId**: 服务器唯一标识（必需，必须唯一）
- **name**: 服务器显示名称（必需）
- **description**: 服务器描述（可选字符串）
- **category**: 服务器分类（字符串枚举，必需）
  - `popular`: 常用服务
  - `database`: 数据库类
  - `search`: 搜索类
  - `development`: 开发工具类
  - `cloud`: 云服务类
  - `ai`: AI服务类
  - `automation`: 自动化类
  - `custom`: 自定义
- **serverType**: 服务器类型（字符串枚举，必需）
  - `stdio`: 标准输入输出（命令行）
  - `http`: HTTP 服务器
  - `sse`: Server-Sent Events
- **icon**: 图标文件名（可选字符串，相对于 assets/icons/platforms/）
- **tags**: 标签列表（可选字符串数组）
- **homepage**: 主页地址（可选字符串，必须使用 HTTPS）
- **docs**: 文档地址（可选字符串，必须使用 HTTPS）

#### stdio 类型专用字段

- **command**: 命令（必需字符串，如 "npx"、"python"）
- **args**: 命令参数列表（可选字符串数组）
- **env**: 环境变量映射（可选对象，键值对为字符串）
- **cwd**: 工作目录（可选字符串）

#### http/sse 类型专用字段

- **url**: 服务器URL（必需字符串，必须使用 HTTPS）
- **headers**: HTTP 请求头（可选对象，键值对为字符串）

## Codex 认证配置（codexAuthConfig）

Codex 认证配置定义了不同平台的认证规则。

### Codex 认证配置结构

```json
{
  "rules": [
    {
      "platformType": "openAI",
      "baseUrlPatterns": ["api.openai.com"],
      "supportsAuthJson": true,
      "requiresOpenaiAuth": true,
      "authJsonKey": "OPENAI_API_KEY",
      "wireApi": "chat"
    },
    {
      "platformType": "anyrouter",
      "baseUrlPatterns": ["anyrouter.top", "anyrouter"],
      "supportsAuthJson": true,
      "requiresOpenaiAuth": true,
      "authJsonKey": "OPENAI_API_KEY",
      "wireApi": "responses"
    }
  ],
  "defaultRule": {
    "supportsAuthJson": false,
    "envKeyName": "CODX_API_KEY",
    "requiresOpenaiAuth": false,
    "wireApi": "chat"
  }
}
```

### Codex 认证配置字段说明

#### rules（规则列表）

规则按顺序匹配，第一个匹配的规则会被使用。

- **platformType**: 平台类型（可选字符串，null 表示匹配所有）
- **baseUrlPatterns**: baseUrl 匹配模式列表（可选字符串数组）
  - 如果 baseUrl 包含列表中的任一模式，则匹配
- **supportsAuthJson**: 是否支持 Auth JSON 格式（必需布尔值）
- **envKeyName**: 环境变量名称（可选字符串）
- **requiresOpenaiAuth**: 是否需要 OpenAI 格式认证（必需布尔值）
- **authJsonKey**: Auth JSON 中的键名（可选字符串）
- **wireApi**: 使用的 API 类型（必需字符串枚举）
  - `chat`: 使用 chat API
  - `responses`: 使用 responses API

#### defaultRule（默认规则）

当没有规则匹配时使用的默认规则，字段与 rules 中的规则相同。

## 版本号规范

配置版本号遵循语义化版本规范（Semantic Versioning）：

- **主版本号（Major）**: 不兼容的架构变更
  - 例如：`2.0.0` → `3.0.0`
  - 通常伴随 `schemaVersion` 的更新
- **次版本号（Minor）**: 向后兼容的功能新增
  - 例如：`2.0.0` → `2.1.0`
  - 添加新供应商、新 MCP 模板等
- **修订号（Patch）**: 向后兼容的问题修复
  - 例如：`2.0.0` → `2.0.1`
  - 修正 URL、修正描述、修正配置值等

## 时间格式

`lastUpdated` 字段必须使用 ISO 8601 格式：

```
YYYY-MM-DDTHH:mm:ss.SSSSSS
```

示例：
- `2025-01-20T10:30:45.123456`
- `2025-01-20T16:10:59.293987`

## 验证规则

### 必需字段验证

- 顶层：`version`、`schemaVersion`、`lastUpdated`、`config`
- 供应商：`id`、`name`、`platformType`、`categories`、`providerCategory`、`websiteUrl`
- MCP 模板：`serverId`、`name`、`category`、`serverType`
- stdio 类型：`command`
- http/sse 类型：`url`

### 格式验证

- 所有 URL 字段必须使用 HTTPS
- `version` 必须符合语义化版本规范
- `lastUpdated` 必须符合 ISO 8601 格式
- `id` 和 `serverId` 必须在各自范围内唯一
- `categories` 和 `tags` 必须是字符串数组
- `env` 和 `headers` 必须是字符串键值对对象

### 类型验证

- `version`: 字符串
- `schemaVersion`: 整数
- `lastUpdated`: 字符串
- `isOfficial`: 布尔值
- `isPartner`: 布尔值
- `supportsAuthJson`: 布尔值
- `requiresOpenaiAuth`: 布尔值

## 常见配置示例

### 添加新供应商

```json
{
  "id": "newProvider",
  "name": "New Provider",
  "platformType": "newProvider",
  "categories": ["claudeCode", "popular"],
  "providerCategory": "thirdParty",
  "websiteUrl": "https://newprovider.com",
  "apiKeyUrl": "https://newprovider.com/api-keys",
  "isOfficial": false,
  "isPartner": false,
  "claudeCode": {
    "baseUrl": "https://api.newprovider.com/anthropic",
    "modelConfig": {
      "mainModel": "model-name"
    }
  },
  "platform": {
    "managementUrl": "https://newprovider.com/keys",
    "apiEndpoint": "https://api.newprovider.com/v1",
    "defaultName": "New Provider API Key"
  }
}
```

### 添加新 MCP 服务器模板

```json
{
  "serverId": "new-mcp-server",
  "name": "New MCP Server",
  "description": "新 MCP 服务器描述",
  "category": "development",
  "serverType": "stdio",
  "command": "npx",
  "args": ["-y", "@package/mcp-server@latest"],
  "env": {
    "API_KEY": ""
  },
  "icon": "mcp.svg",
  "tags": ["new", "feature"],
  "homepage": "https://example.com",
  "docs": "https://example.com/docs"
}
```

## 注意事项

1. **向后兼容性**: 修改配置时尽量保持向后兼容，避免破坏现有功能
2. **字段验证**: 确保所有字段值符合预期类型和格式
3. **唯一性**: `id` 和 `serverId` 必须在各自范围内唯一
4. **URL 安全**: 所有 URL 字段必须使用 HTTPS
5. **版本更新**: 每次修改配置后必须更新 `version` 和 `lastUpdated` 字段

