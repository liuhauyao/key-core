import 'package:flutter/material.dart';
import 'platform_type.dart';
import '../config/provider_config.dart';
import '../utils/app_localizations.dart';
import '../services/platform_registry.dart';
import '../services/cloud_config_service.dart';

/// 平台分类枚举
enum PlatformCategory {
  popular(icon: ''),
  claudeCode(icon: ''),
  codex(icon: ''),
  llm(icon: ''),
  cloud(icon: ''),
  tools(icon: ''),
  vector(icon: ''),
  custom(icon: '');

  const PlatformCategory({
    required this.icon,
  });

  final String icon;
  
  String getValue(BuildContext? context) {
    final localizations = context != null ? AppLocalizations.of(context) : null;
    switch (this) {
      case PlatformCategory.popular:
        return localizations?.categoryPopular ?? '常用';
      case PlatformCategory.claudeCode:
        return localizations?.categoryClaudeCode ?? 'ClaudeCode';
      case PlatformCategory.codex:
        return localizations?.categoryCodex ?? 'Codex';
      case PlatformCategory.llm:
        return localizations?.categoryLlm ?? '大语言模型';
      case PlatformCategory.cloud:
        return localizations?.categoryCloud ?? '云服务';
      case PlatformCategory.tools:
        return localizations?.categoryTools ?? '工具';
      case PlatformCategory.vector:
        return localizations?.categoryVector ?? '其他';
      case PlatformCategory.custom:
        return localizations?.custom ?? '自定义';
    }
  }
}

/// 平台分类管理
class PlatformCategoryManager {
  /// 获取分类下的平台列表
  static List<PlatformType> getPlatformsByCategory(PlatformCategory category) {
    switch (category) {
      case PlatformCategory.popular:
        // 常用平台：硬编码 + 配置文件中标记为 popular 的所有平台（内置和动态）
        final popularIds = [
          'openAI',
          'anthropic',
          'deepSeek',
          'zhipu',
          'qwen',
          'openRouter',
          'gemini',
          'mistral',
          'kimi',
          'zeroOne',
          'githubCopilot',
        ];
        final platforms = popularIds
            .map((id) => PlatformRegistry.get(id))
            .where((p) => p != null)
            .cast<PlatformType>()
            .toList();

        // 添加配置文件中标记为 popular 的所有平台（内置平台和动态平台）
        final configPopularPlatforms = PlatformRegistry.getPlatformsByCategory('popular');
        for (var platform in configPopularPlatforms) {
          if (!platforms.contains(platform)) {
            platforms.add(platform);
          }
        }

        return platforms;
      case PlatformCategory.llm:
        // 大语言模型提供商
        final llmIds = [
          'openAI',
          'anthropic',
          'google',
          'gemini',
          'deepSeek',
          'minimax',
          'zhipu',
          'bailian',
          'baidu',
          'wenxin',
          'qwen',
          'openRouter',
          'huggingFace',
          'mistral',
          'cohere',
          'xai',
          'ollama',
          'moonshot',
          'zeroOne',
          'baichuan',
          'kimi',
          'nova',
        ];
        return llmIds
            .map((id) => PlatformRegistry.get(id))
            .where((p) => p != null)
            .cast<PlatformType>()
            .toList();
      case PlatformCategory.cloud:
        // 云服务平台
        final cloudIds = [
          'azureOpenAI',
          'aws',
          'volcengine',
          'tencent',
          'alibaba',
        ];
        return cloudIds
            .map((id) => PlatformRegistry.get(id))
            .where((p) => p != null)
            .cast<PlatformType>()
            .toList();
      case PlatformCategory.tools:
        // AI工具平台
        final toolsIds = [
          'n8n',
          'dify',
          'openRouter',
          'huggingFace',
          'supabase',
          'notion',
          'ollama',
          'github',
          'githubCopilot',
          'gitee',
          'coze',
          'figma',
          'v0',
        ];
        
        // 从 PlatformRegistry 获取内置平台实例
        final platforms = toolsIds
            .map((id) => PlatformRegistry.get(id))
            .where((p) => p != null)
            .cast<PlatformType>()
            .toList();
        
        // 添加云端配置中 categories 包含 "tools" 的动态平台
        final dynamicToolsPlatforms = PlatformRegistry.getDynamicPlatformsByCategory('tools');
        platforms.addAll(dynamicToolsPlatforms);
        
        return platforms;
      case PlatformCategory.vector:
        // 其他平台
        final vectorIds = [
          'qdrant',
          'pinecone',
          'weaviate',
        ];
        return vectorIds
            .map((id) => PlatformRegistry.get(id))
            .where((p) => p != null)
            .cast<PlatformType>()
            .toList();
      case PlatformCategory.claudeCode:
        // ClaudeCode 支持的平台
        return ProviderConfig.supportedClaudeCodePlatforms;
      case PlatformCategory.codex:
        // Codex 支持的平台
        return ProviderConfig.supportedCodexPlatforms;
      case PlatformCategory.custom:
        final customPlatform = PlatformRegistry.get('custom');
        return customPlatform != null ? [customPlatform] : [];
    }
  }

  /// 获取平台所属的分类
  static List<PlatformCategory> getCategoriesForPlatform(PlatformType platform) {
    final categories = <PlatformCategory>[];
    
    if (getPlatformsByCategory(PlatformCategory.popular).contains(platform)) {
      categories.add(PlatformCategory.popular);
    }
    if (getPlatformsByCategory(PlatformCategory.claudeCode).contains(platform)) {
      categories.add(PlatformCategory.claudeCode);
    }
    if (getPlatformsByCategory(PlatformCategory.codex).contains(platform)) {
      categories.add(PlatformCategory.codex);
    }
    if (getPlatformsByCategory(PlatformCategory.llm).contains(platform)) {
      categories.add(PlatformCategory.llm);
    }
    if (getPlatformsByCategory(PlatformCategory.cloud).contains(platform)) {
      categories.add(PlatformCategory.cloud);
    }
    if (getPlatformsByCategory(PlatformCategory.tools).contains(platform)) {
      categories.add(PlatformCategory.tools);
    }
    if (getPlatformsByCategory(PlatformCategory.vector).contains(platform)) {
      categories.add(PlatformCategory.vector);
    }
    if (platform == PlatformType.custom) {
      categories.add(PlatformCategory.custom);
    }
    
    return categories.isEmpty ? [PlatformCategory.custom] : categories;
  }

  /// 获取所有分类（排除自定义）
  static List<PlatformCategory> get allCategories {
    return PlatformCategory.values.where((c) => c != PlatformCategory.custom).toList();
  }
}

