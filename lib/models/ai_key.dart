import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'platform_type.dart';
import '../services/platform_registry.dart';

/// 卡片内的一把子密钥（同一供应商的多把密钥值之一）。
///
/// [value] 与 `key_value` 列同形态：明文，或以 `{` 开头、内含 nonce 的密文 JSON 字符串。
class KeyEntry extends Equatable {
  final String value;
  final String? label; // 别名（可空）
  final String? endpoint; // 该把独立的 API 地址（可空 = 跟随卡片 / 供应商默认）
  final String? notes; // 备注（可空）
  final bool validated; // 该把的独立校验状态
  final DateTime? lastUsedAt; // 该把的独立最后使用时间
  final DateTime? createdAt;

  const KeyEntry({
    required this.value,
    this.label,
    this.endpoint,
    this.notes,
    this.validated = false,
    this.lastUsedAt,
    this.createdAt,
  });

  /// 该把是否配置了独立地址（不同 plan 通常域名不同）
  bool get hasEndpoint => (endpoint ?? '').trim().isNotEmpty;

  /// 展示用域名（无自定义地址时为 null；非法地址原样返回）
  String? get endpointHost => hostOf(endpoint);

  static String? hostOf(String? raw) {
    final e = raw?.trim();
    if (e == null || e.isEmpty) return null;
    final u = Uri.tryParse(e.contains('://') ? e : 'https://$e');
    return (u != null && u.host.isNotEmpty) ? u.host : e;
  }

  /// 展示用别名：无别名时回退为「密钥 N」（[index] 从 0 起）
  String displayLabel(int index) {
    final l = label?.trim();
    return (l != null && l.isNotEmpty) ? l : '密钥 ${index + 1}';
  }

  KeyEntry copyWith({
    String? value,
    String? label,
    String? endpoint,
    String? notes,
    bool? validated,
    DateTime? lastUsedAt,
    DateTime? createdAt,
    bool clearLabel = false,
    bool clearEndpoint = false,
    bool clearNotes = false,
    bool clearLastUsedAt = false,
    bool clearCreatedAt = false,
  }) {
    return KeyEntry(
      value: value ?? this.value,
      label: clearLabel ? null : (label ?? this.label),
      endpoint: clearEndpoint ? null : (endpoint ?? this.endpoint),
      notes: clearNotes ? null : (notes ?? this.notes),
      validated: validated ?? this.validated,
      lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
      createdAt: clearCreatedAt ? null : (createdAt ?? this.createdAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
        'endpoint': endpoint,
        'notes': notes,
        'validated': validated,
        'lastUsedAt': lastUsedAt?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
      };

  factory KeyEntry.fromJson(Map<String, dynamic> m) => KeyEntry(
        value: (m['value'] ?? '').toString(),
        label: m['label']?.toString(),
        endpoint: m['endpoint']?.toString() ?? m['api_endpoint']?.toString(),
        notes: m['notes']?.toString(),
        validated: m['validated'] == true || (m['validated'] is num && (m['validated'] as num) == 1),
        lastUsedAt: _tryParseDate(m['lastUsedAt'] ?? m['last_used_at']),
        createdAt: _tryParseDate(m['createdAt'] ?? m['created_at']),
      );

  static DateTime? _tryParseDate(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  @override
  List<Object?> get props => [value, label, endpoint, notes, validated, lastUsedAt, createdAt];
}

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

  /// 子密钥列表的原始解析结果（`key_entries` 列），为空表示「单密钥」——
  /// 此时 [keyEntries] 由 [keyValue] 合成唯一一把，老数据零迁移。
  final List<KeyEntry>? keyEntriesRaw;

  /// 当前密钥下标（0 起），仅在 [keyEntriesRaw] 非空时有意义。
  final int activeKeyIndex;
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

  /// Claude Code 的供应商专属参数（JSON 列 `claude_code_config`）：
  /// - `apiKeyField`：密钥写入的 env 变量名（缺省 `ANTHROPIC_AUTH_TOKEN`）；
  /// - `env`：该供应商额外需要的 env（如 `CLAUDE_CODE_MAX_CONTEXT_TOKENS`）。
  final Map<String, dynamic>? claudeCodeConfig;
  
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

  // OpenClaw 相关配置
  final bool enableOpenclaw;
  final String? openclawBaseUrl; // OpenAI 兼容请求地址
  final String? openclawModel; // 写入 OpenClaw 配置时使用的模型

  // Claude Desktop 相关配置
  final bool enableClaudeDesktop;
  final String? claudeDesktopBaseUrl;
  final String? claudeDesktopModel; // 主模型映射（默认对应 sonnet 路由）
  final String? claudeDesktopSonnetModel; // Sonnet 路由映射到哪个上游模型
  final String? claudeDesktopHaikuModel;  // Haiku 路由映射到哪个上游模型
  final String? claudeDesktopOpusModel;   // Opus 路由映射到哪个上游模型

  /// 新工具（OpenCode / Grok Build / Hermes / Pi / MiniMax Code）的按密钥设置
  /// （JSON 列 `tool_configs`）。键为工具 id（与 `AiToolType.value` 一致），值形如
  /// `{enabled: bool, baseUrl?: String, model?: String}`；缺省字段取供应商预设。
  final Map<String, Map<String, dynamic>> toolConfigs;

  // 校验状态
  final bool isValidated; // 是否校验通过

  const AIKey({
    this.id,
    required this.name,
    required this.platform,
    required this.platformType,
    this.managementUrl,
    this.apiEndpoint,
    required this.keyValue,
    this.keyNonce,
    this.keyEntriesRaw,
    this.activeKeyIndex = 0,
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
    this.claudeCodeConfig,
    this.enableCodex = false,
    this.codexApiEndpoint,
    this.codexModel,
    this.codexBaseUrl,
    this.codexConfig,
    this.enableGemini = false,
    this.geminiApiEndpoint,
    this.geminiModel,
    this.geminiBaseUrl,
    this.enableOpenclaw = false,
    this.openclawBaseUrl,
    this.openclawModel,
    this.enableClaudeDesktop = false,
    this.claudeDesktopBaseUrl,
    this.claudeDesktopModel,
    this.claudeDesktopSonnetModel,
    this.claudeDesktopHaikuModel,
    this.claudeDesktopOpusModel,
    this.toolConfigs = const {},
    this.isValidated = false,
  });

  /// 子密钥列表（长度恒 >= 1）。无 `key_entries` 列时由 [keyValue] 合成唯一一把。
  List<KeyEntry> get keyEntries =>
      (keyEntriesRaw != null && keyEntriesRaw!.isNotEmpty)
          ? keyEntriesRaw!
          : <KeyEntry>[KeyEntry(value: keyValue)];

  /// 收敛到合法范围的当前密钥下标
  int get normalizedActiveIndex =>
      (keyEntriesRaw == null || keyEntriesRaw!.isEmpty)
          ? 0
          : activeKeyIndex.clamp(0, keyEntriesRaw!.length - 1);

  /// 当前密钥（`key_value` 镜像的那把）
  KeyEntry get activeEntry => keyEntries[normalizedActiveIndex];

  bool get hasMultipleKeys => keyEntries.length > 1;

  /// 是否有一把子密钥配置了独立地址
  bool get hasEntryEndpoints => keyEntries.any((e) => e.hasEndpoint);

  /// 第 [index] 把子密钥生效的请求地址（未配置则回退卡片级 [apiEndpoint]）
  String? endpointFor(int index) {
    final list = keyEntries;
    if (index < 0 || index >= list.length) return apiEndpoint;
    final custom = list[index].endpoint?.trim();
    return (custom != null && custom.isNotEmpty) ? custom : apiEndpoint;
  }

  /// 当前密钥生效的请求地址
  String? get activeEndpoint => endpointFor(normalizedActiveIndex);

  /// 生成「写工具配置用」的副本：把第 [index] 把子密钥的地址覆盖到各工具 base URL。
  ///
  /// 覆盖规则：
  /// - 地址只有域名（如 `https://api.acme.com`）→ 只替换该工具 base URL 的 origin，路径沿用；
  ///   这样同一把密钥给 Claude Code / Codex 用，各自仍命中正确的 `/anthropic`、`/v1` 路径。
  /// - 地址带路径（如 `https://api.acme.com/planB`）→ 原样作为该工具的 base URL。
  AIKey projectedForEntry(int? index) {
    final i = (index ?? normalizedActiveIndex).clamp(0, keyEntries.length - 1);
    final base = withActiveKeyIndex(i);
    final ep = keyEntries[i].endpoint?.trim();
    if (ep == null || ep.isEmpty) return base;
    return base.copyWith(
      apiEndpoint: ep,
      claudeCodeBaseUrl: _applyEndpointToUrl(base.claudeCodeBaseUrl, ep),
      codexBaseUrl: _applyEndpointToUrl(base.codexBaseUrl, ep),
      geminiBaseUrl: _applyEndpointToUrl(base.geminiBaseUrl, ep),
      openclawBaseUrl: _applyEndpointToUrl(base.openclawBaseUrl, ep),
      claudeDesktopBaseUrl: _applyEndpointToUrl(base.claudeDesktopBaseUrl, ep),
    );
  }

  static String _applyEndpointToUrl(String? toolUrl, String endpoint) {
    final e = endpoint.trim();
    if (e.isEmpty) return toolUrl ?? '';
    final normalized = (e.contains('://') || !e.contains('.')) ? e : 'https://$e';
    final eu = Uri.tryParse(normalized);
    final base = (toolUrl ?? '').trim();
    final hasMeaningfulPath = eu != null && eu.path.isNotEmpty && eu.path != '/';
    // 带路径 = 用户给了完整地址，原样使用；只有域名 = 只换 origin，保留工具默认路径
    if (hasMeaningfulPath) return e.replaceAll(RegExp(r'/+$'), '');
    if (eu == null || eu.host.isEmpty) return e;
    final bu = base.isEmpty ? null : Uri.tryParse(base);
    if (bu == null || !bu.hasScheme) return '${eu.scheme}://${eu.authority}';
    final query = bu.hasQuery ? '?${bu.query}' : '';
    return '${eu.scheme}://${eu.authority}${bu.path}$query';
  }

  /// 以给定子密钥列表重建卡片（`key_value` 自动镜像当前密钥）
  AIKey withKeyEntries(List<KeyEntry> entries, {int? active}) => copyWith(
        keyEntries: entries,
        activeKeyIndex: (active ?? activeKeyIndex)
            .clamp(0, entries.isEmpty ? 0 : entries.length - 1),
      );

  /// 切换当前密钥
  AIKey withActiveKeyIndex(int index) => copyWith(activeKeyIndex: index);

  /// 替换第 [index] 把子密钥
  AIKey replaceEntry(int index, KeyEntry entry) {
    final list = [...keyEntries];
    if (index < 0 || index >= list.length) return this;
    list[index] = entry;
    return copyWith(keyEntries: list);
  }

  /// 追加一把子密钥
  AIKey appendEntry(KeyEntry entry) =>
      copyWith(keyEntries: [...keyEntries, entry]);

  /// 删除第 [index] 把子密钥（至少保留一把）。
  ///
  /// 下标跟随被删元素前移的条目，保证「当前密钥」始终指着同一把：
  /// 删的是在它前面的 → 下标 -1；删的是它自己 → 向左收敛到末位。
  AIKey removeEntry(int index) {
    final list = [...keyEntries];
    if (list.length <= 1 || index < 0 || index >= list.length) return this;
    list.removeAt(index);
    final nextActive = index < activeKeyIndex
        ? activeKeyIndex - 1
        : activeKeyIndex.clamp(0, list.length - 1);
    return copyWith(keyEntries: list, activeKeyIndex: nextActive);
  }

  AIKey copyWith({
    int? id,
    String? name,
    String? platform,
    PlatformType? platformType,
    String? managementUrl,
    String? apiEndpoint,
    String? keyValue,
    String? keyNonce,
    List<KeyEntry>? keyEntries,
    int? activeKeyIndex,
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
    Map<String, dynamic>? claudeCodeConfig,
    bool? enableCodex,
    String? codexApiEndpoint,
    String? codexModel,
    String? codexBaseUrl,
    Map<String, dynamic>? codexConfig,
    bool? enableGemini,
    String? geminiApiEndpoint,
    String? geminiModel,
    String? geminiBaseUrl,
    bool? enableOpenclaw,
    String? openclawBaseUrl,
    String? openclawModel,
    bool? enableClaudeDesktop,
    String? claudeDesktopBaseUrl,
    String? claudeDesktopModel,
    String? claudeDesktopSonnetModel,
    String? claudeDesktopHaikuModel,
    String? claudeDesktopOpusModel,
    Map<String, Map<String, dynamic>>? toolConfigs,
    bool? isValidated,
  }) {
    // 子密钥是唯一写入口：传入 keyEntries / activeKeyIndex 时，
    // key_value、校验状态、最后使用时间都跟随「当前密钥」镜像。
    final nextEntries =
        (keyEntries != null && keyEntries.isNotEmpty) ? keyEntries : keyEntriesRaw;
    final nextActive = activeKeyIndex ?? this.activeKeyIndex;
    final KeyEntry? nextActiveEntry = (nextEntries != null && nextEntries.isNotEmpty)
        ? nextEntries[nextActive.clamp(0, nextEntries.length - 1)]
        : null;
    return AIKey(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      platformType: platformType ?? this.platformType,
      managementUrl: managementUrl ?? this.managementUrl,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      keyValue: nextActiveEntry != null
          ? nextActiveEntry.value
          : (keyValue ?? this.keyValue),
      keyNonce: keyNonce ?? this.keyNonce,
      keyEntriesRaw: nextEntries,
      activeKeyIndex: nextActiveEntry != null
          ? nextActive.clamp(0, nextEntries!.length - 1)
          : nextActive,
      expiryDate: expiryDate ?? this.expiryDate,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: nextActiveEntry != null
          ? nextActiveEntry.lastUsedAt
          : (lastUsedAt ?? this.lastUsedAt),
      isFavorite: isFavorite ?? this.isFavorite,
      icon: icon ?? this.icon,
      enableClaudeCode: enableClaudeCode ?? this.enableClaudeCode,
      claudeCodeApiEndpoint: claudeCodeApiEndpoint ?? this.claudeCodeApiEndpoint,
      claudeCodeModel: claudeCodeModel ?? this.claudeCodeModel,
      claudeCodeHaikuModel: claudeCodeHaikuModel ?? this.claudeCodeHaikuModel,
      claudeCodeSonnetModel: claudeCodeSonnetModel ?? this.claudeCodeSonnetModel,
      claudeCodeOpusModel: claudeCodeOpusModel ?? this.claudeCodeOpusModel,
      claudeCodeBaseUrl: claudeCodeBaseUrl ?? this.claudeCodeBaseUrl,
      claudeCodeConfig: claudeCodeConfig ?? this.claudeCodeConfig,
      enableCodex: enableCodex ?? this.enableCodex,
      codexApiEndpoint: codexApiEndpoint ?? this.codexApiEndpoint,
      codexModel: codexModel ?? this.codexModel,
      codexBaseUrl: codexBaseUrl ?? this.codexBaseUrl,
      codexConfig: codexConfig ?? this.codexConfig,
      enableGemini: enableGemini ?? this.enableGemini,
      geminiApiEndpoint: geminiApiEndpoint ?? this.geminiApiEndpoint,
      geminiModel: geminiModel ?? this.geminiModel,
      geminiBaseUrl: geminiBaseUrl ?? this.geminiBaseUrl,
      enableOpenclaw: enableOpenclaw ?? this.enableOpenclaw,
      openclawBaseUrl: openclawBaseUrl ?? this.openclawBaseUrl,
      openclawModel: openclawModel ?? this.openclawModel,
      enableClaudeDesktop: enableClaudeDesktop ?? this.enableClaudeDesktop,
      claudeDesktopBaseUrl: claudeDesktopBaseUrl ?? this.claudeDesktopBaseUrl,
      claudeDesktopModel: claudeDesktopModel ?? this.claudeDesktopModel,
      claudeDesktopSonnetModel: claudeDesktopSonnetModel ?? this.claudeDesktopSonnetModel,
      claudeDesktopHaikuModel: claudeDesktopHaikuModel ?? this.claudeDesktopHaikuModel,
      claudeDesktopOpusModel: claudeDesktopOpusModel ?? this.claudeDesktopOpusModel,
      toolConfigs: toolConfigs ?? this.toolConfigs,
      isValidated: nextActiveEntry != null
          ? nextActiveEntry.validated
          : (isValidated ?? this.isValidated),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'platform': platform,
      'platform_type': platformType.index, // 保持向后兼容
      'platform_type_id': platformType.id, // 使用平台ID作为主要标识
      'management_url': managementUrl,
      'api_endpoint': apiEndpoint,
      'key_value': keyValue,
      'key_nonce': keyNonce,
      'key_entries': (keyEntriesRaw == null || keyEntriesRaw!.isEmpty)
          ? null
          : jsonEncode({
              'active': normalizedActiveIndex,
              'items': keyEntriesRaw!.map((e) => e.toJson()).toList(),
            }),
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
      'claude_code_config': claudeCodeConfig != null ? jsonEncode(claudeCodeConfig) : null,
      'enable_codex': enableCodex ? 1 : 0,
      'codex_api_endpoint': codexApiEndpoint,
      'codex_model': codexModel,
      'codex_base_url': codexBaseUrl,
      'codex_config': codexConfig != null ? jsonEncode(codexConfig) : null,
      'enable_gemini': enableGemini ? 1 : 0,
      'gemini_api_endpoint': geminiApiEndpoint,
      'gemini_model': geminiModel,
      'gemini_base_url': geminiBaseUrl,
      'enable_openclaw': enableOpenclaw ? 1 : 0,
      'openclaw_base_url': openclawBaseUrl,
      'openclaw_model': openclawModel,
      'enable_claude_desktop': enableClaudeDesktop ? 1 : 0,
      'claude_desktop_base_url': claudeDesktopBaseUrl,
      'claude_desktop_model': claudeDesktopModel,
      'claude_desktop_sonnet_model': claudeDesktopSonnetModel,
      'claude_desktop_haiku_model': claudeDesktopHaikuModel,
      'claude_desktop_opus_model': claudeDesktopOpusModel,
      'tool_configs': toolConfigs.isEmpty ? null : jsonEncode(toolConfigs),
      'is_validated': isValidated ? 1 : 0,
    };
  }

  /// 某个新工具的按密钥设置（无则为空 Map）
  Map<String, dynamic> toolConfig(String toolId) => toolConfigs[toolId] ?? const {};

  /// 是否对某个新工具启用
  bool isToolEnabled(String toolId) => toolConfig(toolId)['enabled'] == true;

  /// 解析 `tool_configs` 列 / 导出文件中的值（字符串或 Map），无效时返回空
  static Map<String, Map<String, dynamic>> parseToolConfigs(Object? raw) {
    Object? v = raw;
    if (v is String) {
      if (v.trim().isEmpty) return const {};
      try {
        v = jsonDecode(v);
      } catch (_) {
        return const {};
      }
    }
    if (v is! Map) return const {};
    return {
      for (final e in v.entries)
        if (e.value is Map) '${e.key}': Map<String, dynamic>.from(e.value as Map),
    };
  }

  /// 解析 `key_entries` 列 / 导出文件中的值（字符串或 Map）。
  ///
  /// 返回 `null` 表示「无该列 / 无效」→ 由 `key_value` 合成唯一一把密钥。
  static (List<KeyEntry>?, int) parseKeyEntries(Object? raw) {
    Object? v = raw;
    if (v is String) {
      if (v.trim().isEmpty) return (null, 0);
      try {
        v = jsonDecode(v);
      } catch (_) {
        return (null, 0);
      }
    }
    if (v is! Map) return (null, 0);
    final itemsRaw = v['items'];
    if (itemsRaw is! List) return (null, 0);
    final items = <KeyEntry>[];
    for (final e in itemsRaw) {
      if (e is Map) items.add(KeyEntry.fromJson(Map<String, dynamic>.from(e)));
    }
    if (items.isEmpty) return (null, 0);
    final active = (v['active'] as num?)?.toInt() ?? 0;
    return (items, active.clamp(0, items.length - 1));
  }

  /// Claude Code 密钥写入的 env 变量名
  String get claudeCodeApiKeyField {
    final v = claudeCodeConfig?['apiKeyField'];
    return v is String && v.trim().isNotEmpty ? v.trim() : 'ANTHROPIC_AUTH_TOKEN';
  }

  /// Claude Code 供应商额外 env
  Map<String, String> get claudeCodeExtraEnv {
    final v = claudeCodeConfig?['env'];
    if (v is! Map) return const {};
    return {
      for (final e in v.entries)
        if (e.key.toString().trim().isNotEmpty) e.key.toString().trim(): e.value?.toString() ?? '',
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
    Map<String, dynamic>? claudeCodeConfig;
    if (map['claude_code_config'] != null) {
      try {
        claudeCodeConfig = jsonDecode(map['claude_code_config'] as String) as Map<String, dynamic>;
      } catch (e) {
        claudeCodeConfig = null;
      }
    }
    
    // 恢复平台类型：优先使用 platform_type_id，其次使用 platform 字段（平台名称），最后使用索引
    PlatformType platformType = PlatformType.custom;
    
    // 方法1：优先使用 platform_type_id（如果存在）
    if (map['platform_type_id'] != null && map['platform_type_id'].toString().isNotEmpty) {
      final platformTypeById = PlatformRegistry.get(map['platform_type_id'] as String);
      if (platformTypeById != null) {
        platformType = platformTypeById;
      }
    }
    
    // 方法2：如果 platform_type_id 不存在，使用 platform 字段（平台名称）恢复
    if (platformType == PlatformType.custom && map['platform'] != null) {
      final platformName = map['platform'] as String;
      if (platformName.isNotEmpty) {
        // 尝试通过平台ID匹配
        final platformTypeById = PlatformRegistry.get(platformName);
        if (platformTypeById != null) {
          platformType = platformTypeById;
        } else {
          // 尝试通过平台显示名称匹配
          final matchedList = PlatformRegistry.values.where((p) => p.value == platformName).toList();
          if (matchedList.isNotEmpty) {
            platformType = matchedList.first;
          } else {
            // 使用 fromString 方法（支持模糊匹配）
            try {
              final platformTypeFromString = PlatformRegistry.fromString(platformName);
              if (platformTypeFromString != PlatformType.custom) {
                platformType = platformTypeFromString;
              }
            } catch (e) {
              // 忽略错误，继续尝试索引恢复
            }
          }
        }
      }
    }
    
    // 方法3：如果都失败，尝试从索引恢复（向后兼容，但可能不准确）
    if (platformType == PlatformType.custom && map['platform_type'] != null) {
      final index = map['platform_type']?.toInt() ?? 0;
      if (index >= 0 && index < PlatformRegistry.values.length) {
        platformType = PlatformRegistry.values[index];
      }
    }
    
    // 子密钥：无 `key_entries` 列时由 `key_value` 合成唯一一把（老数据零迁移）
    final (parsedEntries, parsedActive) = parseKeyEntries(map['key_entries']);
    final entryList =
        parsedEntries ?? <KeyEntry>[KeyEntry(value: (map['key_value'] ?? '').toString())];
    final activeIdx = parsedEntries == null ? 0 : parsedActive;

    return AIKey(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      platform: map['platform'] ?? '',
      platformType: platformType,
      managementUrl: map['management_url'],
      apiEndpoint: map['api_endpoint'],
      keyValue: entryList[activeIdx].value,
      keyNonce: map['key_nonce'],
      keyEntriesRaw: parsedEntries,
      activeKeyIndex: activeIdx,
      expiryDate: map['expiry_date'] != null
          ? DateTime.parse(map['expiry_date'] as String)
          : null,
      tags: _deserializeTags(map['tags']),
      notes: map['notes'],
      isActive: (map['is_active']?.toInt() ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastUsedAt: parsedEntries != null
          ? entryList[activeIdx].lastUsedAt
          : (map['last_used_at'] != null
              ? DateTime.parse(map['last_used_at'] as String)
              : null),
      isFavorite: (map['is_favorite']?.toInt() ?? 0) == 1,
      icon: map['icon'],
      enableClaudeCode: (map['enable_claude_code']?.toInt() ?? 0) == 1,
      claudeCodeApiEndpoint: map['claude_code_api_endpoint'],
      claudeCodeModel: map['claude_code_model'],
      claudeCodeHaikuModel: map['claude_code_haiku_model'],
      claudeCodeSonnetModel: map['claude_code_sonnet_model'],
      claudeCodeOpusModel: map['claude_code_opus_model'],
      claudeCodeBaseUrl: map['claude_code_base_url'],
      claudeCodeConfig: claudeCodeConfig,
      enableCodex: (map['enable_codex']?.toInt() ?? 0) == 1,
      codexApiEndpoint: map['codex_api_endpoint'],
      codexModel: map['codex_model'],
      codexBaseUrl: map['codex_base_url'],
      codexConfig: codexConfig,
      enableGemini: (map['enable_gemini']?.toInt() ?? 0) == 1,
      geminiApiEndpoint: map['gemini_api_endpoint'],
      geminiModel: map['gemini_model'],
      geminiBaseUrl: map['gemini_base_url'],
      enableOpenclaw: (map['enable_openclaw']?.toInt() ?? 0) == 1,
      openclawBaseUrl: map['openclaw_base_url'],
      openclawModel: map['openclaw_model'],
      enableClaudeDesktop: (map['enable_claude_desktop']?.toInt() ?? 0) == 1,
      claudeDesktopBaseUrl: map['claude_desktop_base_url'],
      claudeDesktopModel: map['claude_desktop_model'],
      claudeDesktopSonnetModel: map['claude_desktop_sonnet_model'],
      claudeDesktopHaikuModel: map['claude_desktop_haiku_model'],
      claudeDesktopOpusModel: map['claude_desktop_opus_model'],
      toolConfigs: parseToolConfigs(map['tool_configs']),
      isValidated: parsedEntries != null
          ? entryList[activeIdx].validated
          : ((map['is_validated']?.toInt() ?? 0) == 1),
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
        keyEntriesRaw,
        activeKeyIndex,
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
        claudeCodeConfig,
        enableCodex,
        codexApiEndpoint,
        codexModel,
        codexBaseUrl,
        codexConfig,
        enableGemini,
        geminiApiEndpoint,
        geminiModel,
        geminiBaseUrl,
        enableOpenclaw,
        openclawBaseUrl,
        openclawModel,
        enableClaudeDesktop,
        claudeDesktopBaseUrl,
        claudeDesktopModel,
        claudeDesktopSonnetModel,
        claudeDesktopHaikuModel,
        claudeDesktopOpusModel,
        toolConfigs,
        isValidated,
      ];
}
