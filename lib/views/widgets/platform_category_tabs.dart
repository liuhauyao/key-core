import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:ui';
import '../../models/platform_type.dart';
import '../../models/platform_category.dart';
import '../../utils/platform_presets.dart';
import '../../utils/liquid_glass_decoration.dart';
import '../../utils/platform_icon_service.dart';
import '../../utils/app_localizations.dart';

/// 平台分类选项卡组件
class PlatformCategoryTabs extends StatefulWidget {
  final PlatformType? selectedPlatform;
  final ValueChanged<PlatformType?> onPlatformChanged;
  final List<PlatformType>? usedPlatforms; // 用户使用过的平台

  const PlatformCategoryTabs({
    super.key,
    this.selectedPlatform,
    required this.onPlatformChanged,
    this.usedPlatforms,
  });

  @override
  State<PlatformCategoryTabs> createState() => _PlatformCategoryTabsState();
}

class _PlatformCategoryTabsState extends State<PlatformCategoryTabs> {
  PlatformCategory _selectedCategory = PlatformCategory.popular;

  List<PlatformType> _getDisplayPlatforms() {
    final categoryPlatforms = PlatformCategoryManager.getPlatformsByCategory(_selectedCategory);
    
    // 如果是常用分类，优先显示用户使用过的平台
    if (_selectedCategory == PlatformCategory.popular && widget.usedPlatforms != null) {
      final used = widget.usedPlatforms!.where((p) => categoryPlatforms.contains(p)).toList();
      final unused = categoryPlatforms.where((p) => !used.contains(p)).toList();
      return [...used, ...unused];
    }
    
    return categoryPlatforms;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadTheme = ShadTheme.of(context);
    final displayPlatforms = _getDisplayPlatforms();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 选项卡栏 - 使用 AppSwitcher 样式，居中显示
        Center(
          child: Container(
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
          ),
        ),
        const SizedBox(height: 12),
        // 平台选择区域 - 去掉边框和背景
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // 自定义选项
            _buildPlatformChip(
              PlatformType.custom,
              label: AppLocalizations.of(context)?.custom ?? '自定义',
              isSelected: widget.selectedPlatform == PlatformType.custom,
            ),
            // 分类下的平台
            ...displayPlatforms.map((platform) {
              return _buildPlatformChip(
                platform,
                isSelected: widget.selectedPlatform == platform,
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildPlatformChip(
    PlatformType platform, {
    String? label,
    required bool isSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayLabel = label ?? platform.value;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isSelected) {
            widget.onPlatformChanged(null);
          } else {
            widget.onPlatformChanged(platform);
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
}

