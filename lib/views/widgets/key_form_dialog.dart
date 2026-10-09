import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/ai_key.dart';
import '../../models/platform_type.dart';
import '../../constants/app_constants.dart';
import '../../utils/platform_presets.dart';
import '../../utils/macos_input_decoration.dart';
import '../../utils/platform_icon_service.dart';
import '../../utils/ime_friendly_formatter.dart';
import 'platform_category_tabs.dart';
import 'ime_safe_text_field.dart';

/// 密钥编辑表单对话框
class KeyFormDialog extends StatefulWidget {
  final AIKey? editingKey;
  final Function(AIKey) onSubmit;

  const KeyFormDialog({
    super.key,
    this.editingKey,
    required this.onSubmit,
  });

  @override
  State<KeyFormDialog> createState() => _KeyFormDialogState();
}

class _KeyFormDialogState extends State<KeyFormDialog> {
  // ⚠️ 移除 _formKey，不再使用 Form
  // final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _managementUrlController;
  late TextEditingController _apiEndpointController;
  late TextEditingController _keyValueController;
  late TextEditingController _tagsController;
  late TextEditingController _notesController;

  PlatformType? _selectedPlatform;
  DateTime? _expiryDate;
  bool _isEditMode = false;
  bool _isCustomPlatform = false;
  bool _obscureKeyValue = true;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.editingKey != null;

    _nameController = TextEditingController(text: widget.editingKey?.name ?? '');
    _managementUrlController =
        TextEditingController(text: widget.editingKey?.managementUrl ?? '');
    _apiEndpointController =
        TextEditingController(text: widget.editingKey?.apiEndpoint ?? '');
    _keyValueController = TextEditingController(text: widget.editingKey?.keyValue ?? '');
    _tagsController = TextEditingController(
        text: widget.editingKey?.tags.join(', ') ?? '');
    _notesController = TextEditingController(text: widget.editingKey?.notes ?? '');

    if (widget.editingKey != null) {
      _selectedPlatform = widget.editingKey!.platformType;
      _isCustomPlatform = widget.editingKey!.platformType == PlatformType.custom;
      _expiryDate = widget.editingKey!.expiryDate;
      _obscureKeyValue = false; // 编辑模式下默认显示密钥值
    } else {
      _isCustomPlatform = true;
      _obscureKeyValue = true; // 添加模式下默认隐藏密钥值
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _managementUrlController.dispose();
    _apiEndpointController.dispose();
    _keyValueController.dispose();
    _tagsController.dispose();
    _notesController.dispose();
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
          // 在非编辑模式下，切换供应商时自动更新名称
          // 在编辑模式下，如果名称是空的或者是之前的默认名称，则更新
          if (!_isEditMode) {
            _nameController.text = preset.defaultName ?? '';
          } else {
            // 编辑模式下，如果名称为空或者是之前的默认名称，则更新
            final previousPreset = _selectedPlatform != null 
                ? PlatformPresets.getPreset(_selectedPlatform!) 
                : null;
            if (_nameController.text.isEmpty || 
                (previousPreset != null && _nameController.text == previousPreset.defaultName)) {
              _nameController.text = preset.defaultName ?? '';
            }
          }
          if (preset.managementUrl != null) {
            _managementUrlController.text = preset.managementUrl!;
          }
          if (preset.apiEndpoint != null) {
            _apiEndpointController.text = preset.apiEndpoint!;
          }
        }
      } else {
        // 选择自定义平台时，清空预设信息（保留用户已输入的内容）
        if (!_isEditMode) {
          if (_nameController.text.isEmpty) {
            _nameController.text = '';
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 800),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Icon(
                  _isEditMode ? Icons.edit : Icons.add_circle_outline,
                  size: 28,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isEditMode ? '编辑密钥' : '添加密钥',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 24),
            // 表单内容
            Flexible(
              child: SingleChildScrollView(
                // ⚠️ 移除 Form，使用普通 Column，避免验证导致的重建
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      // 供应商选择（分类选项卡）
                      PlatformCategoryTabs(
                        selectedPlatform: _selectedPlatform,
                        onPlatformChanged: (platform) {
                          if (platform != null) {
                            _selectPlatform(platform);
                          }
                        },
                      ),
                      const SizedBox(height: 24),

                      // 密钥名称
                      ImeSafeTextField(
                        controller: _nameController,
                        labelText: '密钥名称 *',
                        hintText: '请输入密钥名称',
                        prefixIcon: const Icon(Icons.label_outline, size: 20),
                        // ⚠️ 移除 maxLength 和 validator，避免重建
                        // maxLength: AppConstants.maxNameLength,
                        isDark: isDark,
                        // validator 已在 ImeSafeTextField 中移除
                      ),
                      const SizedBox(height: 20),

                      // 平台类型显示（仅在选择供应商时显示）
                      if (_selectedPlatform != null && !_isCustomPlatform)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _selectedPlatform!.color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _selectedPlatform!.color.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              PlatformIconService.buildIcon(
                                platform: _selectedPlatform!,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '已选择: ${_selectedPlatform!.value}',
                                style: TextStyle(
                                  color: _selectedPlatform!.color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_selectedPlatform != null && !_isCustomPlatform)
                        const SizedBox(height: 20),

                      // 管理地址
                      TextField(
                        controller: _managementUrlController,
                        decoration: MacOSInputDecoration.build(
                          labelText: '管理地址',
                          hintText: 'https://example.com',
                          prefixIcon: const Icon(Icons.link, size: 20),
                          isDark: isDark,
                        ),
                        keyboardType: TextInputType.url,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                      ),
                      const SizedBox(height: 20),

                      // API地址
                      TextField(
                        controller: _apiEndpointController,
                        decoration: MacOSInputDecoration.build(
                          labelText: 'API地址',
                          hintText: 'https://api.example.com',
                          prefixIcon: const Icon(Icons.api, size: 20),
                          isDark: isDark,
                        ),
                        keyboardType: TextInputType.url,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                      ),
                      const SizedBox(height: 20),

                      // 密钥值
                      TextField(
                        controller: _keyValueController,
                        decoration: MacOSInputDecoration.build(
                          labelText: '密钥值 *',
                          hintText: '请输入密钥值',
                          prefixIcon: const Icon(Icons.key, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureKeyValue ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureKeyValue = !_obscureKeyValue;
                              });
                            },
                            tooltip: _obscureKeyValue ? '显示' : '隐藏',
                          ),
                          isDark: isDark,
                        ),
                        obscureText: _obscureKeyValue,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                      ),
                      const SizedBox(height: 20),

                      // 过期日期和标签（同一行）
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _selectExpiryDate(context),
                              child: InputDecorator(
                                decoration: MacOSInputDecoration.build(
                                  labelText: '过期日期',
                                  prefixIcon: const Icon(Icons.calendar_today, size: 20),
                                  isDark: isDark,
                                ),
                                child: Text(
                                  _expiryDate != null
                                      ? DateFormat('yyyy-MM-dd').format(_expiryDate!)
                                      : '选择日期（可选）',
                                  style: TextStyle(
                                    color: _expiryDate != null
                                        ? Theme.of(context).textTheme.bodyLarge?.color
                                        : Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ImeSafeTextField(
                              controller: _tagsController,
                              labelText: '标签',
                              hintText: '多个标签用逗号分隔',
                              prefixIcon: const Icon(Icons.local_offer, size: 20),
                              maxLength: 200,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 备注
                      TextField(
                        controller: _notesController,
                        decoration: MacOSInputDecoration.build(
                          labelText: '备注',
                          hintText: '请输入备注信息',
                          prefixIcon: const Icon(Icons.notes, size: 20),
                          isDark: isDark,
                        ).copyWith(
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                        enableSuggestions: false,
                        autocorrect: false,
                        enableIMEPersonalizedLearning: false,
                      ),
                    ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 底部操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                  child: Text(_isEditMode ? '保存' : '添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建平台标签
  Widget _buildPlatformChip(
    PlatformType platform, {
    String? label,
    required bool isSelected,
  }) {
    final displayLabel = label ?? platform.value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlatformIconService.buildIcon(
            platform: platform,
            size: 18,
            color: isSelected ? Colors.white : null,
          ),
          const SizedBox(width: 6),
          Text(displayLabel),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          _selectPlatform(platform);
        }
      },
      selectedColor: platform.color,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Future<void> _selectExpiryDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now,
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && picked != _expiryDate) {
      setState(() {
        _expiryDate = picked;
      });
    }
  }

  void _handleSubmit() {
    // ⚠️ 移除 Form 验证，改用手动检查必填字段和长度

    // 检查必填字段
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入密钥名称')),
      );
      return;
    }
    if (_keyValueController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入密钥值')),
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
    if (_keyValueController.text.trim().length > AppConstants.maxKeyValueLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('密钥值不能超过 ${AppConstants.maxKeyValueLength} 个字符')),
      );
      return;
    }
    if (_notesController.text.trim().length > AppConstants.maxNotesLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备注不能超过 ${AppConstants.maxNotesLength} 个字符')),
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
      updatedAt: now,
      isFavorite: widget.editingKey?.isFavorite ?? false,
    );

    widget.onSubmit(key);
    Navigator.of(context).pop();
  }
}
