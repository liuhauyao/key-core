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
    try {
      // 整体超时控制：最多10秒（每个操作5秒，最多2个操作）
      return await _syncKeyInternal(key).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          return SyncResult.failure(
            error: '同步失败，检查密钥或者网络',
            validationSuccess: false,
          );
        },
      );
    } catch (e) {
      return SyncResult.failure(
        error: '同步失败，检查密钥或者网络',
        validationSuccess: false,
      );
    }
  }

  /// 内部同步实现
  Future<SyncResult> _syncKeyInternal(AIKey key) async {
    final platformType = key.platformType;
    bool validationSuccess = false;
    int? modelCount;
    Map<String, dynamic>? balanceData;
    List<String> successMessages = [];
    List<String> errorMessages = [];

    // 1. 校验密钥有效性（如果支持）- 这是最重要的，如果校验失败，直接返回失败
    final hasValidation = await _validationService.hasValidationConfig(platformType);
    if (hasValidation) {
      try {
        final validationResult = await _validationService.validateKey(
          key: key,
          timeout: const Duration(seconds: 5),
        );
        if (validationResult.isValid) {
          validationSuccess = true;
        } else {
          // 校验失败，清除缓存的校验状态，立即返回失败，不再尝试其他操作
          await _cacheService.saveValidationStatus(key, false);
          return SyncResult.failure(
            error: '同步失败，检查密钥或者网络',
            validationSuccess: false,
          );
        }
      } catch (e) {
        // 校验失败或超时，清除缓存的校验状态，立即返回失败
        await _cacheService.saveValidationStatus(key, false);
        return SyncResult.failure(
          error: '同步失败，检查密钥或者网络',
          validationSuccess: false,
        );
      }
    }

    // 2. 加载模型列表（如果支持）
    final supportsModelList = await _validationService.supportsModelList(platformType);
    if (supportsModelList) {
      try {
        final modelResult = await _modelListService.getModelList(
          key: key,
          timeout: const Duration(seconds: 5),
        );
        if (modelResult.success && modelResult.models != null) {
          modelCount = modelResult.models!.length;
          await _cacheService.saveModelList(key, modelResult.models!);
        }
      } catch (e) {
        // 加载模型列表失败，继续尝试余额查询
      }
    }

    // 3. 查询余额（如果支持）
    final supportsBalance = await _balanceQueryService.supportsBalanceQuery(platformType);
    if (supportsBalance) {
      try {
        final balanceResult = await _balanceQueryService.queryBalance(
          key: key,
          timeout: const Duration(seconds: 5),
        );
        if (balanceResult.success && balanceResult.balanceData != null) {
          balanceData = balanceResult.balanceData;
          await _cacheService.saveBalance(key, balanceData!);
        }
      } catch (e) {
        // 查询余额失败，不影响最终结果
      }
    }

    // 构建结果消息 - 校验已成功，现在构建成功消息
    final messageParts = <String>[];
    if (modelCount != null) {
      messageParts.add('加载模型 $modelCount 个');
    }
    if (balanceData != null) {
      // 格式化余额信息
      final balanceStr = _formatBalance(balanceData);
      if (balanceStr != null) {
        messageParts.add('余额：$balanceStr');
      }
    }
    if (messageParts.isEmpty) {
      messageParts.add('同步成功');
    }
    
    // 保存校验状态到缓存
    if (validationSuccess) {
      await _cacheService.saveValidationStatus(key, true);
    }
    
    return SyncResult.success(
      message: messageParts.join('，'),
      modelCount: modelCount,
      balanceData: balanceData,
      validationSuccess: validationSuccess,
    );
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

