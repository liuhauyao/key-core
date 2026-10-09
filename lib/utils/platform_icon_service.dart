import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/platform_type.dart';
import '../services/cloud_config_service.dart';
import '../services/platform_registry.dart';

/// 平台图标服务
/// 从配置文件加载图标信息，完全依赖配置文件，无硬编码
class PlatformIconService {
  static final CloudConfigService _configService = CloudConfigService();
  static Map<String, String>? _iconCache; // platformType -> icon filename

  /// 初始化图标缓存
  static Future<void> init({bool forceRefresh = false}) async {
    await _configService.init();
    await _loadIcons(forceRefresh: forceRefresh);
  }

  /// 加载图标配置
  static Future<void> _loadIcons({bool forceRefresh = false}) async {
    try {
      final configData = await _configService.getConfigData(forceRefresh: forceRefresh);
      if (configData != null && configData.providers.isNotEmpty) {
        _iconCache = {};
        int iconCount = 0;
        for (final provider in configData.providers) {
          if (provider.icon != null && provider.icon!.isNotEmpty) {
            _iconCache![provider.platformType] = provider.icon!;
            iconCount++;
          }
        }
        print('PlatformIconService: 加载完成 - 配置文件供应商总数: ${configData.providers.length}, 成功加载图标: $iconCount');
      }
    } catch (e) {
      print('PlatformIconService: 加载图标配置失败: $e');
      _iconCache = {};
    }
  }

  /// 配置文件（app_config.json 的 providers[].icon）里没有 logo 的平台的默认 logo。
  ///
  /// 配置中的 icon 始终优先；这里只兜底两类缺口（ui_redesign_plan.md §4.6.3）：
  /// - 内置平台 id 与配置的 platformType 对不上（google ↔ gemini、kimi ↔ moonshot）或配置里没有该平台；
  /// - 配置里有该平台但没写 icon（katCoder / bailing / dmxapi / packycode）。
  /// 放在这里而不是改 app_config.json：该文件由供应商预设工作流维护，避免冲突，也不会多出预设条目。
  static const Map<String, String> builtinIconFallbacks = {
    'google': 'gemini-color.svg',
    'kimi': 'kimi-color.svg',
    'qwen': 'qwen-color.svg',
    'wenxin': 'wenxin-color.svg',
    'coze': 'coze.svg',
    'katCoder': 'kwaikat.svg',
    'bailing': 'bailing-color.png',
    'dmxapi': 'dmxapi-color.svg',
    'packycode': 'packycode.svg',
  };

  /// 获取平台图标文件名（配置优先，其次 [builtinIconFallbacks]；都没有返回 null）
  static String? getIconFileName(PlatformType platform) {
    final fromConfig = _iconCache?[platform.id];
    if (fromConfig != null && fromConfig.isNotEmpty) return fromConfig;
    return builtinIconFallbacks[platform.id];
  }

  /// 是否只能走回退（首字 / Material 图标）：只允许自定义平台出现这种情况。
  static bool hasBrandLogo(PlatformType platform, {String? customIconFileName}) =>
      (customIconFileName != null && customIconFileName.isNotEmpty) || getIconFileName(platform) != null;

  /// 获取平台图标路径（相对于assets目录）
  static String? getIconAssetPath(PlatformType platform) {
    final iconName = getIconFileName(platform);
    if (iconName == null) return null;
    return 'assets/icons/platforms/$iconName';
  }

  /// 构建平台图标Widget
  /// 优先使用自定义图标文件名，其次根据平台ID从配置文件加载图标，最后使用Material Icon作为fallback
  static Widget buildIcon({
    required PlatformType platform,
    String? customIconFileName,
    double size = 24,
    Color? color,
    bool useBrandLogo = true,
  }) {
    // 优先使用自定义图标（数据库存储的图标）
    if (customIconFileName != null && customIconFileName.isNotEmpty) {
      final customAssetPath = 'assets/icons/platforms/$customIconFileName';
      if (customAssetPath.endsWith('.svg')) {
        return SvgPicture.asset(
          customAssetPath,
          width: size,
          height: size,
          allowDrawingOutsideViewBox: true,
          placeholderBuilder: (context) => _buildPlatformTemplateIcon(platform, size, color, useBrandLogo),
        );
      } else {
        return Image.asset(
          customAssetPath,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) {
            // 如果自定义图标加载失败，回退到平台模板图标
            return _buildPlatformTemplateIcon(platform, size, color, useBrandLogo);
          },
        );
      }
    }

    // 如果数据库中没有自定义图标，根据平台ID从配置文件加载
    return _buildPlatformTemplateIcon(platform, size, color, useBrandLogo);
  }

  /// 构建平台模板图标Widget
  static Widget _buildPlatformTemplateIcon(
    PlatformType platform,
    double size,
    Color? color,
    bool useBrandLogo,
  ) {
    if (useBrandLogo) {
      final assetPath = getIconAssetPath(platform);
      if (assetPath != null) {
        // SVG图片
        if (assetPath.endsWith('.svg')) {
          return SvgPicture.asset(
            assetPath,
            width: size,
            height: size,
            // 所有图标都显示原始颜色，不使用 colorFilter
            allowDrawingOutsideViewBox: true,
            placeholderBuilder: (context) => Icon(
              platform.icon,
              size: size,
              color: color ?? platform.color,
            ),
          );
        } else {
          // PNG图片
          return Image.asset(
            assetPath,
            width: size,
            height: size,
            errorBuilder: (context, error, stackTrace) {
              // 如果图片加载失败，使用Material Icon
              return Icon(
                platform.icon,
                size: size,
                color: color ?? platform.color,
              );
            },
          );
        }
      }
    }

    // 使用Material Icon作为fallback
    return Icon(
      platform.icon,
      size: size,
      color: color ?? platform.color,
    );
  }
}
