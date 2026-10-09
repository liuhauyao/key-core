import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/cloud_config.dart';

/// 云端配置服务
class CloudConfigService {
  static const String _keyConfigVersion = 'cloud_config_version';
  static const String _keyConfigUrl = 'cloud_config_url';
  static const String _keyLastUpdateCheck = 'cloud_config_last_update_check';
  static const String _defaultVersion = '1.0.0';
  
  // 默认配置URL（GitHub API）- key-core 主仓库
  // ⭐ 使用 GitHub API 而不是 raw URL，可以绕过 CDN 缓存
  // 格式: https://api.github.com/repos/{owner}/{repo}/contents/{path}?ref={branch}
  static const String _defaultConfigUrl = 
      'https://api.github.com/repos/liuhauyao/key-core/contents/assets/config/app_config.json?ref=main';
  
  // GitHub Raw URL（备选）- 如果 API 失败时使用
  static const String _githubRawUrl = 
      'https://raw.githubusercontent.com/liuhauyao/key-core/main/assets/config/app_config.json';
  
  // Gitee备选URL（国内用户）- key-core 镜像仓库
  // 格式: https://gitee.com/{owner}/{repo}/raw/{branch}/assets/config/app_config.json
  static const String _giteeConfigUrl = 
      'https://gitee.com/liuhauyao/key-core/raw/main/assets/config/app_config.json';
  
  // 更新检查间隔（24小时）
  static const Duration _updateCheckInterval = Duration(hours: 24);
  
  SharedPreferences? _prefs;
  CloudConfig? _cachedConfig;
  bool _isInitialized = false;

  /// 初始化服务
  Future<void> init() async {
    if (_isInitialized) return;
    
    _prefs = await SharedPreferences.getInstance();
    
    // 确保有默认版本号
    if (!_prefs!.containsKey(_keyConfigVersion)) {
      await _prefs!.setString(_keyConfigVersion, _defaultVersion);
    }
    
    _isInitialized = true;
  }

  /// 获取配置URL
  String getConfigUrl() {
    return _prefs?.getString(_keyConfigUrl) ?? _defaultConfigUrl;
  }

  /// 设置配置URL
  Future<void> setConfigUrl(String url) async {
    await init();
    await _prefs?.setString(_keyConfigUrl, url);
    // 清除缓存，强制重新加载
    print('CloudConfigService: 配置已更新');
        _cachedConfig = null;
  }

  /// 获取本地配置版本
  Future<String> getLocalConfigVersion() async {
    await init();
    return _prefs?.getString(_keyConfigVersion) ?? _defaultVersion;
  }

  /// 获取本地配置日期
  Future<String?> getLocalConfigDate() async {
    try {
      final config = await loadLocalCachedConfig();
      if (config != null) {
        return config.lastUpdated;
      }
      // 如果缓存不存在，尝试从默认配置加载
      final defaultConfig = await loadLocalDefaultConfig();
      return defaultConfig?.lastUpdated;
    } catch (e) {
      print('CloudConfigService: 获取本地配置日期失败: $e');
      return null;
    }
  }

  /// 设置本地配置版本
  Future<void> setLocalConfigVersion(String version) async {
    await init();
    await _prefs?.setString(_keyConfigVersion, version);
  }

  /// 比较版本号
  /// 返回: -1 表示 version1 < version2, 0 表示相等, 1 表示 version1 > version2
  int compareVersions(String version1, String version2) {
    final v1Parts = version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final v2Parts = version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    
    // 补齐长度
    while (v1Parts.length < v2Parts.length) v1Parts.add(0);
    while (v2Parts.length < v1Parts.length) v2Parts.add(0);
    
    for (int i = 0; i < v1Parts.length; i++) {
      if (v1Parts[i] < v2Parts[i]) return -1;
      if (v1Parts[i] > v2Parts[i]) return 1;
    }
    return 0;
  }

  /// 检查是否需要更新
  Future<bool> shouldCheckForUpdate() async {
    await init();
    
    final lastCheckStr = _prefs?.getString(_keyLastUpdateCheck);
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

  /// 记录更新检查时间
  Future<void> _recordUpdateCheck() async {
    await init();
    await _prefs?.setString(_keyLastUpdateCheck, DateTime.now().toIso8601String());
  }

  /// 从云端获取配置
  Future<CloudConfig?> fetchConfigFromCloud({String? customUrl}) async {
    await init();
    
    final url = customUrl ?? getConfigUrl();
    
    // 验证URL必须是HTTPS
    if (!url.startsWith('https://')) {
      return null;
    }
    
    try {
      var uri = Uri.parse(url);
      
      // ⭐ 关键修复：无论 URL 是什么，只要检测到是 GitHub 相关的，都优先使用 GitHub API
      // 这样可以确保 release 版本也能绕过 CDN 缓存
      final isGitHubUrl = url.contains('github.com') || 
                         url.contains('raw.githubusercontent.com') ||
                         url == _defaultConfigUrl || 
                         url == _githubRawUrl ||
                         uri.host.contains('github.com');
      
      // ⭐ 如果是 GitHub URL，强制使用 GitHub API（绕过 CDN 缓存）
      if (isGitHubUrl) {
        final config = await _fetchFromGitHubApi();
        if (config != null) {
          return config;
        }
        // API 失败，回退到 raw URL（带时间戳参数）
        // 如果当前 URL 是 API URL，切换到 raw URL
        if (uri.host == 'api.github.com') {
          uri = Uri.parse(_githubRawUrl);
        }
      }
      
      // ⭐ 使用 raw URL 或自定义 URL，添加时间戳参数绕过缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final finalUri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        '_t': timestamp.toString(),
        't': timestamp.toString(),
        'nocache': timestamp.toString(),
        'v': timestamp.toString(),
        'r': DateTime.now().microsecondsSinceEpoch.toString(),
      });
      
      final response = await http.get(
        finalUri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'AI-Key-Manager/1.0',
          'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );
      
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final config = CloudConfig.fromJson(jsonData);
        return config;
      } else if (response.statusCode == 304) {
        // 304 响应，强制重新请求
        return await _forceFetchFromUrl(uri);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
  
  /// 使用 GitHub API 获取配置（绕过 CDN 缓存）
  Future<CloudConfig?> _fetchFromGitHubApi() async {
    try {
      // ⭐ 添加时间戳参数确保每次都是新请求
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final apiUrl = 'https://api.github.com/repos/liuhauyao/key-core/contents/assets/config/app_config.json?ref=main&_t=$timestamp';
      
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'AI-Key-Manager/1.0',
          'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
          'Pragma': 'no-cache',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('GitHub API 请求超时');
        },
      );
      
      if (response.statusCode == 200) {
        // GitHub API 返回的是 base64 编码的内容
        final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final content = jsonData['content'] as String?;
        final encoding = jsonData['encoding'] as String?;
        
        if (content != null && encoding == 'base64') {
          // 解码 base64 内容
          final decodedBytes = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
          final jsonString = utf8.decode(decodedBytes);
          final configJson = jsonDecode(jsonString) as Map<String, dynamic>;
          final config = CloudConfig.fromJson(configJson);
          return config;
        }
        return null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// 强制从 URL 获取配置（多次重试）
  Future<CloudConfig?> _forceFetchFromUrl(Uri uri) async {
    // 尝试多次，每次使用不同的时间戳
    for (int i = 0; i < 3; i++) {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch + i;
        final retryUri = uri.replace(queryParameters: {
          ...uri.queryParameters,
          '_t': timestamp.toString(),
          'force': i.toString(),
          'attempt': i.toString(),
        });
        
        print('CloudConfigService: 强制重试 $i/3: $retryUri');
        
        final response = await http.get(
          retryUri,
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'AI-Key-Manager/1.0',
            'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ).timeout(
          const Duration(seconds: 10),
        );
        
        if (response.statusCode == 200) {
          final jsonData = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final config = CloudConfig.fromJson(jsonData);
          print('CloudConfigService: 强制重试成功 - 版本: ${config.version}');
          return config;
        }
        
        // 等待一下再重试
        await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
      } catch (e) {
        print('CloudConfigService: 强制重试 $i 失败: $e');
      }
    }
    
    return null;
  }

  /// 从本地文件加载配置（assets）
  Future<CloudConfig?> loadLocalDefaultConfig() async {
    try {
      final jsonString = await rootBundle.loadString('assets/config/app_config.json');
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final config = CloudConfig.fromJson(jsonData);
      return config;
    } catch (e) {
      return null;
    }
  }

  /// 从本地缓存文件加载配置
  Future<CloudConfig?> loadLocalCachedConfig() async {
    try {
      await init();
      final appDir = await getApplicationDocumentsDirectory();
      final configFile = File(path.join(appDir.path, 'cloud_config.json'));
      
      if (!await configFile.exists()) {
        return null;
      }
      
      final jsonString = await configFile.readAsString();
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      final config = CloudConfig.fromJson(jsonData);
      return config;
    } catch (e) {
      print('CloudConfigService: 加载本地缓存配置失败: $e');
      return null;
    }
  }

  /// 保存配置到本地缓存
  Future<bool> saveConfigToCache(CloudConfig config) async {
    try {
      await init();
      final appDir = await getApplicationDocumentsDirectory();
      final configFile = File(path.join(appDir.path, 'cloud_config.json'));
      
      final jsonString = const JsonEncoder.withIndent('  ').convert(config.toJson());
      await configFile.writeAsString(jsonString);
      
      // 更新版本号
      await setLocalConfigVersion(config.version);
      
      return true;
    } catch (e) {
      print('CloudConfigService: 保存配置到本地缓存失败: $e');
      return false;
    }
  }

  /// 检查更新
  /// 返回: true表示有更新，false表示无更新或检查失败
  Future<bool> checkForUpdates({bool force = false}) async {
    await init();
    
    // 如果不是强制检查，且距离上次检查时间未超过间隔，则跳过
    if (!force && !await shouldCheckForUpdate()) {
      return false;
    }
    
    // 记录检查时间
    await _recordUpdateCheck();
    
    // 获取本地配置
    final localConfig = await loadLocalCachedConfig();
    
    // ⭐ 关键修复：无论 SharedPreferences 中存储的是什么 URL，都优先使用 GitHub API
    // 这样可以确保 release 版本也能绕过 CDN 缓存
    CloudConfig? cloudConfig = await fetchConfigFromCloud();
    
    // 如果失败，尝试使用Gitee备选URL
    final currentUrl = getConfigUrl();
    if (cloudConfig == null && (currentUrl == _defaultConfigUrl || currentUrl == _githubRawUrl || currentUrl.contains('github.com'))) {
      cloudConfig = await fetchConfigFromCloud(customUrl: _giteeConfigUrl);
    }
    
    if (cloudConfig == null) {
      return false;
    }
    
    // 如果没有本地配置，直接更新
    if (localConfig == null) {
      final saved = await saveConfigToCache(cloudConfig);
      if (saved) {
        _cachedConfig = null;
        return true;
      }
      return false;
    }
    
    // ⭐ 关键修复：优先使用缓存文件中的实际版本号和时间戳
    final localVersion = localConfig.version;
    final localLastUpdated = localConfig.lastUpdated;
    final cloudVersion = cloudConfig.version;
    final cloudLastUpdated = cloudConfig.lastUpdated;
    
    // ⭐ 版本号比较
    final versionCompare = compareVersions(localVersion, cloudVersion);
    final hasVersionUpdate = versionCompare < 0;
    
    // ⭐ 时间戳比较：比较时间戳字符串，如果不同则认为有更新
    // 这样可以处理版本号相同但时间戳不同的情况
    bool hasTimestampUpdate = false;
    
    if (localLastUpdated != cloudLastUpdated) {
      // 时间戳字符串不同，尝试解析比较
      try {
        final localDate = DateTime.parse(localLastUpdated);
        final cloudDate = DateTime.parse(cloudLastUpdated);
        hasTimestampUpdate = cloudDate.isAfter(localDate);
      } catch (e) {
        // 如果时间戳解析失败，但字符串不同，认为有更新
        hasTimestampUpdate = true;
      }
    }
    
    // ⭐ 只要版本号更新，或者时间戳更新，就需要更新
    if (hasVersionUpdate || hasTimestampUpdate) {
      final saved = await saveConfigToCache(cloudConfig);
      if (saved) {
        _cachedConfig = null;
        return true;
      }
      return false;
    }
    
    // ⭐ 如果版本号和时间戳都相同，认为无更新
    return false;
  }

  /// 更新配置（强制从云端下载）
  Future<bool> updateConfig({String? customUrl}) async {
    await init();
    
    final cloudConfig = await fetchConfigFromCloud(customUrl: customUrl);
    
    if (cloudConfig == null) {
      print('CloudConfigService: 无法从云端获取配置');
      return false;
    }
    
    // 保存到本地缓存
    final saved = await saveConfigToCache(cloudConfig);
    if (saved) {
      // 清除内存缓存，强制重新加载
      print('CloudConfigService: 配置已更新');
        _cachedConfig = null;
      await _recordUpdateCheck();
      return true;
    }
    
    return false;
  }

  /// 加载配置（优先级：内存缓存 > 本地缓存 > 云端 > 默认配置）
  Future<CloudConfig?> loadConfig({bool forceRefresh = false}) async {
    await init();
    
    // 如果强制刷新，清除内存缓存
    if (forceRefresh) {
      print('CloudConfigService: 配置已更新');
        _cachedConfig = null;
    }
    
    // 1. 尝试使用内存缓存
    if (_cachedConfig != null) {
      return _cachedConfig;
    }
    
    // 2. 尝试加载本地缓存
    final cachedConfig = await loadLocalCachedConfig();
    if (cachedConfig != null) {
      _cachedConfig = cachedConfig;
      return cachedConfig;
    }
    
    // 3. 尝试从云端获取
    final cloudConfig = await fetchConfigFromCloud();
    if (cloudConfig != null) {
      // 保存到本地缓存
      await saveConfigToCache(cloudConfig);
      _cachedConfig = cloudConfig;
      return cloudConfig;
    }
    
    // 4. 使用默认配置（assets）
    final defaultConfig = await loadLocalDefaultConfig();
    if (defaultConfig != null) {
      // 保存到本地缓存
      await saveConfigToCache(defaultConfig);
      _cachedConfig = defaultConfig;
      return defaultConfig;
    }
    
    print('CloudConfigService: 无法加载任何配置');
    return null;
  }

  /// 获取配置数据
  Future<CloudConfigData?> getConfigData({bool forceRefresh = false}) async {
    final config = await loadConfig(forceRefresh: forceRefresh);
    return config?.config;
  }

  /// 获取缓存的配置数据（同步访问）
  CloudConfigData? get cachedConfigData => _cachedConfig?.config;
  
  /// 获取支持的语言列表
  List<SupportedLanguage> get supportedLanguages {
    final configData = _cachedConfig?.config;
    if (configData?.supportedLanguages != null && configData!.supportedLanguages!.isNotEmpty) {
      return configData.supportedLanguages!;
    }
    // 默认返回中英文
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

  /// 清除缓存
  Future<void> clearCache() async {
    await init();
    print('CloudConfigService: 配置已更新');
        _cachedConfig = null;
    
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final configFile = File(path.join(appDir.path, 'cloud_config.json'));
      if (await configFile.exists()) {
        await configFile.delete();
      }
    } catch (e) {
      print('CloudConfigService: 清除缓存失败: $e');
    }
  }
}

