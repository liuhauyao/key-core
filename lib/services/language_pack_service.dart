import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import '../models/cloud_config.dart';
import 'cloud_config_service.dart';

/// 语言包服务
class LanguagePackService {
  static const String _keyLastUpdateCheckPrefix = 'lang_pack_last_check_';
  
  // 默认语言包URL（GitHub Raw）
  static const String _defaultBaseUrl = 
      'https://raw.githubusercontent.com/liuhauyao/key-core-config/main/locales';
  
  // Gitee备选URL（国内用户）
  static const String _giteeBaseUrl = 
      'https://gitee.com/liuhauyao/key-core-config/raw/main/locales';
  
  // 更新检查间隔（24小时）
  static const Duration _updateCheckInterval = Duration(hours: 24);
  
  SharedPreferences? _prefs;
  final Map<String, Map<String, String>> _cachedPacks = {}; // 内存缓存：语言代码 -> 翻译映射
  final CloudConfigService _cloudConfigService = CloudConfigService();
  bool _isInitialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_isInitialized) return;
    
    _prefs = await SharedPreferences.getInstance();
    await _cloudConfigService.init();
    
    _isInitialized = true;
  }

  /// 获取支持的语言列表
  Future<List<SupportedLanguage>> getSupportedLanguages() async {
    await init();
    
    final configData = await _cloudConfigService.getConfigData();
    if (configData?.supportedLanguages != null) {
      return configData!.supportedLanguages!;
    }
    
    // 如果没有配置，返回默认的中英文
    return [
      SupportedLanguage(
        code: 'zh',
        name: 'Chinese',
        nativeName: '简体中文',
        file: 'zh.json',
        lastUpdated: DateTime.now().toIso8601String(),
      ),
      SupportedLanguage(
        code: 'en',
        name: 'English',
        nativeName: 'English',
        file: 'en.json',
        lastUpdated: DateTime.now().toIso8601String(),
      ),
    ];
  }

  /// 获取语言包的云端URL
  String getLanguagePackUrl(String languageCode, {bool useGitee = false}) {
    final baseUrl = useGitee ? _giteeBaseUrl : _defaultBaseUrl;
    return '$baseUrl/$languageCode.json';
  }

  /// 从云端下载语言包
  Future<Map<String, String>?> fetchLanguagePack(String languageCode) async {
    await init();
    
    // 先尝试GitHub
    final url = getLanguagePackUrl(languageCode);
    
    // 验证URL必须是HTTPS
    if (!url.startsWith('https://')) {
      print('LanguagePackService: 语言包URL必须使用HTTPS: $url');
      return null;
    }
    
    try {
      print('LanguagePackService: 从云端获取语言包: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AI-Key-Manager/1.0',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );
      
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final translations = Map<String, String>.from(
          jsonData.map((key, value) => MapEntry(key as String, value.toString())),
        );
        print('LanguagePackService: 成功获取语言包: $languageCode');
        return translations;
      } else {
        print('LanguagePackService: 获取语言包失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('LanguagePackService: 获取语言包异常: $e');
      // 如果GitHub失败，尝试Gitee
      if (!url.contains('gitee.com')) {
        print('LanguagePackService: GitHub获取失败，尝试Gitee');
        final giteeUrl = getLanguagePackUrl(languageCode, useGitee: true);
        try {
          final response = await http.get(
            Uri.parse(giteeUrl),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'AI-Key-Manager/1.0',
            },
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('请求超时');
            },
          );
          
          if (response.statusCode == 200) {
            final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
            final translations = Map<String, String>.from(
              jsonData.map((key, value) => MapEntry(key as String, value.toString())),
            );
            print('LanguagePackService: 成功从Gitee获取语言包: $languageCode');
            return translations;
          }
        } catch (e2) {
          print('LanguagePackService: Gitee获取也失败: $e2');
        }
      }
      return null;
    }
  }

  /// 从内置 assets 加载语言包（应用打包时内置）
  Future<Map<String, String>?> loadBuiltinLanguagePack(String languageCode) async {
    try {
      print('LanguagePackService: 从内置资源加载语言包: $languageCode');
      final jsonString = await rootBundle.loadString('assets/locales/$languageCode.json');
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final translations = Map<String, String>.from(
        jsonData.map((key, value) => MapEntry(key as String, value.toString())),
      );
      print('LanguagePackService: 成功加载内置语言包: $languageCode');
      return translations;
    } catch (e) {
      print('LanguagePackService: 加载内置语言包失败: $e');
      return null;
    }
  }

  /// 从本地缓存文件加载语言包
  Future<Map<String, String>?> loadLocalLanguagePack(String languageCode) async {
    try {
      await init();
      final appDir = await getApplicationDocumentsDirectory();
      final langFile = File(path.join(appDir.path, 'locales', '$languageCode.json'));
      
      if (!await langFile.exists()) {
        print('LanguagePackService: 本地语言包文件不存在: $languageCode');
        return null;
      }
      
      final jsonString = await langFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final translations = Map<String, String>.from(
        jsonData.map((key, value) => MapEntry(key as String, value.toString())),
      );
      print('LanguagePackService: 成功加载本地语言包: $languageCode');
      return translations;
    } catch (e) {
      print('LanguagePackService: 加载本地语言包失败: $e');
      return null;
    }
  }

  /// 保存语言包到本地缓存
  Future<bool> saveLanguagePackToCache(
    String languageCode,
    Map<String, String> translations,
  ) async {
    try {
      await init();
      final appDir = await getApplicationDocumentsDirectory();
      final localesDir = Directory(path.join(appDir.path, 'locales'));
      
      // 确保目录存在
      if (!await localesDir.exists()) {
        await localesDir.create(recursive: true);
      }
      
      final langFile = File(path.join(localesDir.path, '$languageCode.json'));
      final jsonData = Map<String, dynamic>.from(translations);
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      await langFile.writeAsString(jsonString);
      
      print('LanguagePackService: 成功保存语言包到本地缓存: $languageCode');
      return true;
    } catch (e) {
      print('LanguagePackService: 保存语言包到本地缓存失败: $e');
      return false;
    }
  }

  /// 检查语言包是否需要更新
  Future<bool> shouldCheckLanguagePackUpdate(String languageCode) async {
    await init();
    
    final lastCheckKey = '$_keyLastUpdateCheckPrefix$languageCode';
    final lastCheckStr = _prefs?.getString(lastCheckKey);
    
    if (lastCheckStr == null) {
      return true; // 从未检查过，需要检查
    }
    
    try {
      final lastCheck = DateTime.parse(lastCheckStr);
      final now = DateTime.now();
      return now.difference(lastCheck) >= _updateCheckInterval;
    } catch (e) {
      return true; // 解析失败，需要检查
    }
  }

  /// 记录语言包更新检查时间
  Future<void> _recordLanguagePackUpdateCheck(String languageCode) async {
    await init();
    final lastCheckKey = '$_keyLastUpdateCheckPrefix$languageCode';
    await _prefs?.setString(lastCheckKey, DateTime.now().toIso8601String());
  }

  /// 检查语言包更新
  /// 返回: true表示有更新，false表示无更新或检查失败
  Future<bool> checkLanguagePackUpdate(String languageCode, {bool force = false}) async {
    await init();
    
    // 如果不是强制检查，且距离上次检查时间未超过间隔，则跳过
    if (!force && !await shouldCheckLanguagePackUpdate(languageCode)) {
      print('LanguagePackService: 距离上次检查时间未超过间隔，跳过检查: $languageCode');
      return false;
    }
    
    // 记录检查时间
    await _recordLanguagePackUpdateCheck(languageCode);
    
    // 获取支持的语言列表，找到对应语言的配置
    final supportedLanguages = await getSupportedLanguages();
    final languageInfo = supportedLanguages.firstWhere(
      (lang) => lang.code == languageCode,
      orElse: () => SupportedLanguage(
        code: languageCode,
        name: languageCode,
        nativeName: languageCode,
        file: '$languageCode.json',
        lastUpdated: DateTime.now().toIso8601String(),
      ),
    );
    
    // 获取本地语言包的时间戳
    final localPack = await loadLocalLanguagePack(languageCode);
    final localLastUpdated = localPack != null 
        ? await _getLocalLanguagePackLastUpdated(languageCode)
        : null;
    
    final cloudLastUpdated = languageInfo.lastUpdated;
    
    // 如果没有本地语言包，直接下载
    if (localLastUpdated == null) {
      print('LanguagePackService: 本地无语言包，准备下载: $languageCode');
      final translations = await fetchLanguagePack(languageCode);
      if (translations != null) {
        await saveLanguagePackToCache(languageCode, translations);
        await _saveLocalLanguagePackLastUpdated(languageCode, cloudLastUpdated);
        _cachedPacks[languageCode] = translations;
        return true;
      }
      return false;
    }
    
    // 比较时间戳
    try {
      final localDate = DateTime.parse(localLastUpdated);
      final cloudDate = DateTime.parse(cloudLastUpdated);
      
      if (cloudDate.isAfter(localDate)) {
        // 云端时间戳更新，需要更新
        print('LanguagePackService: 发现新语言包，准备更新: $languageCode');
        final translations = await fetchLanguagePack(languageCode);
        if (translations != null) {
          await saveLanguagePackToCache(languageCode, translations);
          await _saveLocalLanguagePackLastUpdated(languageCode, cloudLastUpdated);
          _cachedPacks[languageCode] = translations;
          return true;
        }
        return false;
      } else {
        print('LanguagePackService: 语言包已是最新版本: $languageCode');
        return false;
      }
    } catch (e) {
      print('LanguagePackService: 时间戳解析失败: $e');
      return false;
    }
  }

  /// 获取本地语言包的最后更新时间
  Future<String?> _getLocalLanguagePackLastUpdated(String languageCode) async {
    await init();
    final key = 'lang_pack_last_updated_$languageCode';
    return _prefs?.getString(key);
  }

  /// 保存本地语言包的最后更新时间
  Future<void> _saveLocalLanguagePackLastUpdated(String languageCode, String lastUpdated) async {
    await init();
    final key = 'lang_pack_last_updated_$languageCode';
    await _prefs?.setString(key, lastUpdated);
  }

  /// 加载语言包（优先级：内存缓存 > 内置资源 > 本地缓存（如果更新）> 云端下载（如果需要更新））
  Future<Map<String, String>?> loadLanguagePack(String languageCode, {bool forceRefresh = false}) async {
    await init();
    
    // 如果强制刷新，清除内存缓存
    if (forceRefresh) {
      _cachedPacks.remove(languageCode);
    }
    
    // 1. 尝试使用内存缓存
    if (_cachedPacks.containsKey(languageCode)) {
      print('LanguagePackService: 使用内存缓存语言包: $languageCode');
      return _cachedPacks[languageCode];
    }
    
    // 2. 优先使用内置资源（应用打包时内置的语言包）
    final builtinPack = await loadBuiltinLanguagePack(languageCode);
    if (builtinPack != null) {
      // 检查本地缓存是否有更新的版本
      final localLastUpdated = await _getLocalLanguagePackLastUpdated(languageCode);
      final cachedPack = await loadLocalLanguagePack(languageCode);
      
      // 如果本地缓存存在且时间戳更新，使用本地缓存
      if (cachedPack != null && localLastUpdated != null) {
        try {
          // 获取内置语言包的时间戳（从配置文件）
          final supportedLanguages = await getSupportedLanguages();
          final languageInfo = supportedLanguages.firstWhere(
            (lang) => lang.code == languageCode,
            orElse: () => SupportedLanguage(
              code: languageCode,
              name: languageCode,
              nativeName: languageCode,
              file: '$languageCode.json',
              lastUpdated: DateTime.now().toIso8601String(),
            ),
          );
          
          final builtinDate = DateTime.parse(languageInfo.lastUpdated);
          final localDate = DateTime.parse(localLastUpdated);
          
          if (localDate.isAfter(builtinDate)) {
            // 本地缓存版本更新，使用本地缓存
            _cachedPacks[languageCode] = cachedPack;
            print('LanguagePackService: 使用本地缓存语言包（版本更新）: $languageCode');
            // 后台检查是否有新的更新（不阻塞）
            _checkAndUpdateLanguagePack(languageCode);
            return cachedPack;
          }
        } catch (e) {
          print('LanguagePackService: 比较时间戳失败，使用内置版本: $e');
        }
      }
      
      // 使用内置语言包
      _cachedPacks[languageCode] = builtinPack;
      print('LanguagePackService: 使用内置语言包: $languageCode');
      // 后台检查是否有更新（不阻塞）
      _checkAndUpdateLanguagePack(languageCode);
      return builtinPack;
    }
    
    // 3. 如果内置资源不存在，尝试加载本地缓存
    final cachedPack = await loadLocalLanguagePack(languageCode);
    if (cachedPack != null) {
      _cachedPacks[languageCode] = cachedPack;
      print('LanguagePackService: 使用本地缓存语言包: $languageCode');
      return cachedPack;
    }
    
    // 4. 最后尝试从云端下载（用于新增语言包的情况）
    final cloudPack = await fetchLanguagePack(languageCode);
    if (cloudPack != null) {
      await saveLanguagePackToCache(languageCode, cloudPack);
      final supportedLanguages = await getSupportedLanguages();
      final languageInfo = supportedLanguages.firstWhere(
        (lang) => lang.code == languageCode,
        orElse: () => SupportedLanguage(
          code: languageCode,
          name: languageCode,
          nativeName: languageCode,
          file: '$languageCode.json',
          lastUpdated: DateTime.now().toIso8601String(),
        ),
      );
      await _saveLocalLanguagePackLastUpdated(languageCode, languageInfo.lastUpdated);
      _cachedPacks[languageCode] = cloudPack;
      print('LanguagePackService: 使用云端语言包: $languageCode');
      return cloudPack;
    }
    
    print('LanguagePackService: 无法加载语言包: $languageCode');
    return null;
  }

  /// 检查并更新语言包（异步，不阻塞主流程）
  /// 仅在以下情况更新：
  /// 1. 应用版本未更新，但需要添加新语言包
  /// 2. 当前版本语言包翻译有误需要更新
  Future<void> _checkAndUpdateLanguagePack(String languageCode) async {
    try {
      // 检查是否有更新（24小时检查一次）
      final hasUpdate = await checkLanguagePackUpdate(languageCode, force: false);
      if (hasUpdate) {
        print('LanguagePackService: 检测到语言包更新，已下载新版本: $languageCode');
        // 清除内存缓存，下次加载时使用新版本
        _cachedPacks.remove(languageCode);
      }
    } catch (e) {
      // 静默忽略错误，不影响使用内置语言包
      print('LanguagePackService: 检查语言包更新失败: $e');
    }
  }

  /// 清除语言包缓存
  Future<void> clearLanguagePackCache(String languageCode) async {
    await init();
    _cachedPacks.remove(languageCode);
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final langFile = File(path.join(appDir.path, 'locales', '$languageCode.json'));
      if (await langFile.exists()) {
        await langFile.delete();
        print('LanguagePackService: 已清除本地语言包缓存: $languageCode');
      }
      
      final lastUpdatedKey = 'lang_pack_last_updated_$languageCode';
      final lastCheckKey = '$_keyLastUpdateCheckPrefix$languageCode';
      await _prefs?.remove(lastUpdatedKey);
      await _prefs?.remove(lastCheckKey);
    } catch (e) {
      print('LanguagePackService: 清除语言包缓存失败: $e');
    }
  }
}

