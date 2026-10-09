/// 各工具配置中由 Key Core “拥有”的关键字段（密钥、地址、模型、协议选择）。
///
/// 借鉴 CC Switch `src-tauri/src/live/floor.rs` 的“关键字段所有权”：切换密钥时，
/// Key Core 只清空并重写这些字段，其他键（hooks、permissions、插件、用户自定义 env 等）
/// 一律不写也不删。清单刻意使用具名键而不是前缀，避免误删无关设置
/// （例如 `CLAUDE_CODE_USE_POWERSHELL_TOOL` 与协议无关）。
class KeyFieldFloor {
  KeyFieldFloor._();

  // ---------------- Claude Code（settings.json 的 env） ----------------

  /// 密钥字段
  static const String claudeAuthToken = 'ANTHROPIC_AUTH_TOKEN';
  static const String claudeApiKey = 'ANTHROPIC_API_KEY';

  /// 请求地址
  static const String claudeBaseUrl = 'ANTHROPIC_BASE_URL';

  /// 模型字段
  static const List<String> claudeModelKeys = [
    'ANTHROPIC_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
  ];

  /// 已废弃的旧模型键：残留时会覆盖 Haiku 档位，切换第三方密钥时一并清除
  static const String claudeSmallFastModel = 'ANTHROPIC_SMALL_FAST_MODEL';

  /// 协议选择器：任何一个为真时 Claude Code 不走 ANTHROPIC_BASE_URL，
  /// 切换到钥匙包中的密钥必须清除，否则切换不生效（与 CC Switch floor.rs 一致）
  static const List<String> claudeProtocolSelectors = [
    'CLAUDE_CODE_USE_BEDROCK',
    'CLAUDE_CODE_USE_VERTEX',
    'CLAUDE_CODE_USE_FOUNDRY',
  ];

  /// AWS Bedrock 的 Bearer Token（CC Switch 预设 “AWS Bedrock (API Key)” 使用）
  static const String claudeBedrockBearerToken = 'AWS_BEARER_TOKEN_BEDROCK';

  /// 允许作为“密钥写入字段”的 env 名（供应商预设的 `claudeCode.apiKeyField`）
  static const List<String> claudeApiKeyFields = [
    claudeAuthToken,
    claudeApiKey,
    claudeBedrockBearerToken,
  ];

  /// 切换到第三方密钥时，写入新值前需要清空的全部 env 键
  static const List<String> claudeKeysClearedOnSwitch = [
    claudeAuthToken,
    claudeApiKey,
    claudeBedrockBearerToken,
    claudeBaseUrl,
    ...claudeModelKeys,
    claudeSmallFastModel,
    ...claudeProtocolSelectors,
  ];

  /// 官方配置编辑器中不可由用户直接编辑、由切换逻辑负责的键
  static const List<String> claudeOfficialManagedKeys = [
    claudeAuthToken,
    claudeBaseUrl,
    ...claudeModelKeys,
  ];

  // ---------------- Gemini CLI（.env） ----------------

  static const String geminiApiKey = 'GEMINI_API_KEY';

  /// 第三方端点（Gemini CLI 读取 `GOOGLE_GEMINI_BASE_URL`）
  static const String geminiBaseUrl = 'GOOGLE_GEMINI_BASE_URL';
  static const String geminiModel = 'GEMINI_MODEL';

  /// 切换时先清空再按密钥写入（`GEMINI_BASE_URL` 是早期误用的旧名，一并清理）
  static const List<String> geminiClearedOnSwitch = [geminiBaseUrl, geminiModel, 'GEMINI_BASE_URL'];

  // ---------------- Codex（auth.json） ----------------

  /// Key Core 可能写入 auth.json 的密钥字段
  static const List<String> codexAuthKeys = [
    'OPENAI_API_KEY',
    'OPENROUTER_API_KEY',
    'GLM_API_KEY',
    'KIMI_API_KEY',
    'AZURE_OPENAI_API_KEY',
    'ANTHROPIC_API_KEY',
    'GOOGLE_GEMINI_API_KEY',
  ];
}
