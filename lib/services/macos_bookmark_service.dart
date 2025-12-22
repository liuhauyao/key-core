import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// macOS Security-Scoped Bookmarks 服务
/// 用于持久化保存用户选择的目录访问权限
class MacOSBookmarkService {
  static const MethodChannel _channel = MethodChannel('cn.dlrow.keycore/fileAccess');
  static const String _keyHomeDirPath = 'home_dir_path';
  
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 保存用户主目录的 Security-Scoped Bookmark
  /// 通过原生代码创建并保存 Security-Scoped Bookmark
  Future<bool> saveHomeDirBookmark(String homeDirPath) async {
    if (!Platform.isMacOS) {
      return false;
    }
    
    await init();
    
    try {
      // 调用原生代码保存 Security-Scoped Bookmark
      final result = await _channel.invokeMethod<bool>(
        'saveSecurityScopedBookmark',
        {'path': homeDirPath},
      );
      
      if (result == true) {
        // 同时保存路径到 SharedPreferences（用于显示）
        await _prefs?.setString(_keyHomeDirPath, homeDirPath);
        return true;
      }
      
      return false;
    } catch (e) {
      print('MacOSBookmarkService: 保存书签失败: $e');
      return false;
    }
  }

  /// 获取保存的用户主目录路径
  Future<String?> getHomeDirPath() async {
    await init();
    return _prefs?.getString(_keyHomeDirPath);
  }

  /// 检查是否有保存的授权
  Future<bool> hasHomeDirAuthorization() async {
    if (!Platform.isMacOS) {
      return false;
    }
    
    await init();
    
    try {
      // 调用原生代码检查是否有保存的 bookmark
      final result = await _channel.invokeMethod<bool>('hasSecurityScopedBookmark');
      return result ?? false;
    } catch (e) {
      print('MacOSBookmarkService: 检查授权失败: $e');
      return false;
    }
  }

  /// 清除保存的书签
  Future<void> clearHomeDirBookmark() async {
    if (!Platform.isMacOS) {
      return;
    }
    
    await init();
    
    try {
      // 调用原生代码清除 bookmark
      await _channel.invokeMethod('clearSecurityScopedBookmark');
      await _prefs?.remove(_keyHomeDirPath);
    } catch (e) {
      print('MacOSBookmarkService: 清除书签失败: $e');
    }
  }

  /// 恢复 Security-Scoped Bookmark 访问权限
  /// 在应用启动时调用，恢复之前保存的目录访问权限
  Future<bool> restoreHomeDirAccess() async {
    if (!Platform.isMacOS) {
      return false;
    }
    
    try {
      // 调用原生代码恢复 bookmark 访问权限
      final result = await _channel.invokeMethod<bool>('restoreSecurityScopedBookmark');
      if (result == true) {
        print('MacOSBookmarkService: Security-Scoped Bookmark 访问权限已恢复');
        return true;
      }
      return false;
    } catch (e) {
      print('MacOSBookmarkService: 恢复目录访问失败: $e');
      return false;
    }
  }
}





