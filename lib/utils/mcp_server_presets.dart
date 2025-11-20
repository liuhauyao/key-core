import 'dart:convert';
import '../models/mcp_server.dart';
import '../models/mcp_server_category.dart';
import '../services/cloud_config_service.dart';
import '../models/cloud_config.dart' as cloud;

/// MCP 服务器模板配置
class McpServerTemplate {
  final String serverId;
  final String name;
  final String? description;
  final String? icon;
  final McpServerCategory category;
  final McpServerType serverType;
  final String? command;
  final List<String>? args;
  final Map<String, String>? env;
  final String? cwd;
  final String? url;
  final Map<String, String>? headers;
  final List<String>? tags;
  final String? homepage;
  final String? docs;

  const McpServerTemplate({
    required this.serverId,
    required this.name,
    this.description,
    this.icon,
    required this.category,
    required this.serverType,
    this.command,
    this.args,
    this.env,
    this.cwd,
    this.url,
    this.headers,
    this.tags,
    this.homepage,
    this.docs,
  });

  /// 转换为JSON配置格式（用于填充表单）
  String toJsonConfig() {
    final config = <String, dynamic>{};
    
    if (serverType == McpServerType.stdio) {
      if (command != null && command!.isNotEmpty) {
        config['command'] = command;
      }
      if (args != null && args!.isNotEmpty) {
        config['args'] = args;
      }
      if (env != null && env!.isNotEmpty) {
        config['env'] = env;
      }
      if (cwd != null && cwd!.isNotEmpty) {
        config['cwd'] = cwd;
      }
    } else if (serverType == McpServerType.http || serverType == McpServerType.sse) {
      if (url != null && url!.isNotEmpty) {
        config['url'] = url;
      }
      if (headers != null && headers!.isNotEmpty) {
        config['headers'] = headers;
      }
    }
    
    final jsonWithId = <String, dynamic>{
      serverId: config,
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }
}

/// MCP 服务器模板管理
class McpServerPresets {
  static final CloudConfigService _configService = CloudConfigService();
  static List<McpServerTemplate>? _cachedTemplates;

  /// 初始化配置（从云端或本地加载）
  static Future<void> init({bool forceRefresh = false}) async {
    await _configService.init();
    await _loadTemplates(forceRefresh: forceRefresh);
  }

  /// 加载MCP服务器模板配置
  static Future<void> _loadTemplates({bool forceRefresh = false}) async {
    try {
      final configData = await _configService.getConfigData(forceRefresh: forceRefresh);
      if (configData != null && configData.mcpServerTemplates.isNotEmpty) {
        final loadedTemplates = configData.mcpServerTemplates.map((templateConfig) {
          try {
            return McpServerTemplate(
              serverId: templateConfig.serverId,
              name: templateConfig.name,
              description: templateConfig.description,
              icon: templateConfig.icon,
              category: _parseCategory(templateConfig.category),
              serverType: McpServerType.fromString(templateConfig.serverType),
              command: templateConfig.command,
              args: templateConfig.args,
              env: templateConfig.env,
              cwd: templateConfig.cwd,
              url: templateConfig.url,
              headers: templateConfig.headers,
              tags: templateConfig.tags,
              homepage: templateConfig.homepage,
              docs: templateConfig.docs,
            );
          } catch (e) {
            print('McpServerPresets: 解析模板失败 ${templateConfig.serverId}: $e');
            return null;
          }
        }).whereType<McpServerTemplate>().toList();
        
        if (loadedTemplates.isNotEmpty) {
          _cachedTemplates = loadedTemplates;
          print('McpServerPresets: 成功加载 ${_cachedTemplates!.length} 个 MCP 服务器模板');
        } else {
          print('McpServerPresets: MCP 服务器模板列表为空，使用默认配置');
        }
      } else {
        print('McpServerPresets: 配置数据为空或模板列表为空，使用默认配置');
      }
    } catch (e, stackTrace) {
      print('McpServerPresets: 加载MCP服务器模板配置失败: $e');
      print('McpServerPresets: 堆栈跟踪: $stackTrace');
      // 加载失败时，缓存保持为 null，getter 会返回默认配置
    }
  }

  /// 解析分类枚举
  static McpServerCategory _parseCategory(String category) {
    switch (category) {
      case 'popular':
        return McpServerCategory.popular;
      case 'database':
        return McpServerCategory.database;
      case 'search':
        return McpServerCategory.search;
      case 'development':
        return McpServerCategory.development;
      case 'cloud':
        return McpServerCategory.cloud;
      case 'ai':
        return McpServerCategory.ai;
      case 'automation':
        return McpServerCategory.automation;
      case 'custom':
      default:
        return McpServerCategory.custom;
    }
  }

  /// 根据分类获取模板列表
  static List<McpServerTemplate> getTemplatesByCategory(McpServerCategory category) {
    if (category == McpServerCategory.custom) {
      return [];
    }
    final templates = _cachedTemplates ?? _defaultTemplates;
    return templates.where((template) => template.category == category).toList();
  }

  /// 根据serverId获取模板
  static McpServerTemplate? getTemplate(String serverId) {
    final templates = _cachedTemplates ?? _defaultTemplates;
    try {
      return templates.firstWhere((template) => template.serverId == serverId);
    } catch (e) {
      return null;
    }
  }

  /// 获取所有模板
  static List<McpServerTemplate> get allTemplates {
    return _cachedTemplates ?? _defaultTemplates;
  }

  /// 获取所有分类（排除自定义）
  static List<McpServerCategory> get allCategories {
    return McpServerCategory.values.where((c) => c != McpServerCategory.custom).toList();
  }

  /// 默认MCP服务器模板（向后兼容）
  static const List<McpServerTemplate> _defaultTemplates = [
    // 常用服务
    McpServerTemplate(
      serverId: 'context7',
      name: 'Context7',
      description: 'Context7 MCP服务器，提供库文档查询功能',
      category: McpServerCategory.popular,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@upstash/context7-mcp@latest'],
      icon: 'mcp.svg', // 使用通用MCP图标
      tags: ['documentation', 'library'],
      homepage: 'https://context7.com',
      docs: 'https://context7.com/docs',
    ),
    McpServerTemplate(
      serverId: 'supabase',
      name: 'Supabase',
      description: 'Supabase MCP服务器，提供数据库和API访问',
      category: McpServerCategory.popular,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@supabase/mcp-server@latest'],
      env: {'SUPABASE_URL': '', 'SUPABASE_ANON_KEY': ''},
      icon: 'supabase-icon.svg',
      tags: ['database', 'api'],
      homepage: 'https://supabase.com',
      docs: 'https://supabase.com/docs',
    ),
    McpServerTemplate(
      serverId: 'n8n',
      name: 'n8n',
      description: 'n8n MCP服务器，提供工作流自动化功能',
      category: McpServerCategory.popular,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@n8n/mcp-server@latest'],
      icon: 'n8n-color.svg',
      tags: ['automation', 'workflow'],
      homepage: 'https://n8n.io',
      docs: 'https://docs.n8n.io',
    ),
    McpServerTemplate(
      serverId: 'alipay',
      name: '支付宝',
      description: '支付宝官方MCP服务器，提供支付、查询、退款等支付功能',
      category: McpServerCategory.popular,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@alipay/mcp-server-alipay@latest'],
      env: {'ALIPAY_APP_ID': '', 'ALIPAY_PRIVATE_KEY': '', 'ALIPAY_PUBLIC_KEY': ''},
      icon: 'alipay.svg',
      tags: ['payment', 'finance', 'alipay'],
      homepage: 'https://open.alipay.com',
      docs: 'https://opendocs.alipay.com',
    ),
    McpServerTemplate(
      serverId: 'unionpay',
      name: '银联',
      description: '银联官方MCP服务器，提供银联支付相关功能',
      category: McpServerCategory.popular,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@UnionPay/unionpay-mcp-server@latest'],
      env: {'UNIONPAY_MERCHANT_ID': '', 'UNIONPAY_SECRET_KEY': ''},
      icon: 'unionpay.svg',
      tags: ['payment', 'finance', 'unionpay'],
      homepage: 'https://open.unionpay.com',
      docs: 'https://open.unionpay.com/ajweb/help',
    ),
    
    // 数据库类
    McpServerTemplate(
      serverId: 'postgres',
      name: 'PostgreSQL',
      description: 'PostgreSQL数据库MCP服务器',
      category: McpServerCategory.database,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-postgres@latest'],
      env: {'POSTGRES_CONNECTION_STRING': ''},
      icon: 'postgres.svg',
      tags: ['database', 'sql'],
      homepage: 'https://www.postgresql.org',
      docs: 'https://www.postgresql.org/docs',
    ),
    McpServerTemplate(
      serverId: 'sqlite',
      name: 'SQLite',
      description: 'SQLite数据库MCP服务器',
      category: McpServerCategory.database,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-sqlite@latest'],
      env: {'SQLITE_DB_PATH': ''},
      icon: 'sql-lite.svg',
      tags: ['database', 'sql'],
      homepage: 'https://www.sqlite.org',
      docs: 'https://www.sqlite.org/docs.html',
    ),
    McpServerTemplate(
      serverId: 'mysql',
      name: 'MySQL',
      description: 'MySQL数据库MCP服务器',
      category: McpServerCategory.database,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-mysql@latest'],
      env: {'MYSQL_CONNECTION_STRING': ''},
      icon: 'mysql.svg',
      tags: ['database', 'sql'],
      homepage: 'https://www.mysql.com',
      docs: 'https://dev.mysql.com/doc',
    ),
    
    // 搜索类
    McpServerTemplate(
      serverId: 'brave-search',
      name: 'Brave Search',
      description: 'Brave搜索引擎MCP服务器',
      category: McpServerCategory.search,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-brave-search@latest'],
      env: {'BRAVE_API_KEY': ''},
      icon: 'brave.svg',
      tags: ['search', 'web'],
      homepage: 'https://brave.com/search',
      docs: 'https://api.search.brave.com',
    ),
    McpServerTemplate(
      serverId: 'google-search',
      name: 'Google Search',
      description: 'Google搜索MCP服务器',
      category: McpServerCategory.search,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-google-search@latest'],
      env: {'GOOGLE_API_KEY': '', 'GOOGLE_CSE_ID': ''},
      icon: 'google-color.svg',
      tags: ['search', 'web'],
      homepage: 'https://www.google.com',
      docs: 'https://developers.google.com/custom-search',
    ),
    McpServerTemplate(
      serverId: 'zhipu-web-search',
      name: '智谱联网搜索',
      description: '智谱AI提供的联网搜索MCP服务器，支持实时互联网搜索',
      category: McpServerCategory.search,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@zhipuai/zhipu-web-search-mcp@latest'],
      env: {'ZHIPU_API_KEY': ''},
      icon: 'zhipu-color.svg',
      tags: ['search', 'web', 'ai'],
      homepage: 'https://www.zhipuai.cn',
      docs: 'https://open.bigmodel.cn',
    ),
    McpServerTemplate(
      serverId: 'bing-cn',
      name: '必应搜索（中文）',
      description: '必应中文搜索MCP服务器，提供中文互联网搜索功能',
      category: McpServerCategory.search,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@yan5236/bing-cn-mcp-server@latest'],
      icon: 'bing-color.svg',
      tags: ['search', 'web', 'chinese'],
      homepage: 'https://www.bing.com',
      docs: 'https://modelscope.cn/mcp/servers/@yan5236/bing-cn-mcp-server',
    ),
    McpServerTemplate(
      serverId: 'baidu-maps',
      name: '百度地图',
      description: '百度地图MCP服务器，提供地图服务、地理编码、路径规划等功能',
      category: McpServerCategory.search,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@baidu-maps/mcp@latest'],
      env: {'BAIDU_MAP_AK': ''},
      icon: 'baidumap.svg',
      tags: ['map', 'location', 'geocoding'],
      homepage: 'https://lbsyun.baidu.com',
      docs: 'https://lbsyun.baidu.com/index.php?title=webapi',
    ),
    
    // 开发工具类
    McpServerTemplate(
      serverId: 'github',
      name: 'GitHub',
      description: 'GitHub API MCP服务器',
      category: McpServerCategory.development,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-github@latest'],
      env: {'GITHUB_PERSONAL_ACCESS_TOKEN': ''},
      icon: 'github.svg',
      tags: ['git', 'version-control'],
      homepage: 'https://github.com',
      docs: 'https://docs.github.com',
    ),
    McpServerTemplate(
      serverId: 'filesystem',
      name: 'Filesystem',
      description: '文件系统操作MCP服务器',
      category: McpServerCategory.development,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-filesystem@latest'],
      env: {'ALLOWED_DIRECTORIES': ''},
      icon: 'filesystem.svg',
      tags: ['filesystem', 'file-operations'],
      homepage: 'https://modelcontextprotocol.io',
      docs: 'https://modelcontextprotocol.io/docs',
    ),
    McpServerTemplate(
      serverId: 'git',
      name: 'Git',
      description: 'Git操作MCP服务器',
      category: McpServerCategory.development,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-git@latest'],
      icon: 'git.svg',
      tags: ['git', 'version-control'],
      homepage: 'https://git-scm.com',
      docs: 'https://git-scm.com/doc',
    ),
    
    // 云服务类
    McpServerTemplate(
      serverId: 'aws',
      name: 'AWS',
      description: 'AWS服务MCP服务器',
      category: McpServerCategory.cloud,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-aws@latest'],
      env: {'AWS_ACCESS_KEY_ID': '', 'AWS_SECRET_ACCESS_KEY': '', 'AWS_REGION': ''},
      icon: 'aws-color.svg',
      tags: ['cloud', 'aws'],
      homepage: 'https://aws.amazon.com',
      docs: 'https://docs.aws.amazon.com',
    ),
    McpServerTemplate(
      serverId: 'gcp',
      name: 'Google Cloud',
      description: 'Google Cloud Platform MCP服务器',
      category: McpServerCategory.cloud,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-gcp@latest'],
      env: {'GOOGLE_APPLICATION_CREDENTIALS': ''},
      icon: 'google-color.svg',
      tags: ['cloud', 'gcp'],
      homepage: 'https://cloud.google.com',
      docs: 'https://cloud.google.com/docs',
    ),
    
    // AI服务类
    McpServerTemplate(
      serverId: 'openai',
      name: 'OpenAI',
      description: 'OpenAI API MCP服务器',
      category: McpServerCategory.ai,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-openai@latest'],
      env: {'OPENAI_API_KEY': ''},
      icon: 'openai.svg',
      tags: ['ai', 'llm'],
      homepage: 'https://openai.com',
      docs: 'https://platform.openai.com/docs',
    ),
    McpServerTemplate(
      serverId: 'anthropic',
      name: 'Anthropic',
      description: 'Anthropic Claude API MCP服务器',
      category: McpServerCategory.ai,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-anthropic@latest'],
      env: {'ANTHROPIC_API_KEY': ''},
      icon: 'anthropic.svg',
      tags: ['ai', 'llm'],
      homepage: 'https://anthropic.com',
      docs: 'https://docs.anthropic.com',
    ),
    McpServerTemplate(
      serverId: 'sequential-thinking',
      name: 'Sequential Thinking',
      description: '顺序思维MCP服务器，提供链式推理和思维过程管理',
      category: McpServerCategory.ai,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/sequentialthinking@latest'],
      icon: 'mcp.svg',
      tags: ['ai', 'reasoning', 'thinking'],
      homepage: 'https://modelcontextprotocol.io',
      docs: 'https://modelscope.cn/mcp/servers/@modelcontextprotocol/sequentialthinking',
    ),
    McpServerTemplate(
      serverId: 'time',
      name: 'Time',
      description: '时间服务MCP服务器，提供当前时间获取和时区转换功能',
      category: McpServerCategory.development,
      serverType: McpServerType.stdio,
      command: 'python',
      args: ['-m', 'mcp_server_time'],
      icon: 'mcp.svg',
      tags: ['time', 'timezone', 'utility'],
      homepage: 'https://modelcontextprotocol.io',
      docs: 'https://modelscope.cn/mcp/servers/@modelcontextprotocol/time',
    ),
    
    // 自动化类
    McpServerTemplate(
      serverId: 'slack',
      name: 'Slack',
      description: 'Slack集成MCP服务器',
      category: McpServerCategory.automation,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-slack@latest'],
      env: {'SLACK_BOT_TOKEN': ''},
      icon: 'slack.svg',
      tags: ['automation', 'communication'],
      homepage: 'https://slack.com',
      docs: 'https://api.slack.com',
    ),
    McpServerTemplate(
      serverId: 'notion',
      name: 'Notion',
      description: 'Notion API MCP服务器',
      category: McpServerCategory.automation,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-notion@latest'],
      env: {'NOTION_API_KEY': ''},
      icon: 'notion.svg',
      tags: ['automation', 'productivity'],
      homepage: 'https://notion.so',
      docs: 'https://developers.notion.com',
    ),
    
    // 其他已验证的官方服务
    McpServerTemplate(
      serverId: 'puppeteer',
      name: 'Puppeteer',
      description: 'Puppeteer浏览器自动化MCP服务器',
      category: McpServerCategory.development,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-puppeteer@latest'],
      icon: 'mcp.svg',
      tags: ['browser', 'automation', 'web-scraping'],
      homepage: 'https://pptr.dev',
      docs: 'https://pptr.dev',
    ),
    McpServerTemplate(
      serverId: 'fetch',
      name: 'Fetch',
      description: 'HTTP请求MCP服务器，提供网络请求功能',
      category: McpServerCategory.development,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-fetch@latest'],
      icon: 'mcp.svg',
      tags: ['http', 'network', 'api'],
      homepage: 'https://modelcontextprotocol.io',
      docs: 'https://modelcontextprotocol.io/docs',
    ),
    McpServerTemplate(
      serverId: 'memory',
      name: 'Memory',
      description: '内存存储MCP服务器，提供对话记忆功能',
      category: McpServerCategory.popular,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@modelcontextprotocol/server-memory@latest'],
      icon: 'mcp.svg',
      tags: ['memory', 'storage', 'context'],
      homepage: 'https://modelcontextprotocol.io',
      docs: 'https://modelcontextprotocol.io/docs',
    ),
    McpServerTemplate(
      serverId: 'dingtalk',
      name: '钉钉',
      description: '钉钉官方MCP服务器，提供钉钉平台集成功能',
      category: McpServerCategory.automation,
      serverType: McpServerType.stdio,
      command: 'npx',
      args: ['-y', '@open-dingtalk/dingtalk-mcp@latest'],
      env: {'DINGTALK_APP_KEY': '', 'DINGTALK_APP_SECRET': ''},
      icon: 'dingding.svg',
      tags: ['automation', 'communication', 'collaboration'],
      homepage: 'https://open.dingtalk.com',
      docs: 'https://open.dingtalk.com/document',
    ),
  ];
}

