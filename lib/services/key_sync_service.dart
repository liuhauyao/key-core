import '../models/ai_key.dart';
import '../models/platform_type.dart';
import 'key_validation_service.dart';
import 'model_list_service.dart';
import 'balance_query_service.dart';
import 'key_cache_service.dart';

/// 同步结果
class SyncResult {
  final bool success;
  final String message;
  final int? modelCount;
  final Map<String, dynamic>? balanceData;
  final String? error;
  final bool validationSuccess; // 校验是否成功

  SyncResult.success({
    required this.message,
    this.modelCount,
    this.balanceData,
    this.validationSuccess = false,
  })  : success = true,
        error = null;

  SyncResult.failure({
    required this.error,
    this.validationSuccess = false,
  })  : success = false,
        message = '',
        modelCount = null,
        balanceData = null;
}

/// 密钥同步服务
/// 整合校验有效性、加载模型列表、查询余额三个功能
class KeySyncService {
  final KeyValidationService _validationService = KeyValidationService();
  final ModelListService _modelListService = ModelListService();
  final BalanceQueryService _balanceQueryService = BalanceQueryService();
  final KeyCacheService _cacheService = KeyCacheService();

  /// 同步密钥信息（依次调用校验、模型列表、余额查询）
  Future<SyncResult> syncKey(AIKey key) async {
    print('KeySyncService: 开始同步密钥，平台类型: ${key.platformType.id}');
    
    final platformType = key.platformType;
    bool validationSuccess = false;
    int? modelCount;
    Map<String, dynamic>? balanceData;
    List<String> successMessages = [];
    List<String> errorMessages = [];

    // 1. 校验密钥有效性（如果支持）
    final hasValidation = await _validationService.hasValidationConfig(platformType);
    if (hasValidation) {
      print('KeySyncService: 开始校验密钥有效性');
      final validationResult = await _validationService.validateKey(
        key: key,
        timeout: const Duration(seconds: 10),
      );
      if (validationResult.isValid) {
        validationSuccess = true;
        successMessages.add('密钥校验成功');
        print('KeySyncService: 密钥校验成功');
      } else {
        errorMessages.add('密钥校验失败：${validationResult.error ?? "未知错误"}');
        print('KeySyncService: 密钥校验失败：${validationResult.error}');
        // 如果校验失败，仍然继续尝试其他操作（因为可能是网络问题）
      }
    }

    // 2. 加载模型列表（如果支持）
    final supportsModelList = await _validationService.supportsModelList(platformType);
    if (supportsModelList) {
      print('KeySyncService: 开始加载模型列表');
      final modelResult = await _modelListService.getModelList(
        key: key,
        timeout: const Duration(seconds: 10),
      );
      if (modelResult.success && modelResult.models != null) {
        modelCount = modelResult.models!.length;
        await _cacheService.saveModelList(key, modelResult.models!);
        successMessages.add('加载模型 ${modelCount} 个');
        print('KeySyncService: 模型列表加载成功，数量: $modelCount');
      } else {
        errorMessages.add('加载模型列表失败：${modelResult.error ?? "未知错误"}');
        print('KeySyncService: 模型列表加载失败：${modelResult.error}');
      }
    }

    // 3. 查询余额（如果支持）
    final supportsBalance = await _balanceQueryService.supportsBalanceQuery(platformType);
    if (supportsBalance) {
      print('KeySyncService: 开始查询余额');
      final balanceResult = await _balanceQueryService.queryBalance(
        key: key,
        timeout: const Duration(seconds: 10),
      );
      if (balanceResult.success && balanceResult.balanceData != null) {
        balanceData = balanceResult.balanceData;
        await _cacheService.saveBalance(key, balanceData!);
        successMessages.add('余额查询成功');
        print('KeySyncService: 余额查询成功');
      } else {
        errorMessages.add('查询余额失败：${balanceResult.error ?? "未知错误"}');
        print('KeySyncService: 余额查询失败：${balanceResult.error}');
      }
    }

    // 构建结果消息
    if (successMessages.isNotEmpty || errorMessages.isEmpty) {
      // 至少有一个成功，或者没有错误（可能是都不支持）
      final messageParts = <String>[];
      if (modelCount != null) {
        messageParts.add('加载模型 $modelCount 个');
      }
      if (balanceData != null) {
        // 格式化余额信息
        print('KeySyncService: 格式化余额，原始数据: $balanceData');
        final balanceStr = _formatBalance(balanceData);
        print('KeySyncService: 格式化后的余额: $balanceStr');
        if (balanceStr != null) {
          messageParts.add('余额：$balanceStr');
        } else {
          print('KeySyncService: 余额格式化返回 null，无法显示');
        }
      }
      if (messageParts.isEmpty && validationSuccess) {
        messageParts.add('同步成功');
      } else if (messageParts.isEmpty) {
        messageParts.add('该平台不支持同步功能');
      }
      
      return SyncResult.success(
        message: messageParts.join('，'),
        modelCount: modelCount,
        balanceData: balanceData,
        validationSuccess: validationSuccess,
      );
    } else {
      // 全部失败
      return SyncResult.failure(
        error: errorMessages.join('；'),
        validationSuccess: validationSuccess, // 传递校验状态，即使其他操作失败
      );
    }
  }

  /// 格式化余额显示
  String? _formatBalance(Map<String, dynamic> balanceData) {
    try {
      // 尝试解析常见的余额字段
      if (balanceData.containsKey('data')) {
        final data = balanceData['data'] as Map<String, dynamic>?;
        if (data != null) {
          // OpenRouter 格式：limit_remaining
          if (data.containsKey('limit_remaining')) {
            final limitRemaining = data['limit_remaining'];
            // 余额为0就是0，即使 limit_remaining 为 null 也显示 $0.00
            if (limitRemaining == null) {
              return '\$0.00';
            } else {
              final remaining = limitRemaining as num?;
              if (remaining != null) {
                return '\$${remaining.toStringAsFixed(2)}';
              } else {
                return '\$0.00';
              }
            }
          }
          // Moonshot/Kimi 格式：available_balance, voucher_balance, cash_balance
          if (data.containsKey('available_balance')) {
            final available = data['available_balance'] as num?;
            if (available != null) {
              return '¥${available.toStringAsFixed(2)}';
            }
          }
          // 其他可能的余额字段
          if (data.containsKey('balance')) {
            final balance = data['balance'] as num?;
            if (balance != null) {
              return '¥${balance.toStringAsFixed(2)}';
            }
          }
        }
      }
      
      // 直接查找余额字段
      if (balanceData.containsKey('balance')) {
        final balance = balanceData['balance'] as num?;
        if (balance != null) {
          return '¥${balance.toStringAsFixed(2)}';
        }
      }
      
      return null;
    } catch (e) {
      print('KeySyncService: 格式化余额失败: $e');
      return null;
    }
  }

  /// 检查平台是否支持同步功能
  Future<bool> supportsSync(PlatformType platformType) async {
    final hasValidation = await _validationService.hasValidationConfig(platformType);
    final supportsModelList = await _validationService.supportsModelList(platformType);
    final supportsBalance = await _balanceQueryService.supportsBalanceQuery(platformType);
    return hasValidation || supportsModelList || supportsBalance;
  }
}

