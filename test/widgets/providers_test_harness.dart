import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:key_core/models/provider.dart';
import 'package:key_core/services/tool_switcher_service.dart';
import 'package:key_core/utils/app_localizations.dart';
import 'package:key_core/viewmodels/providers_viewmodel.dart';
import 'package:provider/provider.dart' hide Provider;
import 'package:shadcn_ui/shadcn_ui.dart';

/// 测试用本地化 delegate：只使用内置翻译，不触发语言包下载 / SharedPreferences
class TestL10nDelegate extends LocalizationsDelegate<AppLocalizations> {
  const TestL10nDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(TestL10nDelegate old) => false;
}

final DateTime fixedNow = DateTime(2026, 10, 9, 12, 0);

Provider makeProvider({
  required String id,
  required String name,
  String? nameZh,
  String type = 'official',
  String? endpoint,
  String? apiKey,
  List<String> models = const [],
  List<String> tools = const ['claude_code', 'gemini_cli', 'openclaw', 'grok_build'],
  bool active = true,
  String? apiKeyUrl,
}) {
  return Provider(
    id: id,
    name: name,
    nameZh: nameZh,
    providerType: type,
    apiEndpoint: endpoint,
    apiKey: apiKey,
    models: models.map((m) => ProviderModel(id: m, displayName: m)).toList(),
    supportedTools: tools,
    isActive: active,
    apiKeyUrl: apiKeyUrl,
    createdAt: fixedNow,
    updatedAt: fixedNow,
  );
}

/// 内存实现的后端，记录所有调用
class FakeProviderBackend implements ProviderBackend {
  final List<Provider> presets;
  final List<Provider> stored;
  final Map<String, String> current;
  final Map<String, List<ConfigBackup>> backups;
  bool encryption;

  final List<Provider> saved = [];
  final List<String> deleted = [];
  final List<MapEntry<String, String>> switched = [];
  final List<String> restored = [];
  Object? switchError;

  FakeProviderBackend({
    List<Provider>? presets,
    List<Provider>? stored,
    Map<String, String>? current,
    Map<String, List<ConfigBackup>>? backups,
    this.encryption = true,
  })  : presets = presets ?? [],
        stored = stored ?? [],
        current = current ?? {},
        backups = backups ?? {};

  @override
  Future<List<Provider>> loadPresets() async => presets;

  @override
  Future<List<Provider>> getAllProviders() async => List.of(stored);

  @override
  Future<void> saveProvider(Provider provider) async {
    saved.add(provider);
    final idx = stored.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      stored[idx] = provider;
    } else {
      stored.insert(0, provider);
    }
  }

  @override
  Future<void> deleteProvider(String id) async {
    deleted.add(id);
    stored.removeWhere((p) => p.id == id);
  }

  @override
  Future<bool> isEncryptionEnabled() async => encryption;

  @override
  Future<void> switchTool(Provider provider, String tool) async {
    if (switchError != null) throw switchError!;
    switched.add(MapEntry(tool, provider.id));
  }

  @override
  Future<ToolLiveState> readLiveState(String tool) async {
    final id = current[tool];
    Provider? p;
    for (final s in stored) {
      if (s.id == id) p = s;
    }
    return ToolLiveState(
      tool: tool,
      configPath: '/home/user/.$tool/config',
      configExists: p != null,
      hasApiKey: p != null,
      baseUrl: p?.apiEndpoint,
      model: p != null && p.models.isNotEmpty ? p.models.first.id : null,
    );
  }

  @override
  Future<List<ConfigBackup>> listBackups(String tool) async => backups[tool] ?? [];

  @override
  Future<void> restoreBackup(String tool, String backupPath) async {
    restored.add('$tool|$backupPath');
  }

  @override
  Future<Map<String, String>> loadCurrentSelections() async => Map.of(current);

  @override
  Future<void> saveCurrentSelection(String tool, String? providerId) async {
    if (providerId == null) {
      current.remove(tool);
    } else {
      current[tool] = providerId;
    }
  }
}

Widget buildTestApp({
  required ProvidersViewModel vm,
  required Widget child,
  Locale locale = const Locale('zh'),
  Brightness brightness = Brightness.light,
}) {
  final shadTheme = ShadThemeData(
    brightness: brightness,
    colorScheme: brightness == Brightness.dark
        ? const ShadSlateColorScheme.dark(primary: Color(0xFF007AFF))
        : const ShadSlateColorScheme.light(primary: Color(0xFF007AFF)),
  );
  return ShadTheme(
    data: shadTheme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        TestL10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(useMaterial3: true, brightness: brightness),
      home: ChangeNotifierProvider<ProvidersViewModel>.value(
        value: vm,
        child: Scaffold(
          backgroundColor: shadTheme.colorScheme.background,
          body: child,
        ),
      ),
    ),
  );
}
