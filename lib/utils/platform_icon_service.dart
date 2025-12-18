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

  /// 获取平台图标文件名
  static String? getIconFileName(PlatformType platform) {
    if (_iconCache == null) {
      // 如果还未加载，返回 null（使用 Material Icon 作为 fallback）
      return null;
    }
    return _iconCache![platform.id];
  }

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
