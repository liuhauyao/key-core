import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/platform_type.dart';

/// 平台图标辅助类
/// 支持使用品牌logo图片或Material Icons作为fallback
class PlatformIconHelper {
  /// 获取平台图标路径（相对于assets目录）
  static String? getIconAssetPath(PlatformType platform) {
    final iconName = _getIconFileName(platform);
    if (iconName == null) return null;
    return 'assets/icons/platforms/$iconName';
  }

  /// 获取图标文件名（匹配实际下载的文件名）
  static String? _getIconFileName(PlatformType platform) {
    switch (platform) {
      case PlatformType.openAI:
        return 'openai.svg';
      case PlatformType.anthropic:
        return 'anthropic.svg';
      case PlatformType.google:
        return 'google-color.svg';
      case PlatformType.azureOpenAI:
        return 'microsoft-color.svg';
      case PlatformType.aws:
        return 'aws-color.svg';
      case PlatformType.minimax:
        return 'minimax-color.svg';
      case PlatformType.deepSeek:
        return 'deepseek-color.svg';
      case PlatformType.siliconFlow:
        return 'siliconcloud-color.svg';
      case PlatformType.zhipu:
        return 'zhipu-color.svg';
      case PlatformType.bailian:
        return 'bailian-color.svg';
      case PlatformType.baidu:
        return 'baiducloud-color.svg';
      case PlatformType.qwen:
        return 'qwen-color.svg';
      case PlatformType.n8n:
        return 'n8n-color.svg';
      case PlatformType.dify:
        return 'dify-color.svg';
      case PlatformType.openRouter:
        return 'openrouter.svg';
      case PlatformType.huggingFace:
        return 'huggingface-color.svg';
      case PlatformType.qdrant:
        return 'qdrant-icon.svg';
      case PlatformType.volcengine:
        return 'volcengine-color.svg';
      case PlatformType.mistral:
        return 'mistral-color.svg';
      case PlatformType.cohere:
        return 'cohere-color.svg';
      case PlatformType.perplexity:
        return 'perplexity-color.svg';
      case PlatformType.gemini:
        return 'gemini-color.svg';
      case PlatformType.xai:
        return 'xai.svg';
      case PlatformType.ollama:
        return 'ollama.svg';
      case PlatformType.moonshot:
        return 'moonshot.svg';
      case PlatformType.zeroOne:
        return 'yi-color.svg';
      case PlatformType.baichuan:
        return 'baichuan-color.svg';
      case PlatformType.wenxin:
        return 'wenxin-color.svg';
      case PlatformType.kimi:
        return 'kimi-color.svg';
      case PlatformType.nova:
        return 'nova-color.svg';
      case PlatformType.tencent:
        return 'tencentcloud-color.svg';
      case PlatformType.alibaba:
        return 'alibabacloud-color.svg';
      case PlatformType.pinecone:
        return 'pinecone-icon.svg';
      case PlatformType.weaviate:
        return 'Weaviate-icon.svg'; // 注意：文件名首字母大写
      case PlatformType.supabase:
        return 'supabase-icon.svg';
      case PlatformType.notion:
        return 'notion.svg';
      case PlatformType.bytedance:
        return 'bytedance-color.svg';
      // ClaudeCode 专用供应商
      case PlatformType.zai:
        return 'zai.svg';
      case PlatformType.longcat:
        return 'longcat-color.svg';
      case PlatformType.modelScope:
        return 'modelscope-color.svg';
      case PlatformType.aihubmix:
        return 'aihubmix-color.svg';
      // 工具平台
      case PlatformType.github:
        return 'github.svg';
      case PlatformType.githubCopilot:
        return 'githubcopilot.svg';
      case PlatformType.gitee:
        return 'giteeai.svg';
      case PlatformType.anyrouter:
        return 'anyrouter-color.svg';
      case PlatformType.coze:
        return 'coze.svg';
      case PlatformType.figma:
        return 'figma-color.svg';
      case PlatformType.v0:
        return 'v0.svg';
      // 以下供应商使用 Material Icon，没有品牌 logo
      case PlatformType.katCoder:
      case PlatformType.bailing:
      case PlatformType.dmxapi:
      case PlatformType.packycode:
        return null; // 使用 Material Icon 作为 fallback
      case PlatformType.custom:
        return null;
    }
  }

  /// 构建平台图标Widget
  /// 优先使用品牌logo，如果不存在则使用Material Icon作为fallback
  static Widget buildIcon({
    required PlatformType platform,
    double size = 24,
    Color? color,
    bool useBrandLogo = true,
  }) {
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

  /// 判断是否为彩色图标（带-color后缀的通常是彩色图标）
  static bool _isColorIcon(String assetPath) {
    return assetPath.contains('-color');
  }
}

