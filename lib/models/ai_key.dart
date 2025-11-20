import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'platform_type.dart';

/// AI密钥数据模型
class AIKey extends Equatable {
  final int? id;
  final String name;
  final String platform;
  final PlatformType platformType;
  final String? managementUrl;
  final String? apiEndpoint;
  final String keyValue;
  final String? keyNonce;
  final DateTime? expiryDate;
  final List<String> tags;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final bool isFavorite;
  final String? icon; // 图标路径（SVG文件名）
  
  // ClaudeCode 相关配置
  final bool enableClaudeCode;
  final String? claudeCodeApiEndpoint;
  final String? claudeCodeModel; // 主模型 (ANTHROPIC_MODEL)
  final String? claudeCodeHaikuModel; // Haiku 模型 (ANTHROPIC_DEFAULT_HAIKU_MODEL)
  final String? claudeCodeSonnetModel; // Sonnet 模型 (ANTHROPIC_DEFAULT_SONNET_MODEL)
  final String? claudeCodeOpusModel; // Opus 模型 (ANTHROPIC_DEFAULT_OPUS_MODEL)
  final String? claudeCodeBaseUrl;
  
  // Codex 相关配置
  final bool enableCodex;
  final String? codexApiEndpoint;
  final String? codexModel;
  final String? codexBaseUrl;
  final Map<String, dynamic>? codexConfig;

  // Gemini 相关配置
  final bool enableGemini;
  final String? geminiApiEndpoint;
  final String? geminiModel;
  final String? geminiBaseUrl;

  const AIKey({
    this.id,
    required this.name,
    required this.platform,
    required this.platformType,
    this.managementUrl,
    this.apiEndpoint,
    required this.keyValue,
    this.keyNonce,
    this.expiryDate,
    required this.tags,
    this.notes,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.lastUsedAt,
    this.isFavorite = false,
    this.icon,
    this.enableClaudeCode = false,
    this.claudeCodeApiEndpoint,
    this.claudeCodeModel,
    this.claudeCodeHaikuModel,
    this.claudeCodeSonnetModel,
    this.claudeCodeOpusModel,
    this.claudeCodeBaseUrl,
    this.enableCodex = false,
    this.codexApiEndpoint,
    this.codexModel,
    this.codexBaseUrl,
    this.codexConfig,
    this.enableGemini = false,
    this.geminiApiEndpoint,
    this.geminiModel,
    this.geminiBaseUrl,
  });

  AIKey copyWith({
    int? id,
    String? name,
    String? platform,
    PlatformType? platformType,
    String? managementUrl,
    String? apiEndpoint,
    String? keyValue,
    String? keyNonce,
    DateTime? expiryDate,
    List<String>? tags,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    bool? isFavorite,
    String? icon,
    bool? enableClaudeCode,
    String? claudeCodeApiEndpoint,
    String? claudeCodeModel,
    String? claudeCodeHaikuModel,
    String? claudeCodeSonnetModel,
    String? claudeCodeOpusModel,
    String? claudeCodeBaseUrl,
    bool? enableCodex,
    String? codexApiEndpoint,
    String? codexModel,
    String? codexBaseUrl,
    Map<String, dynamic>? codexConfig,
    bool? enableGemini,
    String? geminiApiEndpoint,
    String? geminiModel,
    String? geminiBaseUrl,
  }) {
    return AIKey(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      platformType: platformType ?? this.platformType,
      managementUrl: managementUrl ?? this.managementUrl,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      keyValue: keyValue ?? this.keyValue,
      keyNonce: keyNonce ?? this.keyNonce,
      expiryDate: expiryDate ?? this.expiryDate,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      icon: icon ?? this.icon,
      enableClaudeCode: enableClaudeCode ?? this.enableClaudeCode,
      claudeCodeApiEndpoint: claudeCodeApiEndpoint ?? this.claudeCodeApiEndpoint,
      claudeCodeModel: claudeCodeModel ?? this.claudeCodeModel,
      claudeCodeHaikuModel: claudeCodeHaikuModel ?? this.claudeCodeHaikuModel,
      claudeCodeSonnetModel: claudeCodeSonnetModel ?? this.claudeCodeSonnetModel,
      claudeCodeOpusModel: claudeCodeOpusModel ?? this.claudeCodeOpusModel,
      claudeCodeBaseUrl: claudeCodeBaseUrl ?? this.claudeCodeBaseUrl,
      enableCodex: enableCodex ?? this.enableCodex,
      codexApiEndpoint: codexApiEndpoint ?? this.codexApiEndpoint,
      codexModel: codexModel ?? this.codexModel,
      codexBaseUrl: codexBaseUrl ?? this.codexBaseUrl,
      codexConfig: codexConfig ?? this.codexConfig,
      enableGemini: enableGemini ?? this.enableGemini,
      geminiApiEndpoint: geminiApiEndpoint ?? this.geminiApiEndpoint,
      geminiModel: geminiModel ?? this.geminiModel,
      geminiBaseUrl: geminiBaseUrl ?? this.geminiBaseUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'platform': platform,
      'platform_type': platformType.index,
      'management_url': managementUrl,
      'api_endpoint': apiEndpoint,
      'key_value': keyValue,
      'key_nonce': keyNonce,
      'expiry_date': expiryDate?.toIso8601String(),
      'tags': _serializeTags(tags),
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'is_favorite': isFavorite ? 1 : 0,
      'icon': icon,
      'enable_claude_code': enableClaudeCode ? 1 : 0,
      'claude_code_api_endpoint': claudeCodeApiEndpoint,
      'claude_code_model': claudeCodeModel,
      'claude_code_haiku_model': claudeCodeHaikuModel,
      'claude_code_sonnet_model': claudeCodeSonnetModel,
      'claude_code_opus_model': claudeCodeOpusModel,
      'claude_code_base_url': claudeCodeBaseUrl,
      'enable_codex': enableCodex ? 1 : 0,
      'codex_api_endpoint': codexApiEndpoint,
      'codex_model': codexModel,
      'codex_base_url': codexBaseUrl,
      'codex_config': codexConfig != null ? jsonEncode(codexConfig) : null,
      'enable_gemini': enableGemini ? 1 : 0,
      'gemini_api_endpoint': geminiApiEndpoint,
      'gemini_model': geminiModel,
      'gemini_base_url': geminiBaseUrl,
    };
  }

  factory AIKey.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? codexConfig;
    if (map['codex_config'] != null) {
      try {
        codexConfig = jsonDecode(map['codex_config'] as String) as Map<String, dynamic>;
      } catch (e) {
        codexConfig = null;
      }
    }
    
    return AIKey(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      platform: map['platform'] ?? '',
      platformType: PlatformType.values[map['platform_type']?.toInt() ?? 0],
      managementUrl: map['management_url'],
      apiEndpoint: map['api_endpoint'],
      keyValue: map['key_value'] ?? '',
      keyNonce: map['key_nonce'],
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'] as String)
          : null,
      tags: _deserializeTags(map['tags']),
      notes: map['notes'],
      isActive: (map['is_active']?.toInt() ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastUsedAt: map['last_used_at'] != null
          ? DateTime.parse(map['last_used_at'] as String)
          : null,
      isFavorite: (map['is_favorite']?.toInt() ?? 0) == 1,
      icon: map['icon'],
      enableClaudeCode: (map['enable_claude_code']?.toInt() ?? 0) == 1,
      claudeCodeApiEndpoint: map['claude_code_api_endpoint'],
      claudeCodeModel: map['claude_code_model'],
      claudeCodeHaikuModel: map['claude_code_haiku_model'],
      claudeCodeSonnetModel: map['claude_code_sonnet_model'],
      claudeCodeOpusModel: map['claude_code_opus_model'],
      claudeCodeBaseUrl: map['claude_code_base_url'],
      enableCodex: (map['enable_codex']?.toInt() ?? 0) == 1,
      codexApiEndpoint: map['codex_api_endpoint'],
      codexModel: map['codex_model'],
      codexBaseUrl: map['codex_base_url'],
      codexConfig: codexConfig,
      enableGemini: (map['enable_gemini']?.toInt() ?? 0) == 1,
      geminiApiEndpoint: map['gemini_api_endpoint'],
      geminiModel: map['gemini_model'],
      geminiBaseUrl: map['gemini_base_url'],
    );
  }

  static String _serializeTags(List<String> tags) {
    return tags.join(',');
  }

  static List<String> _deserializeTags(String? tagsString) {
    if (tagsString == null || tagsString.isEmpty) {
      return <String>[];
    }
    return tagsString.split(',').where((tag) => tag.isNotEmpty).toList();
  }

  String get formattedExpiryDate {
    if (expiryDate == null) return '永不过期';
    return DateFormat('yyyy-MM-dd').format(expiryDate!);
  }

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final now = DateTime.now();
    final diff = expiryDate!.difference(now).inDays;
    return diff <= 7 && diff >= 0;
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return DateTime.now().isAfter(expiryDate!);
  }

  String get statusText {
    if (isExpired) return '已过期';
    if (isExpiringSoon) return '即将过期';
    if (!isActive) return '已禁用';
    return '正常';
  }

  Color get statusColor {
    if (isExpired) return Colors.red;
    if (isExpiringSoon) return Colors.orange;
    if (!isActive) return Colors.grey;
    return Colors.green;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        platform,
        platformType,
        managementUrl,
        apiEndpoint,
        keyValue,
        keyNonce,
        expiryDate,
        tags,
        notes,
        isActive,
        createdAt,
        updatedAt,
        lastUsedAt,
        isFavorite,
        icon,
        enableClaudeCode,
        claudeCodeApiEndpoint,
        claudeCodeModel,
        claudeCodeHaikuModel,
        claudeCodeSonnetModel,
        claudeCodeOpusModel,
        claudeCodeBaseUrl,
        enableCodex,
        codexApiEndpoint,
        codexModel,
        codexBaseUrl,
        codexConfig,
        enableGemini,
        geminiApiEndpoint,
        geminiModel,
        geminiBaseUrl,
      ];
}
