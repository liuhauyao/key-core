# keycore 2.0.0 · 中国大陆 App Store 合规说明（截图与文案）

> 结论先说：中国大陆店面里，**截图和所有元数据（含英文元数据）都不应出现未在中国备案的境外生成式 AI 服务名称或标识**（OpenAI/ChatGPT/GPT、Anthropic/Claude、Google Gemini、xAI/Grok、OpenRouter 等）。本目录的素材已按此改好。**但二进制里仍内置境外平台预设和工具，这是剩余风险**，见第 5 节。我不是律师，以下为公开资料整理，不构成法律意见。

## 1. 调研结论与来源

| # | 规则 / 事实 | 来源 |
|---|---|---|
| 1 | 2023-08 前后，苹果按中国政府要求从中国区下架 100+ 款 ChatGPT 类应用。通知原文：深度合成（DST）/生成式 AI 服务须取得许可（含工信部 MIIT 许可），"your app is associated with ChatGPT, which does not have requisite permits to operate in China"。 | TechCrunch https://techcrunch.com/2023/08/01/generative-ai-services-pulled-from-apple-app-store-in-china-ahead-of-new-regulations/ ；SCMP https://www.scmp.com/tech/policy/article/3229628/apple-removes-over-hundred-chatgpt-apps-china-tighter-regulations-set-take-effect ；China Digital Times（含通知全文）https://chinadigitaltimes.net/2023/08/generative-ai-apps-removed-from-apples-chinese-app-store/ |
| 2 | 审核拒信（Guideline 5 – Legal）原文：功能须在中国区版本中**停用**，并从 **App 名称、副标题、推广文本、描述和截图**中**删除所有 ChatGPT/OpenAI 的提及**；否则可在 App Store Connect「可用性」中取消勾选中国大陆。 | AngularCorp https://www.angularcorp.com/post/apple-review-reject-guideline5legal/ |
| 3 | 实例：描述里提到"把文本交给 ChatGPT、Claude 或 Perplexity"即被拒；只要名称出现在元数据或截图里就足够触发。中国大陆店面在提交时默认勾选。 | pascalhugo.de https://pascalhugo.de/en/hybrid-rejected-china-chatgpt/ |
| 4 | 法律依据：《互联网信息服务深度合成管理规定》（2023-01-10 施行）、《生成式人工智能服务管理暂行办法》（2023-08-15 施行）要求面向公众的生成式 AI 服务做算法备案 / 安全评估；国内平台调用境外模型 API 会被约谈。 | 金杜律师事务所 https://www.kingandwood.com/cn/zh/insights/latest-thinking/notes-on-chatgpt-utilization-for-domestic-platforms.html ；《财经》 https://www.mycaijing.com/article/detail/498288?source_id=40 |
| 5 | 开发者反馈：关键词里带 ChatGPT/OpenAI，或"支持添加 OpenAI 接口"，更新时大概率被以"国内不上架 ChatGPT"为由拒绝；改为只用国内模型后可通过。审核员的判断带主观性。 | V2EX https://www.v2ex.com/t/1075252 |
| 6 | 2026 年起应用商店须核验 AI 应用的备案 / 安全评估情况（《人工智能拟人化互动服务管理暂行办法》第二十五条，2026-07-15 施行）；网信办"清朗·整治 AI 应用乱象"专项行动在批量处置。 | 腾讯云开发者社区 https://cloud.tencent.com/developer/article/2745358 ；搜狐转载 https://www.sohu.com/a/1077148000_122983014 |
| 7 | ICP 备案：自 2023-09 起，苹果要求中国大陆店面的新 App 提供 ICP 备案号，并校验 App 名称是否与工信部记录一致；2024-04 起强校验。境外主体 / 境外服务器曾被放宽，但趋势是收紧。 | Reuters https://www.reuters.com/technology/apple-enforces-new-check-apps-china-beijing-tightens-oversight-2023-10-03/ ；21 财经 https://m.21jingji.com/article/20240404/herald/0186266187de0c6b1e4b0889dc5392a6.html ；腾讯新闻 https://news.qq.com/rain/a/20240402A09UJI00 ；Apple Developer Forums https://developer.apple.com/forums/thread/743661 |
| 8 | Apple《App 审核指南》第 5 条（法律）：App 须遵守所在地区的全部法律；2.3（准确的元数据）要求截图反映 App 实际使用情况。 | https://developer.apple.com/app-store/review/guidelines/#legal ；https://developer.apple.com/app-store/review/guidelines/#accurate-metadata |

**对 keycore 的含义**
- keycore 本身不提供生成式 AI 服务，只管理用户自己的密钥、写入本地工具配置。但拒信的口径是"与某服务**相关联**"（associated with），而不是"是否提供服务"，所以**提到名字就有风险**。
- 工具名也有风险：Claude Code / Claude Desktop 带 Anthropic 的"Claude"品牌；Codex 是 OpenAI 产品；Gemini CLI 是 Google 产品；Grok Build 是 xAI 产品。这些和 ChatGPT 属于同一类，**在中国区元数据和截图里都应避免**。Cursor、Windsurf 是境外 AI 编辑器，也建议避免。OpenCode（开源，可接国内模型）、MiniMax Code（国内）、OpenClaw 风险低。
- ICP 备案：新 App 若在中国大陆上架，需要 ICP 备案号，且名称须与备案一致（"密枢"）。这是独立于本次素材的上架前置条件，请确认。

## 2. 素材审计（修改前）

| 位置 | 出现的境外 AI 品牌 / 名称 |
|---|---|
| 截图 01 钥匙包 | 卡片：Anthropic 官方、Gemini 个人（Google AI）、OpenRouter 测试、Azure 公司（Azure OpenAI）；Anthropic / Google / OpenRouter / Azure logo；侧栏 Claude Code、Claude Desktop、Codex、Gemini（含 logo）；卡片工具徽标里有 Claude / OpenAI 标志；"Active in Claude" |
| 截图 02 工具页 | Claude Code 页：标题、Claude logo、"Claude Official / 官方配置"卡、Anthropic 官方卡、"Keys not enabled for Claude Code"、写入 ~/.claude/settings.json |
| 截图 03 添加密钥 | 供应商列表：Anthropic、OpenRouter、Gemini、xAI 等；分类标签"ClaudeCode 18""Codex 11"；右栏"ClaudeCode 配置"等工具区 |
| 截图 04 详情抽屉 | Anthropic 官方 key；在用工具：Claude Code、Claude Desktop、Codex、Gemini；更多工具：Grok Build、Hermes、Pi；提示文字含"Grok Build" |
| 截图 05 MCP 按工具启用 | 弹窗列出 Cursor、ClaudeCode、Codex、Windsurf、Gemini、Claude Desktop、Grok Build、Hermes 等；侧栏同 01 |
| 截图 06 MCP 同步 | 目标工具 Cursor、ClaudeCode、Codex、Gemini、Claude Desktop；当前选中 Cursor（~/.cursor/mcp.json） |
| 截图 07 Skills | 卡片目标工具图标（Claude / OpenAI）；侧栏同 01 |
| 截图 08 安全 | 侧栏无工具；无问题 |
| Hero（中/英） | 副标题"一键切换到 Claude Code、Codex、Gemini"；内嵌截图同 01 |
| listing 名称 / 副标题 | 无 |
| listing 推广文本 | OpenAI、Anthropic、Claude Code、Codex、Gemini |
| listing 关键词 | Claude Code、Codex、Gemini、OpenAI、Anthropic |
| listing 描述 | OpenAI、Anthropic、Google Gemini、OpenRouter、Claude Code、Claude Desktop、Codex、Gemini、Grok Build、Hermes、Pi、Cursor、Windsurf |
| listing What's New | Grok Build、Hermes、Pi |
| listing 隐私 | 无 |
| CHANGELOG.md（仓库） | 只有在把它当作 What's New 时才算；现在 What's New 用的是 listing 中的独立文本，未直接使用 CHANGELOG |
| 截图机器自动检测 | 用 OCR（tesseract）扫原截图 en/01：识别到 anthropic、azure、claude、codex、gemini、google、openrouter |

## 3. 已做的修改

**演示数据**（只在截图用的临时数据里改，不涉及用户数据）
- 12 把 key 全部改成国内平台：DeepSeek 主力、通义千问 Qwen3、智谱 GLM-4.6、文心 ERNIE 4.5（百度千帆）、Kimi K2、腾讯混元、硅基流动、豆包 · 火山方舟、阿里云百炼、MiniMax M2、百川 Baichuan4、公司内网网关（自定义）
- 用到的工具只有 OpenClaw、OpenCode、MiniMax Code；MCP 同步示例用 OpenCode（含一项"高德地图 amap-maps"MCP）

**截图专用构建开关**（只在 /tmp 的截图构建里加了 `KC_DEMO_CN`，**没有提交到仓库**；源码见 `demo_cn.dart.txt`）
- 隐藏境外工具：侧栏、详情抽屉、添加密钥表单、MCP 启用 / 同步目标、Skills 目标里只保留 OpenClaw / OpenCode / MiniMax Code
- 供应商选择器只列国内平台（白名单 + 中文名平台），并隐藏"ClaudeCode / Codex"分类标签
- 去掉提示文字里的"Grok Build"
- 红绿灯沿用上一轮：macOS 布局（预留 96px），灯画在应用自身顶栏上

**截图与宣传图**
- 中英各 8 张截图和 1 张 hero 全部重拍、重新合成
- 标题文案不再提到境外品牌：例如"一键切换编程工具的当前密钥""国内主流大模型平台预设""Ready-made platform presets"
- OCR 复检（`ocr_audit.txt`）：16 张原截图均未识别到 openai / anthropic / claude / gemini / google / grok / openrouter / codex / cursor / windsurf / azure / hermes / copilot / xai / gpt
- 用旧截图做了阳性对照，同一方法能识别出上述名称

**文案**（`build_listing.py` 生成，并自动校验字数和禁用词）
- "130+ 供应商" 改为 "国内主流大模型平台预设"，列出的平台都是国内的
- 工具一律称作"AI 编程工具 / 命令行编程工具"，只点名 OpenClaw、OpenCode、MiniMax Code
- 关键词去掉 Claude Code、Codex、Gemini、OpenAI、Anthropic；加入通义千问、智谱、Kimi、豆包、MiniMax、OpenClaw
- 描述里新增一句："本应用本身不提供生成式人工智能服务，只管理你自己的 API 密钥与本地工具配置"
- 英文名为 keycore；英文元数据同样不含境外 AI 品牌（中国大陆店面也会展示英文元数据）
- 禁用词表：openai、chatgpt、gpt、anthropic、claude、gemini、google、bard、xai、grok、openrouter、codex、copilot、cursor、windsurf、perplexity、mistral、cohere、llama、meta ai、azure、aws、bedrock、hermes、hugging

## 4. 关于"不误导"

- 截图里隐藏了境外工具和平台，而**当前 2.0.0 二进制在运行时仍会显示它们**。按 2.3（截图须反映 App 实际使用），审核员装机后看到 Claude Code / OpenAI 等，可能认为截图与 App 不符，也可能直接以第 5 条拒绝。
- 文案没有声称"不支持"任何工具，只是用通用措辞，没有编造功能。

## 5. 剩余风险（二进制）与建议

二进制里实际存在的境外内容：
- 内置平台：OpenAI、Anthropic、Google AI、Gemini、Azure OpenAI、AWS、xAI、OpenRouter、Mistral、Cohere、Perplexity 等
- 内置配置 `assets/config/app_config.json`：openai 出现 415 次、claude 1256 次、grok 83 次……
- 在线模板从 GitHub / Gitee 拉取同一份 `app_config.json`
- 境外品牌 logo 12 个
- 工具页 / 写入：Claude Code、Claude Desktop、Codex、Gemini CLI、Grok Build、Cursor、Windsurf 等

审核员很可能在打开 App 的第一屏就看到这些（侧栏 Claude Code、Codex 等）。

**方案（按稳妥程度）**
- **A. 中国大陆单独构建（推荐，要中国区上架就必须做）**：仿照本次截图开关，正式增加 `KC_REGION=cn`（或 `KC_EDITION=appstore_cn`），做到：
  - 隐藏境外平台预设和 logo；在线模板下发 CN 专用版本（服务端过滤，或 `app_config_cn.json`）
  - 隐藏 Claude Code、Claude Desktop、Codex、Gemini、Grok Build、Cursor、Windsurf 等工具，只保留 OpenClaw、OpenCode、MiniMax Code（Hermes / Pi 可按需评估）
  - 用户仍可添加"自定义平台"。这一点要在审核备注里说明：只用于企业内网 / 国内平台网关
  - 在 Review Notes 里写明：中国区版本已停用境外服务相关功能，App 本身不提供生成式 AI 服务

  难点：App Store 同一个 App 只能上传一个二进制，各店面共用。所以要么全球都用 CN 构建（会丢掉海外用户最看重的 Claude Code / Codex 功能），要么用另一个 Bundle ID 单独上架一个中国版 App（还需要单独的 ICP 备案）。
- **B. 不在中国大陆店面上架（最简单、风险最低）**：在 App Store Connect →「定价与销售范围」中取消勾选中国大陆。全球版保留完整功能、使用原来的截图和文案（之前的 `screenshots/` 与 `listing.md`）。国内用户可用开源版 / DMG。
- **C. 全球一个二进制，只给中国大陆本地化元数据**：只换中国区的截图和文案（即本目录），二进制不变。被拒概率高（见第 4 节和第 1 节 #2、#5），**不推荐**。即便过审，后续抽查或更新时也可能被下架。
- 若选 A 并在中国大陆上架，还需要 **ICP 备案号**，且名称须与"密枢"一致（第 1 节 #7）。

**我的建议**：2.0.0 先用 **B**（全球版完整功能，不选中国大陆），避免卡审；同时开发 A，作为单独的中国大陆版。如果坚持全球只上一个 App 且包含中国区，至少要把 A 的过滤做进正式构建，并接受海外功能被删减。

## 6. 文件清单

```
keycore-appstore-2.0.0/
├── COMPLIANCE.md                 本文
├── build_listing.py              文案生成 + 字数 / 禁用词校验
├── compose_cn.py                 合成脚本（红绿灯沉浸到应用顶栏）
├── demo_cn.dart.txt              截图专用过滤代码（未入库，供实现方案 A 参考）
├── ocr_audit.txt                 OCR 复检结果
├── icon_1024.png
├── zh-Hans/  listing.md · hero_2880x1800.png · screenshots/01–08_*.png（2880×1800）· raw/
└── en/       listing.md · hero_2880x1800.png · screenshots/01–08_*.png（2880×1800）· raw/
```
