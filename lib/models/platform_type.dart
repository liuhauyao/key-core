import 'package:flutter/material.dart';

/// AI平台类型类（从枚举重构为类以支持动态平台）
class PlatformType {
  final String id;
  final String value;
  final String iconName;
  final Color color;
  final bool isBuiltin;

  /// 私有构造函数（用于内置平台）
  const PlatformType._({
    required this.id,
    required this.value,
    required this.iconName,
    required this.color,
    this.isBuiltin = true,
  });

  /// 动态平台构造函数（用于从云端配置加载）
  PlatformType.dynamic({
    required this.id,
    required this.value,
    required this.iconName,
    required this.color,
  }) : isBuiltin = false;

  // ==================== 内置平台常量 ====================
  
  // AI 平台
  static const openAI = PlatformType._(
    id: 'openAI',
    value: 'OpenAI',
    iconName: 'smart_toy',
    color: Colors.green,
  );
  
  static const anthropic = PlatformType._(
    id: 'anthropic',
    value: 'Anthropic',
    iconName: 'psychology',
    color: Colors.orange,
  );
  
  static const google = PlatformType._(
    id: 'google',
    value: 'Google AI',
    iconName: 'bolt',
    color: Colors.blue,
  );
  
  static const azureOpenAI = PlatformType._(
    id: 'azureOpenAI',
    value: 'Azure OpenAI',
    iconName: 'cloud',
    color: Colors.lightBlue,
  );
  
  static const aws = PlatformType._(
    id: 'aws',
    value: 'AWS',
    iconName: 'cloud_queue',
    color: Colors.deepOrange,
  );
  
  // 国产平台
  static const minimax = PlatformType._(
    id: 'minimax',
    value: 'MiniMax',
    iconName: 'auto_awesome',
    color: Colors.purple,
  );
  
  static const deepSeek = PlatformType._(
    id: 'deepSeek',
    value: 'DeepSeek',
    iconName: 'explore',
    color: Colors.teal,
  );
  
  static const siliconFlow = PlatformType._(
    id: 'siliconFlow',
    value: 'SiliconFlow',
    iconName: 'account_tree',
    color: Colors.indigo,
  );
  
  static const zhipu = PlatformType._(
    id: 'zhipu',
    value: '智谱AI',
    iconName: 'psychology_outlined',
    color: Colors.blueAccent,
  );
  
  static const bailian = PlatformType._(
    id: 'bailian',
    value: '百炼云',
    iconName: 'cloud_done',
    color: Colors.orangeAccent,
  );
  
  static const baidu = PlatformType._(
    id: 'baidu',
    value: '百度千帆',
    iconName: 'search',
    color: Colors.red,
  );
  
  static const qwen = PlatformType._(
    id: 'qwen',
    value: '通义千问',
    iconName: 'chat_bubble_outline',
    color: Colors.deepPurple,
  );
  
  // 其他AI平台
  static const n8n = PlatformType._(
    id: 'n8n',
    value: 'n8n',
    iconName: 'settings_applications',
    color: Colors.blueGrey,
  );
  
  static const dify = PlatformType._(
    id: 'dify',
    value: 'Dify',
    iconName: 'auto_awesome_motion',
    color: Colors.cyan,
  );
  
  static const openRouter = PlatformType._(
    id: 'openRouter',
    value: 'OpenRouter',
    iconName: 'router',
    color: Colors.deepPurpleAccent,
  );
  
  static const huggingFace = PlatformType._(
    id: 'huggingFace',
    value: 'Hugging Face',
    iconName: 'face',
    color: Colors.yellow,
  );
  
  static const qdrant = PlatformType._(
    id: 'qdrant',
    value: 'Qdrant',
    iconName: 'storage',
    color: Colors.purpleAccent,
  );
  
  static const volcengine = PlatformType._(
    id: 'volcengine',
    value: '火山引擎',
    iconName: 'local_fire_department',
    color: Colors.redAccent,
  );
  
  // 国际LLM提供商
  static const mistral = PlatformType._(
    id: 'mistral',
    value: 'Mistral AI',
    iconName: 'auto_awesome',
    color: Colors.indigo,
  );
  
  static const cohere = PlatformType._(
    id: 'cohere',
    value: 'Cohere',
    iconName: 'chat_bubble',
    color: Colors.blue,
  );
  
  static const perplexity = PlatformType._(
    id: 'perplexity',
    value: 'Perplexity',
    iconName: 'search',
    color: Colors.teal,
  );
  
  static const gemini = PlatformType._(
    id: 'gemini',
    value: 'Gemini',
    iconName: 'auto_awesome',
    color: Colors.blue,
  );
  
  static const xai = PlatformType._(
    id: 'xai',
    value: 'xAI',
    iconName: 'rocket_launch',
    color: Colors.black,
  );
  
  static const ollama = PlatformType._(
    id: 'ollama',
    value: 'Ollama',
    iconName: 'computer',
    color: Colors.blueGrey,
  );
  
  // 国产LLM提供商
  static const moonshot = PlatformType._(
    id: 'moonshot',
    value: '月之暗面',
    iconName: 'nightlight_round',
    color: Colors.deepPurple,
  );
  
  static const zeroOne = PlatformType._(
    id: 'zeroOne',
    value: '零一万物',
    iconName: 'one_k',
    color: Colors.orange,
  );
  
  static const baichuan = PlatformType._(
    id: 'baichuan',
    value: '百川智能',
    iconName: 'water_drop',
    color: Colors.lightBlue,
  );
  
  static const wenxin = PlatformType._(
    id: 'wenxin',
    value: '文心一言',
    iconName: 'chat',
    color: Colors.red,
  );
  
  static const kimi = PlatformType._(
    id: 'kimi',
    value: 'Kimi',
    iconName: 'chat_bubble_outline',
    color: Colors.purple,
  );
  
  static const nova = PlatformType._(
    id: 'nova',
    value: 'Nova',
    iconName: 'star',
    color: Colors.amber,
  );
  
  // ClaudeCode 专用供应商
  static const zai = PlatformType._(
    id: 'zai',
    value: 'Z.ai GLM',
    iconName: 'psychology_outlined',
    color: Colors.blueAccent,
  );
  
  static const katCoder = PlatformType._(
    id: 'katCoder',
    value: 'KAT-Coder',
    iconName: 'code',
    color: Colors.indigo,
  );
  
  static const longcat = PlatformType._(
    id: 'longcat',
    value: 'Longcat',
    iconName: 'chat_bubble_outline',
    color: Colors.purple,
  );
  
  static const bailing = PlatformType._(
    id: 'bailing',
    value: 'BaiLing',
    iconName: 'auto_awesome',
    color: Colors.orange,
  );
  
  static const modelScope = PlatformType._(
    id: 'modelScope',
    value: 'ModelScope',
    iconName: 'account_tree',
    color: Colors.indigo,
  );
  
  static const aihubmix = PlatformType._(
    id: 'aihubmix',
    value: 'AiHubMix',
    iconName: 'router',
    color: Colors.deepPurpleAccent,
  );
  
  static const dmxapi = PlatformType._(
    id: 'dmxapi',
    value: 'DMXAPI',
    iconName: 'api',
    color: Colors.blueGrey,
  );
  
  static const packycode = PlatformType._(
    id: 'packycode',
    value: 'PackyCode',
    iconName: 'code',
    color: Colors.purple,
  );
  
  static const anyrouter = PlatformType._(
    id: 'anyrouter',
    value: 'AnyRouter',
    iconName: 'router',
    color: Colors.deepPurpleAccent,
  );
  
  // 云服务平台
  static const tencent = PlatformType._(
    id: 'tencent',
    value: '腾讯云',
    iconName: 'cloud',
    color: Colors.blueAccent,
  );
  
  static const alibaba = PlatformType._(
    id: 'alibaba',
    value: '阿里云',
    iconName: 'cloud_circle',
    color: Colors.orange,
  );
  
  // 向量数据库
  static const pinecone = PlatformType._(
    id: 'pinecone',
    value: 'Pinecone',
    iconName: 'forest',
    color: Colors.green,
  );
  
  static const weaviate = PlatformType._(
    id: 'weaviate',
    value: 'Weaviate',
    iconName: 'schema',
    color: Colors.purple,
  );
  
  // 后端即服务
  static const supabase = PlatformType._(
    id: 'supabase',
    value: 'Supabase',
    iconName: 'storage_outlined',
    color: Colors.greenAccent,
  );
  
  static const notion = PlatformType._(
    id: 'notion',
    value: 'Notion',
    iconName: 'note',
    color: Colors.black,
  );
  
  // 其他平台
  static const bytedance = PlatformType._(
    id: 'bytedance',
    value: '字节跳动',
    iconName: 'business',
    color: Colors.blue,
  );
  
  // 工具平台
  static const github = PlatformType._(
    id: 'github',
    value: 'GitHub',
    iconName: 'code',
    color: Colors.black,
  );
  
  static const githubCopilot = PlatformType._(
    id: 'githubCopilot',
    value: 'GitHub Copilot',
    iconName: 'auto_fix_high',
    color: Colors.purple,
  );
  
  static const gitee = PlatformType._(
    id: 'gitee',
    value: 'Gitee',
    iconName: 'storage',
    color: Colors.red,
  );
  
  static const coze = PlatformType._(
    id: 'coze',
    value: 'Coze',
    iconName: 'chat_bubble_outline',
    color: Colors.blue,
  );
  
  static const figma = PlatformType._(
    id: 'figma',
    value: 'Figma',
    iconName: 'design_services',
    color: Colors.purple,
  );
  
  static const v0 = PlatformType._(
    id: 'v0',
    value: 'v0',
    iconName: 'auto_awesome',
    color: Colors.indigo,
  );
  
  static const custom = PlatformType._(
    id: 'custom',
    value: 'Custom',
    iconName: 'code',
    color: Colors.grey,
  );

  // ==================== 工具方法 ====================
  
  /// 获取图标数据
  IconData get icon => _getIconFromName(iconName);
  
  /// 兼容性：获取 name（原枚举的 name 属性）
  String get name => id;
  
  /// 兼容性：获取 index（模拟枚举的 index 行为）
  /// 注意：这只对内置平台有效，动态平台返回 -1
  int get index {
    if (!isBuiltin) return -1;
    
    // 返回在内置平台列表中的索引
    final builtinPlatforms = [
      openAI, anthropic, google, azureOpenAI, aws,
      minimax, deepSeek, siliconFlow, zhipu, bailian, baidu,
      n8n, dify, openRouter, huggingFace, qdrant, volcengine,
      mistral, cohere, perplexity, gemini, xai, ollama,
      zeroOne, baichuan, kimi, nova,
      zai, katCoder, longcat, bailing, modelScope, aihubmix, dmxapi, packycode, anyrouter,
      tencent, alibaba,
      pinecone, weaviate,
      supabase, notion,
      bytedance,
      github, githubCopilot, gitee, coze, figma, v0,
      custom,
    ];
    
    for (int i = 0; i < builtinPlatforms.length; i++) {
      if (builtinPlatforms[i].id == id) {
        return i;
      }
    }
    
    return -1;
  }
  
  /// 相等性比较
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlatformType && other.id == id;
  }
  
  @override
  int get hashCode => id.hashCode;
  
  @override
  String toString() => 'PlatformType.$id';
  
  /// 从图标名称获取 IconData
  static IconData _getIconFromName(String name) {
    // 映射字符串到 IconData
    final iconMap = {
      'smart_toy': Icons.smart_toy,
      'psychology': Icons.psychology,
      'bolt': Icons.bolt,
      'cloud': Icons.cloud,
      'cloud_queue': Icons.cloud_queue,
      'auto_awesome': Icons.auto_awesome,
      'explore': Icons.explore,
      'account_tree': Icons.account_tree,
      'psychology_outlined': Icons.psychology_outlined,
      'cloud_done': Icons.cloud_done,
      'search': Icons.search,
      'chat_bubble_outline': Icons.chat_bubble_outline,
      'settings_applications': Icons.settings_applications,
      'auto_awesome_motion': Icons.auto_awesome_motion,
      'router': Icons.router,
      'face': Icons.face,
      'storage': Icons.storage,
      'local_fire_department': Icons.local_fire_department,
      'chat_bubble': Icons.chat_bubble,
      'rocket_launch': Icons.rocket_launch,
      'computer': Icons.computer,
      'nightlight_round': Icons.nightlight_round,
      'one_k': Icons.one_k,
      'water_drop': Icons.water_drop,
      'chat': Icons.chat,
      'star': Icons.star,
      'code': Icons.code,
      'api': Icons.api,
      'cloud_circle': Icons.cloud_circle,
      'forest': Icons.forest,
      'schema': Icons.schema,
      'storage_outlined': Icons.storage_outlined,
      'note': Icons.note,
      'business': Icons.business,
      'auto_fix_high': Icons.auto_fix_high,
      'design_services': Icons.design_services,
    };
    
    return iconMap[name] ?? Icons.help_outline;
  }
}
