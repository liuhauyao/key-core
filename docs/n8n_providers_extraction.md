# n8n 提供商配置提取汇总

本文档汇总了从 n8n 项目中提取的所有模型供应商和服务提供商的配置信息。

## AI/ML 模型供应商

### 1. OpenAI
- **BaseURL**: `https://api.openai.com/v1`
- **默认URL**: `https://api.openai.com/v1`
- **图标**: `openAi.svg` (已存在: `openai.svg`)
- **管理地址**: `https://platform.openai.com`
- **API Key获取**: `https://platform.openai.com/api-keys`

### 2. Mistral AI
- **BaseURL**: `https://api.mistral.ai`
- **图标**: `mistralAi.svg` (已复制为 `mistral-color.svg`)
- **管理地址**: `https://console.mistral.ai`
- **API Key获取**: `https://console.mistral.ai/api-keys`

### 3. Perplexity
- **BaseURL**: `https://api.perplexity.ai`
- **图标**: `perplexity.svg` (已复制为 `perplexity-color.svg`)
- **管理地址**: `https://www.perplexity.ai`
- **API Key获取**: `https://www.perplexity.ai/settings/api`

### 4. Jina AI
- **BaseURL**: 
  - Reader: `https://r.jina.ai`
  - Search: `https://s.jina.ai`
  - Deep Research: `https://deepsearch.jina.ai`
- **图标**: `jinaAi.svg` (已复制为 `jinaai.svg`)
- **管理地址**: `https://jina.ai`
- **API Key获取**: `https://jina.ai/dashboard`

## 服务提供商

### 1. Supabase
- **BaseURL**: `https://{your_account}.supabase.co/rest/v1`
- **图标**: `supabase.svg` (已存在: `supabase-icon.svg`)
- **管理地址**: `https://app.supabase.com`
- **API Key获取**: `https://app.supabase.com/project/_/settings/api`

### 2. Notion
- **BaseURL**: `https://api.notion.com/v1`
- **OAuth2授权URL**: `https://api.notion.com/v1/oauth/authorize`
- **图标**: `notion.svg` (已存在)
- **管理地址**: `https://www.notion.so`
- **API Key获取**: `https://www.notion.so/my-integrations`

### 3. n8n
- **BaseURL**: `https://{name}.app.n8n.cloud/api/v1` (自定义实例)
- **图标**: `n8n.svg` (已存在: `n8n-color.svg`)
- **管理地址**: `https://app.n8n.cloud` (云版本)
- **API Key获取**: 实例设置中生成

### 4. GitHub
- **BaseURL**: `https://api.github.com`
- **图标**: `github.svg` (已存在)
- **管理地址**: `https://github.com`
- **API Key获取**: `https://github.com/settings/tokens`

### 5. Figma
- **BaseURL**: `https://api.figma.com/v1`
- **图标**: `figma.svg` (已存在: `figma-color.svg`)
- **管理地址**: `https://www.figma.com`
- **API Key获取**: `https://www.figma.com/developers/api#access-tokens`

## 配置更新建议

### 需要添加到 provider_config.dart 的提供商：

1. **Mistral AI** - 新增配置
2. **Perplexity** - 新增配置  
3. **Jina AI** - 新增配置（如果需要）

### 需要更新的现有配置：

1. **OpenAI** - 确认 baseURL 配置正确
2. **Supabase** - 确认 baseURL 格式
3. **Notion** - 确认 OAuth2 配置
4. **n8n** - 确认 baseURL 格式

## 图标文件状态

- ✅ Mistral AI: `mistral-color.svg` (已复制)
- ✅ Perplexity: `perplexity-color.svg` (已复制)
- ✅ Jina AI: `jinaai.svg` (已复制)
- ✅ OpenAI: `openai.svg` (已存在)
- ✅ Supabase: `supabase-icon.svg` (已存在)
- ✅ Notion: `notion.svg` (已存在)
- ✅ n8n: `n8n-color.svg` (已存在)
- ✅ GitHub: `github.svg` (已存在)
- ✅ Figma: `figma-color.svg` (已存在)

