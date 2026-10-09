import 'package:flutter/foundation.dart';

/// 基础ViewModel类
/// 提供通用的状态管理功能
abstract class BaseViewModel extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;

  /// 设置加载状态
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  /// 设置错误信息
  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  /// 清除错误信息
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// 执行异步操作，自动管理加载状态和错误处理
  Future<T?> executeAsync<T>(
    Future<T> Function() action, {
    bool showLoading = true,
    Function(Object)? onError,
  }) async {
    try {
      if (showLoading) setLoading(true);
      clearError();
      final result = await action();
      return result;
    } catch (e) {
      final errorMsg = e.toString();
      setError(errorMsg);
      onError?.call(e);
      return null;
    } finally {
      if (showLoading) setLoading(false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}

