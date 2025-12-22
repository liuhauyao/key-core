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
    'openAI',
    'azureOpenAI',
    'chatgpt',
    'openai-compatible',
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

    // 检查用户是否已手动设置过
    final hasUserManualSet = prefs.containsKey(_userManualSetKey);
    print('👤 RegionFilter: 用户是否手动设置过 - ${hasUserManualSet ? '是' : '否'}');

    // 如果用户从未手动设置过，进行默认值设置
    if (!hasUserManualSet) {
      // 根据地区设置默认值：中国大陆默认开启，非中国大陆默认关闭
      await prefs.setBool(_chinaRegionKey, isChina);
      print('⚙️ RegionFilter: 设置默认值 - ${isChina ? '开启地区过滤' : '关闭地区过滤'}');
    } else {
      // 用户已手动设置过，保持用户设置
      final currentSetting = prefs.getBool(_chinaRegionKey) ?? false;
      print('🔒 RegionFilter: 保持用户手动设置 - ${currentSetting ? '开启地区过滤' : '关闭地区过滤'}');
    }

    // 标记为已检测（用于其他逻辑）
    await prefs.setBool(_regionDetectionKey, true);
    print('✅ RegionFilter: 地区过滤服务初始化完成');

    // 输出最终状态摘要
    final finalStatus = await getRegionStatus();
    print('📊 RegionFilter: 最终状态 - 地区: ${finalStatus['isRegionDetected'] ? '中国大陆' : '非中国大陆'}, 过滤: ${finalStatus['isChinaFilterEnabled'] ? '开启' : '关闭'}');
  }

  /// 检测是否为中国大陆地区
  /// 通过时区、语言环境等多种方式进行检测
  static Future<bool> _detectChinaRegion() async {
    try {
      print('🔎 RegionFilter: 开始检测中国大陆地区特征...');

      // 1. 检查时区
      final timezone = DateTime.now().timeZoneName.toLowerCase();
      print('🕐 RegionFilter: 时区检测 - 原始值: "${DateTime.now().timeZoneName}", 小写: "$timezone"');
      if (timezone.contains('cst') || timezone.contains('china')) {
        print('✅ RegionFilter: 时区检测通过 - 包含 "cst" 或 "china"');
        return true;
      }
      print('❌ RegionFilter: 时区检测未通过');

      // 2. 检查系统语言环境
      final locale = Platform.localeName.toLowerCase();
      print('🌐 RegionFilter: 语言环境检测 - 原始值: "${Platform.localeName}", 小写: "$locale"');
      if (locale.startsWith('zh_cn') || locale.startsWith('zh-hans-cn')) {
        print('✅ RegionFilter: 语言环境检测通过 - 以 "zh_cn" 或 "zh-hans-cn" 开头');
        return true;
      }
      print('❌ RegionFilter: 语言环境检测未通过');

      // 3. 检查环境变量
      final lang = Platform.environment['LANG']?.toLowerCase() ?? '';
      print('🔧 RegionFilter: LANG环境变量检测 - 原始值: "${Platform.environment['LANG']}", 小写: "$lang"');
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
  static Future<bool> isChinaRegionFilterEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chinaRegionKey) ?? false;
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

  /// 检查是否应该显示地区过滤设置（在中国大陆地区必须显示）
  static Future<bool> shouldShowRegionFilterSetting() async {
    return await isInChinaRegion();
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
