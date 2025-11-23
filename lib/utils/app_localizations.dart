import 'package:flutter/material.dart';
import '../services/language_pack_service.dart';

/// 应用本地化
class AppLocalizations {
  final Locale locale;
  final Map<String, String>? _jsonTranslations; // 从JSON加载的翻译

  AppLocalizations(this.locale, [this._jsonTranslations]);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
  
  static final LanguagePackService _languagePackService = LanguagePackService();

  static final Map<String, Map<String, String>> _localizedValues = {
    'zh': {
      'app_name': '密枢',
      'settings': '设置',
      'master_password': '主密码',
      'master_password_set': '主密码已设置',
      'master_password_not_set': '未设置主密码',
      'master_password_encrypted': '密钥已加密存储',
      'master_password_plain': '密钥以明文存储，建议设置主密码',
      'language': '语言',
      'theme': '主题',
      'theme_light': '亮色',
      'theme_dark': '暗色',
      'theme_system': '跟随系统',
      'minimize_to_tray': '最小化到状态栏',
      'minimize_to_tray_desc': '关闭窗口时隐藏到系统状态栏，点击状态栏图标可显示窗口',
      'show_window': '显示窗口',
      'quit': '退出',
      'import_keys': '导入密钥',
      'import_keys_desc': '从文件导入密钥',
      'export_keys': '导出密钥',
      'export_keys_desc': '导出所有密钥到文件',
      'refresh_list': '刷新列表',
      'close': '关闭',
      'cancel': '取消',
      'confirm': '确认',
      'save': '保存',
      'add': '添加',
      'edit': '编辑',
      'delete': '删除',
      'search': '搜索密钥...',
      'all_platforms': '全部平台',
      'add_key': '添加密钥',
      'edit_key': '编辑密钥',
      'key_name': '密钥名称',
      'key_value': '密钥值',
      'key_value_placeholder': '请输入 Anthropic API Key',
      'platform': '平台',
      'management_url': '管理地址',
      'api_endpoint': 'API地址',
      'expiry_date': '过期日期',
      'tags': '标签',
      'notes': '备注',
      'select_supplier': '选择供应商（可选）',
      'select_supplier_hint': '选择后自动填充信息',
      'custom': '自定义',
      'required': '必填',
      'optional': '可选',
      'loading': '加载中...',
      'finish_edit': '完成编辑',
      'add_key_tooltip': '添加密钥',
      'settings_tooltip': '设置',
      'statistics': '统计信息',
      'total': '总数',
      'active': '活跃',
      'expiring_soon': '即将过期',
      'expired': '已过期',
      'no_keys': '暂无密钥',
      'add_first_key': '点击下方按钮添加您的第一个AI密钥',
      'key_copied': '密钥已复制',
      'key_copied_to_clipboard': '密钥已复制到剪贴板',
      'no_api_key': '未设置 API Key',
      'copy': '复制',
      'key_added_success': '密钥添加成功',
      'add_failed': '添加失败',
      'key_updated_success': '密钥更新成功',
      'update_failed': '更新失败',
      'confirm_delete': '确认删除',
      'delete_key_confirm': '确定要删除密钥"{name}"吗？此操作不可撤销。',
      'key_deleted': '密钥已删除',
      'delete_failed': '删除失败',
      'list_refreshed': '列表已刷新',
      'key_switched': '已切换',
      'switch_failed': '切换失败',
      'import_developing': '导入功能开发中',
      'export_developing': '导出功能开发中',
      'import_password_title': '输入导出密码',
      'import_password_desc': '请输入导出时设置的密码以解密文件',
      'export_password_title': '设置导出密码',
      'export_password_desc': '设置密码用于加密导出文件，导入时需要此密码',
      'export_password_label': '密码',
      'export_password_hint': '请输入密码',
      'export_password_required': '密码不能为空',
      'select_import_file': '选择导入文件',
      'select_export_file': '选择导出位置',
      'import_file_not_selected': '未选择文件',
      'export_file_not_selected': '未选择保存位置',
      'import_success': '导入成功',
      'import_failed': '导入失败',
      'export_success': '导出成功',
      'export_failed': '导出失败',
      'import_result': '导入完成：成功 {success} 个，失败 {failed} 个',
      'export_result': '导出完成：已保存到 {path}',
      'file_not_found': '文件不存在',
      'invalid_file_format': '无效的文件格式',
      'decrypt_failed': '解密失败，密码可能不正确',
      'details': '详情',
      'open_management_url': '打开管理地址',
      'copy_api_endpoint': '复制API地址',
      'copy_key': '复制密钥',
      'delete_tooltip': '删除',
      'platform_label': '平台',
      'open': '打开',
      'created_time': '创建时间',
      'updated_time': '更新时间',
      'key_value_label': '密钥值',
      'show': '显示',
      'hide': '隐藏',
      'key_name_required': '请输入密钥名称',
      'key_name_label': '密钥名称 *',
      'key_name_hint': '请输入密钥名称',
      'tags_label': '标签',
      'tags_hint': '多个标签用逗号分隔',
      'management_url_label': '管理地址',
      'management_url_hint': 'https://example.com',
      'api_endpoint_label': 'API地址',
      'api_endpoint_hint': 'https://api.example.com',
      'key_value_label_form': '密钥值 *',
      'key_value_hint': '请输入密钥值',
      'key_value_required': '请输入密钥值',
      'expiry_date_label': '过期日期',
      'expiry_date_hint': '选择日期（可选）',
      'clear_date': '清除日期',
      'notes_label': '备注',
      'notes_hint': '请输入备注信息',
      'master_password_cleared': '已清除主密码，密钥将以明文存储',
      'master_password_set_success': '主密码设置成功',
      'change_master_password': '修改主密码',
      'set_master_password': '设置主密码',
      'change_password_desc': '修改主密码后，所有密钥将使用新密码重新加密',
      'set_password_desc': '设置主密码后，所有密钥将加密存储。不设置则使用明文存储。',
      'master_password_label': '主密码',
      'master_password_hint': '留空则清除主密码（明文存储）',
      'generate_random_password': '生成随机密码',
      'generate_memorable_password': '生成易记密码',
      'password_generated_skip': '已生成密码，跳过强度验证',
      'password_strength_hint': '建议包含大小写字母、数字和特殊字符',
      'password_min_length': '密码长度至少8位',
      'confirm_password_label': '确认密码',
      'confirm_password_required': '请确认密码',
      'password_mismatch': '两次输入的密码不一致',
      'password_weak': '弱',
      'password_medium': '中',
      'password_strong': '强',
      'password_strength': '密码强度: ',
      'interface_language': '界面语言',
      'interface_language_desc': '切换后立即预览界面语言，保存后永久生效。',
      'appearance_theme': '外观主题',
      'appearance_theme_desc': '选择应用的外观主题，立即生效。',
      'window_behavior': '窗口行为',
      'window_behavior_desc': '配置窗口最小化与状态栏联动策略。',
      'data_management': '数据管理',
      'data_management_desc': '导入、导出和管理密钥数据。',
      'security_settings': '安全设置',
      'security_settings_desc': '管理主密码和加密设置。',
      'chinese': '中文',
      'english': 'English',
      'language_changed_zh': '语言已切换为中文，重启应用后生效',
      'language_changed_en': 'Language changed to English, restart app to apply',
      'minimize_to_tray_desc_detail': '勾选后点击关闭按钮会隐藏到系统状态栏，取消则直接退出应用。',
      'minimize_to_tray_enabled': '已启用最小化到状态栏，关闭窗口后状态栏图标将出现',
      'refresh_key_list': '刷新密钥列表',
      'change': '修改',
      'set': '设置',
      'cannot_decrypt_key': '无法解密密钥',
      'request_url': '请求地址',
      'main_model': '主模型',
      'haiku_model': 'Haiku 模型',
      'sonnet_model': 'Sonnet 模型',
      'opus_model': 'Opus 模型',
      'model_name': '模型名称',
      'main_model_hint': '请输入主模型名称',
      'haiku_model_hint': '请输入 Haiku 模型名称',
      'sonnet_model_hint': '请输入 Sonnet 模型名称',
      'opus_model_hint': '请输入 Opus 模型名称',
      'keys': '钥匙包',
      'category_popular': '常用',
      'category_claude_code': 'ClaudeCode',
      'category_codex': 'Codex',
      'category_llm': '大语言模型',
      'category_cloud': '云服务',
      'category_tools': '工具',
      'category_vector': '其他',
      'claude_code_config': 'ClaudeCode 配置',
      'codex_config': 'Codex 配置',
      'gemini_config': 'Gemini 配置',
      'claude_codex_config': 'Claude/Codex 配置',
      'claude_config_dir': 'Claude 配置目录',
      'codex_config_dir': 'Codex 配置目录',
      'gemini_config_dir': 'Gemini 配置目录',
      'official_config': '官方配置',
      'use_official_api': '使用官方 API 地址',
      'current': '当前',
      'no_claude_code_keys': '暂无 ClaudeCode 密钥',
      'enable_claude_code_hint': '请在密钥编辑页面启用 ClaudeCode 选项',
      'no_codex_keys': '暂无 Codex 密钥',
      'enable_codex_hint': '请在密钥编辑页面启用 Codex 选项',
      'no_gemini_keys': '暂无 Gemini 密钥',
      'enable_gemini_hint': '请在密钥编辑页面启用 Gemini 选项',
      'switched_to_official': '已切换 官方配置',
      'edit_official_config': '编辑官方配置',
      'official_config_updated': '官方配置已更新',
      'official_config_update_failed': '更新官方配置失败',
      'anthropic_model': '主模型 (ANTHROPIC_MODEL)',
      'anthropic_model_hint': '例如: claude-3-5-sonnet-20241022',
      'anthropic_haiku_model': 'Haiku 模型 (ANTHROPIC_DEFAULT_HAIKU_MODEL)',
      'anthropic_haiku_model_hint': '例如: claude-3-haiku-20240307',
      'anthropic_sonnet_model': 'Sonnet 模型 (ANTHROPIC_DEFAULT_SONNET_MODEL)',
      'anthropic_sonnet_model_hint': '例如: claude-3-5-sonnet-20241022',
      'anthropic_opus_model': 'Opus 模型 (ANTHROPIC_DEFAULT_OPUS_MODEL)',
      'anthropic_opus_model_hint': '例如: claude-3-opus-20240229',
      'custom_env_var': '自定义环境变量',
      'env_var_name': '变量名',
      'env_var_value': '变量值',
      'add_env_var': '添加环境变量',
      'remove_env_var': '删除',
      'add_common_env_var': '添加常用参数',
      'claude_config_not_found_load': '未找到 ClaudeCode 配置文件，可能 CLI 工具未安装或配置文件路径不正确。当前路径：{path}',
      'claude_config_not_found_switch_key': '未找到 ClaudeCode 配置文件，无法切换密钥。请先安装 CLI 工具或检查配置文件路径。',
      'claude_config_not_found_switch_config': '未找到 ClaudeCode 配置文件，无法切换配置。请先安装 CLI 工具或检查配置文件路径。',
      'codex_config_not_found_load': '未找到 Codex 配置文件，可能 CLI 工具未安装或配置文件路径不正确。当前路径：{path}',
      'codex_config_not_found_switch_key': '未找到 Codex 配置文件，无法切换密钥。请先安装 CLI 工具或检查配置文件路径。',
      'codex_config_not_found_switch_config': '未找到 Codex 配置文件，无法切换配置。请先安装 CLI 工具或检查配置文件路径。',
      'gemini_config_not_found_load': '未找到 Gemini 配置文件，可能工具未安装或配置文件路径不正确。当前路径：{path}',
      'gemini_config_not_found_switch_key': '未找到 Gemini 配置文件，无法切换密钥。请先安装工具或检查配置文件路径。',
      'gemini_config_not_found_switch_config': '未找到 Gemini 配置文件，无法切换配置。请先安装工具或检查配置文件路径。',
      'gemini_base_url_label': 'Base URL',
      'gemini_base_url_hint': '例如: https://generativelanguage.googleapis.com/v1',
      'gemini_model_label': '模型名称',
      'gemini_model_hint': '例如: gemini-pro, gemini-1.5-pro',
      'unknown': '未知',
      'browse': '浏览',
      'default': '默认',
      'select_claude_config_dir': '选择 Claude 配置目录',
      'select_codex_config_dir': '选择 Codex 配置目录',
      'select_gemini_config_dir': '选择 Gemini 配置目录',
      'config_dir_set': '已设置配置目录: {path}',
      'browse_directory_failed': '选择目录失败: {error}',
      'first_launch_title': '首次启动设置',
      'first_launch_message': '为了访问 {toolName} 的配置文件，请选择配置目录。',
      'first_launch_hint': '默认路径：{path}',
      'select_directory': '选择目录',
      'skip': '跳过',
      'select_config_dir': '选择 {toolName} 配置目录',
      'settings_general': '常规',
      'settings_tools': '工具配置',
      'settings_data': '数据选项',
      'settings_security': '安全选项',
      'config_valid': '配置正常',
      'config_missing': '配置缺失',
      // MCP 表单相关
      'mcp_display_name': '显示名称 *',
      'mcp_display_name_hint': '例如: Context7 MCP',
      'mcp_display_name_required': '请输入显示名称',
      'mcp_tags': '标签',
      'mcp_tags_hint': '多个标签用逗号分隔',
      // MCP 标签国际化
      'tag_documentation': '文档',
      'tag_library': '库',
      'tag_database': '数据库',
      'tag_api': 'API',
      'tag_automation': '自动化',
      'tag_workflow': '工作流',
      'tag_payment': '支付',
      'tag_finance': '金融',
      'tag_alipay': '支付宝',
      'tag_unionpay': '银联',
      'tag_sql': 'SQL',
      'tag_search': '搜索',
      'tag_web': '网页',
      'tag_ai': 'AI',
      'tag_chinese': '中文',
      'tag_map': '地图',
      'tag_location': '位置',
      'tag_geocoding': '地理编码',
      'tag_git': 'Git',
      'tag_version_control': '版本控制',
      'tag_filesystem': '文件系统',
      'tag_file_operations': '文件操作',
      'tag_cloud': '云服务',
      'tag_aws': 'AWS',
      'tag_gcp': 'GCP',
      'tag_llm': '大语言模型',
      'tag_reasoning': '推理',
      'tag_thinking': '思考',
      'tag_time': '时间',
      'tag_timezone': '时区',
      'tag_utility': '工具',
      'tag_communication': '通信',
      'tag_productivity': '生产力',
      'tag_browser': '浏览器',
      'tag_web_scraping': '网页抓取',
      'tag_http': 'HTTP',
      'tag_network': '网络',
      'tag_memory': '记忆',
      'tag_storage': '存储',
      'tag_context': '上下文',
      'tag_collaboration': '协作',
      'mcp_json_config': 'JSON配置 *',
      'mcp_json_config_format': '格式化',
      'mcp_json_formatted': 'JSON已格式化',
      'mcp_json_format_error': 'JSON格式错误，无法格式化',
      'mcp_json_config_required': '请输入JSON配置',
      'mcp_json_config_error': 'JSON配置格式错误: 必须包含MCP唯一标识，格式为 {"唯一标识": {配置}} 或 {"mcpServers": {"唯一标识": {配置}}}',
      'mcp_json_config_error_detail': 'JSON配置格式错误: {error}',
      'mcp_json_config_missing_field': 'JSON配置错误: 配置必须包含command或url字段',
      'mcp_json_config_hint': '粘贴MCP配置JSON，例如:\n{\n  "context7": {\n    "command": "npx",\n    "args": [\n      "-y",\n      "@upstash/context7-mcp@latest"\n    ]\n  }\n}\n\n或带mcpServers包装:\n{\n  "mcpServers": {\n    "context7": {...}\n  }\n}',
      'mcp_json_format_error_object': 'JSON格式错误: 必须是JSON对象格式',
      'mcp_json_format_error_identifier': 'JSON格式错误: 必须包含MCP唯一标识，格式为 {"唯一标识": {配置}} 或 {"mcpServers": {"唯一标识": {配置}}}',
      'mcp_json_format_error_value': 'JSON格式错误: 唯一标识的值必须是配置对象',
      'mcp_json_format_error_syntax': 'JSON格式错误: 存在非法字符，请检查JSON语法（注意：JSON不支持注释）',
      'mcp_json_format_error_missing': 'JSON格式错误: 缺少必要的字符，请检查JSON语法',
      'mcp_json_format_error_generic': 'JSON格式错误: {error}',
      'mcp_homepage': '管理地址（选填）',
      'mcp_homepage_hint': 'https://example.com',
      'mcp_docs': '文档地址（选填）',
      'mcp_docs_hint': 'https://docs.example.com',
      'mcp_description': '描述（选填）',
      'mcp_description_hint': 'MCP 服务器描述',
      // MCP 分类相关
      'mcp_category_database': '数据库',
      'mcp_category_search': '搜索',
      'mcp_category_development': '开发工具',
      'mcp_category_cloud': '云服务',
      'mcp_category_ai': 'AI服务',
      'mcp_category_automation': '自动化',
      // MCP 卡片按钮相关
      'mcp_open_docs': '文档地址',
      'mcp_delete_confirm_message': '确定要删除 MCP 服务器"{name}"吗？此操作不可撤销。',
      // MCP 列表界面相关
      'mcp_search_placeholder': '搜索 MCP 服务器...',
      'mcp_import_from_tool': '从工具读取',
      'mcp_export_to_tool': '下发到工具',
      'mcp_sync': '同步',
      'mcp_finish_edit': '完成编辑',
      'mcp_add_server': '添加 MCP 服务器',
      'edit_mcp_server': '编辑MCP服务器',
      'mcp_no_search_results': '未找到匹配的 MCP 服务器',
      'mcp_no_servers': '暂无 MCP 服务器',
      'mcp_add_first_server': '点击上方按钮添加您的第一个 MCP 服务器',
      'mcp_server_added': 'MCP 服务器添加成功',
      'mcp_add_failed': '添加失败',
      'mcp_server_updated': 'MCP 服务器更新成功',
      'mcp_update_failed': '更新失败',
      'mcp_server_deleted': 'MCP 服务器已删除',
      'mcp_delete_failed': '删除失败',
      'mcp_server_activated': 'MCP 服务器已激活',
      'mcp_server_deactivated': 'MCP 服务器已停用',
      'mcp_operation_failed': '操作失败',
      'mcp_server_details': 'MCP 服务器详情：{name}',
      // MCP 导入导出对话框相关
      'mcp_import_dialog_title': '从工具读取 MCP 配置',
      'mcp_export_dialog_title': '下发 MCP 服务到工具',
      'mcp_select_tool': '选择工具',
      'mcp_no_enabled_tools': '没有已启用的工具，请在设置中启用工具',
      'mcp_please_select_tool': '请先选择工具',
      'mcp_please_select_at_least_one': '请至少选择一个 MCP 服务',
      'mcp_read': '读取',
      'mcp_sync_to_list': '同步到列表',
      'mcp_export_to_tool_button': '下发到工具',
      'mcp_server_list': 'MCP 服务列表 ({count} 个)',
      'mcp_select_all': '全选',
      'mcp_deselect_all': '取消全选',
      'mcp_no_config_found': '未找到 MCP 配置',
      'mcp_no_config_in_tool': '工具 {tool} 中没有找到 MCP 配置',
      'mcp_read_failed': '读取失败: {error}',
      'mcp_sync_failed': '同步失败: {error}',
      'mcp_export_failed': '下发失败: {error}',
      'mcp_confirm_override': '确认覆盖',
      'mcp_override_message': '以下 MCP 服务已存在，将被覆盖：\n\n{servers}\n\n确定要继续吗？',
      'mcp_override_message_tool': '工具 {tool} 中以下 MCP 服务将被覆盖：\n\n{servers}\n\n确定要继续吗？',
      'mcp_confirm': '确定',
      'mcp_import_complete': '导入完成：新增 {added} 个，覆盖 {overridden} 个{failed}',
      'mcp_import_complete_failed': '，失败 {failed} 个',
      'mcp_export_success': '已成功下发 {count} 个 MCP 服务到 {tool}',
      'mcp_export_failed_short': '下发失败',
      'mcp_command': '命令: {command}',
      'mcp_args': '参数: {args}',
      'mcp_url': 'URL: {url}',
      'mcp_server_id': 'ID: {id}',
      // MCP 详情弹窗相关
      'mcp_view_details': '查看详情',
      'mcp_details_title': 'MCP 服务器详情',
      'mcp_server_type': '服务器类型',
      'mcp_server_id_label': '服务器ID',
      'mcp_command_label': '命令',
      'mcp_args_label': '参数',
      'mcp_env': '环境变量',
      'mcp_cwd': '工作目录',
      'mcp_url_label': 'URL',
      'mcp_headers': '请求头',
      'mcp_status': '状态',
      'mcp_active': '已激活',
      'mcp_inactive': '未激活',
      'mcp_copy_json': '复制JSON配置',
      'mcp_json_copied': 'JSON配置已复制',
      'mcp_json_config_label': 'JSON配置',
      // MCP 同步对话框相关
      'mcp_sync_dialog_title': 'MCP 配置同步',
      'mcp_local_servers': '本应用中的 MCP 服务',
      'mcp_tool_servers': '工具 {tool} 中的 MCP 服务',
      'mcp_sync_complete': '同步完成：导出 {export} 个，导入 {import} 个，删除 {delete} 个{failed}',
      'mcp_sync_complete_failed': '，失败 {failed} 个',
      'mcp_pending_changes': '待同步：导出 {export} 个，导入 {import} 个，删除 {delete} 个',
      'mcp_sync_to_tool': '同步到工具',
      'mcp_sync_to_local': '同步到本应用',
      'mcp_delete': '删除',
      'mcp_will_sync': '将同步',
      'mcp_will_be_overridden': '将被覆盖',
      'mcp_will_delete': '将删除',
      'mcp_open_homepage': '打开主页',
      'mcp_unsaved_changes': '有未保存的变更',
      'mcp_unsaved_changes_message': '您有未保存的变更，关闭前请选择操作方式。如果选择放弃，所有未保存的更改将丢失。',
      'mcp_unsaved_changes_message_switch': '您有未保存的变更，切换前请选择操作方式。如果选择放弃，所有未保存的更改将丢失。',
      'mcp_save': '保存',
      'mcp_discard': '放弃',
      'mcp_click_read': '请点击工具切换滑块或等待自动读取',
      'mcp_global_config': '全局配置',
      'mcp_claude_code_scope_help': 'ClaudeCode 支持全局配置和项目配置。项目配置优先级高于全局配置。\n\n'
          '全局配置：存储在 ~/.claude.json 的 mcpServers 字段\n'
          '项目配置：存储在 ~/.claude.json 的 projects[项目路径].mcpServers 字段',
      'mcp_project_uses_global_config': '该项目没有单独配置，将使用全局配置',
      // 配置模板更新相关
      'config_template_update': '配置模板更新',
      'cloud_config': '云端配置',
      'config_current_date': '配置文件时间戳',
      'check_update': '检查更新',
      'config_update_success': '配置模板已更新',
      'config_already_latest': '配置模板已是最新版本',
      'config_update_check_failed': '检查更新失败',
      'config_date_today': '今天',
      'config_date_yesterday': '昨天',
      // Codex 官方配置相关
      'codex_official_config_description': '配置官方 OpenAI API Key，用于 Codex 官方配置。API Key 将安全存储在本地，切换到官方配置时自动写入。',
      'codex_official_api_key_label': 'OpenAI API Key',
      'codex_official_api_key_placeholder': '请输入 OpenAI API Key (sk-...)',
      // Gemini 官方配置相关
      'gemini_official_config_description': '配置官方 Google Gemini API Key，用于 Gemini 官方配置。API Key 将安全存储在本地，切换到官方配置时自动写入到 .env 文件。',
      'gemini_official_api_key_label': 'Gemini API Key',
      'gemini_official_api_key_placeholder': '请输入 Gemini API Key',
      // MCP 状态标签相关
      'mcp_status_identical': '一致',
      'mcp_status_only_local': '仅本地',
      'mcp_status_only_tool': '仅工具',
    },
    'en': {
      'app_name': 'Key Core',
      'settings': 'Settings',
      'master_password': 'Master Password',
      'master_password_set': 'Master Password Set',
      'master_password_not_set': 'Master Password Not Set',
      'master_password_encrypted': 'Keys are encrypted',
      'master_password_plain': 'Keys are stored in plain text, recommend setting master password',
      'language': 'Language',
      'theme': 'Theme',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'theme_system': 'Follow System',
      'minimize_to_tray': 'Minimize to Menu Bar',
      'minimize_to_tray_desc': 'Hide to system menu bar when closing window, click menu bar icon to show window',
      'show_window': 'Show Window',
      'quit': 'Quit',
      'import_keys': 'Import Keys',
      'import_keys_desc': 'Import keys from file',
      'export_keys': 'Export Keys',
      'export_keys_desc': 'Export all keys to file',
      'import_password_title': 'Enter Export Password',
      'import_password_desc': 'Please enter the password set during export to decrypt the file',
      'export_password_title': 'Set Export Password',
      'export_password_desc': 'Set a password to encrypt the export file. This password will be required for import',
      'export_password_label': 'Password',
      'export_password_hint': 'Please enter password',
      'export_password_required': 'Password cannot be empty',
      'select_import_file': 'Select Import File',
      'select_export_file': 'Select Export Location',
      'import_file_not_selected': 'No file selected',
      'export_file_not_selected': 'No export location selected',
      'import_success': 'Import Successful',
      'import_failed': 'Import Failed',
      'export_success': 'Export Successful',
      'export_failed': 'Export Failed',
      'import_result': 'Import complete: {success} succeeded, {failed} failed',
      'export_result': 'Export complete: Saved to {path}',
      'file_not_found': 'File not found',
      'invalid_file_format': 'Invalid file format',
      'decrypt_failed': 'Decryption failed, password may be incorrect',
      'refresh_list': 'Refresh List',
      'close': 'Close',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'save': 'Save',
      'add': 'Add',
      'edit': 'Edit',
      'delete': 'Delete',
      'search': 'Search keys...',
      'all_platforms': 'All Platforms',
      'add_key': 'Add Key',
      'edit_key': 'Edit Key',
      'key_name': 'Key Name',
      'key_value': 'Key Value',
      'platform': 'Platform',
      'management_url': 'Management URL',
      'api_endpoint': 'API Endpoint',
      'expiry_date': 'Expiry Date',
      'tags': 'Tags',
      'notes': 'Notes',
      'select_supplier': 'Select Supplier (Optional)',
      'select_supplier_hint': 'Auto-fill information after selection',
      'custom': 'Custom',
      'required': 'Required',
      'optional': 'Optional',
      'loading': 'Loading...',
      'finish_edit': 'Finish Editing',
      'add_key_tooltip': 'Add Key',
      'settings_tooltip': 'Settings',
      'statistics': 'Statistics',
      'total': 'Total',
      'active': 'Active',
      'expiring_soon': 'Expiring Soon',
      'expired': 'Expired',
      'no_keys': 'No Keys',
      'add_first_key': 'Click the button below to add your first AI key',
      'key_copied': 'Key Copied',
      'key_copied_to_clipboard': 'Key copied to clipboard',
      'copy': 'Copy',
      'key_added_success': 'Key added successfully',
      'add_failed': 'Add failed',
      'key_updated_success': 'Key updated successfully',
      'update_failed': 'Update failed',
      'confirm_delete': 'Confirm Delete',
      'delete_key_confirm': 'Are you sure you want to delete key "{name}"? This action cannot be undone.',
      'key_deleted': 'Key deleted',
      'delete_failed': 'Delete failed',
      'list_refreshed': 'List refreshed',
      'key_switched': 'Switched',
      'switch_failed': 'Switch failed',
      'import_developing': 'Import feature under development',
      'export_developing': 'Export feature under development',
      'details': 'Details',
      'open_management_url': 'Open Management URL',
      'copy_api_endpoint': 'Copy API Endpoint',
      'copy_key': 'Copy Key',
      'delete_tooltip': 'Delete',
      'platform_label': 'Platform',
      'open': 'Open',
      'created_time': 'Created Time',
      'updated_time': 'Updated Time',
      'key_value_label': 'Key Value',
      'show': 'Show',
      'hide': 'Hide',
      'key_name_required': 'Please enter key name',
      'key_name_label': 'Key Name *',
      'key_name_hint': 'Please enter key name',
      'tags_label': 'Tags',
      'tags_hint': 'Separate multiple tags with commas',
      'management_url_label': 'Management URL',
      'management_url_hint': 'https://example.com',
      'api_endpoint_label': 'API Endpoint',
      'api_endpoint_hint': 'https://api.example.com',
      'key_value_label_form': 'Key Value *',
      'key_value_hint': 'Please enter key value',
      'key_value_required': 'Please enter key value',
      'expiry_date_label': 'Expiry Date',
      'expiry_date_hint': 'Select date (optional)',
      'clear_date': 'Clear Date',
      'notes_label': 'Notes',
      'notes_hint': 'Please enter notes',
      'master_password_cleared': 'Master password cleared, keys will be stored in plain text',
      'master_password_set_success': 'Master password set successfully',
      'change_master_password': 'Change Master Password',
      'set_master_password': 'Set Master Password',
      'change_password_desc': 'After changing master password, all keys will be re-encrypted with the new password',
      'set_password_desc': 'After setting master password, all keys will be encrypted. If not set, keys will be stored in plain text.',
      'master_password_label': 'Master Password',
      'master_password_hint': 'Leave empty to clear master password (plain text storage)',
      'generate_random_password': 'Generate Random Password',
      'generate_memorable_password': 'Generate Memorable Password',
      'password_generated_skip': 'Password generated, skip strength validation',
      'password_strength_hint': 'Recommended: uppercase, lowercase, numbers, and special characters',
      'password_min_length': 'Password must be at least 8 characters',
      'confirm_password_label': 'Confirm Password',
      'confirm_password_required': 'Please confirm password',
      'password_mismatch': 'Passwords do not match',
      'password_weak': 'Weak',
      'password_medium': 'Medium',
      'password_strong': 'Strong',
      'password_strength': 'Password Strength: ',
      'interface_language': 'Interface Language',
      'interface_language_desc': 'Preview interface language immediately after switching, takes effect permanently after saving.',
      'appearance_theme': 'Appearance Theme',
      'appearance_theme_desc': 'Select application appearance theme, takes effect immediately.',
      'window_behavior': 'Window Behavior',
      'window_behavior_desc': 'Configure window minimization and menu bar linkage strategy.',
      'data_management': 'Data Management',
      'data_management_desc': 'Import, export and manage key data.',
      'security_settings': 'Security Settings',
      'security_settings_desc': 'Manage master password and encryption settings.',
      'chinese': '中文',
      'english': 'English',
      'language_changed_zh': 'Language switched to Chinese, restart app to take effect',
      'language_changed_en': 'Language changed to English, restart app to apply',
      'minimize_to_tray_desc_detail': 'When checked, clicking close button will hide to system menu bar, otherwise exit app directly.',
      'minimize_to_tray_enabled': 'Minimize to menu bar enabled, menu bar icon will appear after closing window',
      'refresh_key_list': 'Refresh Key List',
      'change': 'Change',
      'set': 'Set',
      'cannot_decrypt_key': 'Cannot decrypt key',
      'request_url': 'Request URL',
      'main_model': 'Main Model',
      'haiku_model': 'Haiku Model',
      'sonnet_model': 'Sonnet Model',
      'opus_model': 'Opus Model',
      'main_model_hint': 'Please enter main model name',
      'haiku_model_hint': 'Please enter Haiku model name',
      'sonnet_model_hint': 'Please enter Sonnet model name',
      'opus_model_hint': 'Please enter Opus model name',
      'model_name': 'Model Name',
      'keys': 'Keys',
      'category_popular': 'Popular',
      'category_claude_code': 'ClaudeCode',
      'category_codex': 'Codex',
      'category_llm': 'LLM',
      'category_cloud': 'Cloud',
      'category_tools': 'Tools',
      'category_vector': 'Other',
      'claude_code_config': 'ClaudeCode Config',
      'codex_config': 'Codex Config',
      'gemini_config': 'Gemini Config',
      'claude_codex_config': 'Claude/Codex Config',
      'claude_config_dir': 'Claude Config Directory',
      'codex_config_dir': 'Codex Config Directory',
      'gemini_config_dir': 'Gemini Config Directory',
      'official_config': 'Official Config',
      'use_official_api': 'Use Official API',
      'current': 'Current',
      'no_claude_code_keys': 'No ClaudeCode Keys',
      'enable_claude_code_hint': 'Please enable ClaudeCode option in key edit page',
      'no_codex_keys': 'No Codex Keys',
      'enable_codex_hint': 'Please enable Codex option in key edit page',
      'no_gemini_keys': 'No Gemini Keys',
      'enable_gemini_hint': 'Please enable Gemini option in key edit page',
      'switched_to_official': 'Switched to Official Config',
      'claude_config_not_found_load': 'ClaudeCode config file not found. CLI tool may not be installed or config path is incorrect. Current path: {path}',
      'claude_config_not_found_switch_key': 'ClaudeCode config file not found. Cannot switch key. Please install CLI tool or check config path.',
      'claude_config_not_found_switch_config': 'ClaudeCode config file not found. Cannot switch config. Please install CLI tool or check config path.',
      'codex_config_not_found_load': 'Codex config file not found. CLI tool may not be installed or config path is incorrect. Current path: {path}',
      'codex_config_not_found_switch_key': 'Codex config file not found. Cannot switch key. Please install CLI tool or check config path.',
      'codex_config_not_found_switch_config': 'Codex config file not found. Cannot switch config. Please install CLI tool or check config path.',
      'gemini_config_not_found_load': 'Gemini config file not found. Tool may not be installed or config path is incorrect. Current path: {path}',
      'gemini_config_not_found_switch_key': 'Gemini config file not found. Cannot switch key. Please install tool or check config path.',
      'gemini_config_not_found_switch_config': 'Gemini config file not found. Cannot switch config. Please install tool or check config path.',
      'unknown': 'Unknown',
      'browse': 'Browse',
      'default': 'Default',
      'select_claude_config_dir': 'Select Claude Config Directory',
      'select_codex_config_dir': 'Select Codex Config Directory',
      'select_gemini_config_dir': 'Select Gemini Config Directory',
      'config_dir_set': 'Config directory set: {path}',
      'browse_directory_failed': 'Failed to browse directory: {error}',
      'first_launch_title': 'First Launch Setup',
      'first_launch_message': 'To access {toolName} configuration files, please select the config directory.',
      'first_launch_hint': 'Default path: {path}',
      'select_directory': 'Select Directory',
      'skip': 'Skip',
      'select_config_dir': 'Select {toolName} Config Directory',
      'settings_general': 'General',
      'settings_tools': 'Tools',
      'settings_data': 'Data',
      'settings_security': 'Security',
      'config_valid': 'Config Valid',
      'config_missing': 'Config Missing',
      // MCP Form related
      'mcp_display_name': 'Display Name *',
      'mcp_display_name_hint': 'e.g.: Context7 MCP',
      'mcp_display_name_required': 'Please enter display name',
      'mcp_tags': 'Tags',
      // MCP tag internationalization
      'tag_documentation': 'Documentation',
      'tag_library': 'Library',
      'tag_database': 'Database',
      'tag_api': 'API',
      'tag_automation': 'Automation',
      'tag_workflow': 'Workflow',
      'tag_payment': 'Payment',
      'tag_finance': 'Finance',
      'tag_alipay': 'Alipay',
      'tag_unionpay': 'UnionPay',
      'tag_sql': 'SQL',
      'tag_search': 'Search',
      'tag_web': 'Web',
      'tag_ai': 'AI',
      'tag_chinese': 'Chinese',
      'tag_map': 'Map',
      'tag_location': 'Location',
      'tag_geocoding': 'Geocoding',
      'tag_git': 'Git',
      'tag_version_control': 'Version Control',
      'tag_filesystem': 'Filesystem',
      'tag_file_operations': 'File Operations',
      'tag_cloud': 'Cloud',
      'tag_aws': 'AWS',
      'tag_gcp': 'GCP',
      'tag_llm': 'LLM',
      'tag_reasoning': 'Reasoning',
      'tag_thinking': 'Thinking',
      'tag_time': 'Time',
      'tag_timezone': 'Timezone',
      'tag_utility': 'Utility',
      'tag_communication': 'Communication',
      'tag_productivity': 'Productivity',
      'tag_browser': 'Browser',
      'tag_web_scraping': 'Web Scraping',
      'tag_http': 'HTTP',
      'tag_network': 'Network',
      'tag_memory': 'Memory',
      'tag_storage': 'Storage',
      'tag_context': 'Context',
      'tag_collaboration': 'Collaboration',
      'mcp_tags_hint': 'Separate multiple tags with commas',
      'mcp_json_config': 'JSON Config *',
      'mcp_json_config_format': 'Format',
      'mcp_json_formatted': 'JSON formatted',
      'mcp_json_format_error': 'JSON format error, cannot format',
      'mcp_json_config_required': 'Please enter JSON config',
      'mcp_json_config_error': 'JSON config format error: Must include MCP unique identifier, format: {"identifier": {config}} or {"mcpServers": {"identifier": {config}}}',
      'mcp_json_config_error_detail': 'JSON config format error: {error}',
      'mcp_json_config_missing_field': 'JSON config error: Config must include command or url field',
      'mcp_json_config_hint': 'Paste MCP config JSON, e.g.:\n{\n  "context7": {\n    "command": "npx",\n    "args": [\n      "-y",\n      "@upstash/context7-mcp@latest"\n    ]\n  }\n}\n\nOr with mcpServers wrapper:\n{\n  "mcpServers": {\n    "context7": {...}\n  }\n}',
      'mcp_json_format_error_object': 'JSON format error: Must be JSON object format',
      'mcp_json_format_error_identifier': 'JSON format error: Must include MCP unique identifier, format: {"identifier": {config}} or {"mcpServers": {"identifier": {config}}}',
      'mcp_json_format_error_value': 'JSON format error: Identifier value must be config object',
      'mcp_json_format_error_syntax': 'JSON format error: Invalid characters found, please check JSON syntax (Note: JSON does not support comments)',
      'mcp_json_format_error_missing': 'JSON format error: Missing required characters, please check JSON syntax',
      'mcp_json_format_error_generic': 'JSON format error: {error}',
      'mcp_homepage': 'Homepage (Optional)',
      'mcp_homepage_hint': 'https://example.com',
      'mcp_docs': 'Documentation URL (Optional)',
      'mcp_docs_hint': 'https://docs.example.com',
      'mcp_description': 'Description (Optional)',
      'mcp_description_hint': 'MCP server description',
      // MCP Category related
      'mcp_category_database': 'Database',
      'mcp_category_search': 'Search',
      'mcp_category_development': 'Development Tools',
      'mcp_category_cloud': 'Cloud Services',
      'mcp_category_ai': 'AI Services',
      'mcp_category_automation': 'Automation',
      // MCP Card button related
      'mcp_open_docs': 'Documentation URL',
      'mcp_delete_confirm_message': 'Are you sure you want to delete MCP server "{name}"? This action cannot be undone.',
      // MCP List screen related
      'mcp_search_placeholder': 'Search MCP servers...',
      'mcp_import_from_tool': 'Import from Tool',
      'mcp_export_to_tool': 'Export to Tool',
      'mcp_sync': 'Sync',
      'mcp_finish_edit': 'Finish Editing',
      'mcp_add_server': 'Add MCP Server',
      'edit_mcp_server': 'Edit MCP Server',
      'mcp_no_search_results': 'No matching MCP servers found',
      'mcp_no_servers': 'No MCP Servers',
      'mcp_add_first_server': 'Click the button above to add your first MCP server',
      'mcp_server_added': 'MCP server added successfully',
      'mcp_add_failed': 'Add failed',
      'mcp_server_updated': 'MCP server updated successfully',
      'mcp_update_failed': 'Update failed',
      'mcp_server_deleted': 'MCP server deleted',
      'mcp_delete_failed': 'Delete failed',
      'mcp_server_activated': 'MCP server activated',
      'mcp_server_deactivated': 'MCP server deactivated',
      'mcp_operation_failed': 'Operation failed',
      'mcp_server_details': 'MCP Server Details: {name}',
      // MCP Import/Export dialog related
      'mcp_import_dialog_title': 'Import MCP Config from Tool',
      'mcp_export_dialog_title': 'Export MCP Services to Tool',
      'mcp_select_tool': 'Select Tool',
      'mcp_no_enabled_tools': 'No enabled tools. Please enable tools in settings',
      'mcp_please_select_tool': 'Please select a tool first',
      'mcp_please_select_at_least_one': 'Please select at least one MCP service',
      'mcp_read': 'Read',
      'mcp_sync_to_list': 'Sync to List',
      'mcp_export_to_tool_button': 'Export to Tool',
      'mcp_server_list': 'MCP Service List ({count} items)',
      'mcp_select_all': 'Select All',
      'mcp_deselect_all': 'Deselect All',
      'mcp_no_config_found': 'No MCP config found',
      'mcp_no_config_in_tool': 'No MCP config found in tool {tool}',
      'mcp_read_failed': 'Read failed: {error}',
      'mcp_sync_failed': 'Sync failed: {error}',
      'mcp_export_failed': 'Export failed: {error}',
      'mcp_confirm_override': 'Confirm Override',
      'mcp_override_message': 'The following MCP services already exist and will be overridden:\n\n{servers}\n\nContinue?',
      'mcp_override_message_tool': 'The following MCP services in tool {tool} will be overridden:\n\n{servers}\n\nContinue?',
      'mcp_confirm': 'Confirm',
      'mcp_import_complete': 'Import complete: {added} added, {overridden} overridden{failed}',
      'mcp_import_complete_failed': ', {failed} failed',
      'mcp_export_success': 'Successfully exported {count} MCP services to {tool}',
      'mcp_export_failed_short': 'Export failed',
      'mcp_command': 'Command: {command}',
      'mcp_args': 'Args: {args}',
      'mcp_url': 'URL: {url}',
      'mcp_server_id': 'ID: {id}',
      // MCP Details dialog related
      'mcp_view_details': 'View Details',
      'mcp_details_title': 'MCP Server Details',
      'mcp_server_type': 'Server Type',
      'mcp_server_id_label': 'Server ID',
      'mcp_command_label': 'Command',
      'mcp_args_label': 'Arguments',
      'mcp_env': 'Environment Variables',
      'mcp_cwd': 'Working Directory',
      'mcp_url_label': 'URL',
      'mcp_headers': 'Headers',
      'mcp_status': 'Status',
      'mcp_active': 'Active',
      'mcp_inactive': 'Inactive',
      'mcp_copy_json': 'Copy JSON Config',
      'mcp_json_copied': 'JSON config copied',
      'mcp_json_config_label': 'JSON Config',
      // MCP Sync dialog related
      'mcp_sync_dialog_title': 'MCP Config Sync',
      'mcp_local_servers': 'MCP Services in App',
      'mcp_tool_servers': 'MCP Services in {tool}',
      'mcp_sync_complete': 'Sync complete: {export} exported, {import} imported, {delete} deleted{failed}',
      'mcp_sync_complete_failed': ', {failed} failed',
      'mcp_pending_changes': 'Pending: {export} to export, {import} to import, {delete} to delete',
      'mcp_sync_to_tool': 'Sync to Tool',
      'mcp_sync_to_local': 'Sync to App',
      'mcp_delete': 'Delete',
      'mcp_will_sync': 'Will Sync',
      'mcp_will_be_overridden': 'Will Be Overridden',
      'mcp_will_delete': 'Will Delete',
      'mcp_open_homepage': 'Open Homepage',
      'mcp_unsaved_changes': 'Unsaved Changes',
      'mcp_unsaved_changes_message': 'You have unsaved changes. Please choose an action before closing. If you choose to discard, all unsaved changes will be lost.',
      'mcp_unsaved_changes_message_switch': 'You have unsaved changes. Please choose an action before switching. If you choose to discard, all unsaved changes will be lost.',
      'mcp_save': 'Save',
      'mcp_discard': 'Discard',
      'mcp_click_read': 'Please click tool switcher or wait for auto-read',
      'mcp_global_config': 'Global Config',
      'mcp_claude_code_scope_help': 'ClaudeCode supports both global and project configurations. Project configurations have higher priority than global configurations.\n\n'
          'Global Config: Stored in mcpServers field of ~/.claude.json\n'
          'Project Config: Stored in projects[projectPath].mcpServers field of ~/.claude.json',
      'mcp_project_uses_global_config': 'This project has no separate config, will use global config',
      // Config template update related
      'config_template_update': 'Config Template Update',
      'cloud_config': 'Cloud Config',
      'config_current_date': 'Config File Timestamp',
      'check_update': 'Check Update',
      'config_update_success': 'Config template updated',
      'config_already_latest': 'Config template is already the latest version',
      'config_update_check_failed': 'Update check failed',
      'config_date_today': 'Today',
      'config_date_yesterday': 'Yesterday',
      // Codex official config related
      'codex_official_config_description': 'Configure official OpenAI API Key for Codex official config. API Key will be securely stored locally and automatically written when switching to official config.',
      'codex_official_api_key_label': 'OpenAI API Key',
      'codex_official_api_key_placeholder': 'Please enter OpenAI API Key (sk-...)',
      // Gemini official config related
      'gemini_official_config_description': 'Configure official Google Gemini API Key for Gemini official config. API Key will be securely stored locally and automatically written to .env file when switching to official config.',
      'gemini_official_api_key_label': 'Gemini API Key',
      'gemini_official_api_key_placeholder': 'Please enter Gemini API Key',
      // MCP status labels related
      'mcp_status_identical': 'Identical',
      'mcp_status_only_local': 'Local Only',
      'mcp_status_only_tool': 'Tool Only',
    },
  };

  String translate(String key) {
    // 优先使用从JSON加载的翻译
    if (_jsonTranslations != null && _jsonTranslations!.containsKey(key)) {
      return _jsonTranslations![key]!;
    }
    // 回退到硬编码的翻译
    return _localizedValues[locale.languageCode]?[key] ?? key;
  }

  String get appName => translate('app_name');
  String get settings => translate('settings');
  String get masterPassword => translate('master_password');
  String get masterPasswordSet => translate('master_password_set');
  String get masterPasswordNotSet => translate('master_password_not_set');
  String get masterPasswordEncrypted => translate('master_password_encrypted');
  String get masterPasswordPlain => translate('master_password_plain');
  String get language => translate('language');
  String get theme => translate('theme');
  String get themeLight => translate('theme_light');
  String get themeDark => translate('theme_dark');
  String get themeSystem => translate('theme_system');
  String get minimizeToTray => translate('minimize_to_tray');
  String get minimizeToTrayDesc => translate('minimize_to_tray_desc');
  String get importKeys => translate('import_keys');
  String get importKeysDesc => translate('import_keys_desc');
  String get exportKeys => translate('export_keys');
  String get exportKeysDesc => translate('export_keys_desc');
  String get importPasswordTitle => translate('import_password_title');
  String get importPasswordDesc => translate('import_password_desc');
  String get exportPasswordTitle => translate('export_password_title');
  String get exportPasswordDesc => translate('export_password_desc');
  String get exportPasswordLabel => translate('export_password_label');
  String get exportPasswordHint => translate('export_password_hint');
  String get exportPasswordRequired => translate('export_password_required');
  String get selectImportFile => translate('select_import_file');
  String get selectExportFile => translate('select_export_file');
  String get importFileNotSelected => translate('import_file_not_selected');
  String get exportFileNotSelected => translate('export_file_not_selected');
  String get importSuccess => translate('import_success');
  String get importFailed => translate('import_failed');
  String get exportSuccess => translate('export_success');
  String get exportFailed => translate('export_failed');
  String importResult(int success, int failed) => translate('import_result')
      .replaceAll('{success}', success.toString())
      .replaceAll('{failed}', failed.toString());
  String exportResult(String path) => translate('export_result').replaceAll('{path}', path);
  String get fileNotFound => translate('file_not_found');
  String get invalidFileFormat => translate('invalid_file_format');
  String get decryptFailed => translate('decrypt_failed');
  String get refreshList => translate('refresh_list');
  String get close => translate('close');
  String get cancel => translate('cancel');
  String get confirm => translate('confirm');
  String get save => translate('save');
  String get add => translate('add');
  String get edit => translate('edit');
  String get delete => translate('delete');
  String get search => translate('search');
  String get allPlatforms => translate('all_platforms');
  String get addKey => translate('add_key');
  String get editKey => translate('edit_key');
  String get keyName => translate('key_name');
  String get keyValue => translate('key_value');
  String get platform => translate('platform');
  String get managementUrl => translate('management_url');
  String get apiEndpoint => translate('api_endpoint');
  String get expiryDate => translate('expiry_date');
  String get tags => translate('tags');
  String get notes => translate('notes');
  String get selectSupplier => translate('select_supplier');
  String get selectSupplierHint => translate('select_supplier_hint');
  String get custom => translate('custom');
  String get required => translate('required');
  String get optional => translate('optional');
  String get loading => translate('loading');
  String get finishEdit => translate('finish_edit');
  String get addKeyTooltip => translate('add_key_tooltip');
  String get settingsTooltip => translate('settings_tooltip');
  String get statistics => translate('statistics');
  String get total => translate('total');
  String get active => translate('active');
  String get expiringSoon => translate('expiring_soon');
  String get expired => translate('expired');
  String get noKeys => translate('no_keys');
  String get addFirstKey => translate('add_first_key');
  String get keyCopied => translate('key_copied');
  String get keyCopiedToClipboard => translate('key_copied_to_clipboard');
  String get noApiKey => translate('no_api_key');
  String get copy => translate('copy');
  String get keyAddedSuccess => translate('key_added_success');
  String get addFailed => translate('add_failed');
  String get keyUpdatedSuccess => translate('key_updated_success');
  String get updateFailed => translate('update_failed');
  String get confirmDelete => translate('confirm_delete');
  String deleteKeyConfirm(String name) => translate('delete_key_confirm').replaceAll('{name}', name);
  String get keyDeleted => translate('key_deleted');
  String get deleteFailed => translate('delete_failed');
  String get listRefreshed => translate('list_refreshed');
  String get keySwitched => translate('key_switched');
  String get switchFailed => translate('switch_failed');
  String get importDeveloping => translate('import_developing');
  String get exportDeveloping => translate('export_developing');
  String get details => translate('details');
  String get openManagementUrl => translate('open_management_url');
  String get copyApiEndpoint => translate('copy_api_endpoint');
  String get copyKey => translate('copy_key');
  String get deleteTooltip => translate('delete_tooltip');
  String get platformLabel => translate('platform_label');
  String get open => translate('open');
  String get createdTime => translate('created_time');
  String get updatedTime => translate('updated_time');
  String get keyValueLabel => translate('key_value_label');
  String get keyValuePlaceholder => translate('key_value_placeholder');
  String get show => translate('show');
  String get hide => translate('hide');
  String get keyNameRequired => translate('key_name_required');
  String get keyNameLabel => translate('key_name_label');
  String get keyNameHint => translate('key_name_hint');
  String get tagsLabel => translate('tags_label');
  String get tagsHint => translate('tags_hint');
  String get managementUrlLabel => translate('management_url_label');
  String get managementUrlHint => translate('management_url_hint');
  String get apiEndpointLabel => translate('api_endpoint_label');
  String get apiEndpointHint => translate('api_endpoint_hint');
  String get keyValueLabelForm => translate('key_value_label_form');
  String get keyValueHint => translate('key_value_hint');
  String get keyValueRequired => translate('key_value_required');
  String get expiryDateLabel => translate('expiry_date_label');
  String get expiryDateHint => translate('expiry_date_hint');
  String get clearDate => translate('clear_date');
  String get notesLabel => translate('notes_label');
  String get notesHint => translate('notes_hint');
  String get masterPasswordCleared => translate('master_password_cleared');
  String get masterPasswordSetSuccess => translate('master_password_set_success');
  String get changeMasterPassword => translate('change_master_password');
  String get setMasterPassword => translate('set_master_password');
  String get changePasswordDesc => translate('change_password_desc');
  String get setPasswordDesc => translate('set_password_desc');
  String get masterPasswordLabel => translate('master_password_label');
  String get masterPasswordHint => translate('master_password_hint');
  String get generateRandomPassword => translate('generate_random_password');
  String get generateMemorablePassword => translate('generate_memorable_password');
  String get passwordGeneratedSkip => translate('password_generated_skip');
  String get passwordStrengthHint => translate('password_strength_hint');
  String get passwordMinLength => translate('password_min_length');
  String get confirmPasswordLabel => translate('confirm_password_label');
  String get confirmPasswordRequired => translate('confirm_password_required');
  String get passwordMismatch => translate('password_mismatch');
  String get passwordWeak => translate('password_weak');
  String get passwordMedium => translate('password_medium');
  String get passwordStrong => translate('password_strong');
  String get passwordStrength => translate('password_strength');
  String get interfaceLanguage => translate('interface_language');
  String get interfaceLanguageDesc => translate('interface_language_desc');
  String get appearanceTheme => translate('appearance_theme');
  String get appearanceThemeDesc => translate('appearance_theme_desc');
  String get windowBehavior => translate('window_behavior');
  String get windowBehaviorDesc => translate('window_behavior_desc');
  String get dataManagement => translate('data_management');
  String get dataManagementDesc => translate('data_management_desc');
  String get securitySettings => translate('security_settings');
  String get securitySettingsDesc => translate('security_settings_desc');
  String get chinese => translate('chinese');
  String get english => translate('english');
  String get languageChangedSuccess => translate('language_changed_success');
  String get minimizeToTrayDescDetail => translate('minimize_to_tray_desc_detail');
  String get minimizeToTrayEnabled => translate('minimize_to_tray_enabled');
  String get refreshKeyList => translate('refresh_key_list');
  String get change => translate('change');
  String get set => translate('set');
  String get cannotDecryptKey => translate('cannot_decrypt_key');
  String get requestUrl => translate('request_url');
  String get mainModel => translate('main_model');
  String get haikuModel => translate('haiku_model');
  String get sonnetModel => translate('sonnet_model');
  String get opusModel => translate('opus_model');
  String get modelName => translate('model_name');
  String get mainModelHint => translate('main_model_hint');
  String get haikuModelHint => translate('haiku_model_hint');
  String get sonnetModelHint => translate('sonnet_model_hint');
  String get opusModelHint => translate('opus_model_hint');
  String get keys => translate('keys');
  String get categoryPopular => translate('category_popular');
  String get categoryClaudeCode => translate('category_claude_code');
  String get categoryCodex => translate('category_codex');
  String get categoryLlm => translate('category_llm');
  String get categoryCloud => translate('category_cloud');
  String get categoryTools => translate('category_tools');
  String get categoryVector => translate('category_vector');
  String get claudeCodeConfig => translate('claude_code_config');
  String get codexConfig => translate('codex_config');
  String get geminiConfig => translate('gemini_config');
  String get claudeCodexConfig => translate('claude_codex_config');
  String get claudeConfigDir => translate('claude_config_dir');
  String get codexConfigDir => translate('codex_config_dir');
  String get geminiConfigDir => translate('gemini_config_dir');
  String get officialConfig => translate('official_config');
  String get useOfficialApi => translate('use_official_api');
  String get current => translate('current');
  String get editOfficialConfig => translate('edit_official_config');
  String get officialConfigUpdated => translate('official_config_updated');
  String get officialConfigUpdateFailed => translate('official_config_update_failed');
  String get anthropicModel => translate('anthropic_model');
  String get anthropicModelHint => translate('anthropic_model_hint');
  String get anthropicHaikuModel => translate('anthropic_haiku_model');
  String get anthropicHaikuModelHint => translate('anthropic_haiku_model_hint');
  String get anthropicSonnetModel => translate('anthropic_sonnet_model');
  String get anthropicSonnetModelHint => translate('anthropic_sonnet_model_hint');
  String get anthropicOpusModel => translate('anthropic_opus_model');
  String get anthropicOpusModelHint => translate('anthropic_opus_model_hint');
  String get customEnvVar => translate('custom_env_var');
  String get envVarName => translate('env_var_name');
  String get envVarValue => translate('env_var_value');
  String get addEnvVar => translate('add_env_var');
  String get removeEnvVar => translate('remove_env_var');
  String get addCommonEnvVar => translate('add_common_env_var');
  String get noClaudeCodeKeys => translate('no_claude_code_keys');
  String get enableClaudeCodeHint => translate('enable_claude_code_hint');
  String get noCodexKeys => translate('no_codex_keys');
  String get enableCodexHint => translate('enable_codex_hint');
  String get noGeminiKeys => translate('no_gemini_keys');
  String get enableGeminiHint => translate('enable_gemini_hint');
  String get switchedToOfficial => translate('switched_to_official');
  String claudeConfigNotFoundLoad(String path) => translate('claude_config_not_found_load').replaceAll('{path}', path);
  String get claudeConfigNotFoundSwitchKey => translate('claude_config_not_found_switch_key');
  String get claudeConfigNotFoundSwitchConfig => translate('claude_config_not_found_switch_config');
  String codexConfigNotFoundLoad(String path) => translate('codex_config_not_found_load').replaceAll('{path}', path);
  String get codexConfigNotFoundSwitchKey => translate('codex_config_not_found_switch_key');
  String get codexConfigNotFoundSwitchConfig => translate('codex_config_not_found_switch_config');
  String geminiConfigNotFoundLoad(String path) => translate('gemini_config_not_found_load').replaceAll('{path}', path);
  String get geminiConfigNotFoundSwitchKey => translate('gemini_config_not_found_switch_key');
  String get geminiConfigNotFoundSwitchConfig => translate('gemini_config_not_found_switch_config');
  String get geminiBaseUrlLabel => translate('gemini_base_url_label');
  String get geminiBaseUrlHint => translate('gemini_base_url_hint');
  String get geminiModelLabel => translate('gemini_model_label');
  String get geminiModelHint => translate('gemini_model_hint');
  String get unknown => translate('unknown');
  String get browse => translate('browse');
  String get currentLabel => translate('current');
  String get defaultLabel => translate('default');
  String get selectClaudeConfigDir => translate('select_claude_config_dir');
  String get selectCodexConfigDir => translate('select_codex_config_dir');
  String get selectGeminiConfigDir => translate('select_gemini_config_dir');
  String configDirSet(String path) => translate('config_dir_set').replaceAll('{path}', path);
  String browseDirectoryFailed(String error) => translate('browse_directory_failed').replaceAll('{error}', error);
  String get firstLaunchTitle => translate('first_launch_title');
  String firstLaunchMessage(String toolName) => translate('first_launch_message').replaceAll('{toolName}', toolName);
  String firstLaunchHint(String path) => translate('first_launch_hint').replaceAll('{path}', path);
  String get selectDirectory => translate('select_directory');
  String get skip => translate('skip');
  String selectConfigDir(String toolName) => translate('select_config_dir').replaceAll('{toolName}', toolName);
  String get settingsGeneral => translate('settings_general');
  String get settingsTools => translate('settings_tools');
  String get settingsData => translate('settings_data');
  String get settingsSecurity => translate('settings_security');
  String get configValid => translate('config_valid');
  String get configMissing => translate('config_missing');
  // MCP Form related
  String get mcpDisplayName => translate('mcp_display_name');
  String get mcpDisplayNameHint => translate('mcp_display_name_hint');
  String get mcpDisplayNameRequired => translate('mcp_display_name_required');
  String get mcpTags => translate('mcp_tags');
  String get mcpTagsHint => translate('mcp_tags_hint');
  
  /// 翻译标签键为国际化文本
  String translateTag(String tagKey) {
    final key = 'tag_${tagKey.toLowerCase()}';
    final translated = translate(key);
    // 如果翻译不存在，返回原始标签键
    return translated == key ? tagKey : translated;
  }
  String get mcpJsonConfig => translate('mcp_json_config');
  String get mcpJsonConfigFormat => translate('mcp_json_config_format');
  String get mcpJsonFormatted => translate('mcp_json_formatted');
  String get mcpJsonFormatError => translate('mcp_json_format_error');
  String get mcpJsonConfigRequired => translate('mcp_json_config_required');
  String get mcpJsonConfigError => translate('mcp_json_config_error');
  String mcpJsonConfigErrorDetail(String error) => translate('mcp_json_config_error_detail').replaceAll('{error}', error);
  String get mcpJsonConfigMissingField => translate('mcp_json_config_missing_field');
  String get mcpJsonConfigHint => translate('mcp_json_config_hint');
  String get mcpJsonFormatErrorObject => translate('mcp_json_format_error_object');
  String get mcpJsonFormatErrorIdentifier => translate('mcp_json_format_error_identifier');
  String get mcpJsonFormatErrorValue => translate('mcp_json_format_error_value');
  String get mcpJsonFormatErrorSyntax => translate('mcp_json_format_error_syntax');
  String get mcpJsonFormatErrorMissing => translate('mcp_json_format_error_missing');
  String mcpJsonFormatErrorGeneric(String error) => translate('mcp_json_format_error_generic').replaceAll('{error}', error);
  String get mcpHomepage => translate('mcp_homepage');
  String get mcpHomepageHint => translate('mcp_homepage_hint');
  String get mcpDocs => translate('mcp_docs');
  String get mcpDocsHint => translate('mcp_docs_hint');
  String get mcpDescription => translate('mcp_description');
  String get mcpDescriptionHint => translate('mcp_description_hint');
  // MCP Category related
  String get mcpCategoryDatabase => translate('mcp_category_database');
  String get mcpCategorySearch => translate('mcp_category_search');
  String get mcpCategoryDevelopment => translate('mcp_category_development');
  String get mcpCategoryCloud => translate('mcp_category_cloud');
  String get mcpCategoryAi => translate('mcp_category_ai');
  String get mcpCategoryAutomation => translate('mcp_category_automation');
  // MCP Card button related
  String get mcpOpenDocs => translate('mcp_open_docs');
  String mcpDeleteConfirmMessage(String name) => translate('mcp_delete_confirm_message').replaceAll('{name}', name);
  // MCP List screen related
  String get mcpSearchPlaceholder => translate('mcp_search_placeholder');
  String get mcpImportFromTool => translate('mcp_import_from_tool');
  String get mcpExportToTool => translate('mcp_export_to_tool');
  String get mcpSync => translate('mcp_sync');
  String get mcpFinishEdit => translate('mcp_finish_edit');
  String get mcpAddServer => translate('mcp_add_server');
  String get editMcpServer => translate('edit_mcp_server');
  String get mcpNoSearchResults => translate('mcp_no_search_results');
  String get mcpNoServers => translate('mcp_no_servers');
  String get mcpAddFirstServer => translate('mcp_add_first_server');
  String get mcpServerAdded => translate('mcp_server_added');
  String get mcpAddFailed => translate('mcp_add_failed');
  String get mcpServerUpdated => translate('mcp_server_updated');
  String get mcpUpdateFailed => translate('mcp_update_failed');
  String get mcpServerDeleted => translate('mcp_server_deleted');
  String get mcpDeleteFailed => translate('mcp_delete_failed');
  String get mcpServerActivated => translate('mcp_server_activated');
  String get mcpServerDeactivated => translate('mcp_server_deactivated');
  String get mcpOperationFailed => translate('mcp_operation_failed');
  String mcpServerDetails(String name) => translate('mcp_server_details').replaceAll('{name}', name);
  // MCP Import/Export dialog related
  String get mcpImportDialogTitle => translate('mcp_import_dialog_title');
  String get mcpExportDialogTitle => translate('mcp_export_dialog_title');
  String get mcpSelectTool => translate('mcp_select_tool');
  String get mcpNoEnabledTools => translate('mcp_no_enabled_tools');
  String get mcpPleaseSelectTool => translate('mcp_please_select_tool');
  String get mcpPleaseSelectAtLeastOne => translate('mcp_please_select_at_least_one');
  String get mcpRead => translate('mcp_read');
  String get mcpSyncToList => translate('mcp_sync_to_list');
  String get mcpExportToToolButton => translate('mcp_export_to_tool');
  String mcpServerList(int count) => translate('mcp_server_list').replaceAll('{count}', count.toString());
  String get mcpSelectAll => translate('mcp_select_all');
  String get mcpDeselectAll => translate('mcp_deselect_all');
  String get mcpNoConfigFound => translate('mcp_no_config_found');
  String mcpNoConfigInTool(String tool) => translate('mcp_no_config_in_tool').replaceAll('{tool}', tool);
  String mcpReadFailed(String error) => translate('mcp_read_failed').replaceAll('{error}', error);
  String mcpSyncFailed(String error) => translate('mcp_sync_failed').replaceAll('{error}', error);
  String mcpExportFailed(String error) => translate('mcp_export_failed').replaceAll('{error}', error);
  String get mcpConfirmOverride => translate('mcp_confirm_override');
  String mcpOverrideMessage(String servers) => translate('mcp_override_message').replaceAll('{servers}', servers);
  String mcpOverrideMessageTool(String tool, String servers) => translate('mcp_override_message_tool').replaceAll('{tool}', tool).replaceAll('{servers}', servers);
  String get mcpConfirm => translate('mcp_confirm');
  String mcpImportComplete(int added, int overridden, int failed) {
    final failedText = failed > 0 ? translate('mcp_import_complete_failed').replaceAll('{failed}', failed.toString()) : '';
    return translate('mcp_import_complete')
        .replaceAll('{added}', added.toString())
        .replaceAll('{overridden}', overridden.toString())
        .replaceAll('{failed}', failedText);
  }
  String mcpExportSuccess(int count, String tool) => translate('mcp_export_success').replaceAll('{count}', count.toString()).replaceAll('{tool}', tool);
  String get mcpExportFailedShort => translate('mcp_export_failed_short');
  String mcpCommand(String command) => translate('mcp_command').replaceAll('{command}', command);
  String mcpArgs(String args) => translate('mcp_args').replaceAll('{args}', args);
  String mcpUrl(String url) => translate('mcp_url').replaceAll('{url}', url);
  String mcpServerId(String id) => translate('mcp_server_id').replaceAll('{id}', id);
  // MCP Details dialog related
  String get mcpViewDetails => translate('mcp_view_details');
  String get mcpDetailsTitle => translate('mcp_details_title');
  String get mcpServerType => translate('mcp_server_type');
  String get mcpServerIdLabel => translate('mcp_server_id_label');
  String get mcpCommandLabel => translate('mcp_command_label');
  String get mcpArgsLabel => translate('mcp_args_label');
  String get mcpEnv => translate('mcp_env');
  String get mcpCwd => translate('mcp_cwd');
  String get mcpUrlLabel => translate('mcp_url_label');
  String get mcpHeaders => translate('mcp_headers');
  String get mcpStatus => translate('mcp_status');
  String get mcpActive => translate('mcp_active');
  String get mcpInactive => translate('mcp_inactive');
  String get mcpCopyJson => translate('mcp_copy_json');
  String get mcpJsonCopied => translate('mcp_json_copied');
  String get mcpJsonConfigLabel => translate('mcp_json_config_label');
  // MCP Sync dialog related
  String get mcpSyncDialogTitle => translate('mcp_sync_dialog_title');
  String get mcpLocalServers => translate('mcp_local_servers');
  String mcpToolServers(String tool) => translate('mcp_tool_servers').replaceAll('{tool}', tool);
  String mcpSyncComplete(int export, int import, int delete, int failed) {
    final failedText = failed > 0 ? translate('mcp_sync_complete_failed').replaceAll('{failed}', failed.toString()) : '';
    return translate('mcp_sync_complete')
        .replaceAll('{export}', export.toString())
        .replaceAll('{import}', import.toString())
        .replaceAll('{delete}', delete.toString())
        .replaceAll('{failed}', failedText);
  }
  String mcpPendingChanges(int export, int import, int delete) => translate('mcp_pending_changes')
      .replaceAll('{export}', export.toString())
      .replaceAll('{import}', import.toString())
      .replaceAll('{delete}', delete.toString());
  String get mcpSyncToTool => translate('mcp_sync_to_tool');
  String get mcpSyncToLocal => translate('mcp_sync_to_local');
  String get mcpDelete => translate('mcp_delete');
  String get mcpWillSync => translate('mcp_will_sync');
  String get mcpWillBeOverridden => translate('mcp_will_be_overridden');
  String get mcpWillDelete => translate('mcp_will_delete');
  String get mcpOpenHomepage => translate('mcp_open_homepage');
  String get mcpUnsavedChanges => translate('mcp_unsaved_changes');
  String get mcpUnsavedChangesMessage => translate('mcp_unsaved_changes_message');
  String get mcpUnsavedChangesMessageSwitch => translate('mcp_unsaved_changes_message_switch');
  String get mcpSave => translate('mcp_save');
  String get mcpDiscard => translate('mcp_discard');
  String get mcpClickRead => translate('mcp_click_read');
  String get mcpGlobalConfig => translate('mcp_global_config');
  String get mcpClaudeCodeScopeHelp => translate('mcp_claude_code_scope_help');
  String get mcpProjectUsesGlobalConfig => translate('mcp_project_uses_global_config');
  // Config template update related
  String get configTemplateUpdate => translate('config_template_update');
  String get cloudConfig => translate('cloud_config');
  String get configCurrentDate => translate('config_current_date');
  String get checkUpdate => translate('check_update');
  String get configUpdateSuccess => translate('config_update_success');
  String get configAlreadyLatest => translate('config_already_latest');
  String get configUpdateCheckFailed => translate('config_update_check_failed');
  String get configDateToday => translate('config_date_today');
  String get configDateYesterday => translate('config_date_yesterday');
  // Codex official config related
  String get codexOfficialConfigDescription => translate('codex_official_config_description');
  String get codexOfficialApiKeyLabel => translate('codex_official_api_key_label');
  String get codexOfficialApiKeyPlaceholder => translate('codex_official_api_key_placeholder');
  // Gemini official config related
  String get geminiOfficialConfigDescription => translate('gemini_official_config_description');
  String get geminiOfficialApiKeyLabel => translate('gemini_official_api_key_label');
  String get geminiOfficialApiKeyPlaceholder => translate('gemini_official_api_key_placeholder');
  // MCP status labels related
  String get mcpStatusIdentical => translate('mcp_status_identical');
  String get mcpStatusOnlyLocal => translate('mcp_status_only_local');
  String get mcpStatusOnlyTool => translate('mcp_status_only_tool');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    // 支持动态语言列表，默认支持 zh 和 en
    // 实际支持的语言列表从配置文件中获取
    return true; // 允许所有语言代码，由 LanguagePackService 处理
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    // 构建完整的 locale 代码：如果有国家代码，使用 languageCode_countryCode 格式
    final fullLocaleCode = locale.countryCode != null && locale.countryCode!.isNotEmpty
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    
    // 初始化语言包服务
    await AppLocalizations._languagePackService.init();
    
    // 尝试加载语言包（优先使用完整的 locale 代码）
    var jsonTranslations = await AppLocalizations._languagePackService.loadLanguagePack(fullLocaleCode, forceRefresh: true);
    
    // 如果完整的 locale 代码加载失败，尝试只使用语言代码
    if (jsonTranslations == null && fullLocaleCode != locale.languageCode) {
      jsonTranslations = await AppLocalizations._languagePackService.loadLanguagePack(locale.languageCode, forceRefresh: true);
    }
    
    // 只在加载失败时打印错误日志
    if (jsonTranslations == null) {
      print('AppLocalizations.load: ❌ 加载语言包失败: $fullLocaleCode');
    }
    
    // 创建 AppLocalizations 实例，传入 JSON 翻译
    return AppLocalizations(locale, jsonTranslations);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) {
    // 总是返回 true，确保语言包能够重新加载
    // 这样可以保证在语言切换时，新的语言包能够被正确加载
    // 性能影响很小，因为 LanguagePackService 内部有缓存机制
    return true;
  }
}

