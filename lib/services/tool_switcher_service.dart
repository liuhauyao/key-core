import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/mcp_server.dart';
import '../models/provider.dart';
import 'ai_tool_config_service.dart';
import 'config_file_service.dart';
import 'openclaw_config_service.dart';
import 'platform_config_path_service.dart';
import 'settings_service.dart';

/// 解析工具配置目录的函数（便于测试时注入临时目录）
typedef ToolConfigDirResolver = Future<String> Function(String tool);

/// 工具在磁盘上的实时配置摘要（不包含明文 API Key）
class ToolLiveState {
  final String tool;
  final String configPath;
  final bool configExists;
  final bool hasApiKey;
  final String? baseUrl;
  final String? model;

  const ToolLiveState({
    required this.tool,
    required this.configPath,
    required this.configExists,
    this.hasApiKey = false,
    this.baseUrl,
    this.model,
  });
}

/// 一个配置备份文件
class ConfigBackup {
  final String path;
  final DateTime? createdAt;
  final int sizeBytes;

  const ConfigBackup({required this.path, this.createdAt, this.sizeBytes = 0});

  String get fileName => p.basename(path);
}

/// 工具配置切换服务
///
/// 负责把供应商配置写入各 AI 工具的真实配置文件（参考 CC Switch 的
/// 「切换模式」：只修改与供应商相关的字段，保留用户的其他配置）：
///
/// | 工具 | 文件 | 写入内容 |
/// |------|------|---------|
/// | Claude Code | `~/.claude/settings.json` | `env.ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` |
/// | Gemini CLI | `~/.gemini/.env` | `GEMINI_API_KEY` / `GOOGLE_GEMINI_BASE_URL` / `GEMINI_MODEL` |
/// | OpenClaw | `~/.openclaw/openclaw.json` + `.env` | `models.providers.keycore-*` + `agents.defaults.model.primary` |
/// | Grok Build | `~/.grok/config.toml` | `[models] default` + `[model.keycore]` |
///
/// 每次写入前都会通过 [ConfigFileService] 自动备份并原子性替换文件。
class ToolSwitcherService {
  static ToolSwitcherService? _instance;

  /// UI 支持一键切换的工具（Codex 需要 TOML 读写，暂不支持）
  static const List<String> switchableTools = [
    'claude_code',
    'gemini_cli',
    'openclaw',
    'grok_build',
  ];

  /// Grok Build 中由 Key Core 管理的模型表别名
  static const String grokAlias = 'keycore';

  /// 每个配置文件保留的备份数量
  static const int backupsToKeep = 10;

  final ConfigFileService _configService;
  final ToolConfigDirResolver _resolveDir;

  ToolSwitcherService._(this._configService, this._resolveDir);

  static ToolSwitcherService get instance {
    _instance ??= ToolSwitcherService._(
      ConfigFileService.instance,
      _defaultConfigDir,
    );
    return _instance!;
  }

  /// 测试用：使用自定义的配置目录解析函数
  factory ToolSwitcherService.withResolver(ToolConfigDirResolver resolver) {
    return ToolSwitcherService._(ConfigFileService.instance, resolver);
  }

  static Future<String> _defaultConfigDir(String tool) async {
    final settings = SettingsService();
    await settings.init();
    switch (tool) {
      case 'claude_code':
        return PlatformConfigPathService.getClaudeConfigDir(
          customDir: settings.getClaudeConfigDir(),
        );
      case 'gemini_cli':
        return PlatformConfigPathService.getGeminiConfigDir(
          customDir: settings.getGeminiConfigDir(),
        );
      case 'openclaw':
        return AiToolConfigService().getConfigDir(AiToolType.openclaw);
      case 'grok_build':
        return p.join(await SettingsService.getUserHomeDir(), '.grok');
      default:
        throw UnsupportedError('不支持的工具: $tool');
    }
  }

  /// 工具的主配置文件路径（也是备份列表所针对的文件）
  Future<String> primaryConfigPath(String tool) async {
    final dir = await _resolveDir(tool);
    switch (tool) {
      case 'claude_code':
        return p.join(dir, 'settings.json');
      case 'gemini_cli':
        return p.join(dir, '.env');
      case 'openclaw':
        return p.join(dir, 'openclaw.json');
      case 'grok_build':
        return p.join(dir, 'config.toml');
      default:
        throw UnsupportedError('不支持的工具: $tool');
    }
  }

  void _ensureSwitchable(Provider provider, String tool) {
    if (!switchableTools.contains(tool)) {
      throw UnsupportedError('暂不支持切换 $tool');
    }
    if (!provider.supportedTools.contains(tool)) {
      throw StateError('该供应商不支持 $tool');
    }
    if (provider.apiKey == null || provider.apiKey!.isEmpty) {
      throw StateError('供应商 API Key 未设置');
    }
  }

  static String? _defaultModel(Provider provider) =>
      provider.models.isNotEmpty ? provider.models.first.id : null;

  static bool _notEmpty(String? s) => s != null && s.trim().isNotEmpty;

  /// 切换 Claude Code 配置（~/.claude/settings.json 的 env 字段）
  Future<void> switchClaudeCode(Provider provider) async {
    _ensureSwitchable(provider, 'claude_code');
    final filePath = await primaryConfigPath('claude_code');
    final config = await _readJsonOrEmpty(filePath);

    final env = Map<String, dynamic>.from(
      (config['env'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    env['ANTHROPIC_AUTH_TOKEN'] = provider.apiKey;
    env.remove('ANTHROPIC_API_KEY');
    if (_notEmpty(provider.apiEndpoint)) {
      env['ANTHROPIC_BASE_URL'] = provider.apiEndpoint!.trim();
    } else {
      env.remove('ANTHROPIC_BASE_URL');
    }
    final model = _defaultModel(provider);
    if (_notEmpty(model)) {
      env['ANTHROPIC_MODEL'] = model;
    } else {
      env.remove('ANTHROPIC_MODEL');
    }
    // 上一个供应商写入的分档模型对新供应商通常无效，一并清理
    env.remove('ANTHROPIC_DEFAULT_HAIKU_MODEL');
    env.remove('ANTHROPIC_DEFAULT_SONNET_MODEL');
    env.remove('ANTHROPIC_DEFAULT_OPUS_MODEL');
    config['env'] = env;

    await _configService.writeJsonConfig(filePath, config);
    await _configService.cleanupOldBackups(filePath, keep: backupsToKeep);
  }

  /// 切换 Gemini CLI 配置（~/.gemini/.env）
  Future<void> switchGeminiCli(Provider provider) async {
    _ensureSwitchable(provider, 'gemini_cli');
    final filePath = await primaryConfigPath('gemini_cli');
    final model = _defaultModel(provider);
    final endpoint = provider.apiEndpoint?.trim();
    final isOfficial = endpoint == null ||
        endpoint.isEmpty ||
        endpoint.contains('generativelanguage.googleapis.com');
    await _updateDotEnv(filePath, {
      'GEMINI_API_KEY': provider.apiKey,
      'GOOGLE_GEMINI_BASE_URL': isOfficial ? null : endpoint,
      'GEMINI_MODEL': _notEmpty(model) ? model : null,
    });
    await _configService.cleanupOldBackups(filePath, keep: backupsToKeep);
  }

  /// OpenClaw 中 Key Core 使用的 provider id
  static String openClawProviderId(Provider provider) {
    final base = (provider.family?.isNotEmpty ?? false)
        ? provider.family!
        : provider.id.replaceAll(RegExp(r'-\d{10,}$'), '');
    final slug = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'keycore-${slug.isEmpty ? 'custom' : slug}';
  }

  static String _openClawApiType(Provider provider) {
    final endpoint = provider.apiEndpoint ?? '';
    if (provider.id.startsWith('anthropic') || endpoint.contains('anthropic')) {
      return 'anthropic-messages';
    }
    if (provider.id.startsWith('google') ||
        endpoint.contains('generativelanguage.googleapis.com')) {
      return 'google-generative-ai';
    }
    return 'openai-completions';
  }

  /// 切换 OpenClaw 配置
  ///
  /// API Key 写入 `~/.openclaw/.env`，openclaw.json 中仅引用环境变量，
  /// 避免把明文密钥写进主配置文件。
  Future<void> switchOpenClaw(Provider provider) async {
    _ensureSwitchable(provider, 'openclaw');
    if (!_notEmpty(provider.apiEndpoint)) {
      throw StateError('OpenClaw 需要供应商的 API 地址');
    }
    final filePath = await primaryConfigPath('openclaw');
    final envPath = p.join(p.dirname(filePath), '.env');
    final providerId = openClawProviderId(provider);
    final envKey =
        '${providerId.toUpperCase().replaceAll('-', '_')}_API_KEY';

    await _updateDotEnv(envPath, {envKey: provider.apiKey});

    final config = await _readJsonOrEmpty(filePath, json5: true);
    final modelsRoot = Map<String, dynamic>.from(
      (config['models'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    modelsRoot['mode'] ??= 'merge';
    final providers = Map<String, dynamic>.from(
      (modelsRoot['providers'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    providers[providerId] = {
      'baseUrl': provider.apiEndpoint!.trim(),
      'api': _openClawApiType(provider),
      'apiKey': '\${$envKey}',
      if (provider.models.isNotEmpty)
        'models': provider.models
            .map((m) => {
                  'id': m.id,
                  'name': m.displayName,
                  if (m.contextWindow != null) 'contextWindow': m.contextWindow,
                  if (m.maxOutputTokens != null) 'maxTokens': m.maxOutputTokens,
                })
            .toList(),
    };
    modelsRoot['providers'] = providers;
    config['models'] = modelsRoot;

    final model = _defaultModel(provider);
    if (_notEmpty(model)) {
      final agents = Map<String, dynamic>.from(
        (config['agents'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final defaults = Map<String, dynamic>.from(
        (agents['defaults'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final modelRef = '$providerId/$model';
      final block = defaults['model'];
      if (block is Map) {
        defaults['model'] = {...block.cast<String, dynamic>(), 'primary': modelRef};
      } else {
        defaults['model'] = {'primary': modelRef};
      }
      agents['defaults'] = defaults;
      config['agents'] = agents;
    }

    await _configService.writeJsonConfig(filePath, config);
    await _configService.cleanupOldBackups(filePath, keep: backupsToKeep);
  }

  /// 切换 Grok Build 配置（~/.grok/config.toml）
  ///
  /// 只改写 `[models]` 下的 `default` 和由 Key Core 管理的 `[model.keycore]`
  /// 表，用户自己添加的模型表与 `[mcp_servers]` 等内容保持不变。
  Future<void> switchGrokBuild(Provider provider) async {
    _ensureSwitchable(provider, 'grok_build');
    final model = _defaultModel(provider);
    if (!_notEmpty(model)) {
      throw StateError('Grok Build 需要至少一个模型');
    }
    final filePath = await primaryConfigPath('grok_build');
    final existing = await _configService.readTextConfig(filePath) ?? '';

    final table = <String, Object>{
      'model': model!,
      'name': provider.nameZh?.isNotEmpty == true
          ? '${provider.name} / ${provider.nameZh}'
          : provider.name,
      if (_notEmpty(provider.apiEndpoint)) 'base_url': provider.apiEndpoint!.trim(),
      if (_openClawApiType(provider) == 'anthropic-messages') 'api_backend': 'messages',
      if (provider.models.first.contextWindow != null)
        'context_window': provider.models.first.contextWindow!,
      'api_key': provider.apiKey!,
    };

    final updated = GrokTomlEditor.apply(existing, grokAlias, table);
    await _configService.writeTextConfig(filePath, updated);
    await _configService.cleanupOldBackups(filePath, keep: backupsToKeep);
  }

  /// Codex 使用 TOML 且结构复杂，暂不支持一键切换
  Future<void> switchCodex(Provider provider) async {
    throw UnsupportedError('Codex 配置切换功能待实现（需要 TOML 支持）');
  }

  /// 批量切换多个工具的配置，返回每个工具是否成功
  Future<Map<String, bool>> switchMultipleTools(
    Provider provider,
    List<String> tools,
  ) async {
    final results = <String, bool>{};
    for (final tool in tools) {
      try {
        await switchTool(provider, tool);
        results[tool] = true;
      } catch (_) {
        results[tool] = false;
      }
    }
    return results;
  }

  /// 切换指定工具的配置
  Future<void> switchTool(Provider provider, String tool) async {
    switch (tool.toLowerCase()) {
      case 'claude_code':
        return switchClaudeCode(provider);
      case 'codex':
        return switchCodex(provider);
      case 'gemini_cli':
        return switchGeminiCli(provider);
      case 'openclaw':
        return switchOpenClaw(provider);
      case 'grok_build':
        return switchGrokBuild(provider);
      default:
        throw UnsupportedError('不支持的工具: $tool');
    }
  }

  /// 读取工具当前在磁盘上的配置摘要（用于界面展示，不返回明文密钥）
  Future<ToolLiveState> readLiveState(String tool) async {
    final filePath = await primaryConfigPath(tool);
    try {
      switch (tool) {
        case 'claude_code':
          final text = await _configService.readTextConfig(filePath);
          if (text == null) return ToolLiveState(tool: tool, configPath: filePath, configExists: false);
          final env = ((json.decode(text) as Map)['env'] as Map?) ?? const {};
          return ToolLiveState(
            tool: tool,
            configPath: filePath,
            configExists: true,
            hasApiKey: _notEmpty(env['ANTHROPIC_AUTH_TOKEN'] as String?) ||
                _notEmpty(env['ANTHROPIC_API_KEY'] as String?),
            baseUrl: env['ANTHROPIC_BASE_URL'] as String?,
            model: env['ANTHROPIC_MODEL'] as String?,
          );
        case 'gemini_cli':
          final text = await _configService.readTextConfig(filePath);
          if (text == null) return ToolLiveState(tool: tool, configPath: filePath, configExists: false);
          final env = parseDotEnv(text);
          return ToolLiveState(
            tool: tool,
            configPath: filePath,
            configExists: true,
            hasApiKey: _notEmpty(env['GEMINI_API_KEY']),
            baseUrl: env['GOOGLE_GEMINI_BASE_URL'],
            model: env['GEMINI_MODEL'],
          );
        case 'openclaw':
          final text = await _configService.readTextConfig(filePath);
          if (text == null) return ToolLiveState(tool: tool, configPath: filePath, configExists: false);
          final config = await _readJsonOrEmpty(filePath, json5: true);
          final block = ((config['agents'] as Map?)?['defaults'] as Map?)?['model'];
          final primary = block is Map ? block['primary'] as String? : block as String?;
          String? baseUrl;
          var hasKey = false;
          if (primary != null && primary.contains('/')) {
            final pid = primary.substring(0, primary.indexOf('/'));
            final entry = ((config['models'] as Map?)?['providers'] as Map?)?[pid];
            if (entry is Map) {
              baseUrl = entry['baseUrl'] as String?;
              hasKey = _notEmpty(entry['apiKey'] as String?);
            }
          }
          return ToolLiveState(
            tool: tool,
            configPath: filePath,
            configExists: true,
            hasApiKey: hasKey,
            baseUrl: baseUrl,
            model: primary,
          );
        case 'grok_build':
          final text = await _configService.readTextConfig(filePath);
          if (text == null) return ToolLiveState(tool: tool, configPath: filePath, configExists: false);
          final sections = GrokTomlEditor.parseSimple(text);
          final alias = sections['models']?['default'];
          final table = alias == null ? null : sections['model.$alias'];
          return ToolLiveState(
            tool: tool,
            configPath: filePath,
            configExists: true,
            hasApiKey: _notEmpty(table?['api_key']),
            baseUrl: table?['base_url'],
            model: table?['model'],
          );
      }
    } catch (_) {
      // 配置文件无法解析时仍返回“存在”，由界面提示
      return ToolLiveState(tool: tool, configPath: filePath, configExists: true);
    }
    throw UnsupportedError('不支持的工具: $tool');
  }

  /// 获取当前工具的 JSON 配置（兼容旧接口；非 JSON 工具返回 null）
  Future<Map<String, dynamic>?> getCurrentConfig(String tool) async {
    try {
      final filePath = await primaryConfigPath(tool);
      if (!filePath.endsWith('.json') || !await _configService.exists(filePath)) {
        return null;
      }
      return await _readJsonOrEmpty(filePath, json5: tool == 'openclaw');
    } catch (_) {
      return null;
    }
  }

  /// 验证工具配置中是否已设置 API Key
  Future<bool> validateConfig(String tool) async {
    try {
      final state = await readLiveState(tool);
      return state.configExists && state.hasApiKey;
    } catch (_) {
      return false;
    }
  }

  /// 列出工具主配置文件的备份（新的在前）
  Future<List<ConfigBackup>> listBackups(String tool) async {
    final filePath = await primaryConfigPath(tool);
    final paths = await _configService.listBackups(filePath);
    final result = <ConfigBackup>[];
    for (final path in paths) {
      int size = 0;
      try {
        size = await File(path).length();
      } catch (_) {}
      result.add(ConfigBackup(
        path: path,
        createdAt: ConfigFileService.backupTimestamp(path),
        sizeBytes: size,
      ));
    }
    return result;
  }

  /// 从备份恢复工具主配置文件
  ///
  /// 只接受属于该工具主配置文件的备份路径，防止被用来覆盖任意文件。
  /// 恢复前会先备份当前文件，因此恢复操作本身可撤销。
  Future<void> restoreBackup(String tool, String backupPath) async {
    final filePath = await primaryConfigPath(tool);
    final sameDir = p.equals(p.dirname(backupPath), p.dirname(filePath));
    final validName = p.basename(backupPath).startsWith('${p.basename(filePath)}.backup.');
    if (!sameDir || !validName) {
      throw ArgumentError('备份文件不属于 $tool 的配置: $backupPath');
    }
    await _configService.restoreBackup(backupPath, filePath);
    await _configService.cleanupOldBackups(filePath, keep: backupsToKeep);
  }

  /// 清理旧备份
  Future<void> cleanupBackups(String tool, {int keep = backupsToKeep}) async {
    final filePath = await primaryConfigPath(tool);
    await _configService.cleanupOldBackups(filePath, keep: keep);
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _readJsonOrEmpty(String filePath, {bool json5 = false}) async {
    final text = await _configService.readTextConfig(filePath);
    if (text == null || text.trim().isEmpty) return <String, dynamic>{};
    final source = json5 ? OpenClawConfigService.stripJson5(text) : text;
    final decoded = json.decode(source);
    if (decoded is! Map) {
      // 不覆盖无法识别的配置，避免破坏用户文件
      throw const FormatException('配置文件根节点不是 JSON 对象');
    }
    return decoded.cast<String, dynamic>();
  }

  /// 合并更新 .env 文件：保留注释与其他变量，value 为 null 时删除该变量
  Future<void> _updateDotEnv(String filePath, Map<String, String?> updates) async {
    final existing = await _configService.readTextConfig(filePath) ?? '';
    final content = mergeDotEnv(existing, updates);
    await _configService.writeTextConfig(filePath, content);
  }

  /// 解析 .env 内容
  static Map<String, String> parseDotEnv(String content) {
    final result = <String, String>{};
    for (final raw in const LineSplitter().convert(content)) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trim();
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }

  /// 合并 .env 内容（纯函数，便于测试）
  static String mergeDotEnv(String existing, Map<String, String?> updates) {
    final pending = Map<String, String?>.from(updates);
    final out = <String>[];
    for (final raw in const LineSplitter().convert(existing)) {
      final trimmed = raw.trim();
      var body = trimmed.startsWith('export ') ? trimmed.substring(7).trim() : trimmed;
      final idx = body.indexOf('=');
      if (trimmed.isEmpty || trimmed.startsWith('#') || idx <= 0) {
        out.add(raw);
        continue;
      }
      final key = body.substring(0, idx).trim();
      if (!pending.containsKey(key)) {
        out.add(raw);
        continue;
      }
      final value = pending.remove(key);
      if (value != null) out.add('$key=${_quoteEnv(value)}');
    }
    pending.forEach((key, value) {
      if (value != null) out.add('$key=${_quoteEnv(value)}');
    });
    return '${out.join('\n')}\n';
  }

  static String _quoteEnv(String value) {
    if (RegExp(r'^[A-Za-z0-9_\-\.:/@+=,]*$').hasMatch(value)) return value;
    return '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  }
}

/// 极简 TOML 编辑器：只处理 Grok Build 需要的 `[models] default` 与
/// `[model.<alias>]` 表，其余内容按原文保留。
class GrokTomlEditor {
  static final RegExp _header = RegExp(r'^\s*\[([^\[\]]+)\]\s*(#.*)?$');

  /// 写入/替换 `[model.<alias>]` 表并把 `[models] default` 指向该别名
  static String apply(String content, String alias, Map<String, Object> table) {
    final lines = content.isEmpty ? <String>[] : const LineSplitter().convert(content);
    final out = <String>[];
    String? section;
    var defaultWritten = false;
    var hasModelsSection = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = _header.firstMatch(line);
      if (m != null) {
        // 离开 [models] 时若还没写 default，补上
        if (section == 'models' && !defaultWritten) {
          _insertBeforeTrailingBlank(out, 'default = ${_str(alias)}');
          defaultWritten = true;
        }
        section = m.group(1)!.trim();
        if (section == 'models') hasModelsSection = true;
        if (section == 'model.$alias' || section == 'model."$alias"') {
          continue; // 丢弃旧的受管表头
        }
        out.add(line);
        continue;
      }
      if (section == 'model.$alias' || section == 'model."$alias"') {
        continue; // 丢弃旧的受管表内容
      }
      if (section == 'models' && RegExp(r'^\s*default\s*=').hasMatch(line)) {
        out.add('default = ${_str(alias)}');
        defaultWritten = true;
        continue;
      }
      out.add(line);
    }
    if (section == 'models' && !defaultWritten) {
      out.add('default = ${_str(alias)}');
      defaultWritten = true;
    }
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    if (!hasModelsSection) {
      // 追加到末尾，避免把文件开头的顶层键误归入 [models]
      if (out.isNotEmpty) out.add('');
      out.add('[models]');
      out.add('default = ${_str(alias)}');
    }
    if (out.isNotEmpty) out.add('');
    out.add('[model.$alias]');
    table.forEach((key, value) {
      out.add('$key = ${value is String ? _str(value) : value}');
    });
    return '${out.join('\n')}\n';
  }

  static void _insertBeforeTrailingBlank(List<String> out, String line) {
    var idx = out.length;
    while (idx > 0 && out[idx - 1].trim().isEmpty) {
      idx--;
    }
    out.insert(idx, line);
  }

  static String _str(String s) =>
      '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

  /// 粗略解析 `key = "value"` / `key = 123` 形式，返回 section -> {key: value}
  static Map<String, Map<String, String>> parseSimple(String content) {
    final result = <String, Map<String, String>>{};
    var section = '';
    for (final raw in const LineSplitter().convert(content)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = _header.firstMatch(line);
      if (m != null) {
        section = m.group(1)!.trim().replaceAll('"', '');
        continue;
      }
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      var value = line.substring(idx + 1).trim();
      if (value.startsWith('"')) {
        final end = value.lastIndexOf('"');
        value = end > 0
            ? value.substring(1, end).replaceAll(r'\"', '"').replaceAll(r'\\', r'\')
            : value.substring(1);
      } else {
        final hash = value.indexOf('#');
        if (hash >= 0) value = value.substring(0, hash).trim();
      }
      (result[section] ??= {})[key] = value;
    }
    return result;
  }
}
