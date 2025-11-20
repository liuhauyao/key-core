import 'package:flutter/material.dart';
import 'platform_type.dart';
import '../config/provider_config.dart';
import '../utils/app_localizations.dart';

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
        // 常用平台：OpenAI, Anthropic, DeepSeek, 智谱AI, 通义千问, Gemini, Mistral, Kimi, 零一万物, GitHub Copilot
        return [
          PlatformType.openAI,
          PlatformType.anthropic,
          PlatformType.deepSeek,
          PlatformType.zhipu,
          PlatformType.qwen,
          PlatformType.openRouter,
          PlatformType.gemini,
          PlatformType.mistral,
          PlatformType.kimi,
          PlatformType.zeroOne,
          PlatformType.githubCopilot,
        ];
      case PlatformCategory.llm:
        // 大语言模型提供商
        return [
          PlatformType.openAI,
          PlatformType.anthropic,
          PlatformType.google,
          PlatformType.gemini,
          PlatformType.deepSeek,
          PlatformType.minimax,
          PlatformType.zhipu,
          PlatformType.bailian,
          PlatformType.baidu,
          PlatformType.wenxin,
          PlatformType.qwen,
          PlatformType.openRouter,
          PlatformType.huggingFace,
          PlatformType.mistral,
          PlatformType.cohere,
          PlatformType.xai,
          PlatformType.ollama,
          PlatformType.moonshot,
          PlatformType.zeroOne,
          PlatformType.baichuan,
          PlatformType.kimi,
          PlatformType.nova,
        ];
      case PlatformCategory.cloud:
        // 云服务平台
        return [
          PlatformType.azureOpenAI,
          PlatformType.aws,
          PlatformType.volcengine,
          PlatformType.tencent,
          PlatformType.alibaba,
        ];
      case PlatformCategory.tools:
        // AI工具平台
        return [
          PlatformType.n8n,
          PlatformType.dify,
          PlatformType.openRouter,
          PlatformType.huggingFace,
          PlatformType.supabase,
          PlatformType.notion,
          PlatformType.ollama,
          PlatformType.github,
          PlatformType.githubCopilot,
          PlatformType.gitee,
          PlatformType.coze,
          PlatformType.figma,
          PlatformType.v0,
        ];
      case PlatformCategory.vector:
        // 其他平台
        return [
          PlatformType.qdrant,
          PlatformType.pinecone,
          PlatformType.weaviate,
        ];
      case PlatformCategory.claudeCode:
        // ClaudeCode 支持的平台
        return ProviderConfig.supportedClaudeCodePlatforms;
      case PlatformCategory.codex:
        // Codex 支持的平台
        return ProviderConfig.supportedCodexPlatforms;
      case PlatformCategory.custom:
        return [PlatformType.custom];
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

