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
  final _formKey = GlobalKey<ShadFormState>();
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

      // 如果不是自定义平台，自动填充预设信息
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
            // 提取文件名（去掉路径前缀）
            final iconFileName = iconPath.replaceFirst('assets/icons/platforms/', '');
            _selectedIcon = iconFileName;
          } else {
            _selectedIcon = null;
          }
          
          // 尝试获取平台的 ClaudeCode/Codex 配置（如果有），用于自动填充
          final claudeCodeProvider = ProviderConfig.getClaudeCodeProviderByPlatform(platform);
          final codexProvider = ProviderConfig.getCodexProviderByPlatform(platform);
          
          // ClaudeCode 配置：如果有预设配置，强制填充；如果没有，清空并禁用
          if (claudeCodeProvider != null) {
            // 有预设配置：启用并填充所有字段
            _enableClaudeCode = true;
            _claudeCodeBaseUrlController.text = claudeCodeProvider.baseUrl;
            
            // 先清空所有模型字段，避免残留
            _claudeCodeModelController.clear();
            _claudeCodeHaikuModelController.clear();
            _claudeCodeSonnetModelController.clear();
            _claudeCodeOpusModelController.clear();
            
            // 按照模板填充模型字段
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
            // 没有预设配置：清空所有字段并禁用
            _enableClaudeCode = false;
            _claudeCodeBaseUrlController.clear();
            _claudeCodeModelController.clear();
            _claudeCodeHaikuModelController.clear();
            _claudeCodeSonnetModelController.clear();
            _claudeCodeOpusModelController.clear();
          }
          
          // Codex 配置：如果有预设配置，强制填充；如果没有，清空并禁用
          if (codexProvider != null) {
            // 有预设配置：启用并填充所有字段
            _enableCodex = true;
            _codexBaseUrlController.text = codexProvider.baseUrl;
            _codexModelController.text = codexProvider.model;
          } else {
            // 没有预设配置：清空所有字段并禁用
            _enableCodex = false;
            _codexBaseUrlController.clear();
            _codexModelController.clear();
          }
          
          // 编辑模式下切换模板时，清空模板中没有的字段（tags、notes、expiryDate）
          // 但保留密钥值（key_value）不变
          if (_isEditMode) {
            _tagsController.clear();
            _notesController.clear();
            _expiryDate = null;
            _expiryDateController.text = '';
          }
        }
      } else {
        // 选择自定义平台时，清空基本表单字段
        // 但不清空 ClaudeCode/Codex 相关字段，让用户可以手动配置
        _nameController.clear();
        _managementUrlController.clear();
        _hasManagementUrl = false;
        _apiEndpointController.clear();
        _keyValueController.clear();
        _tagsController.clear();
        _notesController.clear();
        _expiryDate = null;
        // 不清空 ClaudeCode/Codex 字段，保持用户已输入的内容
        // 如果用户需要清空，可以手动禁用开关
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
                child: ShadForm(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

              // 密钥名称和标签（同一行）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ShadInputFormField(
                      id: 'name',
                      controller: _nameController,
                      label: Text(localizations?.keyNameLabel ?? '密钥名称 *'),
                      placeholder: Text(localizations?.keyNameHint ?? '请输入密钥名称'),
                      leading: _buildClickableIcon(context, shadTheme),
                      maxLength: AppConstants.maxNameLength,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return localizations?.keyNameRequired ?? '请输入密钥名称';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShadInputFormField(
                      id: 'tags',
                      controller: _tagsController,
                      label: Text(localizations?.tagsLabel ?? '标签'),
                      placeholder: Text(localizations?.tagsHint ?? '多个标签用逗号分隔'),
                      leading: Icon(Icons.local_offer, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      maxLength: 200,
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
                    child: ShadInputFormField(
                      id: 'managementUrl',
                      controller: _managementUrlController,
                      label: Text(localizations?.managementUrlLabel ?? '管理地址'),
                      placeholder: Text(localizations?.managementUrlHint ?? 'https://example.com'),
                      leading: Icon(Icons.language, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      keyboardType: TextInputType.url,
                      trailing: _hasManagementUrl
                          ? ShadButton(
                              width: 24,
                              height: 24,
                              padding: EdgeInsets.zero,
                              backgroundColor: Colors.transparent,
                              foregroundColor: iconColor,
                              hoverBackgroundColor: Colors.transparent,
                              child: Icon(
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
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ShadInputFormField(
                      id: 'apiEndpoint',
                      controller: _apiEndpointController,
                      label: Text(localizations?.apiEndpointLabel ?? 'API地址'),
                      placeholder: Text(localizations?.apiEndpointHint ?? 'https://api.example.com'),
                      leading: Icon(Icons.code, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      keyboardType: TextInputType.url,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 密钥值
              ShadInputFormField(
                id: 'keyValue',
                controller: _keyValueController,
                label: Text(localizations?.keyValueLabelForm ?? '密钥值 *'),
                placeholder: Text(localizations?.keyValueHint ?? '请输入密钥值'),
                leading: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(Icons.key, size: 18, color: shadTheme.colorScheme.mutedForeground),
                ),
                maxLength: AppConstants.maxKeyValueLength,
                obscureText: _obscureKeyValue,
                trailing: ShadButton(
                  width: 24,
                  height: 24,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                  foregroundColor: iconColor,
                  hoverBackgroundColor: Colors.transparent,
                  child: Icon(
                    _obscureKeyValue ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: iconColor,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureKeyValue = !_obscureKeyValue;
                    });
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return localizations?.keyValueRequired ?? '请输入密钥值';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 过期日期（单独一行）
              ShadInputFormField(
                id: 'expiryDate',
                controller: _expiryDateController,
                label: Text(localizations?.expiryDateLabel ?? '过期日期'),
                placeholder: Text(localizations?.expiryDateHint ?? '选择日期（可选）'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_expiryDate != null) ...[
                      ShadButton(
                        width: 24,
                        height: 24,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.transparent,
                        foregroundColor: iconColor,
                        hoverBackgroundColor: Colors.transparent,
                        child: Icon(Icons.clear, size: 18, color: iconColor),
                        onPressed: () {
                          setState(() {
                            _expiryDate = null;
                            _expiryDateController.text = '';
                          });
                        },
                      ),
                      const SizedBox(width: 4),
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
                      child: ShadButton(
                        width: 24,
                        height: 24,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.transparent,
                        foregroundColor: iconColor,
                        hoverBackgroundColor: Colors.transparent,
                        child: Icon(Icons.calendar_today, size: 18, color: iconColor),
                        onPressed: () => _datePickerPopoverController.toggle(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 备注（单行100字符）
              ShadInputFormField(
                id: 'notes',
                controller: _notesController,
                label: Text(localizations?.notesLabel ?? '备注'),
                placeholder: Text(localizations?.notesHint ?? '请输入备注信息'),
                      leading: Icon(Icons.notes, size: 18, color: shadTheme.colorScheme.mutedForeground),
                maxLength: 100,
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
    if (_formKey.currentState!.saveAndValidate()) {
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
        claudeCodeModel: _enableClaudeCode && _claudeCodeModelController.text.trim().isNotEmpty
            ? _claudeCodeModelController.text.trim()
            : null,
        claudeCodeHaikuModel: _enableClaudeCode && _claudeCodeHaikuModelController.text.trim().isNotEmpty
            ? _claudeCodeHaikuModelController.text.trim()
            : null,
        claudeCodeSonnetModel: _enableClaudeCode && _claudeCodeSonnetModelController.text.trim().isNotEmpty
            ? _claudeCodeSonnetModelController.text.trim()
            : null,
        claudeCodeOpusModel: _enableClaudeCode && _claudeCodeOpusModelController.text.trim().isNotEmpty
            ? _claudeCodeOpusModelController.text.trim()
            : null,
        claudeCodeBaseUrl: _enableClaudeCode && _claudeCodeBaseUrlController.text.trim().isNotEmpty
            ? _claudeCodeBaseUrlController.text.trim()
            : null,
        enableCodex: _enableCodex,
        codexApiEndpoint: null, // 不再使用，使用基本信息中的 API 地址
        codexModel: _enableCodex && _codexModelController.text.trim().isNotEmpty
            ? _codexModelController.text.trim()
            : null,
        codexBaseUrl: _enableCodex && _codexBaseUrlController.text.trim().isNotEmpty
            ? _codexBaseUrlController.text.trim()
            : null,
        enableGemini: _enableGemini,
        geminiApiEndpoint: null,
        geminiModel: null, // Gemini 只支持官方 API，不需要模型配置
        geminiBaseUrl: null, // Gemini 只支持官方 API，不需要 Base URL 配置
      );

      Navigator.of(context).pop(key);
    }
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
    
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
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
                      // 如果启用，自动填充供应商配置（编辑模式和新建模式都支持）
                      if (value && provider != null) {
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
                    });
                  },
                  activeColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (_enableClaudeCode) ...[
            const SizedBox(height: 16),
            ShadInputFormField(
              id: 'claudeCodeBaseUrl',
              controller: _claudeCodeBaseUrlController,
              label: Text(localizations?.requestUrl ?? '请求地址'),
              placeholder: Text('https://api.anthropic.com'),
              leading: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            // 第一行：主模型和 Haiku 模型
            Row(
              children: [
                Expanded(
                  child: ShadInputFormField(
                    id: 'claudeCodeModel',
                    controller: _claudeCodeModelController,
                    label: Text(localizations?.mainModel ?? '主模型'),
                    placeholder: Text(localizations?.mainModelHint ?? '请输入主模型名称'),
                    leading: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShadInputFormField(
                    id: 'claudeCodeHaikuModel',
                    controller: _claudeCodeHaikuModelController,
                    label: Text(localizations?.haikuModel ?? 'Haiku 模型'),
                    placeholder: Text(localizations?.haikuModelHint ?? '请输入 Haiku 模型名称'),
                    leading: Icon(Icons.flash_on, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 第二行：Sonnet 模型和 Opus 模型
            Row(
              children: [
                Expanded(
                  child: ShadInputFormField(
                    id: 'claudeCodeSonnetModel',
                    controller: _claudeCodeSonnetModelController,
                    label: Text(localizations?.sonnetModel ?? 'Sonnet 模型'),
                    placeholder: Text(localizations?.sonnetModelHint ?? '请输入 Sonnet 模型名称'),
                    leading: Icon(Icons.auto_awesome, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ShadInputFormField(
                    id: 'claudeCodeOpusModel',
                    controller: _claudeCodeOpusModelController,
                    label: Text(localizations?.opusModel ?? 'Opus 模型'),
                    placeholder: Text(localizations?.opusModelHint ?? '请输入 Opus 模型名称'),
                    leading: Icon(Icons.stars, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
    
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
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
                      // 如果启用，自动填充供应商配置（编辑模式和新建模式都支持）
                      if (value && provider != null) {
                        // 只有在字段为空时才自动填充，避免覆盖用户已输入的内容
                        if (_codexBaseUrlController.text.isEmpty) {
                          _codexBaseUrlController.text = provider.baseUrl;
                        }
                        if (_codexModelController.text.isEmpty) {
                          _codexModelController.text = provider.model;
                        }
                      }
                    });
                  },
                  activeColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (_enableCodex) ...[
            const SizedBox(height: 16),
            ShadInputFormField(
              id: 'codexBaseUrl',
              controller: _codexBaseUrlController,
              label: Text(localizations?.requestUrl ?? '请求地址'),
              placeholder: Text('https://api.openai.com/v1'),
              leading: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            ShadInputFormField(
              id: 'codexModel',
              controller: _codexModelController,
              label: Text(localizations?.modelName ?? '模型名称'),
              placeholder: Text('gpt-5-codex'),
              leading: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
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
      ),
    );
  }

  /// 构建 Gemini 配置区域
  Widget _buildGeminiConfigSection(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
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
      ),
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
        child: _selectedIcon != null
            ? SvgPicture.asset(
                'assets/icons/platforms/$_selectedIcon',
                width: 18,
                height: 18,
                allowDrawingOutsideViewBox: true,
              )
            : PlatformIconHelper.buildIcon(
                platform: _selectedPlatform!,
                size: 18,
                color: shadTheme.colorScheme.mutedForeground,
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
      child: _selectedIcon != null
          ? SvgPicture.asset(
              'assets/icons/platforms/$_selectedIcon',
              width: 18,
              height: 18,
              allowDrawingOutsideViewBox: true,
            )
          : Icon(Icons.label_outline, size: 18, color: shadTheme.colorScheme.mutedForeground),
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

