import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../utils/liquid_glass_decoration.dart';
import '../../utils/platform_icon_service.dart';
import '../../config/provider_config.dart';
import '../widgets/platform_category_tabs.dart';
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

  PlatformType? _selectedPlatform;
  DateTime? _expiryDate;
  bool _isEditMode = false;
  bool _isCustomPlatform = false;
  bool _initialized = false; // 标记是否已完成初始化
  bool _obscureKeyValue = true;
  PlatformCategory _selectedCategory = PlatformCategory.popular;
  bool _showProviderList = false; // 编辑模式下是否显示供应商列表

  // 地区过滤后的平台列表缓存
  Map<PlatformCategory, List<PlatformType>> _filteredPlatformsCache = {};
  
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

  @override
  void initState() {
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
            // 供应商分组位于标题栏内，高度与主页页面切换栏完全一致
            _buildImmersiveTitleBar(context),
            // 表单内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

              // 密钥名称和供应商（同一行）
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
                    child: _buildProviderDropdown(context, shadTheme, localizations),
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
                              padding: const EdgeInsets.all(0),
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
                  padding: const EdgeInsets.all(0),
                  constraints: const BoxConstraints(),
                ),
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              const SizedBox(height: 16),

              // 标签和过期日期（同一行）
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ImeSafeTextField(
                      controller: _tagsController,
                      labelText: localizations?.tagsLabel ?? '标签',
                      hintText: localizations?.tagsHint ?? '多个标签用逗号分隔',
                      prefixIcon: Icon(Icons.local_offer, size: 18, color: shadTheme.colorScheme.mutedForeground),
                      isDark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ImeSafeTextField(
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
                    ),
                  ),
                ],
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
                  // 校验按钮（如果支持则显示，密钥值为空时禁用）
                  if (_supportsValidation && _selectedPlatform != null) ...[
                    ShadButton.outline(
                      onPressed: _keyValueController.text.isNotEmpty ? _handleValidate : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_validationState == ValidationState.validating)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  shadTheme.colorScheme.primary,
                                ),
                              ),
                            )
                          else
                            Icon(
                              _validationState == ValidationState.success
                                  ? Icons.check_circle
                                  : _validationState == ValidationState.failure
                                      ? Icons.error
                                      : Icons.verified_outlined,
                              size: 16,
                              color: _validationState == ValidationState.success
                                  ? Colors.green
                                  : _validationState == ValidationState.failure
                                      ? Colors.red
                                      : null,
                            ),
                          const SizedBox(width: 6),
                          Text(localizations?.validateKey ?? '验证'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // 查看模型按钮（如果支持则显示，密钥值为空时禁用）
                  if (_supportsModelList && _selectedPlatform != null) ...[
                    ShadButton.outline(
                      onPressed: _keyValueController.text.isNotEmpty ? _handleViewModels : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.list_outlined, size: 16),
                          const SizedBox(width: 6),
                          Text(localizations?.modelList ?? '模型列表'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
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
  /// 供应商分组位于标题栏内，高度与主页页面切换栏完全一致
  Widget _buildImmersiveTitleBar(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Column(
      children: [
        Container(
          height: 56, // 与主页标题栏高度完全一致
          padding: const EdgeInsets.only(top: 20, left: 20), // 与主页 padding top 一致
          decoration: BoxDecoration(
            color: shadTheme.colorScheme.background,
            // 移除底部边框
          ),
          child: Stack(
            children: [
              // 新建模式：显示供应商分组切换滑块（居中，与主页AppSwitcher一致）
              // 编辑模式：点击切换供应商按钮后显示供应商分组切换滑块，否则显示"编辑密钥"标题
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeInOutCubic,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: (!_isEditMode || _showProviderList)
                      ? _buildCategorySwitcher(context, shadTheme)
                      : Text(
                          localizations?.editKey ?? '编辑密钥',
                          key: const ValueKey('edit_title'),
                          style: shadTheme.textTheme.p.copyWith(
                            fontWeight: FontWeight.w600,
                            color: shadTheme.colorScheme.foreground,
                          ),
                        ),
                ),
              ),
              // 右侧：关闭按钮，垂直居中
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: const EdgeInsets.all(0),
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
        ),
        // 供应商选择标签区域 - 仅在显示供应商分组时显示，带丝滑动画
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          child: (!_isEditMode || _showProviderList)
              ? Container(
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
                  alignment: Alignment.centerLeft,
                  child: _buildPlatformChips(context, shadTheme),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// 构建分类切换滑块（与主页AppSwitcher样式一致）
  Widget _buildCategorySwitcher(BuildContext context, ShadThemeData shadTheme) {
    return Container(
      key: const ValueKey('category_switcher'),
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

  /// 构建供应商选择标签区域
  Widget _buildPlatformChips(BuildContext context, ShadThemeData shadTheme) {
    // 获取原始平台列表
    List<PlatformType> displayPlatforms;
    if (_filteredPlatformsCache.containsKey(_selectedCategory)) {
      displayPlatforms = _filteredPlatformsCache[_selectedCategory]!;
    } else {
      displayPlatforms = PlatformCategoryManager.getPlatformsByCategory(_selectedCategory);
      // 如果还没有加载地区过滤，应用同步过滤
      // 注意：这里使用同步检查，只是为了避免UI等待，实际的过滤在异步加载完成后会更新
      // 这里我们简单地返回所有平台，真正的过滤会在 _loadFilteredPlatforms 完成后更新
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localizations = AppLocalizations.of(context);
    
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
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
      controller: _providerDisplayController,
      readOnly: true,
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
          onPressed: () {
            setState(() {
              _showProviderList = !_showProviderList;
            });
          },
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
              if (_isEditMode) {
                _showProviderList = false; // 编辑模式下选择后隐藏列表
              }
            });
          } else {
            if (_isEditMode) {
              _switchProvider(platform);
              setState(() {
                _showProviderList = false; // 编辑模式下选择后隐藏列表
              });
            } else {
              _selectPlatform(platform);
            }
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
              PlatformIconService.buildIcon(
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

  /// 校验密钥
  Future<void> _handleValidate() async {
    final localizations = AppLocalizations.of(context);
    if (_keyValueController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.enterKeyValueFirst ?? '请先输入密钥值')),
      );
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isValid
                  ? (result.message ?? '密钥有效')
                  : (result.message ?? '密钥无效'),
            ),
            backgroundColor: result.isValid ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validationState = ValidationState.failure;
          _validationErrorMessage = '校验失败：${e.toString()}';
        });

        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.validationFailedWithError(e.toString()) ?? '校验失败：${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 查看模型列表
  Future<void> _handleViewModels() async {
    final localizations = AppLocalizations.of(context);
    if (_keyValueController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.enterKeyValueFirst ?? '请先输入密钥值')),
      );
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? '查询模型列表失败'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        final localizations = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations?.queryFailedWithError(e.toString()) ?? '查询失败：${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
        SnackBar(content: Text(localizations?.keyNameTooLong(AppConstants.maxNameLength) ?? '密钥名称不能超过 ${AppConstants.maxNameLength} 个字符')),
      );
      return;
    }
    if (_tagsController.text.trim().length > 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.tagsTooLong ?? '标签不能超过 200 个字符')),
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
        enableCodex: true,
      );
      
      return await _codexConfigService.generateEnvVarCommand(tempKey, permanent: permanent);
    } catch (e) {
      return null;
    }
  }
}

