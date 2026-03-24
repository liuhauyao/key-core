# App Store 文案（v1.0.5）

本文档供 **App Store Connect** 使用，包含**简体中文**与**英文**对应版本。已根据当前产品能力做了事实核对（如剪贴板行为、加密描述用语），并避免在文案中出现未获许可的第三方生成式 AI 品牌名。

---

## 副标题建议（Subtitle，≤30 字符）

| 语言 | 文案 |
|------|------|
| 简体中文 | AI 密钥管理与工具配置 |
| English | AI API Keys & Tool Configuration |

*可按实际上架名称「密枢 / Key Core」微调。*

---

## 推广文本（Promotional Text，可选，约 170 字以内）

### 简体中文

集中管理各类 AI 服务的 API 密钥：本地加密、主密码保护、密钥校验与模型列表查询、余额查看、过期提醒，并支持与常用命令行工具配置协同。多语言界面，菜单栏快速访问。

### English

Manage API keys for AI services in one place—local encryption, master password, validation, model lists, balance checks, and expiry reminders—with shortcuts for common CLI tool configs. Multiple languages and menu bar access.

---

## 应用描述（Description）

### 简体中文

**密枢 — AI 密钥管理应用**

密枢是一款 AI 密钥管理应用，帮助开发者、AI 研究者与内容创作者安全、便捷地管理各类 AI 服务的 API 密钥。

**【安全可靠】**

- 采用 AES-256-GCM 加密保护密钥数据  
- 密钥派生经多轮迭代（约 10,000 次）以增强暴力破解难度  
- 主密码保护，数据默认保存在本机，由你掌控  
- 与系统密钥链集成，用于安全存放加密相关材料  

**【功能强大】**

- 支持众多主流 AI 平台与供应商（如 DeepSeek、Minimax、阿里云百炼、火山引擎等，具体以应用内列表为准）  
- **密钥校验**：一键验证密钥有效性，并尽量根据平台能力检测可用性  
- **模型列表**：在支持的平台获取可用模型与相关信息  
- **余额查询**：在支持的平台查看账户余额与用量（视平台接口而定）  
- **过期提醒**：默认提前 7 天提醒即将过期的密钥  
- **搜索与筛选**：按名称、平台、标签、备注快速查找  
- **一键复制**：将密钥复制到系统剪贴板（请在使用后按需自行清理剪贴板）  
- **排序与收藏**：拖拽排序、收藏常用密钥，提高切换效率  

**【界面与体验】**

- 遵循平台设计习惯，浅色/深色主题并可跟随系统  
- 自适应窗口尺寸，交互与动效保持流畅  

**【数据管理】**

- 加密导出与批量导入，便于备份与迁移  
- 统计面板与标签分类，结构化管理密钥  

**【工具集成】**

- **供应商切换**：在 Claude Code、Codex 等场景下，可在官方与第三方供应商配置间切换，减少手工改配置文件  
- 支持多个第三方聚合/转发类供应商（如 PackyCode、AnyRouter、DMXAPI 等，以应用内为准）  
- 切换前可备份当前配置，降低误操作风险  
- **MCP 服务器**：集中管理多组服务器配置  
- 提供 Claude Code、Codex、Gemini 等工具相关配置入口，便于快速切换  
- 支持自定义配置目录，便于与网盘或同步工具配合  

**【国际化】**

- 支持简体中文、繁体中文与英文等多语言界面与提示  

**【性能】**

- 本地 SQLite 存储，常用操作响应快  
- 对配置与列表等数据做缓存，减少重复加载  
- 可最小化至菜单栏，减少 Dock 占用  

无论你是研发、研究还是内容创作，密枢都能帮你把 API 密钥管清楚，把精力放回真正的工作与创作上。

---

### English

**Key Core (密枢) — AI API Key Manager**

Key Core helps developers, researchers, and creators securely manage API keys for AI services—without juggling spreadsheets or scattered notes.

**Security**

- AES-256-GCM encryption for stored key material  
- Key derivation with thousands of iterations to slow brute-force attempts  
- Optional master password; your data stays on your device by default  
- Uses the system keychain for sensitive encryption material where applicable  

**Powerful workflows**

- Broad provider coverage (e.g. DeepSeek, Minimax, Alibaba Bailian, Volcano Engine—see in-app catalog)  
- **Validation**: verify keys where supported by each provider’s API  
- **Model lists**: fetch available models when the provider exposes them  
- **Balance**: check usage/balance when the provider supports it  
- **Expiry reminders**: default alert 7 days before a key expires  
- **Search & filters**: by name, provider, tags, or notes  
- **Copy to clipboard**: one-tap copy (clear the clipboard yourself when finished—no automatic timed clearing)  
- **Reorder & favorites**: organize keys the way you work  

**Design**

- Clean UI with light/dark themes and system appearance support  
- Responsive layout and smooth interactions  

**Data**

- Encrypted export and batch import for backup and migration  
- Statistics and tags to keep large key sets organized  

**Tool integration**

- **Provider switching** for Claude Code, Codex, and similar flows—move between official and third-party endpoints with less manual file editing  
- Support for multiple third-party aggregators/proxies (e.g. PackyCode, AnyRouter, DMXAPI—see in-app)  
- Backup current tool configs before switching when available  
- **MCP servers**: manage multiple server entries in one place  
- Quick access to Claude Code, Codex, Gemini-related settings  
- Custom config directories for sync-friendly setups  

**Languages**

- Simplified Chinese, Traditional Chinese, English, and more  

**Performance**

- Local SQLite storage with responsive queries  
- Caching to avoid redundant loads  
- Menu bar mode to stay out of the Dock when you prefer  

Download Key Core and spend less time managing keys—and more time building.

---

## 此版本更新 / What’s New（v1.0.5）

### 简体中文

**Key Core v1.0.5**

**新增与改进**

- **平台与展示**：新增大量 AI 平台/供应商图标，优化平台分类与浏览方式，便于查找与管理。  
- **验证与查询**：改进密钥校验流程，支持多区域/多 endpoint 尝试；优化验证速度与成功率；扩展模型列表与余额查询的覆盖范围（视各平台接口而定）。  
- **体验**：优化密钥编辑与设置页布局；增强图标选择器，展示更多平台图标。  

**问题修复**

- 修复部分平台图标显示异常。  
- 改进密钥校验超时等边界情况处理。  
- 优化同步与配置刷新逻辑，减少长时间无响应。  

**其他**

- 更新多语言文案。  
- 总体性能与稳定性改进。  

感谢使用！

---

### English

**Key Core v1.0.5**

**New & improved**

- **Catalog & UI**: large batch of new provider icons; clearer categories and browsing.  
- **Validation & insights**: more robust validation with multi-region/endpoint fallbacks; faster checks; broader model list and balance coverage where APIs allow.  
- **UX**: smoother key editing; refined Settings layout; richer icon picker.  

**Fixes**

- Provider icons rendering incorrectly in some cases.  
- Timeouts and edge cases during key validation.  
- Sync/config refresh reliability and long waits.  

**Other**

- Localization updates.  
- General performance and stability improvements.  

Thank you for using Key Core!

---

## 关键词（Keywords）

App Store 关键词总长度通常 **≤100 个字符**（各语种分别填写）；**勿包含**未授权第三方商标或竞品名；以下为逗号分隔，可按区域删词以符合长度。

### 简体中文（示例，请粘贴前核对字数）

```
AI密钥管理,API密钥,密钥管理,加密存储,凭证管理,开发者工具,AI工具,模型列表,余额查询,供应商切换,Claude,Codex,Gemini,MCP,配置同步
```

### English（示例，≤100 字符）

```
api,key,manager,encryption,credential,validation,models,balance,config,MCP,import,export,tools
```

*若超长，可删 `tools` 或 `import,export` 等次优先词。*

*原稿中的「密码管理 / password manager」易与通用密码管理器混淆，已弱化；若你需保留搜索词，可加入 `password` 但可能降低相关性。*

---

## 修订说明（相对原始草稿）

| 项目 | 处理 |
|------|------|
| 剪贴板 30 秒自动清空 | 当前实现为复制后**不**自动定时清空，文案已改为「自行清理剪贴板」并删除误导性承诺。 |
| PBKDF2 表述 | 实现为**多轮迭代 SHA-256 派生**，已改为不强调 PBKDF2 标准名词，避免审核或用户质疑。 |
| 地区 / 合规 | 全文未加入「中国大陆限制」类叙述（与当前产品策略一致）。 |
| 品牌合规 | 正文未写入 OpenAI、ChatGPT 等；第三方供应商与工具名保留为行业常见集成场景描述。 |
| 英文同步 | 与中文章节一一对应，便于多语言上架。 |

---

*文档版本：与 `pubspec.yaml` 中 `1.0.5` 对齐，提交前请再对照实际构建与商店截图更新最后一轮措辞。*
