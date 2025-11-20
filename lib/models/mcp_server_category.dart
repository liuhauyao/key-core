import 'package:flutter/material.dart';
import '../utils/app_localizations.dart';

/// MCP 服务分类枚举
enum McpServerCategory {
  popular(icon: ''),
  database(icon: ''),
  search(icon: ''),
  development(icon: ''),
  cloud(icon: ''),
  ai(icon: ''),
  automation(icon: ''),
  custom(icon: '');

  const McpServerCategory({
    required this.icon,
  });

  final String icon;
  
  String getValue(BuildContext? context) {
    final localizations = context != null ? AppLocalizations.of(context) : null;
    switch (this) {
      case McpServerCategory.popular:
        return localizations?.categoryPopular ?? '常用';
      case McpServerCategory.database:
        return localizations?.mcpCategoryDatabase ?? '数据库';
      case McpServerCategory.search:
        return localizations?.mcpCategorySearch ?? '搜索';
      case McpServerCategory.development:
        return localizations?.mcpCategoryDevelopment ?? '开发工具';
      case McpServerCategory.cloud:
        return localizations?.mcpCategoryCloud ?? '云服务';
      case McpServerCategory.ai:
        return localizations?.mcpCategoryAi ?? 'AI服务';
      case McpServerCategory.automation:
        return localizations?.mcpCategoryAutomation ?? '自动化';
      case McpServerCategory.custom:
        return localizations?.custom ?? '自定义';
    }
  }
}

