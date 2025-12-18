/// 校验错误类型
enum ValidationError {
  invalidKey,
  networkError,
  timeout,
  serverError,
  unknown,
}

/// 密钥校验结果
class KeyValidationResult {
  final bool isValid;
  final String? message;
  final ValidationError? error;

  KeyValidationResult({
    required this.isValid,
    this.message,
    this.error,
  });

  KeyValidationResult.success({String? message})
      : isValid = true,
        message = message,
        error = null;

  KeyValidationResult.failure({
    required ValidationError error,
    String? message,
  })  : isValid = false,
        message = message,
        error = error;
}





