import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import '../../models/ai_key.dart';
import '../../models/model_info.dart';
import '../../models/platform_type.dart';
import '../../constants/app_constants.dart';
import '../../utils/platform_presets.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_service.dart';
import '../../config/provider_config.dart';
import '../widgets/icon_picker.dart';
import '../../models/platform_category.dart';
import '../../services/codex_config_service.dart';
import '../../services/clipboard_service.dart';
import '../../services/url_launcher_service.dart';
import '../../services/key_validation_service.dart';
import '../../services/model_list_service.dart';
import '../../services/key_cache_service.dart';
import '../../services/region_filter_service.dart';
import '../../viewmodels/settings_viewmodel.dart';
import '../../models/mcp_server.dart';
import '../../models/validation_result.dart';
import '../../utils/ime_friendly_formatter.dart';
import '../widgets/ime_safe_text_field.dart';
import '../widgets/key_validation_button.dart';
import '../widgets/model_list_dialog.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../theme/kc_tokens.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import '../widgets/kc_logo.dart';
import '../widgets/kc_window_header.dart';
import '../widgets/provider_picker.dart';
import '../../services/platform_registry.dart';
import '../../services/platform/window_chrome.dart';
import '../widgets/kc_toast.dart';
import '../../services/tool_providers/tool_provider_service.dart';
import '../widgets/key_card.dart' show toolConfigPathHint;

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

class _KeyFormPageState extends State<KeyFormPage> with WidgetsBindingObserver {
  late TextEditingController _nameController;
  late TextEditingController _managementUrlController;
  late TextEditingController _apiEndpointController;
  late TextEditingController _keyValueController;
  late TextEditingController _tagsController;
  late TextEditingController _notesController;
  late TextEditingController _expiryDateController;
  late TextEditingController _providerDisplayController;
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

  // OpenClaw 配置控制器
  late TextEditingController _openclawBaseUrlController;
  late TextEditingController _openclawModelController;

  // Claude Desktop 配置控制器
  late TextEditingController _claudeDesktopBaseUrlController;
  late TextEditingController _geminiBaseUrlController;
  late TextEditingController _geminiModelController;

  /// 预设带来的工具附加配置（apiKeyField/env、wireApi/reasoningEffort），随密钥保存
  Map<String, dynamic>? _claudeCodeExtraConfig;
  Map<String, dynamic>? _codexExtraConfig;
  late TextEditingController _claudeDesktopSonnetController;
  late TextEditingController _claudeDesktopHaikuController;
  late TextEditingController _claudeDesktopOpusController;

  PlatformType? _selectedPlatform;
  DateTime? _expiryDate;
  bool _isEditMode = false;
  bool _isCustomPlatform = false;
  bool _initialized = false; // 标记是否已完成初始化
  bool _obscureKeyValue = true;
  final GlobalKey _providerFieldKey = GlobalKey();
  bool _moreOpen = false; // 「更多选项」折叠区

  // 地区过滤后的平台列表缓存
  Map<PlatformCategory, List<PlatformType>> _filteredPlatformsCache = {};
  
  // ClaudeCode/Codex/Gemini/OpenClaw 启用状态
  bool _enableClaudeCode = false;
  bool _enableCodex = false;
  bool _enableGemini = false;
  bool _enableOpenclaw = false;
  bool _enableClaudeDesktop = false;
  bool _submitAttempted = false;

  // 图标选择
  String? _selectedIcon;
  
  // 服务实例
  final CodexConfigService _codexConfigService = CodexConfigService();
  final ClipboardService _clipboardService = ClipboardService();
  final UrlLauncherService _urlLauncherService = UrlLauncherService();
  final KeyValidationService _validationService = KeyValidationService();
  final ModelListService _modelListService = ModelListService();
  final KeyCacheService _cacheService = KeyCacheService();
  
  // 校验状态
  ValidationState _validationState = ValidationState.idle;
  String? _validationErrorMessage;
  
  // 是否支持模型列表查询
  bool _supportsModelList = false;
  // 缓存的模型列表
  List<ModelInfo>? _cachedModels;
  // 是否支持密钥校验
  bool _supportsValidation = false;

  
  // 环境变量设置方式（永久）
  bool _envVarPermanent = true;
  
  // 管理地址是否为空（用于控制按钮显示）
  bool _hasManagementUrl = false;

  /// 更多工具（OpenCode / Grok Build / Hermes / Pi / MiniMax Code）的按密钥启用状态，随表单一起保存
  late Map<String, Map<String, dynamic>> _toolConfigs;

  @override
  void initState() {
    _toolConfigs = {for (final e in (widget.editingKey?.toolConfigs ?? const {}).entries) e.key: Map<String, dynamic>.from(e.value)};
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

    // OpenClaw 配置控制器
    _openclawBaseUrlController = TextEditingController(
      text: widget.editingKey?.openclawBaseUrl ?? '',
    );
    _openclawModelController = TextEditingController(
      text: widget.editingKey?.openclawModel ?? '',
    );

    // Claude Desktop 配置控制器
    _geminiBaseUrlController = TextEditingController(text: widget.editingKey?.geminiBaseUrl ?? '');
    _geminiModelController = TextEditingController(text: widget.editingKey?.geminiModel ?? '');
    _claudeCodeExtraConfig = widget.editingKey?.claudeCodeConfig;
    _codexExtraConfig = widget.editingKey?.codexConfig;
    _claudeDesktopBaseUrlController = TextEditingController(
      text: widget.editingKey?.claudeDesktopBaseUrl ?? '',
    );
    _claudeDesktopSonnetController = TextEditingController(
      text: widget.editingKey?.claudeDesktopSonnetModel ?? '',
    );
    _claudeDesktopHaikuController = TextEditingController(
      text: widget.editingKey?.claudeDesktopHaikuModel ?? '',
    );
    _claudeDesktopOpusController = TextEditingController(
      text: widget.editingKey?.claudeDesktopOpusModel ?? '',
    );

    if (widget.editingKey != null) {
      _selectedPlatform = widget.editingKey!.platformType;
      _isCustomPlatform = widget.editingKey!.platformType == PlatformType.custom;
      _expiryDate = widget.editingKey!.expiryDate;
      _obscureKeyValue = true; // v3：编辑模式同样默认掩码（form_v3.md §1）
      _enableClaudeCode = widget.editingKey!.enableClaudeCode;
      _enableCodex = widget.editingKey!.enableCodex;
      _enableGemini = widget.editingKey!.enableGemini;
      _enableOpenclaw = widget.editingKey!.enableOpenclaw;
      _enableClaudeDesktop = widget.editingKey!.enableClaudeDesktop;
      _selectedIcon = widget.editingKey!.icon;
    } else {
      _isCustomPlatform = true;
      _obscureKeyValue = true; // 添加模式下默认隐藏密钥值
      _enableClaudeCode = false;
      _enableCodex = false;
      _enableGemini = false;
      _enableOpenclaw = false;
      _enableClaudeDesktop = false;
      _selectedIcon = null;
      // 新建模式下：默认选择常用分组中的自定义模板
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectPlatform(PlatformType.custom);
        }
      });
    }

    _expiryDateController = TextEditingController(
      text: _expiryDate != null ? DateFormat('yyyy-MM-dd').format(_expiryDate!) : '',
    );
    
    _providerDisplayController = TextEditingController(
      text: _selectedPlatform?.value ?? '自定义',
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
    
    // 监听密钥值变化，重置校验状态
    _keyValueController.addListener(() {
      if (_validationState != ValidationState.idle) {
        setState(() {
          _validationState = ValidationState.idle;
          _validationErrorMessage = null;
        });
      }
    });
    
    // 检查是否支持模型列表查询和密钥校验
    _checkPlatformCapabilities();
    // 加载缓存的模型列表（编辑模式下）
    _loadCachedModels();
    // 加载地区过滤后的平台列表
    _loadFilteredPlatforms();
  }


  /// 加载地区过滤后的平台列表
  Future<void> _loadFilteredPlatforms() async {
    final categories = PlatformCategoryManager.allCategories;
    final filteredCache = <PlatformCategory, List<PlatformType>>{};

    // 检查是否启用中国地区过滤
    final isChinaFilterEnabled = await RegionFilterService.isChinaRegionFilterEnabled();

    for (final category in categories) {
      List<PlatformType> platforms = PlatformCategoryManager.getPlatformsByCategory(category);

      // 应用地区过滤
      if (isChinaFilterEnabled) {
        platforms = platforms.where((platform) =>
          !RegionFilterService.isPlatformRestrictedInChina(platform.id) &&
          !RegionFilterService.isPlatformRestrictedInChina(platform.value)
        ).toList();
      }

      filteredCache[category] = platforms;
    }

    if (mounted) {
      setState(() {
        _filteredPlatformsCache = filteredCache;
      });
    }
  }
  
  /// 检查是否支持模型列表查询和密钥校验
  Future<void> _checkPlatformCapabilities() async {
    // 保存当前选择的平台，避免异步执行时平台已切换
    final currentPlatform = _selectedPlatform;
    
    if (currentPlatform != null) {
      try {
        final supportsModelList = await _validationService.supportsModelList(currentPlatform);
        final supportsValidation = await _validationService.hasValidationConfig(currentPlatform);
        
        // 再次检查平台是否还是当前选择的平台（避免异步执行时平台已切换）
        if (mounted && _selectedPlatform == currentPlatform) {
          setState(() {
            _supportsModelList = supportsModelList;
            _supportsValidation = supportsValidation;
          });
          print('KeyFormPage: 平台 ${currentPlatform.value} - 支持校验: $supportsValidation, 支持模型列表: $supportsModelList');
        }
      } catch (e) {
        print('KeyFormPage: 检查平台能力失败: $e');
        // 如果检查失败，清空按钮状态
        if (mounted && _selectedPlatform == currentPlatform) {
          setState(() {
            _supportsModelList = false;
            _supportsValidation = false;
          });
        }
      }
    } else {
      // 如果没有选择平台，清空按钮状态
      if (mounted) {
        setState(() {
          _supportsModelList = false;
          _supportsValidation = false;
        });
      }
    }
  }
  
  /// 加载缓存的模型列表（复用密钥卡片的逻辑）
  Future<void> _loadCachedModels() async {
    // 编辑模式下，使用当前编辑的密钥
    if (widget.editingKey != null && _selectedPlatform != null) {
      final cachedModels = await _cacheService.getModelList(widget.editingKey!);
      if (mounted) {
        setState(() {
          _cachedModels = cachedModels;
        });
      }
    } else if (_selectedPlatform != null && _keyValueController.text.isNotEmpty) {
      // 新建模式下，如果有密钥值，尝试从缓存加载（基于平台类型）
      // 注意：新建模式下可能没有缓存的模型列表，这里主要是为了保持一致性
      _cachedModels = null;
    }
  }
  
  /// 构建模型选择按钮（复用密钥卡片的逻辑）
  Widget? _buildModelPickerButton(BuildContext context, TextEditingController controller) {
    // 只有在有缓存的模型列表时才显示选择按钮
    if (_cachedModels == null || _cachedModels!.isEmpty) {
      return null;
    }
    
    return IconButton(
      icon: Icon(Icons.arrow_drop_down, size: 18, color: ShadTheme.of(context).colorScheme.mutedForeground),
      onPressed: () => _showModelPickerDialog(context, controller),
      padding: const EdgeInsets.all(0),
      constraints: const BoxConstraints(),
      tooltip: '选择模型',
    );
  }
  
  /// 显示模型选择对话框（复用 ModelListDialog）
  Future<void> _showModelPickerDialog(BuildContext context, TextEditingController controller) async {
    if (_cachedModels == null || _cachedModels!.isEmpty) return;
    
    final localizations = AppLocalizations.of(context);
    final selectedModel = await showDialog<ModelInfo>(
      context: context,
      builder: (context) => ModelListDialog(
        models: _cachedModels!,
        platformName: (_selectedPlatform ?? PlatformType.custom).value,
        onSelectModel: (model) {
          // 选择模型后直接返回
          Navigator.of(context).pop(model);
        },
      ),
    );
    
    if (selectedModel != null && mounted) {
      controller.text = selectedModel.id;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ⚠️ 编辑模式下，确保平台设置正确但不覆盖用户配置
    if (_isEditMode && _selectedPlatform != null && !_initialized) {
      // 编辑模式下只设置平台类型相关标志，不调用 _selectPlatform 避免覆盖用户数据
      setState(() {
        _isCustomPlatform = _selectedPlatform == PlatformType.custom;
      });
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
    _providerDisplayController.dispose();
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
    _openclawBaseUrlController.dispose();
    _openclawModelController.dispose();
    _claudeDesktopBaseUrlController.dispose();
    _geminiBaseUrlController.dispose();
    _geminiModelController.dispose();
    _claudeDesktopSonnetController.dispose();
    _claudeDesktopHaikuController.dispose();
    _claudeDesktopOpusController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 应用重新获得焦点时，重新加载平台列表（以防地区过滤设置改变）
      _loadFilteredPlatforms();
    }
  }

  /// 切换供应商（编辑模式下也支持）
  void _switchProvider(PlatformType platform) {
    // 保存当前过期日期和标签（供应商没有的信息）
    final savedExpiryDate = _expiryDate;
    final savedTags = _tagsController.text;
    final savedNotes = _notesController.text;
    final savedKeyValue = _keyValueController.text;
    
    // 调用选择平台方法（这会清空缓存的模型列表并更新按钮状态）
    _selectPlatform(platform, preserveFields: _isEditMode);
    
    // 恢复过期日期、标签、备注和密钥值，并更新供应商展示框
    if (mounted) {
      setState(() {
        _expiryDate = savedExpiryDate;
        if (savedExpiryDate != null) {
          _expiryDateController.text = DateFormat('yyyy-MM-dd').format(savedExpiryDate);
        }
        _tagsController.text = savedTags;
        _notesController.text = savedNotes;
        _keyValueController.text = savedKeyValue;
        _providerDisplayController.text = platform.value;
      });
    }
  }

  /// 选择供应商并自动填充
  void _selectPlatform(PlatformType platform, {bool preserveFields = false}) {
    setState(() {
      _selectedPlatform = platform;
      _isCustomPlatform = platform == PlatformType.custom;
      // 切换供应商时先重置按钮状态，等待异步检查完成后再更新
      _cachedModels = null;
      _supportsModelList = false;
      _supportsValidation = false;

      // 如果不是自定义平台，自动填充预设信息
      if (platform != PlatformType.custom) {
        final preset = PlatformPresets.getPreset(platform);
        if (preset != null) {
          // 名称：按照模板填充（如果当前名称为空或者是默认名称，则覆盖）
          if (!preserveFields || _nameController.text.trim().isEmpty) {
            _nameController.text = preset.defaultName ?? '';
          }
          
          // 管理URL：仅在新建模式或切换模板时从模板填充
          if (!preserveFields) {
            if (preset.managementUrl != null) {
              _managementUrlController.text = preset.managementUrl!;
              _hasManagementUrl = true;
            } else {
              _managementUrlController.clear();
              _hasManagementUrl = false;
            }
          }
          
          // API端点：仅在新建模式或切换模板时从模板填充
          if (!preserveFields) {
            if (preset.apiEndpoint != null) {
              _apiEndpointController.text = preset.apiEndpoint!;
            } else {
              _apiEndpointController.clear();
            }
          }
          
          // 自动设置平台图标（仅在新建模式或用户明确切换模板时）
          // 编辑模式下，如果已有自定义图标，保留自定义图标；否则从模板加载
          if (!preserveFields || _selectedIcon == null) {
            final iconPath = PlatformIconService.getIconAssetPath(platform);
            if (iconPath != null) {
              final iconFileName = iconPath.replaceFirst('assets/icons/platforms/', '');
              _selectedIcon = iconFileName;
            } else {
              _selectedIcon = null;
            }
          }
          
          // 尝试获取平台的 ClaudeCode/Codex 配置（仅在新建模式或切换模板时）
          if (!preserveFields) {
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

            final preset = ProviderConfig.getPresetByPlatformId(platform.id);

            // Claude Code 的密钥字段 / 附加环境变量（如 ANTHROPIC_API_KEY、Bedrock 区域）
            final cc = preset?.claudeCode;
            _claudeCodeExtraConfig = (cc != null && (cc.apiKeyField != null || (cc.env?.isNotEmpty ?? false)))
                ? {
                    if (cc.apiKeyField != null) 'apiKeyField': cc.apiKeyField,
                    if (cc.env?.isNotEmpty ?? false) 'env': Map<String, String>.from(cc.env!),
                  }
                : null;

            // Claude Desktop：只有预设声明了直连（claude-* 模型名可用）时才自动开启并填充；
            // 旧逻辑对任何有 Claude Code 端点的预设都自动开启，导致不支持直连的供应商在 Desktop 中不可用
            final desktop = preset?.claudeDesktop;
            if (desktop != null && desktop.baseUrl.isNotEmpty) {
              _enableClaudeDesktop = true;
              _claudeDesktopBaseUrlController.text = desktop.baseUrl;
              _claudeDesktopSonnetController.text = desktop.modelConfig.sonnetModel ?? '';
              _claudeDesktopHaikuController.text = desktop.modelConfig.haikuModel ?? '';
              _claudeDesktopOpusController.text = desktop.modelConfig.opusModel ?? '';
            } else {
              _enableClaudeDesktop = false;
              _claudeDesktopBaseUrlController.clear();
              _claudeDesktopSonnetController.clear();
              _claudeDesktopHaikuController.clear();
              _claudeDesktopOpusController.clear();
            }

            // Gemini CLI：预设提供第三方 Gemini 端点时填充
            final gemini = preset?.gemini;
            if (gemini != null && gemini.baseUrl.isNotEmpty) {
              _enableGemini = true;
              _geminiBaseUrlController.text = gemini.baseUrl;
              _geminiModelController.text = gemini.model;
            } else {
              _geminiBaseUrlController.clear();
              _geminiModelController.clear();
            }

            // Codex：wire_api / 推理强度
            final cx = preset?.codex;
            _codexExtraConfig = (cx != null && (cx.wireApi != null || cx.reasoningEffort != null))
                ? {
                    if (cx.wireApi != null) 'wireApi': cx.wireApi,
                    if (cx.reasoningEffort != null) 'reasoningEffort': cx.reasoningEffort,
                  }
                : null;

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
        }
      } else {
        // 选择自定义平台时，清空基本表单字段（仅新建）
        if (!preserveFields) {
          _nameController.clear();
          _managementUrlController.clear();
          _hasManagementUrl = false;
          _apiEndpointController.clear();
          _keyValueController.clear();
          _tagsController.clear();
          _notesController.clear();
          _expiryDate = null;
        }
      }
    });
    
    // 检查是否支持模型列表查询和密钥校验（切换供应商时实时更新）
    // 注意：必须在 setState 之后调用，确保 _selectedPlatform 已更新
    _checkPlatformCapabilities();
    // 切换供应商时重新加载缓存的模型列表（编辑模式下）
    _loadCachedModels();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final shadTheme = ShadTheme.of(context);
    final iconColor = shadTheme.colorScheme.foreground;
    final errors = _submitAttempted ? _formErrors(localizations) : const <String, String>{};

    // ── 左栏：平台预设 + 基本信息（ui_redesign_plan §5.4 / mockup 04） ──
    final nameField = _withFieldError(ImeSafeTextField(
                      controller: _nameController,
                      labelText: localizations?.keyNameLabel ?? '密钥名称 *',
                      hintText: localizations?.keyNameHint ?? '请输入密钥名称',
                      prefixIcon: _buildClickableIcon(context, shadTheme),
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ), errors['name']);
    final providerField = _buildProviderDropdown(context, shadTheme, localizations);
    final managementUrlField = ImeSafeTextField(
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
                              padding: const EdgeInsets.all(0),
                              constraints: const BoxConstraints(),
                            )
                          : null,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    );
    final apiEndpointField = ImeSafeTextField(
                      controller: _apiEndpointController,
                      labelText: localizations?.apiEndpointLabel ?? 'API地址',
                      hintText: localizations?.apiEndpointHint ?? 'https://api.example.com',
                      prefixIcon: Icon(Icons.code, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      keyboardType: TextInputType.url,
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    );
    final keyValueField = _withFieldError(ImeSafeTextField(
                controller: _keyValueController,
                labelText: localizations?.keyValueLabelForm ?? '密钥值 *',
                hintText: localizations?.keyValueHint ?? '请输入密钥值',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(Icons.key, size: 18, color: shadTheme.colorScheme.mutedForeground),
                ),
                obscureText: _obscureKeyValue,
                // 显示 / 粘贴 / 校验（form_v3.md §1）
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    key: const ValueKey('keyForm.toggleObscure'),
                    tooltip: _obscureKeyValue ? (localizations?.tr('show', '显示') ?? '显示') : (localizations?.tr('hide', '隐藏') ?? '隐藏'),
                    icon: Icon(_obscureKeyValue ? Icons.visibility_off : Icons.visibility, size: 18, color: iconColor),
                    onPressed: () => setState(() => _obscureKeyValue = !_obscureKeyValue),
                    padding: const EdgeInsets.all(0),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  IconButton(
                    key: const ValueKey('keyForm.paste'),
                    tooltip: localizations?.tr('paste', '粘贴') ?? '粘贴',
                    icon: Icon(Icons.content_paste, size: 17, color: iconColor),
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      final t = data?.text?.trim();
                      if (t != null && t.isNotEmpty) setState(() => _keyValueController.text = t);
                    },
                    padding: const EdgeInsets.all(0),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                  if (_supportsValidation && _selectedPlatform != null)
                    IconButton(
                      key: const ValueKey('keyForm.validate'),
                      tooltip: localizations?.validateKey ?? '验证',
                      icon: _validationState == ValidationState.validating
                          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: shadTheme.colorScheme.primary))
                          : Icon(
                              _validationState == ValidationState.success
                                  ? Icons.check_circle
                                  : _validationState == ValidationState.failure
                                      ? Icons.error
                                      : Icons.verified_outlined,
                              size: 17,
                              color: _validationState == ValidationState.success
                                  ? context.kc.ok
                                  : _validationState == ValidationState.failure
                                      ? context.kc.danger
                                      : iconColor),
                      onPressed: _keyValueController.text.isNotEmpty ? _handleValidate : null,
                      padding: const EdgeInsets.all(0),
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  const SizedBox(width: 6),
                ]),
                isDark: Theme.of(context).brightness == Brightness.dark,
              ), errors['key']);
    final tagsField = _withFieldError(ImeSafeTextField(
                      controller: _tagsController,
                      labelText: localizations?.tagsLabel ?? '标签',
                      hintText: localizations?.tagsHint ?? '多个标签用逗号分隔',
                      prefixIcon: Icon(Icons.local_offer, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ), errors['tags']);
    final expiryField = ImeSafeTextField(
                      controller: _expiryDateController,
                      labelText: localizations?.expiryDateLabel ?? '过期日期',
                      hintText: localizations?.expiryDateHint ?? '选择日期（可选）',
                      suffixIcon: _expiryDate != null
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.clear, size: 18, color: iconColor),
                                  onPressed: () {
                                    setState(() {
                                      _expiryDate = null;
                                      _expiryDateController.text = '';
                                    });
                                  },
                                  padding: const EdgeInsets.all(0),
                                  constraints: const BoxConstraints(),
                                ),
                                ShadPopover(
                                  controller: _datePickerPopoverController,
                                  padding: const EdgeInsets.all(0),
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
                                    padding: const EdgeInsets.all(0),
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              ],
                            )
                          : ShadPopover(
                              controller: _datePickerPopoverController,
                              padding: const EdgeInsets.all(0),
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
                                padding: const EdgeInsets.all(0),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    );
    final notesField = ImeSafeTextField(
                controller: _notesController,
                labelText: localizations?.notesLabel ?? '备注',
                hintText: localizations?.notesHint ?? '请输入备注信息',
                prefixIcon: Icon(Icons.notes, size: 18, color: shadTheme.colorScheme.mutedForeground),
                isDark: Theme.of(context).brightness == Brightness.dark,
              );

    // 左栏（form_v3.md §1）：供应商 / 名称 / API 密钥 / 请求地址 /「更多选项」
    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _formSectionTitle(context, localizations?.tr('provider', '供应商') ?? '供应商'),
        KeyedSubtree(key: _providerFieldKey, child: providerField),
        const SizedBox(height: KcSpace.x2),
        _buildQuickProviderChips(context, shadTheme),
        const SizedBox(height: KcSpace.x5),
        _formSectionTitle(context, localizations?.basicInfo ?? '基本信息'),
        nameField,
        const SizedBox(height: KcSpace.x4),
        keyValueField,
        const SizedBox(height: KcSpace.x4),
        apiEndpointField,
        const SizedBox(height: KcSpace.x3),
        InkWell(
          key: const ValueKey('keyForm.more'),
          borderRadius: BorderRadius.circular(KcRadius.control),
          onTap: () => setState(() => _moreOpen = !_moreOpen),
          child: SizedBox(
            height: 32,
            child: Row(children: [
              AnimatedRotation(
                turns: _moreOpen ? 0.25 : 0,
                duration: KcMotion.of(context),
                child: Icon(Icons.chevron_right, size: 18, color: shadTheme.colorScheme.mutedForeground),
              ),
              const SizedBox(width: 4),
              Text(localizations?.tr('more_options', '更多选项') ?? '更多选项',
                  style: KcType.strong.copyWith(color: shadTheme.colorScheme.foreground)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(localizations?.tr('more_options_hint', '管理地址、标签、备注、过期') ?? '管理地址、标签、备注、过期',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.caption.copyWith(color: shadTheme.colorScheme.mutedForeground)),
              ),
            ]),
          ),
        ),
        // 有错误时自动展开，保证错误可见
        if (_moreOpen || errors.containsKey('tags')) ...[
          const SizedBox(height: KcSpace.x3),
          managementUrlField,
          const SizedBox(height: KcSpace.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: expiryField),
              const SizedBox(width: KcSpace.x3),
              Expanded(child: tagsField),
            ],
          ),
          const SizedBox(height: KcSpace.x4),
          notesField,
        ],
      ],
    );

    final rightColumn = _buildToolConfigPanel(context, shadTheme, localizations);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true): _openProviderPicker,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _openProviderPicker,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _handleSubmit,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _handleSubmit,
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).popUntil((route) => route.isFirst),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
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
            _buildFormHeader(context, shadTheme, localizations),
            Divider(height: 1, thickness: 1, color: shadTheme.colorScheme.border),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // 宽屏：左 380 基本信息 / 右 工具配置；窄屏上下排
                  if (constraints.maxWidth >= 860) {
                    // 左栏 clamp(340, 35%, 420)，右栏 bg-subtle（form_v3.md §1）
                    final leftW = (constraints.maxWidth * 0.35).clamp(340.0, 420.0);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: leftW,
                          child: SingleChildScrollView(
                            key: const ValueKey('keyForm.left'),
                            primary: false,
                            padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x5, KcSpace.page, KcSpace.page),
                            child: leftColumn,
                          ),
                        ),
                        VerticalDivider(width: 1, thickness: 1, color: shadTheme.colorScheme.border),
                        Expanded(
                          child: ColoredBox(
                            color: context.kc.subtle.withValues(alpha: 0.55),
                            child: SingleChildScrollView(
                            key: const ValueKey('keyForm.right'),
                            primary: false,
                            padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x5, KcSpace.page, KcSpace.page),
                            child: rightColumn,
                          ),
                          ),
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(KcSpace.page, KcSpace.x5, KcSpace.page, KcSpace.page),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [leftColumn, const SizedBox(height: KcSpace.x6), rightColumn],
                    ),
                  );
                },
              ),
            ),
            // 固定底栏（高 56）：左侧状态，右侧 ⌘↵ 提示 / 取消 / 主按钮（form_v3.md §1）
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: shadTheme.colorScheme.background,
                border: Border(top: BorderSide(color: shadTheme.colorScheme.border, width: 1)),
              ),
              child: Row(
                children: [
                  _buildFooterStatus(context, localizations),
                  const Spacer(),
                  if (_supportsModelList && _selectedPlatform != null) ...[
                    ShadButton.ghost(
                      height: 32,
                      onPressed: _keyValueController.text.isNotEmpty ? _handleViewModels : null,
                      leading: const Icon(Icons.list_outlined, size: 16),
                      child: Text(localizations?.modelList ?? '模型列表'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(WindowChrome.isMacOS ? '⌘ Enter' : 'Ctrl Enter', style: KcType.caption.copyWith(color: shadTheme.colorScheme.mutedForeground)),
                  const SizedBox(width: 10),
                  ShadButton.outline(
                    height: 32,
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    child: Text(localizations?.cancel ?? '取消'),
                  ),
                  const SizedBox(width: 10),
                  ShadButton(
                    key: const ValueKey('keyForm.submit'),
                    height: 32,
                    onPressed: _handleSubmit,
                    leading: Icon(_isEditMode ? Icons.save_outlined : Icons.add, size: 16),
                    child: Text(_isEditMode ? (localizations?.save ?? '保存') : (localizations?.addKey ?? '添加密钥')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )));
  }

  /// 底栏左侧状态：n 处需要修改 / 待补全 / 已就绪
  Widget _buildFooterStatus(BuildContext context, AppLocalizations? localizations) {
    final kc = context.kc;
    final errs = _formErrors(localizations);
    if (_submitAttempted && errs.isNotEmpty) {
      return Text(
        localizations?.nFieldsNeedFix(errs.length) ?? '${errs.length} 处需要修改',
        key: const ValueKey('keyForm.errorCount'),
        style: KcType.caption.copyWith(color: kc.dangerText, fontWeight: FontWeight.w500),
      );
    }
    final ready = errs.isEmpty;
    return Row(key: const ValueKey('keyForm.status'), children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: ready ? kc.ok : kc.warn, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(
        ready ? (localizations?.tr('form_ready', '已就绪') ?? '已就绪') : (localizations?.tr('form_incomplete', '待补全') ?? '待补全'),
        style: KcType.caption.copyWith(color: ready ? kc.okText : kc.warnText),
      ),
    ]);
  }

  List<PlatformType> _platformsOf(PlatformCategory c) =>
      _filteredPlatformsCache[c] ?? PlatformCategoryManager.getPlatformsByCategory(c);

  Future<void> _openProviderPicker() async {
    final box = _providerFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box == null
        ? Rect.fromLTWH(24, 120, 300, 44)
        : box.localToGlobal(Offset.zero) & box.size;
    final picked = await showProviderPicker(
      context: context,
      anchor: anchor,
      categories: PlatformCategoryManager.allCategories,
      platformsOf: _platformsOf,
      selected: _selectedPlatform,
    );
    if (picked == null || !mounted) return;
    _applyProvider(picked);
  }

  void _applyProvider(PlatformType platform) {
    if (platform == _selectedPlatform) return;
    if (_isEditMode) {
      _switchProvider(platform);
    } else {
      _selectPlatform(platform);
    }
  }

  /// 供应商字段下方的快捷 chip：数量随栏宽自适应，最后固定一个「全部 N」
  Widget _buildQuickProviderChips(BuildContext context, ShadThemeData shadTheme) {
    final localizations = AppLocalizations.of(context);
    final popular = _platformsOf(PlatformCategory.popular).where((p) => p != PlatformType.custom).toList();
    final total = {
      for (final c in PlatformCategoryManager.allCategories)
        for (final p in _platformsOf(c))
          if (p != PlatformType.custom) p.id,
      for (final p in PlatformRegistry.getFilteredPlatformsSync())
        if (p != PlatformType.custom) p.id,
    }.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      // 估算：每个 chip ≈ 26 + 文字宽；用 TextPainter 精确计算，放不下就停
      final style = KcType.body;
      final allLabel = '${localizations?.tr('all', '全部') ?? '全部'} $total';
      double widthOf(String t) {
        final tp = TextPainter(text: TextSpan(text: t, style: style), textDirection: Directionality.of(context), maxLines: 1)..layout();
        return tp.width + 6 + 20 + 6 + 10 + 2;
      }
      var used = widthOf(allLabel) + 4;
      final shown = <PlatformType>[];
      for (final p in [PlatformType.custom, ...popular]) {
        final w = widthOf(p == PlatformType.custom ? (localizations?.custom ?? '自定义') : p.value) + KcSpace.x1_5;
        if (used + w > c.maxWidth) break;
        used += w;
        shown.add(p);
      }
      return Row(children: [
        for (final p in shown)
          Padding(
            padding: const EdgeInsets.only(right: KcSpace.x1_5),
            child: _buildPlatformChip(context, p,
                label: p == PlatformType.custom ? (localizations?.custom ?? '自定义') : null,
                isSelected: _selectedPlatform == p,
                shadTheme: shadTheme,
                isDark: isDark),
          ),
        InkWell(
          key: const ValueKey('keyForm.presetAll'),
          borderRadius: BorderRadius.circular(KcRadius.control),
          onTap: _openProviderPicker,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KcRadius.control),
              border: Border.all(color: shadTheme.colorScheme.border),
            ),
            child: Text(allLabel, softWrap: false, style: style.copyWith(color: context.kc.actionText)),
          ),
        ),
      ]);
    });
  }


  /// 当前表单里需要修改的字段（key → 错误文案）。只在点过「保存」后展示
  Map<String, String> _formErrors(AppLocalizations? localizations) {
    final errors = <String, String>{};
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      errors['name'] = localizations?.keyNameRequired ?? '请输入密钥名称';
    } else if (name.length > AppConstants.maxNameLength) {
      errors['name'] = localizations?.keyNameTooLong(AppConstants.maxNameLength) ??
          '密钥名称不能超过 ${AppConstants.maxNameLength} 个字符';
    }
    if (_keyValueController.text.trim().isEmpty) {
      errors['key'] = localizations?.keyValueRequired ?? '请输入密钥值';
    }
    if (_tagsController.text.trim().length > 200) {
      errors['tags'] = localizations?.tagsTooLong ?? '标签不能超过 200 个字符';
    }
    return errors;
  }

  Widget _withFieldError(Widget field, String? error) {
    if (error == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 2),
          child: Text(error, style: KcType.caption.copyWith(color: context.kc.dangerText)),
        ),
      ],
    );
  }

  Widget _formSectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: KcSpace.x3),
        child: Text(text, style: KcType.section.copyWith(color: ShadTheme.of(context).colorScheme.foreground)),
      );

  /// 顶部标题栏：标题 + 平台 · 名称 + 关闭
  Widget _buildFormHeader(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations) {
    final platform = _selectedPlatform;
    final subtitle = [
      if (platform != null) platform == PlatformType.custom ? (localizations?.custom ?? '自定义') : platform.value,
      if (_nameController.text.trim().isNotEmpty) _nameController.text.trim(),
    ].join(' · ');
    // 统一顶栏：高 52，macOS 非全屏时内缩 96 给红绿灯让位（form_v3.md §0 / §10）
    return KcWindowHeader(
      key: const ValueKey('keyForm.header'),
      title: _isEditMode ? (localizations?.editKeyTitle ?? '编辑密钥') : (localizations?.addKeyTitle ?? '添加密钥'),
      titleKey: const ValueKey('keyForm.title'),
      subtitle: subtitle,
      leading: platform != null
          ? KcPlatformLogo(platform: platform, customIconFileName: _selectedIcon, name: _nameController.text, size: 28, logoSize: 18)
          : null,
      closeKey: const ValueKey('keyForm.close'),
      onClose: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
  }

  bool _toolEnabledInForm(AiToolType t) {
    switch (t) {
      case AiToolType.claudecode:
        return _enableClaudeCode;
      case AiToolType.claudeDesktop:
        return _enableClaudeDesktop;
      case AiToolType.codex:
        return _enableCodex;
      case AiToolType.gemini:
        return _enableGemini;
      case AiToolType.openclaw:
        return _enableOpenclaw;
      default:
        return false;
    }
  }

  Widget _toolSection(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations, AiToolType t) {
    switch (t) {
      case AiToolType.claudecode:
        return _buildClaudeCodeConfigSection(context, shadTheme, localizations);
      case AiToolType.claudeDesktop:
        return _buildClaudeDesktopConfigSection(context, shadTheme, localizations);
      case AiToolType.codex:
        return _buildCodexConfigSection(context, shadTheme, localizations);
      case AiToolType.gemini:
        return _buildGeminiConfigSection(context, shadTheme, localizations);
      case AiToolType.openclaw:
        return _buildOpenClawConfigSection(context, shadTheme, localizations);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 右栏：工具页签（已用的打 ✓）+ 当前工具的配置区 + 「开启 / 生效中」后果说明
  /// 右栏「更多工具」：5 个新工具也在表单里列出；开关 = 为该工具启用这把密钥（toolConfigs.enabled），
  /// 写入工具配置在密钥详情的「更多工具」里进行（applyKeyToTool）。
  Widget _buildMoreToolsCard(BuildContext context, AppLocalizations? l) {
    final cs = ShadTheme.of(context).colorScheme;
    String t(String k, String f) => l?.tr(k, f) ?? f;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: KcSpace.x2, bottom: KcSpace.x1),
        child: Text(t('more_tools', '更多工具'), style: KcType.section.copyWith(color: cs.foreground)),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: KcSpace.x2),
        child: Text(t('more_tools_form_hint', '开关 = 为该工具启用这把密钥；保存后在密钥详情里「写入」到工具配置。'),
            style: KcType.caption.copyWith(color: cs.mutedForeground)),
      ),
      Container(
        key: const ValueKey('keyForm.moreTools'),
        decoration: BoxDecoration(color: cs.card, border: Border.all(color: cs.border), borderRadius: BorderRadius.circular(KcRadius.panel)),
        child: Column(children: [
          for (final (i, tool) in ToolProviderService.tools.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: cs.border),
            SizedBox(
              key: ValueKey('keyForm.tool.${tool.value}'),
              height: 44,
              child: Row(children: [
                const SizedBox(width: KcSpace.x3),
                KcToolLogo(tool: tool, size: 22),
                const SizedBox(width: 10),
                Expanded(child: Text(tool.displayName, style: KcType.strong.copyWith(color: cs.foreground))),
                Switch.adaptive(
                  key: ValueKey('keyForm.moreTool.${tool.value}'),
                  value: _toolConfigs[tool.value]?['enabled'] == true,
                  onChanged: (v) => setState(() {
                    _toolConfigs = {..._toolConfigs, tool.value: {...?_toolConfigs[tool.value], 'enabled': v}};
                  }),
                ),
                const SizedBox(width: KcSpace.x2),
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget _buildToolConfigPanel(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations) {
    // 右栏「用在哪些工具」（form_v3.md §1）：列出**全部**工具，每个工具一张卡；
    // 开关打开后就地展开字段；设置中未启用的工具置灰并说明去哪里开启。
    final cs = shadTheme.colorScheme;
    final kc = context.kc;
    return Consumer<SettingsViewModel>(
      builder: (context, settingsViewModel, _) {
        final enabledTools = settingsViewModel.getEnabledTools();
        Map<AiToolType, int?> currentIds = const {};
        try {
          currentIds = Provider.of<KeyManagerViewModel>(context, listen: false).currentKeyIds;
        } catch (_) {}
        final editingId = widget.editingKey?.id;

        Widget badge(String text, Color fg, Color bg) => Container(
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(text, style: KcType.badge.copyWith(color: fg)),
            );

        final cards = <Widget>[];
        for (final t in kcKeyTools) {
          final name = kcToolName(t);
          if (!enabledTools.contains(t)) {
            cards.add(Container(
              key: ValueKey('keyForm.tool.${t.value}'),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: KcSpace.x3),
              decoration: BoxDecoration(
                color: cs.card.withValues(alpha: 0.5),
                border: Border.all(color: cs.border),
                borderRadius: BorderRadius.circular(KcRadius.panel),
              ),
              child: Opacity(
                opacity: 0.6,
                child: Row(children: [
                  KcToolLogo(tool: t, size: 22),
                  const SizedBox(width: 10),
                  Text(name, style: KcType.strong.copyWith(color: cs.foreground)),
                  const SizedBox(width: 8),
                  badge(localizations?.tr('tool_disabled_in_settings', '设置中未启用') ?? '设置中未启用', kc.text2, kc.subtle),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(textAlign: TextAlign.right, localizations?.tr('enable_in_settings_hint', '在 设置 › 工具配置 中开启') ?? '在 设置 › 工具配置 中开启',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: KcType.caption.copyWith(color: cs.mutedForeground)),
                  ),
                ]),
              ),
            ));
            continue;
          }
          final on = _toolEnabledInForm(t);
          final isActive = editingId != null && currentIds[t] == editingId && on;
          final status = isActive
              ? badge(localizations?.statusActive ?? '生效中', kc.okText, kc.okSoft)
              : on
                  ? badge(localizations?.tr('status_candidate', '候选') ?? '候选', kc.actionText, kc.actionSoft)
                  : null;
          cards.add(Container(
            key: ValueKey('keyForm.tool.${t.value}'),
            padding: const EdgeInsets.fromLTRB(KcSpace.x4, KcSpace.x3, KcSpace.x4, KcSpace.x3),
            decoration: BoxDecoration(
              color: cs.card,
              border: Border.all(color: isActive ? kc.ok.withValues(alpha: 0.6) : cs.border),
              borderRadius: BorderRadius.circular(KcRadius.panel),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(children: [
                  _toolSection(context, shadTheme, localizations, t),
                  if (status != null) Positioned(top: 10, right: 52, child: IgnorePointer(child: status)),
                ]),
                if (on) ...[
                  const SizedBox(height: KcSpace.x2),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(isActive ? Icons.bolt : Icons.info_outline, size: 14, color: isActive ? kc.okText : kc.text2),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isActive
                            ? (localizations?.useForToolActiveHint(name, toolConfigPathHint(t)) ??
                                '这把密钥正在 $name 生效，保存后会同步写入 ${toolConfigPathHint(t)}')
                            : (localizations?.useForToolHint(name) ?? '开启后出现在 $name 的候选列表；在工具页或卡片上「设为当前」才会写入配置'),
                        key: ValueKey('keyForm.toolNote.${t.value}'),
                        style: KcType.caption.copyWith(color: isActive ? kc.okText : kc.text2),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _formSectionTitle(context, localizations?.tr('use_in_tools', '用在哪些工具') ?? '用在哪些工具'),
            if (_selectedPlatform == null)
              Padding(
                padding: const EdgeInsets.only(bottom: KcSpace.x3),
                child: Text(localizations?.selectPlatformFirst ?? '先在左侧选择平台预设',
                    style: KcType.body.copyWith(color: cs.mutedForeground)),
              ),
            for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: KcSpace.x3), child: c),
            _buildMoreToolsCard(context, localizations),
          ],
        );
      },
    );
  }






  /// 构建供应商展示框（样式与 ImeSafeTextField 一致）
  Widget _buildProviderDropdown(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations) {
    final currentPlatform = _selectedPlatform ?? PlatformType.custom;
    final iconColor = shadTheme.colorScheme.foreground;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[400]!;
    final fillColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    
    // 更新显示内容 - 对于自定义平台使用本地化文本
    if (currentPlatform == PlatformType.custom) {
      _providerDisplayController.text = localizations?.custom ?? '自定义';
    } else {
      _providerDisplayController.text = currentPlatform.value;
    }
    
    // 使用 TextField 只读模式来展示供应商
    return TextField(
      key: const ValueKey('keyForm.provider'),
      controller: _providerDisplayController,
      readOnly: true,
      onTap: _openProviderPicker,
      style: const TextStyle(
        fontSize: 14,
        height: 1.2,
      ),
      decoration: InputDecoration(
        labelText: localizations?.providerLabel ?? '密钥供应商',
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: PlatformIconService.buildIcon(
                platform: currentPlatform,
                size: 18,
              ),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          maxWidth: 32,
          minHeight: 32,
          maxHeight: 32,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            Icons.swap_horiz,
            size: 18,
            color: iconColor,
          ),
          tooltip: '⌘P',
          onPressed: _openProviderPicker,
          padding: const EdgeInsets.all(0),
          constraints: const BoxConstraints(),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 52,
          minHeight: 32,
        ),
        filled: true,
        fillColor: fillColor,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        floatingLabelAlignment: FloatingLabelAlignment.start,
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: borderColor,
            width: 0.5,
          ),
        ),
      ),
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
    final localizations = AppLocalizations.of(context);
    final displayLabel = label ?? (platform == PlatformType.custom
        ? (localizations?.custom ?? '自定义')
        : platform.value);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isSelected) {
            setState(() {
              _selectedPlatform = null;
            });
          } else {
            if (_isEditMode) {
              _switchProvider(platform);
            } else {
              _selectPlatform(platform);
            }
          }
        },
        borderRadius: BorderRadius.circular(KcRadius.control),
        child: AnimatedContainer(
          key: ValueKey('keyForm.preset.${platform.id}'),
          duration: KcMotion.of(context, KcMotion.fast),
          height: 32,
          padding: const EdgeInsets.only(left: 6, right: 10),
          decoration: BoxDecoration(
            color: isSelected ? context.kc.actionSoft : shadTheme.colorScheme.card,
            borderRadius: BorderRadius.circular(KcRadius.control),
            border: Border.all(
              color: isSelected ? shadTheme.colorScheme.primary : shadTheme.colorScheme.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              KcPlatformLogo(platform: platform, name: displayLabel, size: 20, logoSize: 14),
              const SizedBox(width: 6),
              Text(
                displayLabel,
                style: KcType.body.copyWith(
                  color: isSelected ? context.kc.actionText : shadTheme.colorScheme.foreground,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 校验密钥
  Future<void> _handleValidate() async {
    final localizations = AppLocalizations.of(context);
    if (_keyValueController.text.trim().isEmpty) {
      showKcToast(context, localizations?.enterKeyValueFirst ?? '请先输入密钥值', kind: KcToastKind.success);
      return;
    }

    setState(() {
      _validationState = ValidationState.validating;
      _validationErrorMessage = null;
    });

    try {
      // 创建临时 AIKey 对象
      final tempKey = AIKey(
        id: widget.editingKey?.id ?? 0,
        name: _nameController.text.trim().isEmpty
            ? '临时密钥'
            : _nameController.text.trim(),
        platform: (_selectedPlatform ?? PlatformType.custom).value,
        platformType: _selectedPlatform ?? PlatformType.custom,
        keyValue: _keyValueController.text.trim(),
        apiEndpoint: _apiEndpointController.text.trim().isEmpty
            ? null
            : _apiEndpointController.text.trim(),
        tags: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        claudeCodeBaseUrl: _claudeCodeBaseUrlController.text.trim().isEmpty
            ? null
            : _claudeCodeBaseUrlController.text.trim(),
        codexBaseUrl: _codexBaseUrlController.text.trim().isEmpty
            ? null
            : _codexBaseUrlController.text.trim(),
        enableClaudeCode: _enableClaudeCode,
        enableCodex: _enableCodex,
      );

      final result = await _validationService.validateKey(
        key: tempKey,
        timeout: const Duration(seconds: 5),
      );

      if (mounted) {
        setState(() {
          if (result.isValid) {
            _validationState = ValidationState.success;
            _validationErrorMessage = null;
          } else {
            _validationState = ValidationState.failure;
            _validationErrorMessage = result.message ?? '校验失败';
          }
        });
        
        // 校验成功后写入缓存（复用密钥卡片的逻辑）
        if (result.isValid) {
          // 创建临时密钥对象用于缓存
          final tempKey = AIKey(
            id: widget.editingKey?.id ?? 0,
            name: _nameController.text.trim().isEmpty
                ? '临时密钥'
                : _nameController.text.trim(),
            platform: (_selectedPlatform ?? PlatformType.custom).value,
            platformType: _selectedPlatform ?? PlatformType.custom,
            keyValue: _keyValueController.text.trim(),
            apiEndpoint: _apiEndpointController.text.trim().isEmpty
                ? null
                : _apiEndpointController.text.trim(),
            tags: const [],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            claudeCodeBaseUrl: _claudeCodeBaseUrlController.text.trim().isEmpty
                ? null
                : _claudeCodeBaseUrlController.text.trim(),
            codexBaseUrl: _codexBaseUrlController.text.trim().isEmpty
                ? null
                : _codexBaseUrlController.text.trim(),
            enableClaudeCode: _enableClaudeCode,
            enableCodex: _enableCodex,
          );
          await _cacheService.saveValidationStatus(tempKey, true);
        }

        showKcToast(context, result.isValid
                  ? (result.message ?? '密钥有效')
                  : (result.message ?? '密钥无效'), kind: result.isValid ? KcToastKind.success : KcToastKind.error);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validationState = ValidationState.failure;
          _validationErrorMessage = '校验失败：${e.toString()}';
        });

        final localizations = AppLocalizations.of(context);
        showKcToast(context, localizations?.validationFailedWithError(e.toString()) ?? '校验失败：${e.toString()}', kind: KcToastKind.error);
      }
    }
  }

  /// 查看模型列表
  Future<void> _handleViewModels() async {
    final localizations = AppLocalizations.of(context);
    if (_keyValueController.text.trim().isEmpty) {
      showKcToast(context, localizations?.enterKeyValueFirst ?? '请先输入密钥值', kind: KcToastKind.success);
      return;
    }

    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ShadTheme.of(context).colorScheme.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const CircularProgressIndicator(),
        ),
      ),
    );

    try {
      // 创建临时 AIKey 对象
      final tempKey = AIKey(
        id: widget.editingKey?.id ?? 0,
        name: _nameController.text.trim().isEmpty
            ? '临时密钥'
            : _nameController.text.trim(),
        platform: (_selectedPlatform ?? PlatformType.custom).value,
        platformType: _selectedPlatform ?? PlatformType.custom,
        keyValue: _keyValueController.text.trim(),
        apiEndpoint: _apiEndpointController.text.trim().isEmpty
            ? null
            : _apiEndpointController.text.trim(),
        tags: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        claudeCodeBaseUrl: _claudeCodeBaseUrlController.text.trim().isEmpty
            ? null
            : _claudeCodeBaseUrlController.text.trim(),
        codexBaseUrl: _codexBaseUrlController.text.trim().isEmpty
            ? null
            : _codexBaseUrlController.text.trim(),
        enableClaudeCode: _enableClaudeCode,
        enableCodex: _enableCodex,
      );

      final result = await _modelListService.getModelList(key: tempKey);

      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (result.success && result.models != null) {
        // 获取模型列表成功后写入缓存（复用密钥卡片的逻辑）
        await _cacheService.saveModelList(tempKey, result.models!);
        
        // 更新缓存的模型列表状态
        if (mounted) {
          setState(() {
            _cachedModels = result.models!;
          });
        }
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => ModelListDialog(
              models: result.models!,
              platformName: (_selectedPlatform ?? PlatformType.custom).value,
            ),
          );
        }
      } else {
        if (mounted) {
          showKcToast(context, result.error ?? '查询模型列表失败', kind: KcToastKind.error);
        }
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        final localizations = AppLocalizations.of(context);
        showKcToast(context, localizations?.queryFailedWithError(e.toString()) ?? '查询失败：${e.toString()}', kind: KcToastKind.error);
      }
    }
  }

  void _handleSubmit() {
    final localizations = AppLocalizations.of(context);
    
    // ⚠️ 手动验证必填字段和长度（替代 validator 以避免输入时重建导致 IME 卡住）。错误就地显示在字段下方，底栏显示「n 处需要修改」
    if (_formErrors(localizations).isNotEmpty) {
      setState(() => _submitAttempted = true);
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
        geminiModel: _enableGemini && _geminiModelController.text.trim().isNotEmpty
            ? _geminiModelController.text.trim()
            : null,
        geminiBaseUrl: _enableGemini && _geminiBaseUrlController.text.trim().isNotEmpty
            ? _geminiBaseUrlController.text.trim()
            : null,
        codexConfig: _codexExtraConfig,
        claudeCodeConfig: _claudeCodeExtraConfig,
        enableOpenclaw: _enableOpenclaw,
        openclawBaseUrl: _openclawBaseUrlController.text.trim().isNotEmpty
            ? _openclawBaseUrlController.text.trim()
            : null,
        openclawModel: _openclawModelController.text.trim().isNotEmpty
            ? _openclawModelController.text.trim()
            : null,
        enableClaudeDesktop: _enableClaudeDesktop,
        claudeDesktopBaseUrl: _claudeDesktopBaseUrlController.text.trim().isNotEmpty
            ? _claudeDesktopBaseUrlController.text.trim()
            : null,
        claudeDesktopModel: null,
        claudeDesktopSonnetModel: _claudeDesktopSonnetController.text.trim().isNotEmpty
            ? _claudeDesktopSonnetController.text.trim()
            : null,
        claudeDesktopHaikuModel: _claudeDesktopHaikuController.text.trim().isNotEmpty
            ? _claudeDesktopHaikuController.text.trim()
            : null,
        claudeDesktopOpusModel: _claudeDesktopOpusController.text.trim().isNotEmpty
            ? _claudeDesktopOpusController.text.trim()
            : null,
        toolConfigs: _toolConfigs,
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
              PlatformIconService.buildIcon(
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
                      if (value && provider != null) {
                        // 开启时始终从模板加载默认配置（开/关/重开都重置为模板值）
                        _claudeCodeBaseUrlController.text = provider.baseUrl;
                        _claudeCodeModelController.text = provider.modelConfig.mainModel;
                        _claudeCodeHaikuModelController.text = provider.modelConfig.haikuModel ?? '';
                        _claudeCodeSonnetModelController.text = provider.modelConfig.sonnetModel ?? '';
                        _claudeCodeOpusModelController.text = provider.modelConfig.opusModel ?? '';
                      } else if (!value) {
                        // 关闭时清空，下次开启时重新从模板加载
                        _claudeCodeBaseUrlController.clear();
                        _claudeCodeModelController.clear();
                        _claudeCodeHaikuModelController.clear();
                        _claudeCodeSonnetModelController.clear();
                        _claudeCodeOpusModelController.clear();
                      }
                    });
                  },
                  activeTrackColor: shadTheme.colorScheme.primary,
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
                  suffixIcon: _buildModelPickerButton(context, _claudeCodeModelController),
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
                  suffixIcon: _buildModelPickerButton(context, _claudeCodeHaikuModelController),
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
                  suffixIcon: _buildModelPickerButton(context, _claudeCodeSonnetModelController),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                child: ImeSafeTextField(
                    controller: _claudeCodeOpusModelController,
                  labelText: localizations?.opusModel ?? 'Opus 模型',
                  hintText: localizations?.opusModelHint ?? '请输入 Opus 模型名称',
                  suffixIcon: _buildModelPickerButton(context, _claudeCodeOpusModelController),
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
              PlatformIconService.buildIcon(
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
                      if (value && provider != null) {
                        // 开启时始终从模板加载默认配置
                        _codexBaseUrlController.text = provider.baseUrl;
                        _codexModelController.text = provider.model;
                      } else if (!value) {
                        // 关闭时清空，下次开启时重新从模板加载
                        _codexBaseUrlController.clear();
                        _codexModelController.clear();
                      }
                    });
                  },
                  activeTrackColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          if (_enableCodex) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ImeSafeTextField(
                    controller: _codexBaseUrlController,
                    labelText: localizations?.requestUrl ?? '请求地址',
                    hintText: 'https://api.openai.com/v1',
                    prefixIcon: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
                    keyboardType: TextInputType.url,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ImeSafeTextField(
                    controller: _codexModelController,
                    labelText: localizations?.modelName ?? '模型名称',
                    hintText: 'gpt-5-codex',
                    prefixIcon: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
                    suffixIcon: _buildModelPickerButton(context, _codexModelController),
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ],
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
                  activeTrackColor: shadTheme.colorScheme.primary,
                ),
              ),
            ],
          ),
          // 第三方 Gemini 端点（留空则使用官方 API）
          if (_enableGemini) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ImeSafeTextField(
                    controller: _geminiBaseUrlController,
                    labelText: localizations?.requestUrl ?? '请求地址',
                    hintText: 'https://generativelanguage.googleapis.com',
                    prefixIcon: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
                    keyboardType: TextInputType.url,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ImeSafeTextField(
                    controller: _geminiModelController,
                    labelText: localizations?.modelName ?? '模型名称',
                    hintText: 'gemini-2.5-pro',
                    prefixIcon: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
                    suffixIcon: _buildModelPickerButton(context, _geminiModelController),
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ],
            ),
          ],
        ],
    );
  }

  /// 构建 OpenClaw 配置区域
  Widget _buildOpenClawConfigSection(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final provider = _selectedPlatform != null
        ? ProviderConfig.getOpenClawProviderByPlatform(_selectedPlatform!)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SvgPicture.asset(
              'assets/icons/platforms/openclaw-color.svg',
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
                    'OpenClaw 配置',
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
                value: _enableOpenclaw,
                onChanged: (value) {
                  setState(() {
                    _enableOpenclaw = value;
                    if (value && provider != null) {
                      // 开启时始终从配置文件加载默认值
                      _openclawBaseUrlController.text = provider.baseUrl;
                      _openclawModelController.text = provider.model;
                    } else if (!value) {
                      // 关闭时清空，下次开启时重新从配置加载
                      _openclawBaseUrlController.clear();
                      _openclawModelController.clear();
                    }
                  });
                },
                activeTrackColor: shadTheme.colorScheme.primary,
              ),
            ),
          ],
        ),
        if (_enableOpenclaw) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ImeSafeTextField(
                  controller: _openclawBaseUrlController,
                  labelText: localizations?.requestUrl ?? '请求地址',
                  hintText: provider?.baseUrl ?? 'https://api.example.com/v1',
                  prefixIcon: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  keyboardType: TextInputType.url,
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ImeSafeTextField(
                  controller: _openclawModelController,
                  labelText: localizations?.modelName ?? '模型名称',
                  hintText: provider?.model ?? 'provider/model-name',
                  prefixIcon: Icon(Icons.smart_toy, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  suffixIcon: _buildModelPickerButton(context, _openclawModelController),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 构建 Claude Desktop 配置区域
  Widget _buildClaudeDesktopConfigSection(
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
              'assets/icons/platforms/anthropic.svg',
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
                    'Claude Desktop 配置',
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.w600,
                      color: shadTheme.colorScheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '通过 Claude Desktop 3-Profile 配置注入',
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
                value: _enableClaudeDesktop,
                onChanged: (value) {
                  setState(() {
                    _enableClaudeDesktop = value;
                    if (!value) {
                      _claudeDesktopBaseUrlController.clear();
                      _claudeDesktopSonnetController.clear();
                      _claudeDesktopHaikuController.clear();
                      _claudeDesktopOpusController.clear();
                    }
                  });
                },
                activeTrackColor: shadTheme.colorScheme.primary,
              ),
            ),
          ],
        ),
        if (_enableClaudeDesktop) ...[
          const SizedBox(height: 16),
          ImeSafeTextField(
            controller: _claudeDesktopBaseUrlController,
            labelText: localizations?.requestUrl ?? '请求地址',
            hintText: 'https://api.anthropic.com',
            prefixIcon: Icon(Icons.link, size: 18, color: shadTheme.colorScheme.mutedForeground),
            keyboardType: TextInputType.url,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
          const SizedBox(height: 12),
          // 模型映射：Sonnet / Haiku / Opus 路由，参考 Claude Code 的紧凑布局
          Row(
            children: [
              Expanded(
                child: ImeSafeTextField(
                  controller: _claudeDesktopSonnetController,
                  labelText: 'Sonnet →',
                  hintText: 'deepseek-v4-pro',
                  prefixIcon: Icon(Icons.swap_horiz, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  suffixIcon: _buildModelPickerButton(context, _claudeDesktopSonnetController),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ImeSafeTextField(
                  controller: _claudeDesktopHaikuController,
                  labelText: 'Haiku →',
                  hintText: 'deepseek-v4-flash',
                  prefixIcon: Icon(Icons.swap_horiz, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  suffixIcon: _buildModelPickerButton(context, _claudeDesktopHaikuController),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ImeSafeTextField(
                  controller: _claudeDesktopOpusController,
                  labelText: 'Opus →',
                  hintText: 'deepseek-v4-ultra',
                  prefixIcon: Icon(Icons.swap_horiz, size: 18, color: shadTheme.colorScheme.mutedForeground),
                  suffixIcon: _buildModelPickerButton(context, _claudeDesktopOpusController),
                  isDark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
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
                    child: PlatformIconService.buildIcon(
                platform: _selectedPlatform!,
                customIconFileName: _selectedIcon,
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
        codexConfig: _codexExtraConfig,
        enableCodex: true,
      );
      
      final providerConfig = await _codexConfigService.getProviderConfig(tempKey);
      return providerConfig.needsEnvVar;
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
                          showKcToast(context, localizations?.keyCopied ?? '已复制', kind: KcToastKind.success);
                        }
                      },
                      tooltip: localizations?.copy ?? '复制',
                      padding: const EdgeInsets.all(0),
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
        codexConfig: _codexExtraConfig,
        enableCodex: true,
      );
      
      return await _codexConfigService.generateEnvVarCommand(tempKey, permanent: permanent);
    } catch (e) {
      return null;
    }
  }
}

/// 表单右栏的工具页签：logo + 名称，已用于该工具时带 ✓

