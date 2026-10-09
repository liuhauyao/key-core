import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_core/services/tool_switcher_service.dart';
import 'package:key_core/utils/app_localizations.dart';
import 'package:key_core/viewmodels/providers_viewmodel.dart';
import 'package:key_core/views/screens/providers_screen.dart';
import 'package:key_core/views/widgets/app_switcher.dart';

import 'providers_test_harness.dart';

FakeProviderBackend _backend() => FakeProviderBackend(
      presets: [
        makeProvider(
          id: 'deepseek-official',
          name: 'DeepSeek',
          nameZh: '深度求索',
          endpoint: 'https://api.deepseek.com/anthropic',
          models: ['deepseek-v4-pro', 'deepseek-v4-flash'],
          tools: ['claude_code', 'openclaw', 'grok_build', 'codex'],
          apiKeyUrl: 'https://platform.deepseek.com/api_keys',
        ),
      ],
      stored: [
        makeProvider(
          id: 'anthropic-official-1',
          name: 'Anthropic Official',
          endpoint: 'https://api.anthropic.com',
          apiKey: 'sk-ant-1234567890abcd',
          models: ['claude-sonnet-5-5'],
          tools: ['claude_code', 'openclaw'],
        ),
        makeProvider(
          id: 'custom-2',
          name: 'My Relay',
          type: 'custom',
          endpoint: 'https://relay.example.com/v1',
          apiKey: 'sk-relay-9999999999wxyz',
          models: ['glm-5-pro'],
        ),
      ],
      current: {'claude_code': 'anthropic-official-1'},
      backups: {
        'claude_code': [
          ConfigBackup(
            path: '/home/user/.claude/settings.json.backup.1791520569415',
            createdAt: DateTime(2026, 10, 9, 11, 30, 5),
            sizeBytes: 2048,
          ),
        ],
      },
    );

Future<ProvidersViewModel> _pump(
  WidgetTester tester,
  FakeProviderBackend backend, {
  ProvidersTab tab = ProvidersTab.list,
  Locale locale = const Locale('zh'),
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final vm = ProvidersViewModel(backend: backend);
  await tester.pumpWidget(buildTestApp(
    vm: vm,
    locale: locale,
    child: ProvidersScreen(initialTab: tab),
  ));
  await tester.pumpAndSettle();
  return vm;
}

void main() {
  group('Provider list', () {
    testWidgets('shows providers with masked keys and in-use badge', (tester) async {
      await _pump(tester, _backend());

      expect(find.text('Anthropic Official'), findsOneWidget);
      expect(find.text('My Relay'), findsOneWidget);
      // 只显示末 4 位
      expect(find.textContaining('••••abcd'), findsOneWidget);
      expect(find.textContaining('sk-ant-1234567890abcd'), findsNothing);
      expect(find.text('使用中：Claude Code'), findsOneWidget);
      // 已设置主密码 → 显示加密标识
      expect(find.text('密钥已加密存储'), findsOneWidget);
    });

    testWidgets('search filters providers', (tester) async {
      await _pump(tester, _backend());
      await tester.enterText(find.byKey(const Key('providers_search')), 'relay');
      await tester.pumpAndSettle();
      expect(find.text('My Relay'), findsOneWidget);
      expect(find.text('Anthropic Official'), findsNothing);
    });

    testWidgets('create provider from preset stores api key via backend', (tester) async {
      final backend = _backend();
      await _pump(tester, backend);

      await tester.tap(find.byKey(const Key('providers_add')));
      await tester.pumpAndSettle();
      expect(find.text('添加供应商'), findsWidgets);

      await tester.tap(find.byKey(const Key('preset_deepseek-official')));
      await tester.pumpAndSettle();
      // 预设自动填充
      expect(find.text('https://api.deepseek.com/anthropic'), findsOneWidget);
      expect(find.text('获取 API Key'), findsOneWidget);

      // 缺少 API Key 时校验失败
      await tester.tap(find.byKey(const Key('provider_form_save')));
      await tester.pumpAndSettle();
      expect(find.text('请输入 API Key'), findsOneWidget);
      expect(backend.saved, isEmpty);

      await tester.enterText(find.byKey(const Key('provider_api_key')), 'sk-deepseek-new-key');
      await tester.tap(find.byKey(const Key('provider_form_save')));
      await tester.pumpAndSettle();

      expect(backend.saved, hasLength(1));
      final saved = backend.saved.single;
      expect(saved.name, 'DeepSeek');
      expect(saved.apiKey, 'sk-deepseek-new-key');
      expect(saved.id, startsWith('deepseek-official-'));
      expect(saved.models.first.id, 'deepseek-v4-pro');
      // 非可切换工具（codex）从预设中保留
      expect(saved.supportedTools, containsAll(['claude_code', 'openclaw', 'grok_build', 'codex']));
      // 返回列表并提示
      expect(find.text('供应商已保存'), findsOneWidget);
      expect(find.text('DeepSeek'), findsOneWidget);
    });

    testWidgets('editing without new key keeps the existing key', (tester) async {
      final backend = _backend();
      await _pump(tester, backend);

      await tester.tap(find.byKey(const Key('provider_edit_custom-2')));
      await tester.pumpAndSettle();
      expect(find.text('编辑供应商'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('provider_name')), 'Relay Renamed');
      await tester.enterText(find.byKey(const Key('provider_model')), 'glm-5.2-flash');
      await tester.tap(find.byKey(const Key('provider_form_save')));
      await tester.pumpAndSettle();

      final saved = backend.saved.single;
      expect(saved.id, 'custom-2');
      expect(saved.name, 'Relay Renamed');
      expect(saved.apiKey, 'sk-relay-9999999999wxyz');
      expect(saved.models.first.id, 'glm-5.2-flash');
      expect(saved.models.map((m) => m.id), contains('glm-5-pro'));
    });

    testWidgets('delete asks for confirmation and clears tool selection', (tester) async {
      final backend = _backend();
      final vm = await _pump(tester, backend);

      await tester.tap(find.byKey(const Key('provider_delete_anthropic-official-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定删除供应商"Anthropic Official"'), findsOneWidget);

      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(backend.deleted, ['anthropic-official-1']);
      expect(find.text('Anthropic Official'), findsNothing);
      expect(vm.currentProvider('claude_code'), isNull);
      expect(backend.current.containsKey('claude_code'), isFalse);
    });

    testWidgets('shows plaintext warning when no master password', (tester) async {
      final backend = _backend()..encryption = false;
      await _pump(tester, backend);
      expect(find.text('未设置主密码'), findsOneWidget);
    });
  });

  testWidgets('still lists providers when secure storage is unavailable', (tester) async {
    final backend = _backend()..encryptionError = Exception('Libsecret error');
    await _pump(tester, backend);
    expect(find.text('My Relay'), findsOneWidget);
    expect(find.text('未设置主密码'), findsOneWidget);
  });

  group('Tool switch', () {
    testWidgets('shows current provider per tool and switches in one click', (tester) async {
      final backend = _backend();
      final vm = await _pump(tester, backend, tab: ProvidersTab.tools);

      for (final name in ['Claude Code', 'Gemini CLI', 'OpenClaw', 'Grok Build']) {
        expect(find.text(name), findsOneWidget);
      }
      final claudeCurrent = tester.widget<Text>(find.byKey(const Key('tool_current_claude_code')));
      expect(claudeCurrent.data, 'Anthropic Official');
      final geminiCurrent = tester.widget<Text>(find.byKey(const Key('tool_current_gemini_cli')));
      expect(geminiCurrent.data, '未通过 Key Core 设置');

      await tester.tap(find.byKey(const Key('switch_claude_code_custom-2')));
      await tester.pumpAndSettle();

      expect(backend.switched.single.key, 'claude_code');
      expect(backend.switched.single.value, 'custom-2');
      expect(vm.currentProvider('claude_code')?.id, 'custom-2');
      expect(find.text('已将 Claude Code 切换到 My Relay，重启 Claude Code 后生效'), findsOneWidget);
      final updated = tester.widget<Text>(find.byKey(const Key('tool_current_claude_code')));
      expect(updated.data, 'My Relay');
    });

    testWidgets('reports switch failures', (tester) async {
      final backend = _backend()..switchError = StateError('boom');
      final vm = await _pump(tester, backend, tab: ProvidersTab.tools);
      await tester.tap(find.byKey(const Key('switch_gemini_cli_custom-2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('切换失败'), findsOneWidget);
      expect(vm.currentProvider('gemini_cli'), isNull);
    });
  });

  group('Backups', () {
    testWidgets('lists backups and restores after confirmation', (tester) async {
      final backend = _backend();
      await _pump(tester, backend, tab: ProvidersTab.backups);

      expect(find.text('2026-10-09 11:30:05'), findsOneWidget);
      expect(find.textContaining('settings.json.backup.1791520569415'), findsOneWidget);

      await tester.tap(find.byKey(const Key('restore_backup_0')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确定将 Claude Code 的配置恢复到 2026-10-09 11:30:05 的备份吗'),
          findsOneWidget);
      await tester.tap(find.text('恢复').last);
      await tester.pumpAndSettle();

      expect(backend.restored,
          ['claude_code|/home/user/.claude/settings.json.backup.1791520569415']);
      expect(find.text('配置已恢复'), findsOneWidget);
      // 恢复后不再认为工具使用某个供应商
      expect(backend.current.containsKey('claude_code'), isFalse);
    });

    testWidgets('switching tool shows empty state', (tester) async {
      await _pump(tester, _backend(), tab: ProvidersTab.backups);
      await tester.tap(find.byKey(const Key('backup_tool_grok_build')));
      await tester.pumpAndSettle();
      expect(find.text('暂无备份'), findsOneWidget);
    });
  });

  testWidgets('renders English strings', (tester) async {
    await _pump(tester, _backend(), locale: const Locale('en'));
    expect(find.text('Add Provider'), findsOneWidget);
    expect(find.text('Tool Switch'), findsOneWidget);
    expect(find.text('In use: Claude Code'), findsOneWidget);
  });

  test('navigation includes providers entry with localized label', () {
    expect(AppType.values, contains(AppType.providers));
    expect(AppType.values.indexOf(AppType.providers), 1);
    expect(AppLocalizations(const Locale('zh')).navProviders, '供应商');
    expect(AppLocalizations(const Locale('en')).navProviders, 'Providers');
    // 其他语言缺失时回退英文而不是显示 key
    expect(AppLocalizations(const Locale('ja')).navProviders, 'Providers');
  });
}
