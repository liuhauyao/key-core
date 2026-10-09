import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../../config/provider_config.dart';
import '../../models/ai_key.dart';
import '../../models/mcp_server.dart';
import '../../models/unified_provider_config.dart';
import '../ai_tool_config_service.dart';
import '../live_config/live_config_writer.dart';
import '../mcp/mcp_tool_formats.dart';

/// 一把密钥在某个新工具里的“供应商”定义（已合并预设与密钥自身设置）
class ToolProviderSpec {
  /// 写入工具配置的供应商键（`keycore-<密钥 id>`，用于识别与删除）
  final String providerKey;
  final String displayName;
  final String baseUrl;

  /// 默认模型 id
  final String model;

  /// 协议：OpenCode 为 npm 包名；Pi / MiniMax Code 为 `openai-completions` 等；
  /// Hermes 为 `chat_completions` 等；Grok Build 为 `responses` / `chat_completions`
  final String api;

  /// 预设块原样（模型列表等），可能为空
  final Map<String, dynamic> preset;

  const ToolProviderSpec({
    required this.providerKey,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.api,
    this.preset = const {},
  });
}

/// 写入失败（配置不完整、工具正忙等），消息可直接展示给用户
class ToolProviderException implements Exception {
  final String message;
  ToolProviderException(this.message);
  @override
  String toString() => message;
}

/// OpenCode / Grok Build / Hermes / Pi / MiniMax Code 的密钥切换。
///
/// 对齐 CC Switch v4.0.6 各工具的写入方式：
/// - **OpenCode**（累加）：`opencode.json` 的 `provider.<key>` = `{npm, name, options: {baseURL, apiKey}, models}`；
///   设为默认时写顶层 `model: "<key>/<模型>"`。
/// - **Grok Build**（切换）：`~/.grok/config.toml` 的 `[models] default` 与 `[model."<模型>"]`
///   （`model` / `base_url` / `name` / `api_key` / `api_backend` / `context_window`）；
///   切回官方 = 删除 `[models]` 与对应的 `[model.*]` 表，其余内容（如 `[mcp_servers]`）保留。
/// - **Hermes**（累加）：`config.yaml` 的 `custom_providers:` 列表按 `name` 增改（保留用户加的未知字段），
///   设为默认时更新 `model.default` / `model.provider`。
/// - **Pi**（累加）：`models.json` 的 `providers.<key>`；设为默认时写 `settings.json` 的
///   `defaultProvider` / `defaultModel`。
/// - **MiniMax Code**（累加）：`config.yaml` 的 `custom_provider.<key>`（`kind: custom`）；
///   设为默认时写 `defaultModel: "custom_provider:<key>/<模型>"`；写入期间持有 MCode 自己的
///   `config.yaml.lock` 目录锁。
///
/// 所有写入经 [LiveConfigWriter]：解析失败即中止、原子写、首写与滚动备份、0600 权限。
class ToolProviderService {
  ToolProviderService({AiToolConfigService? toolConfig}) : _toolConfig = toolConfig ?? AiToolConfigService();

  final AiToolConfigService _toolConfig;

  static const List<AiToolType> tools = [
    AiToolType.opencode,
    AiToolType.grokBuild,
    AiToolType.hermes,
    AiToolType.pi,
    AiToolType.mcode,
  ];

  /// 是否是“切换型”工具（同一时间只有一个生效），其余为累加型
  static bool isSwitchMode(AiToolType tool) => tool == AiToolType.grokBuild;

  static const String providerKeyPrefix = 'keycore-';

  static String providerKeyFor(int keyId) => '$providerKeyPrefix$keyId';

  static int? keyIdFromProviderKey(String providerKey) => providerKey.startsWith(providerKeyPrefix)
      ? int.tryParse(providerKey.substring(providerKeyPrefix.length))
      : null;

  /// app_config.json 中对应的预设块键
  static String presetKeyFor(AiToolType tool) => switch (tool) {
        AiToolType.grokBuild => 'grokBuild',
        _ => tool.value,
      };

  // ---------------------------------------------------------------------------
  // 解析：密钥 + 预设 → 写入规格
  // ---------------------------------------------------------------------------

  /// 合并预设与密钥自身设置。密钥设置（`toolConfigs[tool]` 的 baseUrl / model）优先；
  /// 预设没有该工具的块时，OpenAI 兼容类工具回退到密钥的 API 地址。无法确定地址或模型时返回 null。
  static ToolProviderSpec? resolve(AIKey key, AiToolType tool, {UnifiedProviderConfig? preset}) {
    if (key.id == null) return null;
    final cfg = key.toolConfig(tool.value);
    final block = preset?.toolPresets[presetKeyFor(tool)] ?? const <String, dynamic>{};
    String? str(Object? v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

    var baseUrl = str(cfg['baseUrl']) ?? str(block['baseUrl']);
    if (baseUrl == null && tool != AiToolType.grokBuild && block.isEmpty) {
      baseUrl = str(key.apiEndpoint) ?? str(key.openclawBaseUrl);
    }
    final model = str(cfg['model']) ?? str(block['model']) ?? _firstModelId(tool, block) ?? str(key.openclawModel);
    if (baseUrl == null || model == null) return null;

    final api = switch (tool) {
      AiToolType.opencode => str(cfg['npm']) ?? str(block['npm']) ?? '@ai-sdk/openai-compatible',
      AiToolType.grokBuild => str(cfg['apiBackend']) ?? str(block['apiBackend']) ?? 'responses',
      AiToolType.hermes => str(cfg['apiMode']) ?? str(block['apiMode']) ?? 'chat_completions',
      _ => str(cfg['api']) ?? str(block['api']) ?? 'openai-completions',
    };
    return ToolProviderSpec(
      providerKey: providerKeyFor(key.id!),
      displayName: key.name,
      baseUrl: baseUrl,
      model: model,
      api: api,
      preset: block,
    );
  }

  static String? _firstModelId(AiToolType tool, Map<String, dynamic> block) {
    final models = block['models'];
    if (models is Map && models.isNotEmpty) return '${models.keys.first}';
    if (models is List && models.isNotEmpty && models.first is Map) {
      final id = (models.first as Map)['id'];
      if (id is String && id.isNotEmpty) return id;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 纯函数：各工具的原生条目（便于测试）
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> buildOpenCodeEntry(ToolProviderSpec s, String apiKey) {
    final options = <String, dynamic>{
      ...?(s.preset['options'] as Map?)?.cast<String, dynamic>(),
      'baseURL': s.baseUrl,
      'apiKey': apiKey,
    };
    final presetModels = (s.preset['models'] as Map?)?.cast<String, dynamic>() ?? const {};
    return {
      'npm': s.api,
      'name': s.displayName,
      'options': options,
      'models': {
        ...presetModels,
        if (!presetModels.containsKey(s.model)) s.model: {'name': s.model},
      },
    };
  }

  static Map<String, dynamic> buildPiEntry(ToolProviderSpec s, String apiKey) {
    final presetModels = ((s.preset['models'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    return {
      'baseUrl': s.baseUrl,
      'api': s.api,
      'apiKey': apiKey,
      'models': [
        ...presetModels,
        if (!presetModels.any((m) => m['id'] == s.model)) {'id': s.model, 'name': s.model},
      ],
    };
  }

  static Map<String, dynamic> buildMCodeEntry(ToolProviderSpec s, String apiKey) {
    final presetModels = (s.preset['models'] as Map?)?.cast<String, dynamic>() ?? const {};
    return {
      'name': s.displayName,
      'kind': 'custom',
      'enabled': true,
      'api': s.api,
      'options': {'baseURL': s.baseUrl, 'apiKey': apiKey},
      'models': {
        ...presetModels,
        if (!presetModels.containsKey(s.model)) s.model: {'name': s.model},
      },
    };
  }

  static Map<String, dynamic> buildHermesEntry(ToolProviderSpec s, String apiKey) {
    final models = <String, dynamic>{};
    for (final m in ((s.preset['models'] as List?) ?? const []).whereType<Map>()) {
      final id = m['id'];
      if (id is! String || id.isEmpty) continue;
      models[id] = {
        for (final e in m.entries)
          if (e.key != 'id' && e.key != 'name') '${e.key}': e.value,
      };
    }
    models.putIfAbsent(s.model, () => <String, dynamic>{});
    // Hermes 运行时读单数 `model` 字段（CC Switch 取第一个模型）；把默认模型放在首位
    final ordered = {s.model: models.remove(s.model), ...models};
    return {
      'name': s.providerKey,
      'base_url': s.baseUrl,
      'api_key': apiKey,
      'api_mode': s.api,
      'model': s.model,
      'models': ordered,
    };
  }

  // ---------------------------------------------------------------------------
  // 纯函数：YAML / TOML 文本编辑（只重写受管的顶层块，其余原样保留）
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> _yamlRoot(String text, String label) {
    if (text.trim().isEmpty) return {};
    final doc = loadYaml(text);
    if (doc == null) return {};
    if (doc is! YamlMap) throw FormatException('$label 顶层不是映射，已中止写入');
    return _plain(doc) as Map<String, dynamic>;
  }

  static Object? _plain(Object? v) {
    if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _plain(e.value)};
    if (v is List) return v.map(_plain).toList();
    return v;
  }

  /// 替换（或删除，value 为 null 时）YAML 文本中的一个顶层键，其余行原样保留
  static String replaceTopLevelYaml(String text, String key, Object? value) {
    final lines = text.isEmpty ? <String>[] : text.split('\n');
    final keyPattern = RegExp('^${RegExp.escape(key)}\\s*:');
    final start = lines.indexWhere(keyPattern.hasMatch);
    final List<String> block;
    if (value == null) {
      block = const [];
    } else if (value is Map || value is List) {
      final inner = McpToolFormats.emitYaml(value, 1);
      block = inner.isEmpty ? ['$key: ${value is Map ? '{}' : '[]'}'] : ['$key:', ...inner];
    } else {
      block = [McpToolFormats.emitYaml({key: value}, 0).single];
    }
    if (start < 0) {
      if (block.isEmpty) return text;
      final body = text.trimRight();
      return '${body.isEmpty ? '' : '$body\n'}${block.join('\n')}\n';
    }
    var end = start + 1;
    while (end < lines.length) {
      final l = lines[end];
      if (l.isNotEmpty && !l.startsWith(' ') && !l.startsWith('\t') && !l.startsWith('#') && !l.startsWith('-')) break;
      end++;
    }
    while (end > start + 1 && (lines[end - 1].trim().isEmpty || lines[end - 1].startsWith('#'))) {
      end--;
    }
    final out = [...lines.sublist(0, start), ...block, ...lines.sublist(end)];
    var result = out.join('\n');
    if (text.endsWith('\n') && !result.endsWith('\n')) result = '$result\n';
    return result;
  }

  /// Hermes：增改 / 删除 `custom_providers` 中的条目，并按需更新 `model` 段
  static String applyHermes(
    String text, {
    required String providerKey,
    Map<String, dynamic>? entry,
    bool makeDefault = false,
  }) {
    final root = _yamlRoot(text, 'Hermes config.yaml');
    final list = ((root['custom_providers'] as List?) ?? const []).toList();
    final idx = list.indexWhere((e) => e is Map && e['name'] == providerKey);
    var out = text;
    if (entry != null) {
      // 保留用户在 Hermes 里给该条目加的其他字段（如 request_timeout_seconds）
      final merged = <String, dynamic>{
        ...entry,
        if (idx >= 0)
          for (final e in (list[idx] as Map).entries)
            if (!entry.containsKey(e.key)) '${e.key}': e.value,
      };
      if (idx >= 0) {
        list[idx] = merged;
      } else {
        list.add(merged);
      }
    } else if (idx >= 0) {
      list.removeAt(idx);
    }
    if (entry != null || idx >= 0) {
      out = replaceTopLevelYaml(out, 'custom_providers', list.isEmpty ? null : list);
    }

    final model = _hermesModelSection(root['model']);
    if (entry != null && makeDefault) {
      model['default'] = entry['model'];
      model['provider'] = providerKey;
      out = replaceTopLevelYaml(out, 'model', model);
    } else if (entry == null && model['provider'] == providerKey) {
      model.remove('provider');
      model.remove('default');
      out = replaceTopLevelYaml(out, 'model', model.isEmpty ? null : model);
    }
    return out;
  }

  /// Hermes 的 `model` 段：新版是映射；旧版可能直接写成模型名字符串
  static Map<String, dynamic> _hermesModelSection(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String && v.isNotEmpty) return {'default': v};
    return {};
  }

  /// MiniMax Code：增改 / 删除 `custom_provider.<key>`，并按需更新 `defaultModel`
  static String applyMCode(
    String text, {
    required String providerKey,
    Map<String, dynamic>? entry,
    String? defaultModel,
  }) {
    final root = _yamlRoot(text, 'MiniMax Code config.yaml');
    final providers = Map<String, dynamic>.from((root['custom_provider'] as Map?) ?? const {});
    final existing = providers[providerKey];
    if (existing is Map && existing['kind'] != null && existing['kind'] != 'custom') {
      throw ToolProviderException('MiniMax Code 中的 $providerKey 是 MiniMax 账号供应商，Key Core 不会修改');
    }
    var out = text;
    if (entry != null) {
      providers[providerKey] = entry;
    } else {
      providers.remove(providerKey);
    }
    if (entry != null || existing != null) {
      out = replaceTopLevelYaml(out, 'custom_provider', providers.isEmpty ? null : providers);
    }
    final prefix = 'custom_provider:$providerKey/';
    if (entry != null && defaultModel != null) {
      out = replaceTopLevelYaml(out, 'defaultModel', '$prefix$defaultModel');
    } else if (entry == null) {
      for (final field in ['defaultModel', 'defaultLightModel']) {
        final v = root[field];
        if (v is String && v.startsWith(prefix)) out = replaceTopLevelYaml(out, field, null);
      }
    }
    return out;
  }

  static String _tomlKey(String k) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(k) ? k : McpToolFormats.tomlString(k);

  /// Grok Build：写入（[s] 非空）或切回官方（[s] 为空）。只动 `[models]` 与受管的 `[model.*]` 表。
  static String applyGrok(String toml, ToolProviderSpec? s, {String? apiKey, int contextWindow = 500000}) {
    final doc = TomlDoc.parse(toml);
    String? currentProfile;
    final modelsExtra = <String>[];
    for (final t in doc.tables) {
      if (t.path.length == 1 && t.path[0] == 'models') {
        for (final e in TomlDoc.parseEntries(t.lines.skip(1).join('\n'))) {
          if (e.key == 'default' && e.value is String) {
            currentProfile = e.value as String;
          } else {
            modelsExtra.add(e.raw);
          }
        }
      }
    }
    final newProfile = s?.model;
    // 需要移除的表：[models]、当前默认模型表、新模型同名表
    bool managed(List<String> path) =>
        (path.length == 1 && path[0] == 'models') ||
        (path.length >= 2 && path[0] == 'model' && (path[1] == currentProfile || path[1] == newProfile));

    final out = <String>[...doc.preamble];
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    for (final t in doc.tables) {
      if (managed(t.path)) continue;
      var lines = t.lines.toList();
      while (lines.isNotEmpty && lines.last.trim().isEmpty) {
        lines = lines.sublist(0, lines.length - 1);
      }
      if (out.isNotEmpty) out.add('');
      out.addAll(lines);
    }
    if (s != null) {
      if (out.isNotEmpty) out.add('');
      out
        ..add('[models]')
        ..add('default = ${McpToolFormats.tomlString(s.model)}')
        ..addAll(modelsExtra)
        ..add('')
        ..add('[model.${_tomlKey(s.model)}]')
        ..add('model = ${McpToolFormats.tomlString(s.model)}')
        ..add('base_url = ${McpToolFormats.tomlString(s.baseUrl)}')
        ..add('name = ${McpToolFormats.tomlString(s.displayName)}')
        ..add('api_key = ${McpToolFormats.tomlString(apiKey ?? '')}')
        ..add('api_backend = ${McpToolFormats.tomlString(s.api)}')
        ..add('context_window = $contextWindow');
    }
    while (out.isNotEmpty && out.first.trim().isEmpty) {
      out.removeAt(0);
    }
    return out.isEmpty ? '' : '${out.join('\n')}\n';
  }

  /// Grok Build 当前默认模型表的 `api_key`（官方态或未配置时为 null）
  static String? readGrokApiKey(String toml) {
    final doc = TomlDoc.parse(toml);
    String? profile;
    for (final t in doc.tables.where((t) => t.path.length == 1 && t.path[0] == 'models')) {
      for (final e in TomlDoc.parseEntries(t.lines.skip(1).join('\n'))) {
        if (e.key == 'default' && e.value is String) profile = e.value as String;
      }
    }
    if (profile == null) return null;
    for (final t in doc.tables.where((t) => t.path.length == 2 && t.path[0] == 'model' && t.path[1] == profile)) {
      for (final e in TomlDoc.parseEntries(t.lines.skip(1).join('\n'))) {
        if (e.key == 'api_key' && e.value is String) return e.value as String;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 写入 / 删除 / 读取
  // ---------------------------------------------------------------------------

  Future<String> configDir(AiToolType tool) => _toolConfig.getConfigDir(tool);

  /// 该工具的主配置文件
  Future<String> primaryFile(AiToolType tool) async {
    final dir = await configDir(tool);
    return switch (tool) {
      AiToolType.opencode => AiToolConfigService.getConfigFilePath(tool, customConfigDir: dir),
      AiToolType.grokBuild => p.join(dir, 'config.toml'),
      AiToolType.hermes => p.join(dir, 'config.yaml'),
      AiToolType.pi => p.join(dir, 'models.json'),
      AiToolType.mcode => p.join(dir, 'config.yaml'),
      _ => throw ArgumentError('不支持的工具：$tool'),
    };
  }

  /// 把密钥写入工具配置。[makeDefault] 为 true 时同时设为该工具的默认供应商/模型
  /// （Grok Build 是切换型，总是设为默认）。
  Future<ToolProviderSpec> apply(
    AiToolType tool,
    AIKey key,
    String apiKey, {
    bool makeDefault = true,
    UnifiedProviderConfig? preset,
  }) async {
    if (!tools.contains(tool)) throw ArgumentError('不支持的工具：$tool');
    final spec = resolve(key, tool, preset: preset ?? ProviderConfig.getPresetByPlatformId(key.platformType.id));
    if (spec == null) {
      throw ToolProviderException('“${key.name}”缺少 ${tool.value} 所需的请求地址或模型，请在密钥中补充后再试');
    }
    if (apiKey.trim().isEmpty) throw ToolProviderException('密钥值为空');
    final file = await primaryFile(tool);
    final writer = LiveConfigWriter.instance;
    switch (tool) {
      case AiToolType.opencode:
        await writer.updateJson(tool, file, (doc) {
          final providers = Map<String, dynamic>.from((doc['provider'] as Map?) ?? const {});
          providers[spec.providerKey] = buildOpenCodeEntry(spec, apiKey);
          doc['provider'] = providers;
          if (makeDefault) doc['model'] = '${spec.providerKey}/${spec.model}';
          doc.putIfAbsent(r'$schema', () => 'https://opencode.ai/config.json');
        }, containsSecrets: true);
      case AiToolType.pi:
        final settings = p.join(p.dirname(file), 'settings.json');
        await writer.apply(tool, [
          LiveEdit.json(file, (doc) {
            final providers = Map<String, dynamic>.from((doc['providers'] as Map?) ?? const {});
            providers[spec.providerKey] = buildPiEntry(spec, apiKey);
            doc['providers'] = providers;
          }, containsSecrets: true),
          if (makeDefault)
            LiveEdit.json(settings, (doc) {
              doc['defaultProvider'] = spec.providerKey;
              doc['defaultModel'] = spec.model;
            }),
        ]);
      case AiToolType.hermes:
        await writer.updateText(
          tool,
          file,
          (t) => applyHermes(t,
              providerKey: spec.providerKey, entry: buildHermesEntry(spec, apiKey), makeDefault: makeDefault),
          containsSecrets: true,
        );
      case AiToolType.mcode:
        await _withMCodeLock(file, () => writer.updateText(
              tool,
              file,
              (t) => applyMCode(t,
                  providerKey: spec.providerKey,
                  entry: buildMCodeEntry(spec, apiKey),
                  defaultModel: makeDefault ? spec.model : null),
              containsSecrets: true,
            ));
      case AiToolType.grokBuild:
        await writer.updateText(tool, file, (t) => applyGrok(t, spec, apiKey: apiKey), containsSecrets: true);
      default:
        break;
    }
    return spec;
  }

  /// 从工具配置中移除这把密钥（若是默认项，一并清除默认设置）。
  /// Grok Build：仅当当前生效的就是这把密钥时切回官方。
  Future<void> remove(AiToolType tool, AIKey key, {String? decryptedKey}) async {
    if (key.id == null || !tools.contains(tool)) return;
    final pk = providerKeyFor(key.id!);
    final file = await primaryFile(tool);
    if (!File(file).existsSync()) return;
    final writer = LiveConfigWriter.instance;
    switch (tool) {
      case AiToolType.opencode:
        await writer.updateJson(tool, file, (doc) {
          final providers = doc['provider'];
          if (providers is Map) providers.remove(pk);
          final m = doc['model'];
          if (m is String && m.startsWith('$pk/')) doc.remove('model');
        }, containsSecrets: true, createIfMissing: false);
      case AiToolType.pi:
        final settings = p.join(p.dirname(file), 'settings.json');
        await writer.apply(tool, [
          LiveEdit.json(file, (doc) {
            final providers = doc['providers'];
            if (providers is Map) providers.remove(pk);
          }, containsSecrets: true, createIfMissing: false),
          LiveEdit.json(settings, (doc) {
            if (doc['defaultProvider'] == pk) {
              doc.remove('defaultProvider');
              doc.remove('defaultModel');
            }
          }, createIfMissing: false),
        ]);
      case AiToolType.hermes:
        await writer.updateText(tool, file, (t) => applyHermes(t, providerKey: pk), containsSecrets: true);
      case AiToolType.mcode:
        await _withMCodeLock(
            file, () => writer.updateText(tool, file, (t) => applyMCode(t, providerKey: pk), containsSecrets: true));
      case AiToolType.grokBuild:
        final current = readGrokApiKey(File(file).readAsStringSync());
        if (current != null && decryptedKey != null && current == decryptedKey) {
          await switchGrokToOfficial();
        }
      default:
        break;
    }
  }

  /// Grok Build 切回官方登录（删除 `[models]` 与当前默认模型表）
  Future<void> switchGrokToOfficial() async {
    final file = await primaryFile(AiToolType.grokBuild);
    if (!File(file).existsSync()) return;
    await LiveConfigWriter.instance
        .updateText(AiToolType.grokBuild, file, (t) => applyGrok(t, null), containsSecrets: true);
  }

  /// 累加型工具中已写入的 Key Core 密钥 id
  Future<Set<int>> appliedKeyIds(AiToolType tool) async {
    final file = await primaryFile(tool);
    final f = File(file);
    if (!f.existsSync()) return {};
    final text = await f.readAsString();
    Iterable<String> keys;
    try {
      switch (tool) {
        case AiToolType.opencode:
          keys = ((jsonDecode(text) as Map)['provider'] as Map? ?? const {}).keys.cast<String>();
        case AiToolType.pi:
          keys = ((jsonDecode(text) as Map)['providers'] as Map? ?? const {}).keys.cast<String>();
        case AiToolType.hermes:
          keys = ((_yamlRoot(text, 'Hermes')['custom_providers'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => '${e['name']}');
        case AiToolType.mcode:
          keys = ((_yamlRoot(text, 'MiniMax Code')['custom_provider'] as Map?) ?? const {}).keys.cast<String>();
        default:
          return {};
      }
    } catch (_) {
      return {};
    }
    return keys.map(keyIdFromProviderKey).whereType<int>().toSet();
  }

  /// 当前设为默认的 Key Core 密钥 id（Grok Build 返回 null，由调用方按 api_key 匹配）
  Future<int?> defaultKeyId(AiToolType tool) async {
    final file = await primaryFile(tool);
    try {
      switch (tool) {
        case AiToolType.opencode:
          final m = (jsonDecode(await File(file).readAsString()) as Map)['model'];
          return m is String ? keyIdFromProviderKey(m.split('/').first) : null;
        case AiToolType.pi:
          final settings = File(p.join(p.dirname(file), 'settings.json'));
          final v = (jsonDecode(await settings.readAsString()) as Map)['defaultProvider'];
          return v is String ? keyIdFromProviderKey(v) : null;
        case AiToolType.hermes:
          final v = _hermesModelSection(_yamlRoot(await File(file).readAsString(), 'Hermes')['model'])['provider'];
          return v is String ? keyIdFromProviderKey(v) : null;
        case AiToolType.mcode:
          final v = _yamlRoot(await File(file).readAsString(), 'MiniMax Code')['defaultModel'];
          if (v is! String || !v.startsWith('custom_provider:')) return null;
          return keyIdFromProviderKey(v.substring('custom_provider:'.length).split('/').first);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// Grok Build 当前生效的 api_key（官方态为 null）
  Future<String?> currentGrokApiKey() async {
    final f = File(await primaryFile(AiToolType.grokBuild));
    if (!f.existsSync()) return null;
    return readGrokApiKey(await f.readAsString());
  }

  /// MiniMax Code 与其桌面端共用的目录锁（proper-lockfile 约定：`<文件>.lock` 目录）
  static Future<T> _withMCodeLock<T>(String file, Future<T> Function() action) async {
    final lock = Directory('$file.lock');
    if (lock.existsSync()) {
      final age = DateTime.now().difference(lock.statSync().modified);
      if (age < const Duration(seconds: 10)) {
        throw ToolProviderException('MiniMax Code 正在保存配置，请稍后重试');
      }
      lock.deleteSync(recursive: true);
    }
    await Directory(p.dirname(file)).create(recursive: true);
    lock.createSync();
    try {
      return await action();
    } finally {
      if (lock.existsSync()) lock.deleteSync(recursive: true);
    }
  }
}
