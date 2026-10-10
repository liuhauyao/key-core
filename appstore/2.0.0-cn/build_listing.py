# 中国大陆合规版 App Store 文案：生成 zh-Hans/listing.md、en/listing.md，校验字数与禁用词
import os, re
FORBIDDEN = ['openai','chatgpt','gpt','anthropic','claude','gemini','google','bard','xai','grok','openrouter','codex',
             'copilot','cursor','windsurf','perplexity','mistral','cohere','llama','meta ai','azure','aws','bedrock','hermes','hugging']
L = {
'zh-Hans': dict(
 name='密枢',
 subtitle='AI 密钥管理与一键切换',
 promo='集中管理 DeepSeek、通义千问、智谱 GLM、Kimi、豆包、MiniMax 等大模型平台的 API 密钥，一键切换编程工具当前使用的密钥；MCP 与 Skills 统一同步。数据仅存本机。',
 keywords='API密钥,密钥管理,大模型,DeepSeek,通义千问,智谱,Kimi,豆包,MiniMax,MCP,Skills,编程工具,开发者,OpenClaw',
 desc='''密枢（keycore）是一款面向开发者的本地 API 密钥管理工具。它把分散在各处的大模型平台密钥收进一个整洁的钥匙包，并能直接切换 AI 编程工具当前使用的密钥。

【一处管理所有密钥】
· 卡片化展示，支持分组、标签、置顶与搜索
· 卡片底栏常驻快捷操作：复制密钥、复制请求地址、编辑、打开控制台
· 复制时不在界面上回显密钥

【国内主流大模型平台预设】
· 内置 DeepSeek、通义千问 / 阿里云百炼、智谱 GLM、Kimi / 月之暗面、豆包 / 火山方舟、文心 / 百度千帆、MiniMax、腾讯混元、硅基流动、百川、零一万物等平台模板
· 搜索选择后自动填好请求地址与常用模型，也可以添加自定义平台（如企业内网网关）
· 平台模板可在线更新

【一键切换工具密钥】
· 侧栏按工具查看当前使用的密钥，例如 OpenClaw
· 一把密钥可以启用到多个命令行编程工具，「设为当前」即写入对应工具的配置文件
· 支持 OpenCode、MiniMax Code 等工具的配置写入

【密钥详情】
· 右侧抽屉查看密钥信息、请求地址和在各工具中的启用状态
· 「模型」标签页可查看与刷新该密钥可用的模型列表

【MCP 服务管理】
· 集中维护 MCP 服务，可从模板添加或导入 JSON
· 按工具启用，一次配置同步到多个编程工具
· 同步页逐项对比本地与工具配置的差异，可选择推送、拉取或忽略；环境变量与请求头中的敏感字段自动打码；写入前列出将修改的文件供确认

【Skills 管理】
· 卡片浏览、分类筛选、详情查看
· 一键同步到各个编程工具

【安全与隐私】
· 可设置主密码，密钥加密存储
· 所有数据只保存在本机，不需要账号，不收集任何使用数据
· 本应用本身不提供生成式人工智能服务，只管理你自己的 API 密钥与本地工具配置

【为 macOS 设计】
· 原生风格的侧栏与工具栏，支持浅色 / 深色外观
· 支持简体中文、繁体中文、English 等多种界面语言''',
 whatsnew='''2.0.0 全新版本
· 全新界面：macOS 风格侧栏与工具栏，钥匙包、MCP、Skills 统一卡片与详情抽屉
· 侧栏按工具查看当前密钥，一键切换
· 密钥卡片常驻「复制密钥 / 复制请求地址 / 编辑 / 打开控制台」
· 新的添加密钥表单：可搜索的平台预设
· 密钥详情新增「模型」标签页
· 新增支持 OpenCode、MiniMax Code 等工具
· MCP：按工具启用，全新同步与差异对比页
· Skills：卡片、分类筛选与详情抽屉
· 设置页重新设计
· 修复主密码开启时密钥尾号显示异常等问题''',
 privacy='隐私：密枢不收集、不上传任何个人数据或使用数据，没有统计与追踪 SDK。密钥、MCP 与 Skills 配置只保存在你的 Mac 上；设置主密码后，密钥加密存储。应用只在你主动刷新模型列表或更新平台模板时访问网络，读写编程工具的配置文件也只在你操作时发生。\n支持：如需帮助，请通过 App Store 页面上的「App 支持」链接联系我们，或发邮件至 liuhuayao@126.com。',
),
'en': dict(
 name='keycore',
 subtitle='API key manager & switcher',
 promo='All your LLM API keys in one place — DeepSeek, Qwen, GLM, Kimi, Doubao, MiniMax & more. Switch the key your coding tools use in a click; sync MCP and Skills. Local only.',
 keywords='API key,key manager,LLM,DeepSeek,Qwen,GLM,Kimi,Doubao,MiniMax,MCP,Skills,developer,OpenClaw',
 desc='''keycore is a local API key manager for developers. It gathers your scattered LLM platform keys into one tidy wallet and switches the key your AI coding tools are using.

ALL YOUR KEYS IN ONE PLACE
• Clean cards with groups, tags, pinning and search
• Always-visible quick actions: copy key, copy base URL, edit, open console
• Copying never echoes the key on screen

PLATFORM PRESETS
• Built-in templates for DeepSeek, Qwen / Alibaba Cloud Bailian, Zhipu GLM, Kimi / Moonshot, Doubao / Volcano Ark, ERNIE / Baidu Qianfan, MiniMax, Tencent Hunyuan, SiliconFlow, Baichuan, 01.AI and more
• Pick a platform and the base URL and common models are filled in; custom platforms (e.g. an internal gateway) supported
• Templates can be updated online

SWITCH KEYS PER TOOL
• The sidebar shows the key each tool is using, e.g. OpenClaw
• Enable one key for several command-line coding tools; "Set as current" writes it to that tool's config file
• Also writes configs for OpenCode, MiniMax Code and more

KEY DETAILS
• A side drawer shows the key, base URL and where it is enabled
• A Models tab lists and refreshes the models available to the key

MCP SERVERS
• Maintain MCP servers centrally, from templates or imported JSON
• Enable per tool and sync one config to several coding tools
• The sync view compares local and tool configs item by item — push, pull or ignore; secrets in env vars and headers are masked; files to be written are listed for confirmation

SKILLS
• Browse as cards, filter by category, view details
• Sync to your coding tools in one click

SECURITY & PRIVACY
• Optional master password; keys are stored encrypted
• Everything stays on your Mac — no account, no analytics, no tracking
• keycore itself provides no generative AI service; it only manages your own API keys and local tool configs

DESIGNED FOR macOS
• Native-style sidebar and toolbar, light and dark appearance
• Interface in English, Simplified and Traditional Chinese and more''',
 whatsnew='''keycore 2.0 — a major update
• All-new macOS-style interface with unified cards and side drawers for Keys, MCP and Skills
• See and switch the key each tool is using right from the sidebar
• Key cards with always-visible copy key / copy base URL / edit / open console
• New add-key form with searchable platform presets
• New Models tab in key details
• Support for OpenCode, MiniMax Code and more
• MCP: per-tool enable and a brand-new sync & diff view
• Skills: cards, category filter and details drawer
• Redesigned Settings
• Fixes, including key-suffix display with a master password''',
 privacy='Privacy: keycore does not collect or upload any personal or usage data and contains no analytics or tracking SDKs. Keys, MCP and Skills settings are stored only on your Mac, encrypted when a master password is set. The app goes online only when you refresh a model list or update platform templates, and reads or writes coding-tool config files only when you ask it to.\nSupport: use the "App Support" link on the App Store page, or email liuhuayao@126.com.',
),
}
LIMITS = dict(name=30, subtitle=30, promo=170, keywords=100, desc=4000, whatsnew=4000)
TITLES = dict(name='App 名称 / Name', subtitle='副标题 / Subtitle', promo='推广文本 / Promotional Text', keywords='关键词 / Keywords',
              desc='描述 / Description', whatsnew="此版本新增内容 / What's New (2.0.0)", privacy='隐私与支持 / Privacy & Support')
bad = []
for lang, d in L.items():
    out = [f'# App Store 文案 · keycore 2.0.0 · {lang}（中国大陆合规版）', '', '字数与禁用词已用 build_listing.py 校验。', '']
    for k in ['name','subtitle','promo','keywords','desc','whatsnew','privacy']:
        v = d[k]; n = len(v); lim = LIMITS.get(k)
        if lim and n > lim: bad.append(f'{lang}.{k} {n}>{lim}')
        for w in FORBIDDEN:
            if re.search(r'(?<![a-z])' + re.escape(w) + r'(?![a-z])', v.lower()): bad.append(f'{lang}.{k} 含禁用词 {w}')
        if k == 'keywords': assert all(x.strip()==x and x for x in v.split(','))
        out.append(f'### {TITLES[k]}' + (f'（{n}/{lim} ✓）' if lim else '') + f'\n\n{v}\n')
        print(lang, k, n, lim)
    os.makedirs(lang, exist_ok=True)
    open(f'{lang}/listing.md', 'w').write('\n'.join(out))
assert not bad, bad
print('ALL OK')
