import 'package:flutter/material.dart';

/// AI平台类型枚举
enum PlatformType {
  openAI(value: 'OpenAI', icon: Icons.smart_toy, color: Colors.green),
  anthropic(value: 'Anthropic', icon: Icons.psychology, color: Colors.orange),
  google(value: 'Google AI', icon: Icons.bolt, color: Colors.blue),
  azureOpenAI(value: 'Azure OpenAI', icon: Icons.cloud, color: Colors.lightBlue),
  aws(value: 'AWS', icon: Icons.cloud_queue, color: Colors.deepOrange),
  // 国产平台
  minimax(value: 'MiniMax', icon: Icons.auto_awesome, color: Colors.purple),
  deepSeek(value: 'DeepSeek', icon: Icons.explore, color: Colors.teal),
  siliconFlow(value: 'SiliconFlow', icon: Icons.account_tree, color: Colors.indigo),
  zhipu(value: '智谱AI', icon: Icons.psychology_outlined, color: Colors.blueAccent),
  bailian(value: '百炼云', icon: Icons.cloud_done, color: Colors.orangeAccent),
  baidu(value: '百度千帆', icon: Icons.search, color: Colors.red),
  qwen(value: '通义千问', icon: Icons.chat_bubble_outline, color: Colors.deepPurple),
  // 其他AI平台
  n8n(value: 'n8n', icon: Icons.settings_applications, color: Colors.blueGrey),
  dify(value: 'Dify', icon: Icons.auto_awesome_motion, color: Colors.cyan),
  openRouter(value: 'OpenRouter', icon: Icons.router, color: Colors.deepPurpleAccent),
  huggingFace(value: 'Hugging Face', icon: Icons.face, color: Colors.yellow),
  qdrant(value: 'Qdrant', icon: Icons.storage, color: Colors.purpleAccent),
  volcengine(value: '火山引擎', icon: Icons.local_fire_department, color: Colors.redAccent),
  // 国际LLM提供商
  mistral(value: 'Mistral AI', icon: Icons.auto_awesome, color: Colors.indigo),
  cohere(value: 'Cohere', icon: Icons.chat_bubble, color: Colors.blue),
  perplexity(value: 'Perplexity', icon: Icons.search, color: Colors.teal),
  gemini(value: 'Gemini', icon: Icons.auto_awesome, color: Colors.blue),
  xai(value: 'xAI', icon: Icons.rocket_launch, color: Colors.black),
  ollama(value: 'Ollama', icon: Icons.computer, color: Colors.blueGrey),
  // 国产LLM提供商
  moonshot(value: '月之暗面', icon: Icons.nightlight_round, color: Colors.deepPurple),
  zeroOne(value: '零一万物', icon: Icons.one_k, color: Colors.orange),
  baichuan(value: '百川智能', icon: Icons.water_drop, color: Colors.lightBlue),
  wenxin(value: '文心一言', icon: Icons.chat, color: Colors.red),
  kimi(value: 'Kimi', icon: Icons.chat_bubble_outline, color: Colors.purple),
  nova(value: 'Nova', icon: Icons.star, color: Colors.amber),
  // ClaudeCode 专用供应商（没有独立平台类型）
  zai(value: 'Z.ai GLM', icon: Icons.psychology_outlined, color: Colors.blueAccent),
  katCoder(value: 'KAT-Coder', icon: Icons.code, color: Colors.indigo),
  longcat(value: 'Longcat', icon: Icons.chat_bubble_outline, color: Colors.purple),
  bailing(value: 'BaiLing', icon: Icons.auto_awesome, color: Colors.orange),
  modelScope(value: 'ModelScope', icon: Icons.account_tree, color: Colors.indigo),
  aihubmix(value: 'AiHubMix', icon: Icons.router, color: Colors.deepPurpleAccent),
  dmxapi(value: 'DMXAPI', icon: Icons.api, color: Colors.blueGrey),
  packycode(value: 'PackyCode', icon: Icons.code, color: Colors.purple),
  anyrouter(value: 'AnyRouter', icon: Icons.router, color: Colors.deepPurpleAccent),
  // 云服务平台
  tencent(value: '腾讯云', icon: Icons.cloud, color: Colors.blueAccent),
  alibaba(value: '阿里云', icon: Icons.cloud_circle, color: Colors.orange),
  // 向量数据库
  pinecone(value: 'Pinecone', icon: Icons.forest, color: Colors.green),
  weaviate(value: 'Weaviate', icon: Icons.schema, color: Colors.purple),
  // 后端即服务
  supabase(value: 'Supabase', icon: Icons.storage_outlined, color: Colors.greenAccent),
  notion(value: 'Notion', icon: Icons.note, color: Colors.black),
  // 其他平台
  bytedance(value: '字节跳动', icon: Icons.business, color: Colors.blue),
  // 工具平台
  github(value: 'GitHub', icon: Icons.code, color: Colors.black),
  githubCopilot(value: 'GitHub Copilot', icon: Icons.auto_fix_high, color: Colors.purple),
  gitee(value: 'Gitee', icon: Icons.storage, color: Colors.red),
  coze(value: 'Coze', icon: Icons.chat_bubble_outline, color: Colors.blue),
  figma(value: 'Figma', icon: Icons.design_services, color: Colors.purple),
  v0(value: 'v0', icon: Icons.auto_awesome, color: Colors.indigo),
  custom(value: 'Custom', icon: Icons.code, color: Colors.grey);

  const PlatformType({
    required this.value,
    required this.icon,
    required this.color,
  });

  final String value;
  final IconData icon;
  final Color color;

  /// 从字符串获取枚举
  /// 支持两种格式：
  /// 1. 枚举名称（如 "deepSeek", "openAI"）- 使用 e.name
  /// 2. 枚举的 value（如 "DeepSeek", "OpenAI"）- 使用 e.value
  static PlatformType fromString(String str) {
    // 先尝试通过枚举名称匹配（e.name 返回枚举名称，如 "deepSeek"）
    final byName = PlatformType.values.where(
      (e) => e.name == str,
    );
    if (byName.isNotEmpty) {
      return byName.first;
    }
    
    // 如果枚举名称匹配失败，尝试通过 value 匹配
    return PlatformType.values.firstWhere(
      (e) => e.value == str || e.value.toLowerCase() == str.toLowerCase(),
      orElse: () => PlatformType.custom,
    );
  }

  /// 获取所有值用于下拉选择
  static List<PlatformType> get all => PlatformType.values;
}
