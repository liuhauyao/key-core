# 密钥校验系统设计说明

## 概述

密钥校验系统是密枢（Key Core）项目的核心功能之一，用于验证 API 密钥的有效性、查询可用模型列表以及查询账户余额。系统采用模板化配置和校验器模式，支持多种 API 类型和自定义配置。

## 架构设计

### 核心组件

密钥校验系统由以下核心组件构成：

1. **ValidationConfig（校验配置）**：定义校验规则的数据模型
2. **BaseValidator（校验器基类）**：所有校验器的抽象基类
3. **具体校验器**：针对不同 API 类型的实现
4. **KeyValidationService（校验服务）**：统一入口，负责配置加载和校验器选择
5. **ValidationHelper（校验辅助工具）**：提供 URL 构建、占位符替换等工具方法

### 组件关系图

```
KeyValidationService
    ├── CloudConfigService (加载配置)
    ├── ValidationConfig (解析配置)
    └── BaseValidator (选择校验器)
            ├── OpenAIValidator
            ├── AnthropicValidator
            ├── GoogleValidator
            └── ConfigurableValidator
                    └── ValidationHelper (工具方法)
```

## 校验配置（ValidationConfig）

### 配置结构

校验配置通过 `app_config.json` 中的 `validation` 字段定义，包含以下部分：

1. **基础校验配置**：用于密钥有效性验证
2. **模型列表查询配置**：用于查询可用模型
3. **余额查询配置**：用于查询账户余额

### 配置字段详解

#### 基础字段

- **type**（必需）：校验器类型
  - `openai`：OpenAI 官方 API
  - `openai-compatible`：OpenAI 兼容 API（使用 OpenAIValidator）
  - `anthropic`：Anthropic 官方 API
  - `anthropic-compatible`：Anthropic 兼容 API（使用 AnthropicValidator）
  - `google`：Google API
  - `custom`：自定义配置（使用 ConfigurableValidator）

- **endpoint**（可选）：校验端点路径
  - 相对于 baseUrl 的路径，如 `/v1/messages`
  - 如果为空，校验器会使用默认端点

- **method**（可选）：HTTP 方法
  - 支持：`GET`、`POST`、`PUT`、`DELETE`
  - 默认：`GET`

- **headers**（可选）：请求头映射
  - 键值对为字符串
  - 支持 `{apiKey}` 占位符，会被替换为实际密钥值
  - 示例：`{"Authorization": "Bearer {apiKey}"}`

- **body**（可选）：请求体
  - 仅 POST/PUT 方法使用
  - 支持 `{apiKey}` 占位符
  - 示例：`{"model": "gpt-4", "messages": []}`

- **successStatus**（可选）：成功状态码列表
  - 整数数组，如 `[200, 201]`
  - 如果响应状态码在此列表中，视为校验成功

- **errorStatus**（可选）：错误状态码映射
  - 状态码字符串 -> 错误消息的映射
  - 示例：`{"401": "密钥无效或已过期", "403": "密钥权限不足"}`

- **baseUrlSource**（可选）：baseUrl 来源字段
  - 支持路径：
    - `claudeCode.baseUrl`：从供应商的 claudeCode.baseUrl 获取
    - `codex.baseUrl`：从供应商的 codex.baseUrl 获取
    - `platform.apiEndpoint`：从供应商的 platform.apiEndpoint 获取
  - 如果为空，使用 `fallbackBaseUrl`

- **fallbackBaseUrl**（可选）：备用 baseUrl
  - 当 `baseUrlSource` 为空或无法解析时使用
  - 必须是完整的 HTTPS URL

#### 模型列表查询字段

- **modelsEndpoint**（可选）：模型列表查询端点
  - 如果为空，则不显示"查看模型列表"功能
  - 示例：`/v1/models`、`/models`

- **modelsMethod**（可选）：模型列表查询方法
  - 默认：`GET`

- **modelsResponsePath**（可选）：JSON 响应中模型列表的路径
  - 使用点号分隔的路径，如 `"data"` 表示从 `response.data` 中获取
  - 如果为空，则从响应根级别获取数组

- **modelIdField**（可选）：模型 ID 字段名
  - 默认：`"id"`

- **modelNameField**（可选）：模型名称字段名
  - 默认：`"name"`

- **modelDescriptionField**（可选）：模型描述字段名
  - 默认：`null`（不提取描述）

- **modelsBaseUrlSource**（可选）：模型列表查询的 baseUrl 来源
  - 如果为空，则使用 `baseUrlSource`
  - 允许模型列表使用不同的 baseUrl（例如，某些平台校验和模型列表使用不同的 API 端点）

- **modelsFallbackBaseUrl**（可选）：模型列表查询的备用 baseUrl
  - 如果为空，则使用 `fallbackBaseUrl`

#### 余额查询字段

- **balanceEndpoint**（可选）：余额查询端点
  - 如果为空，则不显示"查询余额"功能
  - 示例：`/users/me/balance`、`/v1/account/balance`

- **balanceMethod**（可选）：余额查询方法
  - 默认：`GET`

- **balanceBody**（可选）：余额查询请求体
  - 仅 POST 方法使用
  - 支持 `{apiKey}` 占位符

- **balanceBaseUrlSource**（可选）：余额查询的 baseUrl 来源
  - 如果为空，则使用 `baseUrlSource`
  - 允许余额查询使用不同的 baseUrl

- **balanceFallbackBaseUrl**（可选）：余额查询的备用 baseUrl
  - 如果为空，则使用 `fallbackBaseUrl`

## 校验器设计

### 校验器基类（BaseValidator）

所有校验器都继承自 `BaseValidator` 抽象类，提供以下功能：

1. **validate 方法**：执行校验的核心方法（子类必须实现）
2. **getBaseUrl**：获取 baseUrl（委托给 ValidationHelper）
3. **replaceApiKeyInHeaders**：替换请求头中的占位符
4. **replaceApiKeyInBody**：替换请求体中的占位符
5. **buildUrl**：构建完整的 URL
6. **handleHttpError**：处理 HTTP 响应错误

### 具体校验器实现

#### OpenAIValidator

用于 OpenAI 官方 API 和所有 OpenAI 兼容 API。

**特点**：
- **完全基于配置驱动**：所有行为都通过 `ValidationConfig` 配置决定
- **默认值仅作后备**：只有在配置缺失时才使用默认值
  - 默认端点为 `/v1/models`（GET 方法）
  - 默认使用 `Authorization: Bearer {apiKey}` 请求头
- **高度灵活**：支持通过配置文件自定义所有参数
  - 自定义 endpoint、method、headers、body
  - 自定义 baseUrlSource 和 fallbackBaseUrl
  - 自定义成功状态码和错误状态码映射
  - 支持模型列表查询和余额查询配置

**使用场景**：
- OpenAI 官方 API
- **所有 OpenAI 兼容的第三方 API**（如火山引擎、OpenRouter、AnyRouter、Azure OpenAI 等）

**重要说明**：
- **配置文件与校验器完全解耦**：所有使用 OpenAI 兼容 API 的供应商都可以通过配置文件中的 `openai-compatible` 类型配置来实现校验
- **无需修改代码**：添加新的 OpenAI 兼容供应商时，只需在配置文件中添加相应的 `validation` 配置，无需编写新的校验器代码
- **配置优先**：如果配置文件中提供了完整的配置，校验器会完全按照配置执行，不会使用任何硬编码的默认值

#### AnthropicValidator

用于 Anthropic 官方 API 和 Anthropic 兼容 API。

**特点**：
- 默认使用 `x-api-key: {apiKey}` 和 `anthropic-version: 2023-06-01` 请求头
- 默认端点为 `/v1/messages`（POST 方法）
- 需要提供 `body` 配置（至少包含 `model` 和 `messages` 字段）

**使用场景**：
- Anthropic 官方 API
- Anthropic 兼容的第三方 API（如 Moonshot/Kimi）

#### GoogleValidator

用于 Google API（如 Gemini）。

**特点**：
- 默认使用 `x-goog-api-key: {apiKey}` 请求头
- 默认端点为 `/models`（GET 方法）

**使用场景**：
- Google Gemini API

#### ConfigurableValidator

通用配置校验器，适用于自定义 API。

**特点**：
- 完全基于配置执行校验
- 不预设任何默认值
- 支持任意 HTTP 方法和请求格式

**使用场景**：
- 不遵循标准 API 格式的第三方服务
- 需要完全自定义的校验逻辑

## 配置文件与校验器解耦设计

### 核心设计理念

**配置文件与校验器完全解耦**：所有使用标准协议（OpenAI、Anthropic、Google）兼容 API 的供应商都可以通过配置文件实现校验，无需修改代码或创建新的校验器。

### 解耦实现方式

1. **统一的校验器类型**：
   - `openai-compatible`：所有 OpenAI 兼容 API 使用 `OpenAIValidator`
   - `anthropic-compatible`：所有 Anthropic 兼容 API 使用 `AnthropicValidator`
   - `google`：所有 Google API 使用 `GoogleValidator`

2. **配置驱动的行为**：
   - 校验器完全基于 `ValidationConfig` 配置执行
   - 所有参数（endpoint、method、headers、body、baseUrl 等）都可通过配置指定
   - 默认值仅作为后备，配置优先

3. **添加新供应商的流程**：
   ```
   添加新供应商 → 在配置文件中添加 validation 配置 → 完成
   ```
   **无需**：
   - 创建新的校验器类
   - 修改现有校验器代码
   - 更新校验器选择逻辑

### 实际应用示例

**火山引擎**（OpenAI 兼容）：
- 类型：`openai-compatible`
- 校验器：`OpenAIValidator`（复用）
- 配置：通过 `app_config.json` 中的 `validation` 字段配置

**OpenRouter**（OpenAI 兼容）：
- 类型：`openai-compatible`
- 校验器：`OpenAIValidator`（复用）
- 配置：只需在配置文件中添加相应的 `validation` 配置

**Moonshot**（Anthropic 兼容）：
- 类型：`anthropic-compatible`
- 校验器：`AnthropicValidator`（复用）
- 配置：通过配置文件指定不同的 endpoint、headers、body

### 优势

1. **零代码修改**：添加新供应商只需更新配置文件
2. **易于维护**：配置集中管理，逻辑清晰
3. **代码简洁**：校验器专注于通用逻辑，不包含特定供应商的硬编码
4. **灵活扩展**：支持不同供应商的个性化配置需求

## 校验流程

### 1. 配置加载

```
KeyValidationService.validateKey()
    └── CloudConfigService.getConfigData()
        └── 加载 app_config.json
            └── 查找对应供应商配置
                └── 获取 validation 配置
```

### 2. 配置解析

如果没有 `validation` 配置，系统会尝试使用默认配置：

- OpenAI 平台：使用 `/models` 端点（GET）
- Anthropic 平台：使用 `/v1/messages` 端点（POST）
- Google 平台：使用 `/models` 端点（GET）

如果都没有匹配，则使用通用校验器。

### 3. 校验器选择

根据 `type` 字段选择对应的校验器：

```dart
switch (type) {
  case 'openai':
  case 'openai-compatible':
    return OpenAIValidator();
  case 'anthropic':
  case 'anthropic-compatible':
    return AnthropicValidator();
  case 'google':
    return GoogleValidator();
  case 'custom':
  default:
    return ConfigurableValidator();
}
```

### 4. 执行校验

校验器执行以下步骤：

1. **解析 baseUrl**：根据 `baseUrlSource` 或 `fallbackBaseUrl` 获取 baseUrl
2. **构建请求**：
   - 替换请求头中的 `{apiKey}` 占位符
   - 替换请求体中的 `{apiKey}` 占位符（如果有）
   - 构建完整的 URL
3. **发送请求**：使用配置的 HTTP 方法发送请求
4. **处理响应**：
   - 检查状态码是否在 `successStatus` 列表中
   - 如果在 `errorStatus` 映射中，返回对应的错误消息
   - 否则返回通用错误

### 5. 返回结果

校验结果通过 `KeyValidationResult` 返回：

- **isValid**：布尔值，表示密钥是否有效
- **message**：字符串，成功或错误消息
- **error**：`ValidationError` 枚举，错误类型

## 密钥同步功能

密钥同步功能整合了三个操作：

1. **校验有效性**：使用基础校验配置
2. **查询模型列表**：使用模型列表查询配置
3. **查询余额**：使用余额查询配置

### 同步流程

```
KeySyncService.syncKey()
    ├── 1. 校验密钥有效性（如果支持）
    │   └── KeyValidationService.validateKey()
    ├── 2. 查询模型列表（如果支持）
    │   └── ModelListService.getModelList()
    │       └── 保存到缓存
    └── 3. 查询余额（如果支持）
        └── BalanceQueryService.queryBalance()
            └── 保存到缓存
```

### 结果汇总

同步服务会汇总三个操作的结果：

- **成功消息**：包含成功操作的信息（如"加载模型 10 个，余额：¥100.00"）
- **错误消息**：包含失败操作的错误信息
- **最终结果**：如果至少有一个操作成功，返回成功；否则返回失败

## 配置示例

### OpenAI 兼容 API 示例

```json
{
  "validation": {
    "type": "openai-compatible",
    "endpoint": "/v1/models",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer {apiKey}"
    },
    "successStatus": [200],
    "baseUrlSource": "platform.apiEndpoint",
    "fallbackBaseUrl": "https://api.openai.com/v1",
    "modelsEndpoint": "/v1/models",
    "modelsMethod": "GET",
    "modelIdField": "id",
    "modelNameField": "id"
  }
}
```

### Anthropic 兼容 API 示例（支持同步）

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
    "modelsBaseUrlSource": "platform.apiEndpoint",
    "modelsFallbackBaseUrl": "https://api.moonshot.cn/v1",
    "balanceEndpoint": "/users/me/balance",
    "balanceMethod": "GET",
    "balanceBaseUrlSource": "platform.apiEndpoint",
    "balanceFallbackBaseUrl": "https://api.moonshot.cn/v1"
  }
}
```

### 阿里云百炼 API 示例（OpenAI 兼容模式）

阿里云百炼（DashScope）提供了 OpenAI 兼容接口，可以使用 `openai-compatible` 类型进行校验。

**API 文档参考**：https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope

**配置示例**：

```json
{
  "validation": {
    "type": "openai-compatible",
    "endpoint": "/models",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer {apiKey}"
    },
    "successStatus": [200],
    "errorStatus": {
      "400": "请求参数错误",
      "401": "API Key 不正确或已过期",
      "429": "请求频率超限或额度不足",
      "500": "服务器错误",
      "503": "服务暂时不可用，请稍后重试"
    },
    "baseUrlSource": "platform.apiEndpoint",
    "fallbackBaseUrls": [
      "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    ],
    "modelsEndpoint": "/models",
    "modelsMethod": "GET",
    "modelIdField": "id",
    "modelNameField": "id",
    "modelsBaseUrlSource": "platform.apiEndpoint",
    "modelsFallbackBaseUrls": [
      "https://dashscope.aliyuncs.com/compatible-mode/v1",
      "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    ]
  }
}
```

**配置说明**：

1. **API 端点**：
   - 基础 URL（北京）：`https://dashscope.aliyuncs.com/compatible-mode/v1`
   - 基础 URL（新加坡）：`https://dashscope-intl.aliyuncs.com/compatible-mode/v1`
   - 使用 `fallbackBaseUrls` 支持多区域自动切换
   - 使用 `platform.apiEndpoint` 作为主要 baseUrl 来源，支持用户自定义端点

2. **鉴权方式**：
   - 使用 Bearer Token 鉴权
   - 请求头格式：`Authorization: Bearer {apiKey}`
   - API Key 可通过阿里云百炼控制台获取：https://dashscope.console.aliyun.com

3. **校验端点**：
   - 使用 `/models` 端点进行密钥有效性校验（注意：不是 `/v1/models`）
   - 由于 baseUrl 已经包含 `/compatible-mode/v1`，所以 endpoint 只需要 `/models`
   - 完整的请求 URL 为：`https://dashscope.aliyuncs.com/compatible-mode/v1/models`
   - 该方法兼容 OpenAI SDK，通过查询模型列表来验证密钥
   - 如果返回 200 状态码，表示密钥有效

4. **模型列表查询**：
   - 使用相同的 `/models` 端点查询可用模型
   - 支持北京和新加坡两个区域的自动切换
   - 响应格式遵循 OpenAI 兼容格式，包含 `data` 数组，每个模型对象包含 `id` 字段

5. **错误处理**：
   - `400`：请求参数错误
   - `401`：API Key 不正确或已过期
   - `429`：请求频率超限或额度不足
   - `500`：服务器错误
   - `503`：服务暂时不可用，请稍后重试

6. **OpenAI SDK 兼容性**：
   - 阿里云百炼完全兼容 OpenAI SDK 1.0+ 版本
   - 可以使用 OpenAI Python SDK 进行调用：
     ```python
     from openai import OpenAI
     client = OpenAI(
         base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
         api_key="your-api-key"
     )
     ```

7. **多区域支持**：
   - 通过 `fallbackBaseUrls` 配置支持北京和新加坡两个区域
   - 系统会按顺序尝试，如果第一个区域失败会自动尝试第二个区域
   - 适用于需要跨区域容灾的场景

8. **注意事项**：
   - 阿里云百炼官方没有提供专门的密钥校验 API，因此使用模型列表接口进行校验
   - 确保 API Key 已开通模型服务权限
   - 需要在阿里云百炼控制台获取 API Key
   - 北京和新加坡区域的 API Key 不同，需要分别获取

### OpenRouter API 示例（OpenAI 兼容模式，支持余额查询）

OpenRouter 提供了 OpenAI 兼容接口，可以使用 `openai-compatible` 类型进行校验，并且支持余额查询功能。

**API 文档参考**：https://openrouter.ai/docs

**配置示例**：

```json
{
  "validation": {
    "type": "openai-compatible",
    "endpoint": "/key",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer {apiKey}"
    },
    "successStatus": [200],
    "errorStatus": {
      "401": "API Key 不正确或已过期",
      "403": "API Key 权限不足",
      "429": "请求频率超限",
      "500": "服务器错误"
    },
    "baseUrlSource": "platform.apiEndpoint",
    "fallbackBaseUrl": "https://openrouter.ai/api/v1",
    "modelsEndpoint": "/models",
    "modelsMethod": "GET",
    "modelsResponsePath": "data",
    "modelIdField": "id",
    "modelNameField": "id",
    "modelsBaseUrlSource": "platform.apiEndpoint",
    "modelsFallbackBaseUrl": "https://openrouter.ai/api/v1",
    "balanceEndpoint": "/key",
    "balanceMethod": "GET",
    "balanceBaseUrlSource": "platform.apiEndpoint",
    "balanceFallbackBaseUrl": "https://openrouter.ai/api/v1"
  }
}
```

**配置说明**：

1. **API 端点**：
   - 基础 URL：`https://openrouter.ai/api/v1`
   - 使用 `platform.apiEndpoint` 作为主要 baseUrl 来源，支持用户自定义端点

2. **鉴权方式**：
   - 使用 Bearer Token 鉴权
   - 请求头格式：`Authorization: Bearer {apiKey}`
   - API Key 可通过 OpenRouter 控制台获取：https://openrouter.ai/keys

3. **校验端点**：
   - 使用 `/key` 端点进行密钥有效性校验
   - 完整的请求 URL 为：`https://openrouter.ai/api/v1/key`
   - 该端点返回 API Key 的详细信息，包括余额和使用情况
   - 如果返回 200 状态码，表示密钥有效

4. **模型列表查询**：
   - 使用 `/models` 端点查询可用模型
   - 完整的请求 URL 为：`https://openrouter.ai/api/v1/models`
   - 响应格式：`{"data": [...]}`，需要设置 `modelsResponsePath: "data"` 来解析模型列表
   - 模型 ID 字段和名称字段都使用 `id`

5. **余额查询**（✅ 支持）：
   - 使用 `/key` 端点查询余额（与校验端点相同）
   - 响应格式：`{"data": {"limit_remaining": 74.5, "limit": 100, ...}}`
   - 余额信息在 `data.limit_remaining` 字段中
   - 如果 `limit` 为 `null`，表示无限制额度，显示为"无限制"
   - 余额以美元（$）为单位显示
   - 还包含使用统计：`usage`、`usage_daily`、`usage_weekly`、`usage_monthly`

6. **错误处理**：
   - `401`：API Key 不正确或已过期
   - `403`：API Key 权限不足
   - `429`：请求频率超限
   - `500`：服务器错误

7. **OpenAI SDK 兼容性**：
   - OpenRouter 完全兼容 OpenAI SDK 1.0+ 版本
   - 可以使用 OpenAI Python SDK 进行调用：
     ```python
     from openai import OpenAI
     client = OpenAI(
         base_url="https://openrouter.ai/api/v1",
         api_key="your-api-key"
     )
     ```

8. **注意事项**：
   - OpenRouter 提供了专门的 `/key` 端点用于校验和余额查询
   - 该端点返回详细的 API Key 信息，包括余额、使用情况等
   - 支持查询模型列表，可以获取所有可用的模型
   - 余额查询和密钥校验使用同一个端点

### Hugging Face API 示例（自定义类型，支持模型列表）

Hugging Face 提供了 REST API 接口，可以使用 `custom` 类型进行校验，并支持模型列表查询功能。

**API 文档参考**：https://huggingface.co/docs/huggingface_hub

**配置示例**：

```json
{
  "validation": {
    "type": "custom",
    "endpoint": "/api/whoami-v2",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer {apiKey}"
    },
    "successStatus": [200],
    "errorStatus": {
      "401": "API Token 无效或已过期",
      "403": "API Token 权限不足",
      "429": "请求频率超限",
      "500": "服务器错误"
    },
    "baseUrlSource": null,
    "fallbackBaseUrl": "https://huggingface.co",
    "modelsEndpoint": "/api/models",
    "modelsMethod": "GET",
    "modelsResponsePath": null,
    "modelIdField": "id",
    "modelNameField": "id",
    "modelDescriptionField": null,
    "modelsBaseUrlSource": null,
    "modelsFallbackBaseUrl": "https://huggingface.co",
    "balanceEndpoint": null,
    "balanceMethod": null,
    "balanceBaseUrlSource": null,
    "balanceFallbackBaseUrl": null
  }
}
```

**配置说明**：

1. **API 端点**：
   - 基础 URL：`https://huggingface.co`
   - 使用 `fallbackBaseUrl` 作为主要 baseUrl，因为 Hugging Face 的 API 端点在主域名下

2. **鉴权方式**：
   - 使用 Bearer Token 鉴权
   - 请求头格式：`Authorization: Bearer {apiKey}`
   - API Token 可通过 Hugging Face 设置页面获取：https://huggingface.co/settings/tokens

3. **校验端点**：
   - 使用 `/api/whoami-v2` 端点进行密钥有效性校验
   - 完整的请求 URL 为：`https://huggingface.co/api/whoami-v2`
   - 该端点返回用户信息，包括用户名、邮箱等
   - 如果返回 200 状态码，表示 Token 有效

4. **模型列表查询**（✅ 支持）：
   - 使用 `/api/models` 端点查询可用模型
   - 完整的请求 URL 为：`https://huggingface.co/api/models`
   - 响应格式：`[{...}, {...}, ...]`，直接返回模型数组
   - 模型 ID 字段和名称字段都使用 `id`
   - 支持分页查询，可以通过 `limit` 和 `page` 参数控制
   - 支持过滤参数：`search`、`author`、`filter`、`sort` 等

5. **余额查询**（❌ 不支持）：
   - Hugging Face 不提供直接的余额查询 API 端点
   - 需要登录网站查看余额：https://huggingface.co/settings/billing
   - 配置中 `balanceEndpoint` 设置为 `null`

6. **错误处理**：
   - `401`：API Token 无效或已过期（可能是旧格式的 token，需要生成新 token）
   - `403`：API Token 权限不足
   - `429`：请求频率超限
   - `500`：服务器错误

7. **注意事项**：
   - Hugging Face 的 API 端点位于主域名 `https://huggingface.co`，而不是 `https://api-inference.huggingface.co`
   - 旧的 API token（以 `api_` 开头）可能不支持 `whoami-v2` 端点，需要生成新的 token
   - 模型列表支持大量过滤和排序选项，可以根据需要配置查询参数
   - 模型列表响应是分页的，可以通过 `Link` 头或查询参数进行分页

### 火山引擎 API 示例（OpenAI 兼容模式）

火山引擎（Volcengine Ark）提供了 OpenAI 兼容接口，可以使用 `openai-compatible` 类型进行校验。

**API 文档参考**：https://www.volcengine.com/docs/82379/1330626?lang=zh

**配置示例**：

```json
{
  "validation": {
    "type": "openai-compatible",
    "endpoint": "/models",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer {apiKey}"
    },
    "successStatus": [200],
    "errorStatus": {
      "401": "密钥无效或已过期",
      "403": "密钥权限不足"
    },
    "baseUrlSource": "platform.apiEndpoint",
    "fallbackBaseUrl": "https://ark.cn-beijing.volces.com/api/v3",
    "modelsEndpoint": "/models",
    "modelsMethod": "GET",
    "modelIdField": "id",
    "modelNameField": "id",
    "modelsBaseUrlSource": "platform.apiEndpoint",
    "modelsFallbackBaseUrl": "https://ark.cn-beijing.volces.com/api/v3"
  }
}
```

**配置说明**：

1. **API 端点**：
   - 基础 URL：`https://ark.cn-beijing.volces.com/api/v3`
   - 当前主要支持北京区域（cn-beijing）
   - 使用 `platform.apiEndpoint` 作为主要 baseUrl 来源，支持用户自定义端点

2. **鉴权方式**：
   - 使用 Bearer Token 鉴权
   - 请求头格式：`Authorization: Bearer {apiKey}`
   - API Key 可通过火山引擎控制台获取：https://console.volcengine.com/ark/keymanage

3. **校验端点**：
   - 使用 `/models` 端点进行密钥有效性校验（注意：不是 `/v1/models`）
   - 由于 baseUrl 已经包含 `/api/v3`，所以 endpoint 只需要 `/models`
   - 完整的请求 URL 为：`https://ark.cn-beijing.volces.com/api/v3/models`
   - 该方法兼容 OpenAI SDK，通过查询模型列表来验证密钥
   - 如果返回 200 状态码，表示密钥有效

4. **模型列表查询**：
   - 使用相同的 `/models` 端点查询可用模型（注意：不是 `/v1/models`）
   - 完整的请求 URL 为：`https://ark.cn-beijing.volces.com/api/v3/models`
   - 响应格式遵循 OpenAI 兼容格式，包含 `data` 数组，每个模型对象包含 `id` 字段
   - 模型 ID 字段和名称字段都使用 `id`

5. **错误处理**：
   - `401`：密钥无效或已过期
   - `403`：密钥权限不足
   - 其他错误按通用错误处理

6. **OpenAI SDK 兼容性**：
   - 火山引擎完全兼容 OpenAI SDK 1.0+ 版本
   - 可以使用 OpenAI Python SDK 进行调用：
     ```python
     from openai import OpenAI
     client = OpenAI(
         base_url="https://ark.cn-beijing.volces.com/api/v3",
         api_key="your-api-key"
     )
     ```

7. **余额查询**：
   - 火山引擎 Ark API（OpenAI 兼容接口）不提供余额查询功能
   - 如需查询账户余额，需要使用火山引擎费用中心的 OpenAPI 接口（`QueryBalanceAcct`）
   - 费用中心 API 使用不同的认证方式和端点，不在当前校验系统范围内
   - 建议通过火山引擎控制台查看余额：https://console.volcengine.com/

8. **注意事项**：
   - 火山引擎官方没有提供专门的密钥校验 API，因此使用模型列表接口进行校验
   - 确保 API Key 已开通模型服务权限
   - 需要在火山引擎控制台获取 Model ID 或 Endpoint ID
   - 当前配置仅支持 Ark API 的校验和模型列表查询，不支持余额查询

9. **故障排除**：
   - 如果遇到 404 错误，请检查：
     - baseUrl 是否正确：应为 `https://ark.cn-beijing.volces.com/api/v3`
     - endpoint 是否正确：应为 `/models`（不是 `/v1/models`）
     - 完整的请求 URL 应为：`https://ark.cn-beijing.volces.com/api/v3/models`
   - 如果 `/models` 端点返回 404，可以尝试：
     - 将 endpoint 改为 `/v1/models`，同时将 baseUrl 改为 `https://ark.cn-beijing.volces.com/api/v3/v1`
     - 或者将 baseUrl 改为 `https://ark.cn-beijing.volces.com`，endpoint 改为 `/api/v3/v1/models`
   - 确保 API Key 有效且具有模型服务权限

### 自定义 API 示例

```json
{
  "validation": {
    "type": "custom",
    "endpoint": "/api/v1/validate",
    "method": "POST",
    "headers": {
      "X-API-Key": "{apiKey}",
      "Content-Type": "application/json"
    },
    "body": {
      "action": "validate",
      "key": "{apiKey}"
    },
    "successStatus": [200, 201],
    "errorStatus": {
      "400": "请求格式错误",
      "401": "密钥无效",
      "500": "服务器错误"
    },
    "baseUrlSource": "platform.apiEndpoint",
    "fallbackBaseUrl": "https://api.example.com"
  }
}
```

## 最佳实践

### 1. 选择合适的校验器类型

- **标准 API**：优先使用对应的官方类型（`openai`、`anthropic`、`google`）
- **兼容 API**：使用兼容类型（`openai-compatible`、`anthropic-compatible`）
- **自定义 API**：使用 `custom` 类型

### 2. 配置 baseUrl 来源

- 优先使用 `baseUrlSource` 引用供应商配置中的字段
- 提供 `fallbackBaseUrl` 作为备用方案
- 如果不同功能需要不同的 baseUrl，使用独立的 `*BaseUrlSource` 字段

### 3. 错误处理

- 为常见错误状态码配置 `errorStatus` 映射，提供友好的错误消息
- 设置 `successStatus` 列表，明确哪些状态码表示成功

### 4. 占位符使用

- 在 `headers` 和 `body` 中使用 `{apiKey}` 占位符
- 系统会自动替换为实际密钥值
- 不要在配置中硬编码密钥值

### 5. 模型列表解析

- 如果 API 返回的模型列表不在根级别，使用 `modelsResponsePath` 指定路径
- 根据实际 API 响应调整 `modelIdField`、`modelNameField` 等字段名

## 扩展性

### 添加新的 OpenAI 兼容供应商（推荐方式）

**无需修改代码，只需添加配置**：

1. 在 `app_config.json` 的 `providers` 数组中添加新的供应商配置
2. 添加 `validation` 配置，设置 `type: "openai-compatible"`
3. 根据供应商的 API 文档配置相应的参数：
   - `endpoint`：校验端点（如 `/models`、`/v1/models`）
   - `baseUrlSource` 或 `fallbackBaseUrl`：API 基础 URL
   - `headers`：请求头（通常包含 `Authorization: Bearer {apiKey}`）
   - `modelsEndpoint`：模型列表查询端点（可选）
   - `balanceEndpoint`：余额查询端点（可选）

**示例**：火山引擎、OpenRouter、AnyRouter 等都可以通过这种方式添加，无需编写新的校验器代码。

### 添加新的校验器类型（仅在必要时）

只有在以下情况才需要创建新的校验器类型：
- API 协议与 OpenAI/Anthropic/Google 完全不兼容
- 需要特殊的校验逻辑（无法通过配置实现）

步骤：
1. 创建新的校验器类，继承 `BaseValidator`
2. 实现 `validate` 方法
3. 在 `KeyValidationService._getValidator` 中添加类型映射

### 添加新的配置字段

1. 在 `ValidationConfig` 模型中添加新字段
2. 更新 `fromJson` 和 `toJson` 方法
3. 在相关校验器中使用新字段
4. 更新本文档说明

### 配置驱动的设计原则

**核心原则**：配置文件与校验器完全解耦

- ✅ **推荐**：通过配置文件添加新的 OpenAI/Anthropic/Google 兼容供应商
- ✅ **推荐**：使用 `openai-compatible`、`anthropic-compatible` 类型
- ❌ **不推荐**：为每个兼容 API 创建新的校验器类型
- ❌ **不推荐**：在校验器中硬编码特定供应商的逻辑

**优势**：
- 添加新供应商无需修改代码，只需更新配置文件
- 配置集中管理，易于维护
- 校验器代码保持简洁，专注于通用逻辑

## 注意事项

1. **安全性**：配置文件中不应包含实际的 API 密钥，使用 `{apiKey}` 占位符
2. **URL 格式**：所有 URL 必须使用 HTTPS
3. **端点路径**：`endpoint`、`modelsEndpoint`、`balanceEndpoint` 都是相对于 baseUrl 的路径
4. **向后兼容**：添加新字段时，应设为可选，避免破坏现有配置
5. **错误处理**：为常见错误提供友好的错误消息映射

