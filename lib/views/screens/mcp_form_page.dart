import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:convert';
import '../../models/mcp_server.dart';
import '../../models/mcp_server_category.dart';
import '../../utils/app_localizations.dart';
import '../../utils/mcp_server_presets.dart';
import '../../utils/ime_friendly_formatter.dart';
import '../widgets/icon_picker.dart';
import '../widgets/ime_safe_text_field.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// JSON 输入格式化器，自动去除 mcpServers 包装
class _JsonConfigFormatter extends TextInputFormatter {
  final Function(String?)? onServerIdExtracted;
  
  _JsonConfigFormatter({this.onServerIdExtracted});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 如果正在输入法输入（composing），直接返回原值，不进行处理
    // 这样可以避免在输入法输入过程中触发构建
    if (newValue.composing.isValid) {
      return newValue;
    }
    
    final newText = newValue.text;
    
    // 如果文本为空，直接返回
    if (newText.trim().isEmpty) {
      return newValue;
    }

    // 只在文本变化较大时（可能是粘贴操作）才进行处理
    // 如果只是单个字符的变化，且不是粘贴操作，则跳过处理
    final textLengthDiff = newText.length - oldValue.text.length;
    if (textLengthDiff <= 1 && newText.length > 10) {
      // 单个字符输入，且文本已经较长，可能是正常输入，不处理
      // 但如果是粘贴操作（文本长度突然增加很多），则需要处理
      return newValue;
    }

    try {
      // 清理 JSON 字符串，去除注释
      final cleaned = _cleanJsonStringStatic(newText);
      
      // 尝试解析 JSON
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      
      // 检查是否有 mcpServers 包装
      final hasMcpServersWrapper = decoded.length == 1 && 
          (decoded.containsKey('mcpServers') || 
           decoded.keys.any((k) => k.toLowerCase() == 'mcpservers'));
      
      if (hasMcpServersWrapper) {
        final unwrapped = _unwrapMcpServersStatic(decoded);
        if (unwrapped.length == 1 &&
            unwrapped.values.first is Map<String, dynamic>) {
          // 提取唯一标识
          final serverId = unwrapped.keys.first;
          // 使用 addPostFrameCallback 延迟回调，避免在构建过程中调用 setState
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onServerIdExtracted?.call(serverId);
          });
          
          // 格式化并返回去除包装后的 JSON
          final formatted = const JsonEncoder.withIndent('  ').convert(unwrapped);
          return TextEditingValue(
            text: formatted,
            selection: TextSelection.collapsed(offset: formatted.length),
          );
        }
      } else {
        // 即使没有包装，也尝试提取唯一标识
        if (decoded.length == 1) {
          final serverId = decoded.keys.first;
          // 使用 addPostFrameCallback 延迟回调，避免在构建过程中调用 setState
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onServerIdExtracted?.call(serverId);
          });
        }
      }
    } catch (e) {
      // 解析失败，可能是用户正在输入，返回原值
      return newValue;
    }

    return newValue;
  }

  static String _cleanJsonStringStatic(String jsonText) {
    String cleaned = jsonText;
    
    // 去除单行注释（// 开头的注释）
    cleaned = cleaned.split('\n').map((line) {
      final commentIndex = line.indexOf('//');
      if (commentIndex >= 0) {
        final beforeComment = line.substring(0, commentIndex);
        final quoteCount = beforeComment.split('"').length - 1;
        if (quoteCount % 2 == 0) {
          return line.substring(0, commentIndex).trimRight();
        }
      }
      return line;
    }).join('\n');
    
    // 去除多行注释 /* */
    final multilineCommentRegex = RegExp(r'/\*[\s\S]*?\*/');
    cleaned = cleaned.replaceAll(multilineCommentRegex, '');
    
    return cleaned.trim();
  }

  static Map<String, dynamic> _unwrapMcpServersStatic(Map<String, dynamic> decoded) {
    if (decoded.length == 1) {
      final key = decoded.keys.first;
      if (key.toLowerCase() == 'mcpservers' || key == 'mcpServers') {
        final mcpServers = decoded[key];
        if (mcpServers is Map<String, dynamic>) {
          return mcpServers;
        }
      }
    }
    return decoded;
  }
}

/// MCP 服务器表单页面
class McpFormPage extends StatefulWidget {
  final McpServer? editingServer;

  const McpFormPage({
    super.key,
    this.editingServer,
  });

  @override
  State<McpFormPage> createState() => _McpFormPageState();
}

class _McpFormPageState extends State<McpFormPage> {
  final _formKey = GlobalKey<ShadFormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _jsonConfigController;
  late TextEditingController _tagsController;
  late TextEditingController _homepageController;
  late TextEditingController _docsController;

  String? _selectedIcon;
  bool _isEditMode = false;
  McpServerCategory _selectedCategory = McpServerCategory.popular;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.editingServer != null;

    if (widget.editingServer != null) {
      final server = widget.editingServer!;
      _nameController = TextEditingController(text: server.name);
      _descriptionController = TextEditingController(text: server.description ?? '');
      _tagsController = TextEditingController(
        text: server.tags?.join(', ') ?? '',
      );
      _homepageController = TextEditingController(text: server.homepage ?? '');
      _docsController = TextEditingController(text: server.docs ?? '');
      _selectedIcon = server.icon;
      
      // 从服务器配置生成JSON配置
      _jsonConfigController = TextEditingController(
        text: _generateJsonConfigFromServer(server),
      );
    } else {
      _nameController = TextEditingController();
      _descriptionController = TextEditingController();
      _jsonConfigController = TextEditingController();
      _tagsController = TextEditingController();
      _homepageController = TextEditingController();
      _docsController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _jsonConfigController.dispose();
    _tagsController.dispose();
    _homepageController.dispose();
    _docsController.dispose();
    super.dispose();
  }

  /// 从服务器配置生成JSON配置字符串（包含MCP唯一标识）
  String _generateJsonConfigFromServer(McpServer server) {
    final mcpConfig = <String, dynamic>{};
    
    if (server.serverType == McpServerType.stdio) {
      if (server.command != null && server.command!.isNotEmpty) {
        mcpConfig['command'] = server.command;
      }
      if (server.args != null && server.args!.isNotEmpty) {
        mcpConfig['args'] = server.args;
      }
      if (server.env != null && server.env!.isNotEmpty) {
        mcpConfig['env'] = server.env;
      }
      if (server.cwd != null && server.cwd!.isNotEmpty) {
        mcpConfig['cwd'] = server.cwd;
      }
    } else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) {
      if (server.url != null && server.url!.isNotEmpty) {
        mcpConfig['url'] = server.url;
      }
      if (server.headers != null && server.headers!.isNotEmpty) {
        mcpConfig['headers'] = server.headers;
      }
    }
    
    // 生成包含唯一标识的JSON格式：{"serverId": {配置}}
    final jsonWithId = <String, dynamic>{
      server.serverId: mcpConfig,
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }

  /// 清理JSON字符串，去除注释和多余空白
  String _cleanJsonString(String jsonText) {
    // 去除单行注释 // 和 /* */ 注释
    String cleaned = jsonText;
    
    // 去除单行注释（// 开头的注释）
    cleaned = cleaned.split('\n').map((line) {
      final commentIndex = line.indexOf('//');
      if (commentIndex >= 0) {
        // 检查是否在字符串中
        final beforeComment = line.substring(0, commentIndex);
        final quoteCount = beforeComment.split('"').length - 1;
        // 如果引号数量是偶数，说明不在字符串中，可以安全去除注释
        if (quoteCount % 2 == 0) {
          return line.substring(0, commentIndex).trimRight();
        }
      }
      return line;
    }).join('\n');
    
    // 去除多行注释 /* */
    final multilineCommentRegex = RegExp(r'/\*[\s\S]*?\*/');
    cleaned = cleaned.replaceAll(multilineCommentRegex, '');
    
    return cleaned.trim();
  }

  /// 去除外层的mcpServers包装（如果存在）
  /// 返回去除包装后的JSON对象
  Map<String, dynamic> _unwrapMcpServers(Map<String, dynamic> decoded) {
    // 检查是否有mcpServers包装（不区分大小写）
    if (decoded.length == 1) {
      final key = decoded.keys.first;
      // 支持 mcpServers 或 mcp_servers 等变体（不区分大小写）
      if (key.toLowerCase() == 'mcpservers' || key == 'mcpServers') {
        final mcpServers = decoded[key];
        if (mcpServers is Map<String, dynamic>) {
          return mcpServers;
        }
      }
    }
    return decoded;
  }

  /// 检测JSON配置中的唯一标识（如果存在）
  /// 支持两种格式：
  /// 1. {"serverId": {配置}}
  /// 2. {"mcpServers": {"serverId": {配置}}}
  /// 返回唯一标识，如果不存在或格式不正确则返回null
  String? _extractServerIdFromJson(String jsonText) {
    if (jsonText.trim().isEmpty) return null;
    
    try {
      final cleaned = _cleanJsonString(jsonText);
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      
      // 去除mcpServers包装（如果存在）
      final unwrapped = _unwrapMcpServers(decoded);
      
      // 只支持包含唯一标识的格式：{"serverId": {配置}}
      // 如果对象只有一个键，且值是对象，则提取唯一标识
      if (unwrapped.length == 1) {
        final entry = unwrapped.entries.first;
        final value = entry.value;
        
        // 如果值是对象，则返回唯一标识
        if (value is Map<String, dynamic>) {
          return entry.key;
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 解析JSON配置并提取MCP服务器信息
  /// 支持两种格式：
  /// 1. {"serverId": {配置}}
  /// 2. {"mcpServers": {"serverId": {配置}}} - 会自动去除mcpServers包装
  /// 返回：{serverId: 唯一标识, config: 配置对象}
  Map<String, dynamic>? _parseJsonConfig() {
    final localizations = AppLocalizations.of(context);
    if (_jsonConfigController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations?.mcpJsonConfigRequired ?? '请输入JSON配置'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }

    try {
      // 清理JSON字符串，去除注释
      final cleaned = _cleanJsonString(_jsonConfigController.text);
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      
      // 去除mcpServers包装（如果存在）
      final unwrapped = _unwrapMcpServers(decoded);
      
      // 只支持包含唯一标识的格式：{"serverId": {配置}}
      // 如果对象只有一个键，且值是对象，则认为是包含唯一标识的格式
      if (unwrapped.length == 1) {
        final entry = unwrapped.entries.first;
        final key = entry.key;
        final value = entry.value;
        
        // 如果值是对象，则提取唯一标识和配置
        if (value is Map<String, dynamic>) {
          return {
            'serverId': key,
            'config': value,
          };
        }
      }
      
      // 不支持没有唯一标识的格式
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations?.mcpJsonConfigError ?? 'JSON配置格式错误: 必须包含MCP唯一标识，格式为 {"唯一标识": {配置}} 或 {"mcpServers": {"唯一标识": {配置}}}'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(localizations?.mcpJsonConfigErrorDetail(e.toString()) ?? 'JSON配置格式错误: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  void _handleSubmit() {
    if (_formKey.currentState!.saveAndValidate()) {
      // 解析JSON配置
      final parsedResult = _parseJsonConfig();
      if (parsedResult == null) return;

      // 提取配置对象和唯一标识
      final config = parsedResult['config'] as Map<String, dynamic>;
      final jsonServerId = parsedResult['serverId'] as String?;

      // 验证配置对象必须包含command或url字段
      final localizations = AppLocalizations.of(context);
      if (!config.containsKey('command') && !config.containsKey('url')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
            content: Text(localizations?.mcpJsonConfigMissingField ?? 'JSON配置错误: 配置必须包含command或url字段'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

      // 从JSON配置中提取服务器类型（根据是否有command或url判断）
      McpServerType serverType;
      if (config.containsKey('command')) {
        serverType = McpServerType.stdio;
      } else if (config.containsKey('url')) {
        // 根据是否有headers判断是http还是sse，默认http
        serverType = McpServerType.http;
      } else {
        // 默认stdio（理论上不会到这里，因为上面已经验证过）
        serverType = McpServerType.stdio;
      }

      // 从JSON配置中提取字段
      String? command;
      List<String>? args;
      Map<String, String>? env;
      String? cwd;
      String? url;
      Map<String, String>? headers;

      if (serverType == McpServerType.stdio) {
        command = config['command'] as String?;
        if (config['args'] != null) {
          args = List<String>.from(config['args'] as List);
        }
        if (config['env'] != null) {
          env = Map<String, String>.from(config['env'] as Map);
        }
        cwd = config['cwd'] as String?;
      } else if (serverType == McpServerType.http || serverType == McpServerType.sse) {
        url = config['url'] as String?;
        if (config['headers'] != null) {
          headers = Map<String, String>.from(config['headers'] as Map);
        }
      }

      // 解析标签
      List<String>? tags;
      if (_tagsController.text.trim().isNotEmpty) {
        tags = _tagsController.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }

      // 确定serverId：优先使用JSON中的唯一标识，其次使用编辑模式的serverId
      // 注意：现在只支持包含唯一标识的格式，所以jsonServerId不应该为null
      final serverId = jsonServerId ?? widget.editingServer?.serverId ?? 
          _nameController.text.trim().toLowerCase().replaceAll(' ', '-');

      final now = DateTime.now();
      final server = McpServer(
        id: widget.editingServer?.id,
        serverId: serverId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        icon: _selectedIcon,
        serverType: serverType,
        command: command,
        args: args,
        env: env,
        cwd: cwd,
        url: url,
        headers: headers,
        tags: tags?.isEmpty ?? true ? null : tags,
        homepage: _homepageController.text.trim().isEmpty
            ? null
            : _homepageController.text.trim(),
        docs: _docsController.text.trim().isEmpty ? null : _docsController.text.trim(),
        isActive: widget.editingServer?.isActive ?? true,
        createdAt: widget.editingServer?.createdAt ?? now,
        // 编辑模式下保持原有的 updatedAt，避免改变卡片位置
        updatedAt: widget.editingServer?.updatedAt ?? now,
      );

      Navigator.of(context).pop(server);
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        left: false,
        right: false,
        child: Column(
          children: [
            // macOS 26 风格：沉浸式标题栏（与界面融为一体）
            _buildImmersiveTitleBar(context),
            // 分类切换区域 - 仅在新建模式下显示
            if (!_isEditMode)
              Container(
                padding: const EdgeInsets.only(top: 12, bottom: 12, left: 24, right: 24),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.background,
                  border: Border(
                    bottom: BorderSide(
                      color: shadTheme.colorScheme.border,
                      width: 1,
                    ),
                  ),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTemplateChips(context, shadTheme),
                ),
              ),
            // 表单内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: ShadForm(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 第一行：显示名称、标签
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        // 显示名称 - 使用 ImeSafeTextField，统一输入框高度和图标尺寸
                        Expanded(
                          child: ImeSafeTextField(
                            controller: _nameController,
                            labelText: localizations?.mcpDisplayName ?? '显示名称 *',
                            hintText: localizations?.mcpDisplayNameHint ?? '例如: Context7 MCP',
                            prefixIcon: _buildClickableIcon(context, shadTheme),
                            isDark: Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                          const SizedBox(width: 12),
                          // 标签
                          Expanded(
                            child: ImeSafeTextField(
                              controller: _tagsController,
                              labelText: localizations?.mcpTags ?? '标签',
                              hintText: localizations?.mcpTagsHint ?? '多个标签用逗号分隔',
                              prefixIcon: Icon(Icons.local_offer, size: 18, color: shadTheme.colorScheme.mutedForeground),
                              isDark: Theme.of(context).brightness == Brightness.dark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 第二行：JSON配置文本输入框（不需要icon）
                      _buildJsonConfigField(context, shadTheme),
                      const SizedBox(height: 16),
                      // 第三行：管理地址（选填）、文档地址（选填）
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ImeSafeTextField(
                              controller: _homepageController,
                              labelText: localizations?.mcpHomepage ?? '管理地址（选填）',
                              hintText: localizations?.mcpHomepageHint ?? 'https://example.com',
                              prefixIcon: Icon(Icons.language, size: 18, color: shadTheme.colorScheme.mutedForeground),
                              keyboardType: TextInputType.url,
                              isDark: Theme.of(context).brightness == Brightness.dark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ImeSafeTextField(
                              controller: _docsController,
                              labelText: localizations?.mcpDocs ?? '文档地址（选填）',
                              hintText: localizations?.mcpDocsHint ?? 'https://docs.example.com',
                              prefixIcon: Icon(Icons.book, size: 18, color: shadTheme.colorScheme.mutedForeground),
                              keyboardType: TextInputType.url,
                              isDark: Theme.of(context).brightness == Brightness.dark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // 第四行：描述文本输入框（选填）去掉前置图标
                      ImeSafeTextField(
                        controller: _descriptionController,
                        labelText: localizations?.mcpDescription ?? '描述（选填）',
                        hintText: localizations?.mcpDescriptionHint ?? 'MCP 服务器描述',
                        maxLines: 3,
                        isDark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 底部按钮区域
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: shadTheme.colorScheme.background,
                border: Border(
                  top: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: Text(localizations?.cancel ?? '取消'),
                  ),
                  const SizedBox(width: 12),
                  ShadButton(
                    onPressed: _handleSubmit,
                    leading: Icon(
                      _isEditMode ? Icons.save : Icons.add,
                      size: 18,
                    ),
                    child: Text(
                      _isEditMode
                          ? (localizations?.save ?? '保存')
                          : (localizations?.add ?? '添加'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// macOS 26 风格：沉浸式标题栏（与界面融为一体）
  Widget _buildImmersiveTitleBar(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Container(
      height: 56, // 与主页标题栏高度一致
      padding: const EdgeInsets.only(top: 20, left: 20), // 与主页 padding top 一致
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.background,
        // 移除底部边框
      ),
      child: Stack(
        children: [
          // 新建模式：分类切换滑块居中显示，与主页位置一致
          // 编辑模式：显示"编辑MCP服务器"标题
          Center(
            child: _isEditMode
                ? Text(
                    localizations?.editMcpServer ?? '编辑MCP服务器',
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.w600,
                      color: shadTheme.colorScheme.foreground,
                    ),
                  )
                : _buildCategorySwitcher(context, shadTheme), // 新建模式下在标题栏显示分类切换滑块
          ),
          // 右侧：关闭按钮，与分组切换滑块同一高度（垂直居中）
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ShadButton.ghost(
                width: 30,
                height: 30,
                padding: EdgeInsets.zero,
                child: Icon(
                  Icons.close,
                  size: 20,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
                onPressed: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建分类切换滑块（仅在新建模式下显示）
  Widget _buildCategorySwitcher(BuildContext context, ShadThemeData shadTheme) {
    // 编辑模式下不显示分类切换滑块
    if (_isEditMode) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: McpServerPresets.allCategories.map((category) {
          final isActive = category == _selectedCategory;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = category;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? shadTheme.colorScheme.background
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                category.getValue(context),
                style: shadTheme.textTheme.small.copyWith(
                  color: isActive
                      ? shadTheme.colorScheme.foreground
                      : shadTheme.colorScheme.mutedForeground,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建模板标签（仅在新建模式下显示）
  Widget _buildTemplateChips(BuildContext context, ShadThemeData shadTheme) {
    // 编辑模式下不显示模板标签
    if (_isEditMode) {
      return const SizedBox.shrink();
    }
    
    final localizations = AppLocalizations.of(context);
    final templates = McpServerPresets.getTemplatesByCategory(_selectedCategory);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // 自定义选项
        _buildTemplateChip(
          context,
          null,
          label: localizations?.custom ?? '自定义',
          isSelected: false,
          shadTheme: shadTheme,
          isDark: isDark,
        ),
        // 分类下的模板
        ...templates.map((template) {
          return _buildTemplateChip(
            context,
            template,
            isSelected: false,
            shadTheme: shadTheme,
            isDark: isDark,
          );
        }),
      ],
    );
  }

  /// 构建单个模板标签
  Widget _buildTemplateChip(
    BuildContext context,
    McpServerTemplate? template, {
    String? label,
    required bool isSelected,
    required ShadThemeData shadTheme,
    required bool isDark,
  }) {
    final displayLabel = label ?? template?.name ?? '';
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (template != null) {
            _selectTemplate(template);
          } else {
            // 选择自定义，清空表单
            setState(() {
              _nameController.clear();
              _descriptionController.clear();
              _jsonConfigController.clear();
              _tagsController.clear();
              _homepageController.clear();
              _docsController.clear();
              _selectedIcon = null;
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? shadTheme.colorScheme.primary.withOpacity(0.9)
                : (isDark 
                    ? Colors.white.withOpacity(0.08) 
                    : Colors.white.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? shadTheme.colorScheme.primary
                  : (isDark 
                      ? Colors.white.withOpacity(0.15) 
                      : Colors.black.withOpacity(0.1)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: shadTheme.colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (template?.icon != null)
                SvgPicture.asset(
                  'assets/icons/platforms/${template!.icon}',
                  width: 16,
                  height: 16,
                  // 所有图标都显示原始颜色，不使用colorFilter
                  allowDrawingOutsideViewBox: true,
                )
              else
                Icon(
                  Icons.extension,
                  size: 16,
                  color: isSelected 
                      ? Colors.white 
                      : (isDark 
                          ? Colors.white.withOpacity(0.7) 
                          : Colors.black.withOpacity(0.7)),
                ),
              const SizedBox(width: 6),
              Text(
                displayLabel,
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected 
                      ? Colors.white 
                      : (isDark 
                          ? Colors.white.withOpacity(0.7) 
                          : Colors.black.withOpacity(0.7)),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  /// 选择模板并自动填充
  void _selectTemplate(McpServerTemplate template) {
    setState(() {
      // 填充基本信息
      if (!_isEditMode || _nameController.text.isEmpty) {
        _nameController.text = template.name;
      }
      if (template.description != null && 
          (!_isEditMode || _descriptionController.text.isEmpty)) {
        _descriptionController.text = template.description!;
      }
      if (template.tags != null && 
          (!_isEditMode || _tagsController.text.isEmpty)) {
        // 根据当前语言环境翻译标签
        final localizations = AppLocalizations.of(context);
        final translatedTags = template.tags!.map((tag) {
          return localizations?.translateTag(tag) ?? tag;
        }).toList();
        _tagsController.text = translatedTags.join(', ');
      }
      if (template.homepage != null && 
          (!_isEditMode || _homepageController.text.isEmpty)) {
        _homepageController.text = template.homepage!;
      }
      if (template.docs != null && 
          (!_isEditMode || _docsController.text.isEmpty)) {
        _docsController.text = template.docs!;
      }
      if (template.icon != null) {
        _selectedIcon = template.icon;
      }
      
      // 填充JSON配置
      _jsonConfigController.text = template.toJsonConfig();
    });
  }

  /// 格式化JSON字符串（保持原有格式，只美化缩进）
  String? _formatJson(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString.trim());
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (e) {
      return null;
  }
  }

  /// 构建JSON配置输入框（使用等宽字体，更友好的展示）
  Widget _buildJsonConfigField(BuildContext context, ShadThemeData shadTheme) {
    final localizations = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              localizations?.mcpJsonConfig ?? 'JSON配置 *',
              style: shadTheme.textTheme.small.copyWith(
                fontWeight: FontWeight.w500,
                color: shadTheme.colorScheme.foreground,
              ),
            ),
            ShadButton.ghost(
              onPressed: () {
                final currentText = _jsonConfigController.text.trim();
                if (currentText.isEmpty) return;
                
                final formatted = _formatJson(currentText);
                if (formatted != null) {
                  setState(() {
                    _jsonConfigController.text = formatted;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations?.mcpJsonFormatted ?? 'JSON已格式化'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations?.mcpJsonFormatError ?? 'JSON格式错误，无法格式化'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                ),
                  );
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.format_align_left,
                    size: 16,
                    color: shadTheme.colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    localizations?.mcpJsonConfigFormat ?? '格式化',
                    style: shadTheme.textTheme.small.copyWith(
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: shadTheme.colorScheme.muted.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: EdgeInsets.zero,
          child: TextFormField(
            controller: _jsonConfigController,
            maxLines: 12,
            inputFormatters: [
              _JsonConfigFormatter(
                onServerIdExtracted: (serverId) {
                  // 如果显示名称为空，自动填充唯一标识
                  if (serverId != null && _nameController.text.trim().isEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _nameController.text = serverId;
                        });
                      }
                    });
                  }
                },
              ),
            ],
            style: TextStyle(
              fontFamily: 'JetBrainsMono, SFMono-Regular, Menlo, Consolas, monospace',
              fontSize: 13.5,
              height: 1.7,
              letterSpacing: 0.4,
              color: shadTheme.colorScheme.foreground,
            ),
            decoration: InputDecoration(
              hintText: localizations?.mcpJsonConfigHint ?? '粘贴MCP配置JSON，例如:\n{\n  "context7": {\n    "command": "npx",\n    "args": [\n      "-y",\n      "@upstash/context7-mcp@latest"\n    ]\n  }\n}\n\n或带mcpServers包装:\n{\n  "mcpServers": {\n    "context7": {...}\n  }\n}',
              hintStyle: TextStyle(
                fontFamily: 'JetBrainsMono, SFMono-Regular, Menlo, Consolas, monospace',
                fontSize: 13.5,
            color: shadTheme.colorScheme.mutedForeground,
                height: 1.7,
                letterSpacing: 0.4,
              ),
              // 增加内边距，特别是上下间距
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              filled: true,
              fillColor: shadTheme.colorScheme.background,
              isDense: false,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: shadTheme.colorScheme.border,
                  width: 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: shadTheme.colorScheme.border,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: shadTheme.colorScheme.foreground.withOpacity(0.5),
                  width: 1.2,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return localizations?.mcpJsonConfigRequired ?? '请输入JSON配置';
              }
              
              // 尝试解析JSON，只验证JSON格式是否正确
              // 支持两种格式：
              // 1. {"serverId": {配置}}
              // 2. {"mcpServers": {"serverId": {配置}}}
              try {
                // 清理JSON字符串，去除注释
                final cleaned = _cleanJsonString(value);
                final decoded = jsonDecode(cleaned);
                
                // 验证必须是对象类型
                if (decoded is! Map<String, dynamic>) {
                  return localizations?.mcpJsonFormatErrorObject ?? 'JSON格式错误: 必须是JSON对象格式';
                }
                
                // 去除mcpServers包装（如果存在）
                final unwrapped = _unwrapMcpServers(decoded);
                
                // 必须包含唯一标识的格式：对象只有一个键，且值是对象
                if (unwrapped.length != 1) {
                  return localizations?.mcpJsonFormatErrorIdentifier ?? 'JSON格式错误: 必须包含MCP唯一标识，格式为 {"唯一标识": {配置}} 或 {"mcpServers": {"唯一标识": {配置}}}';
                }
                
                final entry = unwrapped.entries.first;
                if (entry.value is! Map<String, dynamic>) {
                  return localizations?.mcpJsonFormatErrorValue ?? 'JSON格式错误: 唯一标识的值必须是配置对象';
                }
                
                // JSON格式正确，业务逻辑验证在提交时进行
                return null;
              } catch (e) {
                // 提取更友好的错误信息
                final errorMsg = e.toString();
                if (errorMsg.contains('Unexpected character')) {
                  return localizations?.mcpJsonFormatErrorSyntax ?? 'JSON格式错误: 存在非法字符，请检查JSON语法（注意：JSON不支持注释）';
                } else if (errorMsg.contains('Expected')) {
                  return localizations?.mcpJsonFormatErrorMissing ?? 'JSON格式错误: 缺少必要的字符，请检查JSON语法';
                }
                final firstLine = errorMsg.split('\n').first;
                return localizations?.mcpJsonFormatErrorGeneric(firstLine) ?? 'JSON格式错误: $firstLine';
              }
            },
          ),
        ),
      ],
    );
  }

  /// 构建可点击的图标（用于输入框的leading属性）
  Widget _buildClickableIcon(BuildContext context, ShadThemeData shadTheme) {
    return GestureDetector(
      onTap: () async {
        final icon = await showDialog<String?>(
          context: context,
          builder: (context) => IconPicker(
            selectedIcon: _selectedIcon,
            onIconSelected: (icon) {
              // IconPicker会在确定时自动pop并返回图标
            },
          ),
        );
        if (mounted) {
          setState(() {
            _selectedIcon = icon;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: SvgPicture.asset(
              'assets/icons/platforms/${_selectedIcon ?? 'mcp.svg'}',
              allowDrawingOutsideViewBox: true,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

}


