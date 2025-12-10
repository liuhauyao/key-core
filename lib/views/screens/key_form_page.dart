import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../../models/ai_key.dart';
import '../../models/platform_type.dart';
import '../../constants/app_constants.dart';
import '../../utils/platform_presets.dart';
import '../../utils/app_localizations.dart';
import '../../utils/liquid_glass_decoration.dart';
import '../../utils/platform_icon_helper.dart';
import '../../config/provider_config.dart';
import '../widgets/platform_category_tabs.dart';
import '../widgets/icon_picker.dart';
import '../../models/platform_category.dart';
import '../../services/codex_config_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/url_launcher_service.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../models/mcp_server.dart';
import '../../utils/ime_friendly_formatter.dart';
import '../widgets/ime_safe_text_field.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 密钥编辑表单页面
class KeyFormPage extends StatefulWidget {
  final AIKey? editingKey;

  const KeyFormPage({
    super.key,
    this.editingKey,
  });

  @override
  State<KeyFormPage> createState() => _KeyFormPageState();
}

class _KeyFormPageState extends State<KeyFormPage> {
  late TextEditingController _nameController;
  late TextEditingController _managementUrlController;
  late TextEditingController _apiEndpointController;
  late TextEditingController _keyValueController;
  late TextEditingController _tagsController;
  late TextEditingController _notesController;
  late TextEditingController _expiryDateController;
  final ShadPopoverController _datePickerPopoverController = ShadPopoverController();
  
  // ClaudeCode 配置控制器
  late TextEditingController _claudeCodeApiEndpointController;
  late TextEditingController _claudeCodeModelController; // 主模型
  late TextEditingController _claudeCodeHaikuModelController; // Haiku 模型
  late TextEditingController _claudeCodeSonnetModelController; // Sonnet 模型
  late TextEditingController _claudeCodeOpusModelController; // Opus 模型
  late TextEditingController _claudeCodeBaseUrlController;
  
  // Codex 配置控制器
  late TextEditingController _codexApiEndpointController;
  late TextEditingController _codexModelController;
  late TextEditingController _codexBaseUrlController;
  
  // Gemini 配置控制器（已移除，不再需要）

  PlatformType? _selectedPlatform;
  DateTime? _expiryDate;
  bool _isEditMode = false;
  bool _isCustomPlatform = false;
  bool _initialized = false; // 标记是否已完成初始化
  bool _obscureKeyValue = true;
  PlatformCategory _selectedCategory = PlatformCategory.popular;
  
  // ClaudeCode/Codex/Gemini 启用状态
  bool _enableClaudeCode = false;
  bool _enableCodex = false;
  bool _enableGemini = false;
  
  // 图标选择
  String? _selectedIcon;
  
  // 服务实例
  final CodexConfigService _codexConfigService = CodexConfigService();
  final ClipboardService _clipboardService = ClipboardService();
  final UrlLauncherService _urlLauncherService = UrlLauncherService();
  
  // 环境变量设置方式（永久）
  bool _envVarPermanent = true;
  
  // 管理地址是否为空（用于控制按钮显示）
  bool _hasManagementUrl = false;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.editingKey != null;

    _nameController = TextEditingController(text: widget.editingKey?.name ?? '');
    _managementUrlController =
        TextEditingController(text: widget.editingKey?.managementUrl ?? '');
    _hasManagementUrl = (widget.editingKey?.managementUrl ?? '').trim().isNotEmpty;
    _apiEndpointController =
        TextEditingController(text: widget.editingKey?.apiEndpoint ?? '');
    _keyValueController = TextEditingController(text: widget.editingKey?.keyValue ?? '');
    _tagsController = TextEditingController(
        text: widget.editingKey?.tags.join(', ') ?? '');
    _notesController = TextEditingController(text: widget.editingKey?.notes ?? '');

    // ClaudeCode 配置控制器
    _claudeCodeApiEndpointController = TextEditingController(
      text: widget.editingKey?.claudeCodeApiEndpoint ?? '',
    );
    _claudeCodeModelController = TextEditingController(
      text: widget.editingKey?.claudeCodeModel ?? '',
    );
    _claudeCodeHaikuModelController = TextEditingController(
      text: widget.editingKey?.claudeCodeHaikuModel ?? '',
    );
    _claudeCodeSonnetModelController = TextEditingController(
      text: widget.editingKey?.claudeCodeSonnetModel ?? '',
    );
    _claudeCodeOpusModelController = TextEditingController(
      text: widget.editingKey?.claudeCodeOpusModel ?? '',
    );
    _claudeCodeBaseUrlController = TextEditingController(
      text: widget.editingKey?.claudeCodeBaseUrl ?? '',
    );

    // Codex 配置控制器
    _codexApiEndpointController = TextEditingController(
      text: widget.editingKey?.codexApiEndpoint ?? '',
    );
    _codexModelController = TextEditingController(
      text: widget.editingKey?.codexModel ?? '',
    );
    _codexBaseUrlController = TextEditingController(
      text: widget.editingKey?.codexBaseUrl ?? '',
    );

    if (widget.editingKey != null) {
      _selectedPlatform = widget.editingKey!.platformType;
      _isCustomPlatform = widget.editingKey!.platformType == PlatformType.custom;
      _expiryDate = widget.editingKey!.expiryDate;
      _obscureKeyValue = false; // 编辑模式下默认显示密钥值
      _enableClaudeCode = widget.editingKey!.enableClaudeCode;
      _enableCodex = widget.editingKey!.enableCodex;
      _enableGemini = widget.editingKey!.enableGemini;
      _selectedIcon = widget.editingKey!.icon;
    } else {
      _isCustomPlatform = true;
      _obscureKeyValue = true; // 添加模式下默认隐藏密钥值
      _enableClaudeCode = false;
      _enableCodex = false;
      _enableGemini = false;
      _selectedIcon = null;
      // 新建模式下：默认选择常用分组中的自定义模板
      _selectedCategory = PlatformCategory.popular;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectPlatform(PlatformType.custom);
        }
      });
    }

    _expiryDateController = TextEditingController(
      text: _expiryDate != null ? DateFormat('yyyy-MM-dd').format(_expiryDate!) : '',
    );

    // 监听日期输入框变化，解析用户输入的日期
    _expiryDateController.addListener(_parseDateInput);

    // 监听管理地址输入框变化，更新按钮显示状态
    _managementUrlController.addListener(() {
      final hasUrl = _managementUrlController.text.trim().isNotEmpty;
      if (_hasManagementUrl != hasUrl) {
        setState(() {
          _hasManagementUrl = hasUrl;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ⚠️ 编辑模式下，确保平台设置正确但不覆盖用户配置
    if (_isEditMode && _selectedPlatform != null && !_initialized) {
      // 再次设置平台（不会覆盖ClaudeCode/Codex配置，因为有 _isEditMode 保护）
      // 这确保了编辑模式下平台相关的其他字段（如 _isCustomPlatform）正确设置
      _selectPlatform(_selectedPlatform!);
      _initialized = true; // 标记初始化完成，防止重复初始化
    }
  }
  
  bool _isUpdatingDateFromPicker = false;
  
  void _parseDateInput() {
    // 如果是从日期选择器更新的，跳过解析
    if (_isUpdatingDateFromPicker) return;
    
    final text = _expiryDateController.text.trim();
    if (text.isEmpty) {
      if (_expiryDate != null) {
        // 使用 postFrameCallback 避免在 build 期间调用 setState
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _expiryDate = null;
            });
          }
        });
      }
      return;
    }
    
    // 如果已经是标准格式 yyyy-MM-dd，直接解析
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      try {
        final parsedDate = DateFormat('yyyy-MM-dd').parse(text);
        final now = DateTime.now();
        final maxDate = DateTime(now.year + 10);
        if (parsedDate.isAfter(now.subtract(const Duration(days: 1))) && 
            parsedDate.isBefore(maxDate.add(const Duration(days: 1)))) {
          if (parsedDate != _expiryDate) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _expiryDate = parsedDate;
                });
              }
            });
          }
        }
      } catch (e) {
        // 解析失败，保持当前状态
      }
      return;
    }
    
    // 尝试解析其他日期格式
    final formats = [
      'yyyy/MM/dd',
      'yyyy.MM.dd',
      'MM/dd/yyyy',
      'dd/MM/yyyy',
    ];
    
    for (final format in formats) {
      try {
        final parsedDate = DateFormat(format).parse(text);
        // 验证日期是否在合理范围内（今天到10年后）
        final now = DateTime.now();
        final maxDate = DateTime(now.year + 10);
        if (parsedDate.isAfter(now.subtract(const Duration(days: 1))) && 
            parsedDate.isBefore(maxDate.add(const Duration(days: 1)))) {
          if (parsedDate != _expiryDate) {
            _isUpdatingDateFromPicker = true;
            // 先更新 controller，移除监听器避免循环
            _expiryDateController.removeListener(_parseDateInput);
            _expiryDateController.text = DateFormat('yyyy-MM-dd').format(parsedDate);
            _expiryDateController.addListener(_parseDateInput);
            
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _expiryDate = parsedDate;
                });
                _isUpdatingDateFromPicker = false;
              }
            });
          }
          return;
        }
      } catch (e) {
        // 继续尝试下一个格式
        continue;
      }
    }
    // 如果所有格式都解析失败，保持当前状态
  }

  @override
  void dispose() {
    _nameController.dispose();
    _managementUrlController.dispose();
    _apiEndpointController.dispose();
    _keyValueController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
    _expiryDateController.removeListener(_parseDateInput);
    _expiryDateController.dispose();
    _datePickerPopoverController.dispose();
    _claudeCodeApiEndpointController.dispose();
    _claudeCodeModelController.dispose();
    _claudeCodeHaikuModelController.dispose();
    _claudeCodeSonnetModelController.dispose();
    _claudeCodeOpusModelController.dispose();
    _claudeCodeBaseUrlController.dispose();
    _codexApiEndpointController.dispose();
    _codexModelController.dispose();
    _codexBaseUrlController.dispose();
    super.dispose();
  }

  /// 选择供应商并自动填充
  void _selectPlatform(PlatformType platform) {
    setState(() {
      _selectedPlatform = platform;
      _isCustomPlatform = platform == PlatformType.custom;

      // 编辑模式下只更新平台选择状态，不覆盖已保存的字段
      if (_isEditMode) {
        return;
      }

      // 如果不是自定义平台，自动填充预设信息（仅新建）
      if (platform != PlatformType.custom) {
        final preset = PlatformPresets.getPreset(platform);
        if (preset != null) {
          // 名称：按照模板填充
          _nameController.text = preset.defaultName ?? '';
          
          // 管理URL：按照模板填充，如果没有则清空
          if (preset.managementUrl != null) {
            _managementUrlController.text = preset.managementUrl!;
            _hasManagementUrl = true;
          } else {
            _managementUrlController.clear();
            _hasManagementUrl = false;
          }
          
          // API端点：按照模板填充，如果没有则清空
          if (preset.apiEndpoint != null) {
            _apiEndpointController.text = preset.apiEndpoint!;
          } else {
            _apiEndpointController.clear();
          }
          
          // 自动设置平台图标
          final iconPath = PlatformIconHelper.getIconAssetPath(platform);
          if (iconPath != null) {
            final iconFileName = iconPath.replaceFirst('assets/icons/platforms/', '');
            _selectedIcon = iconFileName;
          } else {
            _selectedIcon = null;
          }
          
          // 尝试获取平台的 ClaudeCode/Codex 配置（仅在新建模式下自动填充）
          final claudeCodeProvider = ProviderConfig.getClaudeCodeProviderByPlatform(platform);
          final codexProvider = ProviderConfig.getCodexProviderByPlatform(platform);

          if (claudeCodeProvider != null) {
            _enableClaudeCode = true;
            _claudeCodeBaseUrlController.text = claudeCodeProvider.baseUrl;

            _claudeCodeModelController.clear();
            _claudeCodeHaikuModelController.clear();
            _claudeCodeSonnetModelController.clear();
            _claudeCodeOpusModelController.clear();

            if (claudeCodeProvider.modelConfig.mainModel.isNotEmpty) {
              _claudeCodeModelController.text = claudeCodeProvider.modelConfig.mainModel;
            }
            if (claudeCodeProvider.modelConfig.haikuModel != null &&
                claudeCodeProvider.modelConfig.haikuModel!.isNotEmpty) {
              _claudeCodeHaikuModelController.text = claudeCodeProvider.modelConfig.haikuModel!;
            }
            if (claudeCodeProvider.modelConfig.sonnetModel != null &&
                claudeCodeProvider.modelConfig.sonnetModel!.isNotEmpty) {
              _claudeCodeSonnetModelController.text = claudeCodeProvider.modelConfig.sonnetModel!;
            }
            if (claudeCodeProvider.modelConfig.opusModel != null &&
                claudeCodeProvider.modelConfig.opusModel!.isNotEmpty) {
              _claudeCodeOpusModelController.text = claudeCodeProvider.modelConfig.opusModel!;
            }
          } else {
            _enableClaudeCode = false;
            _claudeCodeBaseUrlController.clear();
            _claudeCodeModelController.clear();
            _claudeCodeHaikuModelController.clear();
            _claudeCodeSonnetModelController.clear();
            _claudeCodeOpusModelController.clear();
          }

          if (codexProvider != null) {
            _enableCodex = true;
            _codexBaseUrlController.text = codexProvider.baseUrl;
            _codexModelController.text = codexProvider.model;
          } else {
            _enableCodex = false;
            _codexBaseUrlController.clear();
            _codexModelController.clear();
          }
        }
      } else {
        // 选择自定义平台时，清空基本表单字段（仅新建）
        _nameController.clear();
        _managementUrlController.clear();
        _hasManagementUrl = false;
        _apiEndpointController.clear();
        _keyValueController.clear();
        _tagsController.clear();
        _notesController.clear();
        _expiryDate = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);
    final iconColor = shadTheme.colorScheme.foreground;

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false, // macOS 沉浸式标题栏：不预留顶部安全区域
        bottom: false,
        left: false,
        right: false,
        child: Column(
          children: [
            // macOS 26 风格：沉浸式标题栏（与界面融为一体）
            _buildImmersiveTitleBar(context),
            // 供应商标签区域 - 仅在新建模式下显示
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
                  child: _buildPlatformChips(context, shadTheme),
                ),
              ),
            // 表单内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

              // 密钥名称和标签（同一行）
              // ⚠️ 使用 ImeSafeTextField 替代 ShadInputFormField，避免中文输入法问题
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ImeSafeTextField(
                      controller: _nameController,
                      labelText: localizations?.keyNameLabel ?? '密钥名称 *',
                      hintText: localizations?.keyNameHint ?? '请输入密钥名称',
                      prefixIcon: _buildClickableIcon(context, shadTheme),
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ImeSafeTextField(
                      controller: _tagsController,
                      labelText: localizations?.tagsLabel ?? '标签',
                      hintText: localizations?.tagsHint ?? '多个标签用逗号分隔',
                      prefixIcon: Icon(Icons.local_offer, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 管理地址和API地址（同一行）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ImeSafeTextField(
                      controller: _managementUrlController,
                      labelText: localizations?.managementUrlLabel ?? '管理地址',
                      hintText: localizations?.managementUrlHint ?? 'https://example.com',
                      prefixIcon: Icon(Icons.language, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      keyboardType: TextInputType.url,
                      suffixIcon: _hasManagementUrl
                          ? IconButton(
                              icon: Icon(
                                Icons.open_in_new,
                                size: 18,
                                color: iconColor,
                              ),
                              onPressed: () async {
                                final url = _managementUrlController.text.trim();
                                if (url.isNotEmpty) {
                                  await _urlLauncherService.openManagementUrl(url);
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ImeSafeTextField(
                      controller: _apiEndpointController,
                      labelText: localizations?.apiEndpointLabel ?? 'API地址',
                      hintText: localizations?.apiEndpointHint ?? 'https://api.example.com',
                      prefixIcon: Icon(Icons.code, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      keyboardType: TextInputType.url,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 密钥值
              ImeSafeTextField(
                controller: _keyValueController,
                labelText: localizations?.keyValueLabelForm ?? '密钥值 *',
                hintText: localizations?.keyValueHint ?? '请输入密钥值',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(Icons.key, size: 18, color: shadTheme.colorScheme.mutedForeground),
                ),
                obscureText: _obscureKeyValue,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureKeyValue ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: iconColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureKeyValue = !_obscureKeyValue;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              const SizedBox(height: 16),

              // 过期日期（单独一行）
              ImeSafeTextField(
                controller: _expiryDateController,
                labelText: localizations?.expiryDateLabel ?? '过期日期',
                hintText: localizations?.expiryDateHint ?? '选择日期（可选）',
                suffixIcon: SizedBox(
                  width: _expiryDate != null ? 56 : 32, // 有清除按钮时更宽
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_expiryDate != null) ...[
                        IconButton(
                          icon: Icon(Icons.clear, size: 18, color: iconColor),
                        onPressed: () {
                          setState(() {
                            _expiryDate = null;
                            _expiryDateController.text = '';
                          });
                        },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                      ),
                        ),
                    ],
                    ShadPopover(
                      controller: _datePickerPopoverController,
                      padding: EdgeInsets.zero,
                      decoration: ShadDecoration(
                        border: ShadBorder.all(width: 0),
                      ),
                      popover: (context) => ShadCalendar(
                        selected: _expiryDate,
                        fromMonth: DateTime.now(),
                        toMonth: DateTime.now().add(const Duration(days: 3650)),
                        onChanged: (date) {
                          if (date != null) {
                            _isUpdatingDateFromPicker = true;
                            // 移除监听器避免循环调用
                            _expiryDateController.removeListener(_parseDateInput);
                            _expiryDateController.text = DateFormat('yyyy-MM-dd').format(date);
                            _expiryDateController.addListener(_parseDateInput);
                            
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() {
                                  _expiryDate = date;
                                });
                                _isUpdatingDateFromPicker = false;
                                _datePickerPopoverController.hide();
                              }
                            });
                          }
                        },
                      ),
                        child: IconButton(
                          icon: Icon(Icons.calendar_today, size: 18, color: iconColor),
                        onPressed: () => _datePickerPopoverController.toggle(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 24,
                          ),
                      ),
                    ),
                  ],
                ),
                ),
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              const SizedBox(height: 16),

              // 备注（单行100字符）
              ImeSafeTextField(
                controller: _notesController,
                labelText: localizations?.notesLabel ?? '备注',
                hintText: localizations?.notesHint ?? '请输入备注信息',
                prefixIcon: Icon(Icons.notes, size: 18, color: shadTheme.colorScheme.mutedForeground),
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              const SizedBox(height: 24),
              
              // ClaudeCode 配置区域（仅在工具启用时显示）
              Consumer<SettingsViewModel>(
                builder: (context, settingsViewModel, child) {
                  final enabledTools = settingsViewModel.getEnabledTools();
                  final isClaudeCodeEnabled = enabledTools.contains(AiToolType.claudecode);
                  if (_selectedPlatform != null && isClaudeCodeEnabled) {
                    return Column(
                      children: [
                _buildClaudeCodeConfigSection(context, shadTheme, localizations),
                const SizedBox(height: 24),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              // Codex 配置区域（仅在工具启用时显示）
              Consumer<SettingsViewModel>(
                builder: (context, settingsViewModel, child) {
                  final enabledTools = settingsViewModel.getEnabledTools();
                  final isCodexEnabled = enabledTools.contains(AiToolType.codex);
                  if (_selectedPlatform != null && isCodexEnabled) {
                    return Column(
                      children: [
                _buildCodexConfigSection(context, shadTheme, localizations),
                const SizedBox(height: 24),
                    ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              // Gemini 配置区域（仅在工具启用时显示）
              Consumer<SettingsViewModel>(
                builder: (context, settingsViewModel, child) {
                  final enabledTools = settingsViewModel.getEnabledTools();
                  final isGeminiEnabled = enabledTools.contains(AiToolType.gemini);
                  if (_selectedPlatform != null && isGeminiEnabled) {
                    return Column(
                      children: [
                        _buildGeminiConfigSection(context, shadTheme, localizations),
                        const SizedBox(height: 24),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
                    ],
                ),
              ),
            ),
            // 底部按钮区域 - Shadcn 风格
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
          // 新建模式：分组切换滑块居中显示，与主页位置一致
          // 编辑模式：显示"编辑密钥"标题
          Center(
            child: _isEditMode
                ? Text(
                    localizations?.editKey ?? '编辑密钥',
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.w600,
                      color: shadTheme.colorScheme.foreground,
                    ),
                  )
                : _buildCategorySwitcher(context, shadTheme),
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
        children: PlatformCategoryManager.allCategories.map((category) {
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ClaudeCode 使用 SVG 图标
                  if (category == PlatformCategory.claudeCode)
                    SvgPicture.asset(
                      'assets/icons/platforms/claude-color.svg',
                      width: 16,
                      height: 16,
                    )
                  else if (category.icon.isNotEmpty)
                    Text(
                      category.icon,
                      style: TextStyle(
                        fontSize: 16,
                        color: isActive
                            ? shadTheme.colorScheme.foreground
                            : shadTheme.colorScheme.mutedForeground,
                      ),
                    ),
                  if (category.icon.isNotEmpty || category == PlatformCategory.claudeCode)
                    const SizedBox(width: 6),
                  Text(
                    category.getValue(context),
                    style: shadTheme.textTheme.small.copyWith(
                      color: isActive
                          ? shadTheme.colorScheme.foreground
                          : shadTheme.colorScheme.mutedForeground,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 构建供应商标签（仅在新建模式下显示）
  Widget _buildPlatformChips(BuildContext context, ShadThemeData shadTheme) {
    // 编辑模式下不显示供应商标签
    if (_isEditMode) {
      return const SizedBox.shrink();
    }
    
    final displayPlatforms = PlatformCategoryManager.getPlatformsByCategory(_selectedCategory);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localizations = AppLocalizations.of(context);
    
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // 自定义选项
        _buildPlatformChip(
          context,
          PlatformType.custom,
          label: localizations?.custom ?? '自定义',
          isSelected: _selectedPlatform == PlatformType.custom,
          shadTheme: shadTheme,
          isDark: isDark,
        ),
        // 分类下的平台
        ...displayPlatforms.map((platform) {
          return _buildPlatformChip(
            context,
            platform,
            isSelected: _selectedPlatform == platform,
            shadTheme: shadTheme,
            isDark: isDark,
          );
        }),
      ],
    );
  }

  /// 构建单个供应商标签
  Widget _buildPlatformChip(
    BuildContext context,
    PlatformType platform, {
    String? label,
    required bool isSelected,
    required ShadThemeData shadTheme,
    required bool isDark,
  }) {
    final displayLabel = label ?? platform.value;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isSelected) {
            setState(() {
              _selectedPlatform = null;
            });
          } else {
            _selectPlatform(platform);
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? platform.color.withOpacity(0.9)
                : (isDark 
                    ? Colors.white.withOpacity(0.08) 
                    : Colors.white.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? platform.color
                  : (isDark 
                      ? Colors.white.withOpacity(0.15) 
                      : Colors.black.withOpacity(0.1)),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected ? [
              BoxShadow(
                color: platform.color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlatformIconHelper.buildIcon(
                platform: platform,
                size: 16,
                color: isSelected ? Colors.white : null,
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




  void _handleSubmit() {
    final localizations = AppLocalizations.of(context);
    
    // ⚠️ 手动验证必填字段和长度（替代 validator 以避免输入时重建导致 IME 卡住）
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.keyNameRequired ?? '请输入密钥名称')),
      );
      return;
    }
    if (_keyValueController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.keyValueRequired ?? '请输入密钥值')),
      );
      return;
    }
    
    // 手动验证长度（替代 maxLength 以避免 IME 冲突）
    if (_nameController.text.trim().length > AppConstants.maxNameLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('密钥名称不能超过 ${AppConstants.maxNameLength} 个字符')),
      );
      return;
    }
    if (_tagsController.text.trim().length > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签不能超过 200 个字符')),
      );
      return;
    }
    
      // 解析标签
      final tags = _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();

      final now = DateTime.now();
      final platform = _selectedPlatform ?? PlatformType.custom;
      
      final key = AIKey(
        id: widget.editingKey?.id,
        name: _nameController.text.trim(),
        platform: platform.value,
        platformType: platform,
        managementUrl: _managementUrlController.text.trim().isEmpty
            ? null
            : _managementUrlController.text.trim(),
        apiEndpoint: _apiEndpointController.text.trim().isEmpty
            ? null
            : _apiEndpointController.text.trim(),
        keyValue: _keyValueController.text.trim(),
        expiryDate: _expiryDate,
        tags: tags,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isActive: widget.editingKey?.isActive ?? true,
        createdAt: widget.editingKey?.createdAt ?? now,
        // 编辑模式下保持原有的 updatedAt，避免改变卡片位置
        updatedAt: widget.editingKey?.updatedAt ?? now,
        isFavorite: widget.editingKey?.isFavorite ?? false,
        icon: _selectedIcon,
        enableClaudeCode: _enableClaudeCode,
        claudeCodeApiEndpoint: null, // 不再使用，使用基本信息中的 API 地址
        claudeCodeModel: _claudeCodeModelController.text.trim().isNotEmpty
            ? _claudeCodeModelController.text.trim()
            : null,
        claudeCodeHaikuModel: _claudeCodeHaikuModelController.text.trim().isNotEmpty
            ? _claudeCodeHaikuModelController.text.trim()
            : null,
        claudeCodeSonnetModel: _claudeCodeSonnetModelController.text.trim().isNotEmpty
            ? _claudeCodeSonnetModelController.text.trim()
            : null,
        claudeCodeOpusModel: _claudeCodeOpusModelController.text.trim().isNotEmpty
            ? _claudeCodeOpusModelController.text.trim()
            : null,
        claudeCodeBaseUrl: _claudeCodeBaseUrlController.text.trim().isNotEmpty
            ? _claudeCodeBaseUrlController.text.trim()
            : null,
        enableCodex: _enableCodex,
        codexApiEndpoint: null, // 不再使用，使用基本信息中的 API 地址
        codexModel: _codexModelController.text.trim().isNotEmpty
            ? _codexModelController.text.trim()
            : null,
        codexBaseUrl: _codexBaseUrlController.text.trim().isNotEmpty
            ? _codexBaseUrlController.text.trim()
            : null,
        enableGemini: _enableGemini,
        geminiApiEndpoint: null,
        geminiModel: null, // Gemini 只支持官方 API，不需要模型配置
        geminiBaseUrl: null, // Gemini 只支持官方 API，不需要 Base URL 配置
      );

      Navigator.of(context).pop(key);
  }

  /// 构建 ClaudeCode 配置区域
  Widget _buildClaudeCodeConfigSection(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final provider = _selectedPlatform != null
        ? ProviderConfig.getClaudeCodeProviderByPlatform(_selectedPlatform!)
        : null;
    
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlatformIconHelper.buildIcon(
                platform: PlatformType.anthropic,
                size: 18,
                color: shadTheme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations?.claudeCodeConfig ?? 'ClaudeCode 配置',
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    if (provider != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        provider.name,
                        style: shadTheme.textTheme.small.copyWith(
                          color: shadTheme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _enableClaudeCode,
                  onChanged: (value) {
                    setState(() {
                      _enableClaudeCode = value;
                      // ⚠️ 重要：只在新建模式下自动填充模板配置
                      // 编辑模式下只处理启用/禁用状态，不覆盖用户自定义配置
                      if (value && provider != null && !_isEditMode) {
                        // 新建模式：自动填充供应商配置
                        // 先填充 Base URL（如果为空）
                        if (_claudeCodeBaseUrlController.text.isEmpty) {
                          _claudeCodeBaseUrlController.text = provider.baseUrl;
                        }

                        // 先清空所有模型字段，避免残留其他供应商的配置
                        _claudeCodeModelController.clear();
                        _claudeCodeHaikuModelController.clear();
                        _claudeCodeSonnetModelController.clear();
                        _claudeCodeOpusModelController.clear();

                        // 只有当模型配置不为空时才自动填充
                        if (provider.modelConfig.mainModel.isNotEmpty) {
                          _claudeCodeModelController.text = provider.modelConfig.mainModel;
                        }
                        if (provider.modelConfig.haikuModel != null &&
                            provider.modelConfig.haikuModel!.isNotEmpty) {
                          _claudeCodeHaikuModelController.text = provider.modelConfig.haikuModel!;
                        }
                        if (provider.modelConfig.sonnetModel != null &&
                            provider.modelConfig.sonnetModel!.isNotEmpty) {
                          _claudeCodeSonnetModelController.text = provider.modelConfig.sonnetModel!;
                        }
                        if (provider.modelConfig.opusModel != null &&
                            provider.modelConfig.opusModel!.isNotEmpty) {
                          _claudeCodeOpusModelController.text = provider.modelConfig.opusModel!;
                        }
                      } else if (!value) {
                        // 如果禁用，清空所有 ClaudeCode 相关字段
                        _claudeCodeBaseUrlController.clear();
                        _claudeCodeModelController.clear();
                        _claudeCodeHaikuModelController.clear();
                        _claudeCodeSonnetModelController.clear();
                        _claudeCodeOpusModelController.clear();
                      }
                      // 编辑模式且启用：什么也不做，保留用户已有配置
                    });
                  },
                  activeColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (_enableClaudeCode) ...[
            const SizedBox(height: 16),
          ImeSafeTextField(
              controller: _claudeCodeBaseUrlController,
            labelText: localizations?.requestUrl ?? '请求地址',
            hintText: 'https://api.anthropic.com',
            prefixIcon: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
              keyboardType: TextInputType.url,
            isDark: Theme.of(context).brightness == Brightness.dark,
            ),
            const SizedBox(height: 12),
            // 第一行：主模型和 Haiku 模型
            Row(
              children: [
                Expanded(
                child: ImeSafeTextField(
                    controller: _claudeCodeModelController,
                  labelText: localizations?.mainModel ?? '主模型',
                  hintText: localizations?.mainModelHint ?? '请输入主模型名称',
                  prefixIcon: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                child: ImeSafeTextField(
                    controller: _claudeCodeHaikuModelController,
                  labelText: localizations?.haikuModel ?? 'Haiku 模型',
                  hintText: localizations?.haikuModelHint ?? '请输入 Haiku 模型名称',
                  prefixIcon: Icon(Icons.flash_on, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 第二行：Sonnet 模型和 Opus 模型
            Row(
              children: [
                Expanded(
                child: ImeSafeTextField(
                    controller: _claudeCodeSonnetModelController,
                  labelText: localizations?.sonnetModel ?? 'Sonnet 模型',
                  hintText: localizations?.sonnetModelHint ?? '请输入 Sonnet 模型名称',
                  prefixIcon: Icon(Icons.auto_awesome, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                child: ImeSafeTextField(
                    controller: _claudeCodeOpusModelController,
                  labelText: localizations?.opusModel ?? 'Opus 模型',
                  hintText: localizations?.opusModelHint ?? '请输入 Opus 模型名称',
                  prefixIcon: Icon(Icons.stars, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ],
            ),
          ],
        ],
    );
  }

  /// 构建 Codex 配置区域
  Widget _buildCodexConfigSection(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final provider = _selectedPlatform != null
        ? ProviderConfig.getCodexProviderByPlatform(_selectedPlatform!)
        : null;
    
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlatformIconHelper.buildIcon(
                platform: PlatformType.openAI,
                size: 18,
                color: shadTheme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations?.codexConfig ?? 'Codex 配置',
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    if (provider != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        provider.name,
                        style: shadTheme.textTheme.small.copyWith(
                          color: shadTheme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _enableCodex,
                  onChanged: (value) {
                    setState(() {
                      _enableCodex = value;
                      // ⚠️ 重要：模板配置只在新建模式下自动填充
                      // 编辑模式下保留用户自定义配置
                      if (value && provider != null && !_isEditMode) {
                        // 新建模式：只在字段为空时才自动填充
                        if (_codexBaseUrlController.text.isEmpty) {
                          _codexBaseUrlController.text = provider.baseUrl;
                        }
                        if (_codexModelController.text.isEmpty) {
                          _codexModelController.text = provider.model;
                        }
                      }
                      // 编辑模式：什么也不做，保留用户已有配置
                    });
                  },
                  activeColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (_enableCodex) ...[
            const SizedBox(height: 16),
          ImeSafeTextField(
              controller: _codexBaseUrlController,
            labelText: localizations?.requestUrl ?? '请求地址',
            hintText: 'https://api.openai.com/v1',
            prefixIcon: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
              keyboardType: TextInputType.url,
            isDark: Theme.of(context).brightness == Brightness.dark,
            ),
            const SizedBox(height: 12),
          ImeSafeTextField(
              controller: _codexModelController,
            labelText: localizations?.modelName ?? '模型名称',
            hintText: 'gpt-5-codex',
            prefixIcon: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
            isDark: Theme.of(context).brightness == Brightness.dark,
            ),
            // 环境变量提示（如果不支持 auth.json）
            FutureBuilder<bool>(
              future: _checkIfNeedsEnvVar(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data == true) {
                  return _buildEnvVarHint(context, shadTheme, localizations);
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ],
    );
  }

  /// 构建 Gemini 配置区域
  Widget _buildGeminiConfigSection(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/platforms/gemini-color.svg',
                width: 18,
                height: 18,
                allowDrawingOutsideViewBox: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations?.geminiConfig ?? 'Gemini 配置',
                      style: shadTheme.textTheme.p.copyWith(
                        fontWeight: FontWeight.w600,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Google Gemini API',
                      style: shadTheme.textTheme.small.copyWith(
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: _enableGemini,
                  onChanged: (value) {
                    setState(() {
                      _enableGemini = value;
                    });
                  },
                  activeColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          // Gemini 只支持官方 API，无需额外配置
        ],
    );
  }

  /// 构建可点击的图标（用于输入框的leading属性）
  Widget _buildClickableIcon(BuildContext context, ShadThemeData shadTheme) {
    // 如果选择了平台且不是自定义平台，优先显示平台图标
    if (_selectedPlatform != null && _selectedPlatform != PlatformType.custom) {
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
          // 处理返回的图标（包括null，表示取消或清除）
          if (mounted) {
            setState(() {
              _selectedIcon = icon;
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Center(
        child: _selectedIcon != null
                ? SizedBox(
                width: 18,
                height: 18,
                    child: SvgPicture.asset(
                      'assets/icons/platforms/$_selectedIcon',
                allowDrawingOutsideViewBox: true,
                      fit: BoxFit.contain,
                    ),
              )
                : SizedBox(
                    width: 18,
                    height: 18,
                    child: PlatformIconHelper.buildIcon(
                platform: _selectedPlatform!,
                size: 18,
                color: shadTheme.colorScheme.mutedForeground,
                    ),
                  ),
          ),
              ),
      );
    }
    
    // 自定义平台或未选择平台时，显示可选择的图标
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
        // 处理返回的图标（包括null，表示取消或清除）
        if (mounted) {
          setState(() {
            _selectedIcon = icon;
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Center(
      child: _selectedIcon != null
              ? SizedBox(
              width: 18,
              height: 18,
                  child: SvgPicture.asset(
                    'assets/icons/platforms/$_selectedIcon',
              allowDrawingOutsideViewBox: true,
                    fit: BoxFit.contain,
                  ),
            )
              : const Icon(Icons.label_outline, size: 18),
        ),
      ),
    );
  }
  
  /// 检查是否需要环境变量
  Future<bool> _checkIfNeedsEnvVar() async {
    if (!_enableCodex || _selectedPlatform == null || _keyValueController.text.isEmpty) {
      return false;
    }
    
    try {
      // 创建临时 AIKey 对象用于检查
      final tempKey = AIKey(
        id: widget.editingKey?.id ?? 0,
        name: _nameController.text,
        platform: _selectedPlatform!.value,
        platformType: _selectedPlatform!,
        keyValue: _keyValueController.text,
        tags: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        codexBaseUrl: _codexBaseUrlController.text.isNotEmpty 
            ? _codexBaseUrlController.text 
            : null,
        enableCodex: true,
      );
      
      final providerConfig = await _codexConfigService.getProviderConfig(tempKey);
      return !providerConfig.supportsAuthJson && providerConfig.envKeyName != null;
    } catch (e) {
      return false;
    }
  }
  
  /// 构建环境变量提示 UI
  Widget _buildEnvVarHint(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    return FutureBuilder<String?>(
      future: _getEnvVarCommand(permanent: true),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        
        final command = snapshot.data!;
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: shadTheme.colorScheme.muted.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: shadTheme.colorScheme.border,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: shadTheme.colorScheme.mutedForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此供应商需要设置环境变量',
                      style: shadTheme.textTheme.small.copyWith(
                        fontWeight: FontWeight.w600,
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        command,
                        style: shadTheme.textTheme.small.copyWith(
                          fontFamily: 'monospace',
                          color: shadTheme.colorScheme.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.copy_outlined,
                        size: 16,
                        color: shadTheme.colorScheme.primary,
                      ),
                      onPressed: () async {
                        await _clipboardService.copyToClipboard(command);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(localizations?.keyCopied ?? '已复制'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      tooltip: localizations?.copy ?? '复制',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '执行后将永久添加到配置文件，重启终端后仍然有效',
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.mutedForeground,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  /// 获取环境变量命令
  Future<String?> _getEnvVarCommand({bool permanent = false}) async {
    if (!_enableCodex || _selectedPlatform == null || _keyValueController.text.isEmpty) {
      return null;
    }
    
    try {
      // 创建临时 AIKey 对象
      final tempKey = AIKey(
        id: widget.editingKey?.id ?? 0,
        name: _nameController.text,
        platform: _selectedPlatform!.value,
        platformType: _selectedPlatform!,
        keyValue: _keyValueController.text,
        tags: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        codexBaseUrl: _codexBaseUrlController.text.isNotEmpty 
            ? _codexBaseUrlController.text 
            : null,
        enableCodex: true,
      );
      
      return await _codexConfigService.generateEnvVarCommand(tempKey, permanent: permanent);
    } catch (e) {
      return null;
    }
  }
}

