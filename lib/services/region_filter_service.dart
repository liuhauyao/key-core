import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// 地区过滤服务
/// 用于检测用户地区并提供地区相关的过滤功能
class RegionFilterService {
  static const String _chinaRegionKey = 'region_filter_china';
  static const String _regionDetectionKey = 'region_filter_detected';
  static const String _userManualSetKey = 'region_filter_user_manual_set';
  static const String _detectedRegionKey = 'region_filter_detected_region';

  static final List<String> _chinaRestrictedPlatforms = [
    'openai',
    'azureopenai',
    'chatgpt',
  ];

  static final List<String> _chinaRestrictedKeywords = [
    'openai',
    'chatgpt',
    'api.openai.com',
    'platform.openai.com',
    'chatgpt.com',
    'openai.azure.com',
  ];

  /// 初始化地区检测
  static Future<void> init() async {
    print('🔍 RegionFilter: 开始初始化地区过滤服务');
    final prefs = await SharedPreferences.getInstance();

    // 每次启动都重新检测地区
    final isChina = await _detectChinaRegion();
    print('📍 RegionFilter: 时区检测结果 - ${isChina ? '中国大陆' : '非中国大陆'}');

    // 记录当前检测到的地区
    await prefs.setBool(_detectedRegionKey, isChina);
    print('💾 RegionFilter: 已保存检测结果到SharedPreferences');

    // 中国大陆地区强制开启地区过滤，非中国大陆地区关闭
    final shouldEnableFilter = isChina;
    await prefs.setBool(_chinaRegionKey, shouldEnableFilter);
    print(
        '🔒 RegionFilter: 强制设置地区过滤 - ${shouldEnableFilter ? '开启（中国大陆地区合规要求）' : '关闭（非中国大陆地区）'}');

    // 标记为已检测（用于其他逻辑）
    await prefs.setBool(_regionDetectionKey, true);
    print('✅ RegionFilter: 地区过滤服务初始化完成');

    // 输出最终状态摘要
    final finalStatus = await getRegionStatus();
    print(
        '📊 RegionFilter: 最终状态 - 地区: ${finalStatus['isRegionDetected'] ? '中国大陆' : '非中国大陆'}, 过滤: ${finalStatus['isChinaFilterEnabled'] ? '开启（强制）' : '关闭'}');
  }

  /// 检测是否为中国大陆地区
  /// 通过时区、语言环境等多种方式进行检测
  static Future<bool> _detectChinaRegion() async {
    try {
      print('🔎 RegionFilter: 开始检测中国大陆地区特征...');

      // 1. 检查时区
      final timezone = DateTime.now().timeZoneName.toLowerCase();
      print(
          '🕐 RegionFilter: 时区检测 - 原始值: "${DateTime.now().timeZoneName}", 小写: "$timezone"');
      if (timezone.contains('cst') || timezone.contains('china')) {
        print('✅ RegionFilter: 时区检测通过 - 包含 "cst" 或 "china"');
        return true;
      }
      print('❌ RegionFilter: 时区检测未通过');

      // 2. 检查系统语言环境
      final locale = Platform.localeName.toLowerCase();
      print(
          '🌐 RegionFilter: 语言环境检测 - 原始值: "${Platform.localeName}", 小写: "$locale"');
      if (locale.startsWith('zh_cn') || locale.startsWith('zh-hans-cn')) {
        print('✅ RegionFilter: 语言环境检测通过 - 以 "zh_cn" 或 "zh-hans-cn" 开头');
        return true;
      }
      print('❌ RegionFilter: 语言环境检测未通过');

      // 3. 检查环境变量
      final lang = Platform.environment['LANG']?.toLowerCase() ?? '';
      print(
          '🔧 RegionFilter: LANG环境变量检测 - 原始值: "${Platform.environment['LANG']}", 小写: "$lang"');
      if (lang.contains('zh_cn') || lang.contains('zh-hans')) {
        print('✅ RegionFilter: LANG环境变量检测通过 - 包含 "zh_cn" 或 "zh-hans"');
        return true;
      }
      print('❌ RegionFilter: LANG环境变量检测未通过');

      print('🚫 RegionFilter: 未检测到任何中国大陆地区特征，返回非中国大陆地区');
      // 默认返回false（非中国大陆）
      return false;
    } catch (e) {
      // 检测失败时默认返回false
      print('💥 RegionFilter: 地区检测过程中发生错误: $e');
      print('🚫 RegionFilter: 由于检测失败，返回非中国大陆地区');
      return false;
    }
  }

  /// 获取当前是否启用中国地区过滤
  /// 中国大陆地区强制返回true，非中国大陆地区返回false
  static Future<bool> isChinaRegionFilterEnabled() async {
    final isChina = await isInChinaRegion();
    if (isChina) {
      // 中国大陆地区强制开启地区过滤
      return true;
    }
    // 非中国大陆地区关闭地区过滤
    return false;
  }

  /// 设置中国地区过滤状态
  static Future<void> setChinaRegionFilter(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_chinaRegionKey, enabled);

    // 记录用户已手动设置
    await prefs.setBool(_userManualSetKey, true);
  }

  /// 检查是否在中国大陆地区
  static Future<bool> isInChinaRegion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_detectedRegionKey) ?? false;
  }

  /// 检查用户是否手动设置过地区过滤
  static Future<bool> isUserManualSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_userManualSetKey) ?? false;
  }

  /// 检查是否应该显示地区过滤设置（中国大陆地区隐藏设置项，因为强制开启）
  static Future<bool> shouldShowRegionFilterSetting() async {
    // 中国大陆地区强制开启地区过滤，隐藏设置项
    // 非中国大陆地区显示设置项，让用户可以选择
    return !(await isInChinaRegion());
  }

  /// 重置地区检测（用于测试或重新检测）
  static Future<void> resetRegionDetection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chinaRegionKey);
    await prefs.remove(_regionDetectionKey);
    await prefs.remove(_userManualSetKey);
    await prefs.remove(_detectedRegionKey);
  }

  /// 检查平台是否在中国大陆受限
  static bool isPlatformRestrictedInChina(String platformId) {
    return _chinaRestrictedPlatforms.contains(platformId.toLowerCase()) ||
        _chinaRestrictedPlatforms.any((restricted) =>
            platformId.toLowerCase().contains(restricted.toLowerCase()));
  }

  /// 文本是否包含中国大陆受限关键词（OpenAI/ChatGPT 相关）
  static bool containsRestrictedKeyword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final normalized = value.toLowerCase();
    return _chinaRestrictedKeywords.any(normalized.contains);
  }

  /// URL/域名是否命中中国大陆受限域名（OpenAI/ChatGPT 相关）
  static bool isRestrictedUrlInChina(String? urlOrHost) {
    if (urlOrHost == null || urlOrHost.trim().isEmpty) {
      return false;
    }

    final raw = urlOrHost.trim();
    final uri = Uri.tryParse(
        raw.startsWith('http://') || raw.startsWith('https://')
            ? raw
            : 'https://$raw');
    final host = uri?.host.toLowerCase() ?? raw.toLowerCase();
    return _chinaRestrictedKeywords.any(host.contains);
  }

  /// 基于平台与端点配置检查是否命中中国大陆受限能力
  static bool isKeyRestrictedInChina({
    required String platformId,
    String? platformName,
    String? apiEndpoint,
    String? codexBaseUrl,
    String? claudeCodeBaseUrl,
    String? managementUrl,
  }) {
    if (isPlatformRestrictedInChina(platformId)) {
      return true;
    }
    if (platformName != null && containsRestrictedKeyword(platformName)) {
      return true;
    }

    return isRestrictedUrlInChina(apiEndpoint) ||
        isRestrictedUrlInChina(codexBaseUrl) ||
        isRestrictedUrlInChina(claudeCodeBaseUrl) ||
        isRestrictedUrlInChina(managementUrl);
  }

  /// 获取过滤后的平台列表（移除中国大陆受限平台）
  static List<T> filterPlatformsForChina<T>(
    List<T> platforms,
    String Function(T) getPlatformId,
  ) {
    // 如果未启用中国地区过滤，返回原始列表
    // 注意：这里我们直接返回false，因为在UI层面我们需要根据用户设置来决定
    // 实际的过滤逻辑在调用处处理
    return platforms;
  }

  /// 获取中国大陆受限平台列表
  static List<String> get chinaRestrictedPlatforms => _chinaRestrictedPlatforms;

  /// 获取当前地区状态信息
  static Future<Map<String, dynamic>> getRegionStatus() async {
    final isChinaFilterEnabled = await isChinaRegionFilterEnabled();
    final prefs = await SharedPreferences.getInstance();
    final isRegionDetected = prefs.getBool(_regionDetectionKey) ?? false;

    return {
      'isChinaFilterEnabled': isChinaFilterEnabled,
      'isRegionDetected': isRegionDetected,
      'chinaRestrictedPlatforms': _chinaRestrictedPlatforms,
      'timezone': DateTime.now().timeZoneName,
      'locale': Platform.localeName,
      'lang': Platform.environment['LANG'],
    };
  }
}
