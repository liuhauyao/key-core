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
      print('CloudConfigService: 配置URL必须使用HTTPS: $url');
      return null;
    }
    
    try {
      final uri = Uri.parse(url);
      
      // ⭐ 策略：优先使用 GitHub API（绕过 CDN 缓存），失败时回退到 raw URL
      CloudConfig? config;
      
      // 如果是默认 URL，先尝试使用 GitHub API
      if (url == _defaultConfigUrl || url == _githubRawUrl) {
        config = await _fetchFromGitHubApi();
        if (config != null) {
          return config;
        }
        // API 失败，回退到 raw URL
        print('CloudConfigService: GitHub API 失败，回退到 raw URL...');
      }
      
      // ⭐ 使用 raw URL 或自定义 URL，添加时间戳参数绕过缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final uriWithTimestamp = uri.replace(queryParameters: {
        ...uri.queryParameters,
        '_t': timestamp.toString(),
        't': timestamp.toString(),
        'nocache': timestamp.toString(),
        'v': timestamp.toString(),
        'r': DateTime.now().microsecondsSinceEpoch.toString(), // 随机参数
      });
      
      print('CloudConfigService: 从云端获取配置: $uriWithTimestamp');
      
      final response = await http.get(
        uriWithTimestamp,
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
        config = CloudConfig.fromJson(jsonData);
        print('CloudConfigService: 成功获取云端配置 - 版本: ${config.version}, 时间: ${config.lastUpdated}');
        return config;
      } else if (response.statusCode == 304) {
        // 304 响应，强制重新请求
        print('CloudConfigService: 收到 304 响应，强制重新请求...');
        return await _forceFetchFromUrl(uri);
      } else {
        print('CloudConfigService: 获取配置失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('CloudConfigService: 获取云端配置异常: $e');
      return null;
    }
  }
  
  /// 使用 GitHub API 获取配置（绕过 CDN 缓存）
  Future<CloudConfig?> _fetchFromGitHubApi() async {
    try {
      final apiUrl = 'https://api.github.com/repos/liuhauyao/key-core/contents/assets/config/app_config.json?ref=main';
      print('CloudConfigService: 使用 GitHub API 获取配置: $apiUrl');
      
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
          print('CloudConfigService: GitHub API 成功获取配置 - 版本: ${config.version}, 时间: ${config.lastUpdated}');
          return config;
        } else {
          print('CloudConfigService: GitHub API 返回格式异常');
          return null;
        }
      } else {
        print('CloudConfigService: GitHub API 请求失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('CloudConfigService: GitHub API 请求异常: $e');
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
  /// 基于时间戳比较，而非版本号
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
    
    // 尝试从云端获取配置
    CloudConfig? cloudConfig = await fetchConfigFromCloud();
    
    // 如果失败，尝试使用Gitee备选URL（仅当使用默认URL时）
    final currentUrl = getConfigUrl();
    if (cloudConfig == null && (currentUrl == _defaultConfigUrl || currentUrl == _githubRawUrl)) {
      print('CloudConfigService: GitHub 获取失败，尝试使用 Gitee 备选源...');
      cloudConfig = await fetchConfigFromCloud(customUrl: _giteeConfigUrl);
    }
    
    if (cloudConfig == null) {
      print('CloudConfigService: 无法从云端获取配置，使用本地配置');
      return false;
    }
    
    // 如果没有本地配置，直接更新
    if (localConfig == null) {
      final saved = await saveConfigToCache(cloudConfig);
      if (saved) {
        print('CloudConfigService: 配置已更新（首次安装）');
        _cachedConfig = null;
        return true;
      }
      return false;
    }
    
    // ⭐ 关键修复：优先使用缓存文件中的实际版本号和时间戳
    // 而不是 SharedPreferences 中的版本号（可能不同步）
    final localVersion = localConfig.version; // 从缓存文件读取实际版本号
    final localLastUpdated = localConfig.lastUpdated; // 从缓存文件读取实际时间戳
    final cloudVersion = cloudConfig.version;
    final cloudLastUpdated = cloudConfig.lastUpdated;
    
    // 比较版本号
    final versionCompare = compareVersions(localVersion, cloudVersion);
    final hasVersionUpdate = versionCompare < 0;
    
    // 比较时间戳
    bool hasTimestampUpdate = false;
    try {
      final localDate = DateTime.parse(localLastUpdated);
      final cloudDate = DateTime.parse(cloudLastUpdated);
      hasTimestampUpdate = cloudDate.isAfter(localDate);
    } catch (e) {
      print('CloudConfigService: 时间戳解析失败: $e，仅使用版本号比较');
      // 如果时间戳解析失败，仅依赖版本号比较
    }
    
    // 只要版本号或时间戳任一更新，就需要更新
    if (hasVersionUpdate || hasTimestampUpdate) {
      print('CloudConfigService: 检测到配置更新 - 版本号: ${hasVersionUpdate ? "是" : "否"}, 时间戳: ${hasTimestampUpdate ? "是" : "否"}');
      print('CloudConfigService: 本地版本: $localVersion, 云端版本: $cloudVersion');
      print('CloudConfigService: 本地时间: $localLastUpdated, 云端时间: $cloudLastUpdated');
      
      final saved = await saveConfigToCache(cloudConfig);
      if (saved) {
        print('CloudConfigService: 配置已更新');
        _cachedConfig = null;
        return true;
      } else {
        print('CloudConfigService: 配置更新失败');
        return false;
      }
    } else {
      print('CloudConfigService: 配置已是最新版本 - 本地版本: $localVersion, 云端版本: $cloudVersion');
      return false;
    }
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

