import 'dart:io';
import 'package:flutter/services.dart';
import '../models/mcp_server.dart';
import '../services/tool_enable_service.dart';
import '../services/settings_service.dart';
import '../viewmodels/key_manager_viewmodel.dart';

/// 状态栏菜单桥接服务
/// 用于在 Flutter 和 macOS 原生代码之间同步状态栏菜单数据
class StatusBarMenuBridge {
  static const MethodChannel _channel = MethodChannel('cn.dlrow.keycore/window');
  static const MethodChannel _statusBarChannel = MethodChannel('cn.dlrow.keycore/statusBar');
  static SettingsService? _settingsService;

  /// 初始化状态栏菜单桥接
  /// 注册原生端调用 Flutter 的方法
  static Future<void> init(KeyManagerViewModel keyManagerViewModel) async {
    if (!Platform.isMacOS) return;
    
    // 初始化 SettingsService 以便获取语言设置
    _settingsService = SettingsService();
    await _settingsService?.init();

    _statusBarChannel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'getClaudeCodeKeys':
            return await _getClaudeCodeKeys(keyManagerViewModel);
          case 'getCodexKeys':
            return await _getCodexKeys(keyManagerViewModel);
          case 'getGeminiKeys':
            return await _getGeminiKeys(keyManagerViewModel);
          case 'getCurrentClaudeCodeKeyId':
            return await _getCurrentClaudeCodeKeyId(keyManagerViewModel);
          case 'getCurrentCodexKeyId':
            return await _getCurrentCodexKeyId(keyManagerViewModel);
          case 'getCurrentGeminiKeyId':
            return await _getCurrentGeminiKeyId(keyManagerViewModel);
          case 'isToolEnabled':
            return await _isToolEnabled(call.arguments as String);
          case 'switchClaudeCodeKey':
            return await _switchClaudeCodeKey(keyManagerViewModel, call.arguments as int);
          case 'switchCodexKey':
            return await _switchCodexKey(keyManagerViewModel, call.arguments as int);
          case 'switchGeminiKey':
            return await _switchGeminiKey(keyManagerViewModel, call.arguments as int);
          default:
            throw PlatformException(
              code: 'UNKNOWN_METHOD',
              message: 'Unknown method: ${call.method}',
            );
        }
      } catch (e) {
        rethrow;
      }
    });
  }

  /// 获取官方配置的国际化文本
  /// 使用与 AppLocalizations 一致的翻译逻辑
  static String _getOfficialConfigText() {
    // 确保 SettingsService 已初始化
    if (_settingsService == null) {
      _settingsService = SettingsService();
      _settingsService?.init();
    }
    
    // 等待初始化完成（使用同步方式，因为 SharedPreferences.getInstance() 是异步的）
    // 但 getLanguage() 方法内部已经处理了 _prefs 为 null 的情况，会返回默认值
    final language = _settingsService?.getLanguage() ?? 'zh';
    
    // 使用与 AppLocalizations 相同的翻译映射
    const Map<String, Map<String, String>> localizedValues = {
      'zh': {
        'official_config': '官方配置',
      },
      'en': {
        'official_config': 'Official Config',
      },
    };
    
    // 根据语言返回对应的文本，默认使用中文
    return localizedValues[language]?['official_config'] ?? 
           localizedValues['zh']!['official_config']!;
  }

  /// 获取 ClaudeCode 密钥列表（包括官方配置）
  static Future<List<Map<String, dynamic>>> _getClaudeCodeKeys(
      KeyManagerViewModel viewModel) async {
    final keys = await viewModel.getClaudeCodeKeys();
    final result = keys.map((key) => {
      'id': key.id,
      'name': key.name,
      'platform': key.platform,
    }).toList();
    
    // 在列表开头添加官方配置选项
    result.insert(0, {
      'id': -1, // 使用 -1 表示官方配置
      'name': _getOfficialConfigText(),
      'platform': 'official',
    });
    
    return result;
  }

  /// 获取 Codex 密钥列表（包括官方配置）
  static Future<List<Map<String, dynamic>>> _getCodexKeys(
      KeyManagerViewModel viewModel) async {
    final keys = await viewModel.getCodexKeys();
    final result = keys.map((key) => {
      'id': key.id,
      'name': key.name,
      'platform': key.platform,
    }).toList();
    
    // 在列表开头添加官方配置选项
    result.insert(0, {
      'id': -1, // 使用 -1 表示官方配置
      'name': _getOfficialConfigText(),
      'platform': 'official',
    });
    
    return result;
  }

  /// 获取 Gemini 密钥列表（包括官方配置）
  static Future<List<Map<String, dynamic>>> _getGeminiKeys(
      KeyManagerViewModel viewModel) async {
    final keys = await viewModel.getGeminiKeys();
    final result = keys.map((key) => {
      'id': key.id,
      'name': key.name,
      'platform': key.platform,
    }).toList();
    
    // 在列表开头添加官方配置选项
    result.insert(0, {
      'id': -1, // 使用 -1 表示官方配置
      'name': _getOfficialConfigText(),
      'platform': 'official',
    });
    
    return result;
  }

  /// 获取当前 ClaudeCode 使用的密钥ID
  /// 返回 -1 表示当前是官方配置，null 表示未配置，其他值表示密钥ID
  static Future<int?> _getCurrentClaudeCodeKeyId(
      KeyManagerViewModel viewModel) async {
    final isOfficial = await viewModel.isOfficialClaudeCodeConfig();
    if (isOfficial) {
      return -1; // 返回 -1 表示官方配置
    }
    final currentKey = await viewModel.getCurrentClaudeCodeKey();
    return currentKey?.id;
  }

  /// 获取当前 Codex 使用的密钥ID
  /// 返回 -1 表示当前是官方配置，null 表示未配置，其他值表示密钥ID
  static Future<int?> _getCurrentCodexKeyId(
      KeyManagerViewModel viewModel) async {
    final isOfficial = await viewModel.isOfficialCodexConfig();
    if (isOfficial) {
      return -1; // 返回 -1 表示官方配置
    }
    final currentKey = await viewModel.getCurrentCodexKey();
    return currentKey?.id;
  }

  /// 获取当前 Gemini 使用的密钥ID
  /// 返回 -1 表示当前是官方配置，null 表示未配置，其他值表示密钥ID
  static Future<int?> _getCurrentGeminiKeyId(
      KeyManagerViewModel viewModel) async {
    final isOfficial = await viewModel.isOfficialGeminiConfig();
    if (isOfficial) {
      return -1; // 返回 -1 表示官方配置
    }
    final currentKey = await viewModel.getCurrentGeminiKey();
    return currentKey?.id;
  }

  /// 检查工具是否启用
  static Future<bool> _isToolEnabled(String toolValue) async {
    final toolEnableService = ToolEnableService();
    await toolEnableService.init();
    
    AiToolType tool;
    switch (toolValue) {
      case 'claudecode':
        tool = AiToolType.claudecode;
        break;
      case 'codex':
        tool = AiToolType.codex;
        break;
      case 'gemini':
        tool = AiToolType.gemini;
        break;
      default:
        return false;
    }
    
    return await toolEnableService.isToolEnabled(tool);
  }

  /// 切换 ClaudeCode 密钥
  /// keyId 为 -1 时表示切换到官方配置
  static Future<bool> _switchClaudeCodeKey(
      KeyManagerViewModel viewModel, int keyId) async {
    if (keyId == -1) {
      // 切换到官方配置
      return await viewModel.switchToOfficialClaudeCode();
    } else {
      // 切换到指定密钥
      return await viewModel.switchClaudeCodeProvider(keyId);
    }
  }

  /// 切换 Codex 密钥
  /// keyId 为 -1 时表示切换到官方配置
  static Future<bool> _switchCodexKey(
      KeyManagerViewModel viewModel, int keyId) async {
    if (keyId == -1) {
      // 切换到官方配置
      return await viewModel.switchToOfficialCodex();
    } else {
      // 切换到指定密钥
      return await viewModel.switchCodexProvider(keyId);
    }
  }

  /// 切换 Gemini 密钥
  /// keyId 为 -1 时表示切换到官方配置
  static Future<bool> _switchGeminiKey(
      KeyManagerViewModel viewModel, int keyId) async {
    if (keyId == -1) {
      // 切换到官方配置
      return await viewModel.switchToOfficialGemini();
    } else {
      // 切换到指定密钥
      return await viewModel.switchGeminiProvider(keyId);
    }
  }

  /// 通知原生端更新状态栏菜单
  static Future<void> updateStatusBarMenu() async {
    if (!Platform.isMacOS) return;

    try {
      await _channel.invokeMethod('updateStatusBarMenu');
    } catch (e) {
      // 忽略 MissingPluginException，因为 MethodChannel 可能还未注册
      if (e is MissingPluginException) {
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await _channel.invokeMethod('updateStatusBarMenu');
          } catch (_) {
            // 忽略重试失败
          }
        });
      }
    }
  }
}

