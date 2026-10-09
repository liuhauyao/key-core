// 测试用假数据：与 UI mockup 同一批密钥（全部为虚构值，不含任何真实凭据）。
import 'package:key_core/models/ai_key.dart';
import 'package:key_core/models/platform_type.dart';

final DateTime _base = DateTime(2026, 10, 9, 10);

AIKey fakeKey(
  int id,
  String name,
  PlatformType platform, {
  List<String> tags = const [],
  bool claudeCode = false,
  bool claudeDesktop = false,
  bool codex = false,
  bool gemini = false,
  bool openclaw = false,
  bool favorite = false,
  String? model,
  DateTime? expiry,
}) {
  return AIKey(
    id: id,
    name: name,
    platform: platform.value,
    platformType: platform,
    keyValue: 'sk-test-$id-demo0000${id.toString().padLeft(4, '0')}',
    tags: tags,
    createdAt: _base.subtract(Duration(days: 30 - id)),
    updatedAt: _base.subtract(Duration(minutes: id)),
    isFavorite: favorite,
    expiryDate: expiry,
    apiEndpoint: 'https://api.example.com/$id',
    enableClaudeCode: claudeCode,
    claudeCodeBaseUrl: claudeCode ? 'https://api.example.com/anthropic' : null,
    claudeCodeModel: claudeCode ? model : null,
    enableClaudeDesktop: claudeDesktop,
    claudeDesktopBaseUrl: claudeDesktop ? 'https://api.example.com/anthropic' : null,
    enableCodex: codex,
    codexBaseUrl: codex ? 'https://api.example.com/v1' : null,
    codexModel: codex ? model : null,
    enableGemini: gemini,
    geminiModel: gemini ? model : null,
    enableOpenclaw: openclaw,
    openclawModel: openclaw ? model : null,
  );
}

/// 12 把密钥（与 mockup 01 一致的名称），顺序即钥匙包里的显示顺序。
List<AIKey> buildFakeKeys() => [
      fakeKey(1, 'DeepSeek 主力', PlatformType.deepSeek,
          tags: ['工作'], claudeCode: true, codex: true, openclaw: true, favorite: true, model: 'deepseek-chat'),
      fakeKey(2, 'Anthropic 官方', PlatformType.anthropic,
          tags: ['工作'], claudeCode: true, claudeDesktop: true, favorite: true),
      fakeKey(3, '智谱 GLM-4.6', PlatformType.zhipu, tags: ['编程'], claudeCode: true, openclaw: true, model: 'glm-4.6'),
      fakeKey(4, 'Gemini 个人', PlatformType.google, tags: ['个人'], gemini: true, model: 'gemini-2.5-pro'),
      fakeKey(5, 'Kimi K2', PlatformType.kimi, tags: ['编程'], claudeCode: true, model: 'kimi-k2-turbo-preview'),
      fakeKey(6, 'OpenRouter 测试', PlatformType.openRouter, tags: ['测试'], codex: true, model: 'openai/gpt-5'),
      fakeKey(7, '硅基流动', PlatformType.siliconFlow, tags: ['个人']),
      fakeKey(8, '火山方舟', PlatformType.volcengine, tags: ['工作']),
      fakeKey(9, '百炼 Qwen', PlatformType.bailian, tags: ['工作'], codex: true, model: 'qwen3-coder-plus'),
      fakeKey(10, 'MiniMax M2', PlatformType.minimax, tags: ['编程'], claudeCode: true, model: 'MiniMax-M2'),
      fakeKey(11, 'Azure 公司', PlatformType.azureOpenAI, tags: ['工作']),
      fakeKey(12, '公司内网网关', PlatformType.custom, tags: ['内网']),
    ];
