import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import '../../models/ai_key.dart';
import '../../models/model_info.dart';
import '../../models/platform_category.dart';
import '../../utils/app_localizations.dart';
import '../../services/key_validation_service.dart';
import '../../services/model_list_service.dart';
import '../../services/balance_query_service.dart';
import '../../services/key_sync_service.dart';
import '../../services/key_cache_service.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import 'package:provider/provider.dart';
import 'model_list_dialog.dart';
import 'kc_logo.dart';
import '../../models/mcp_server.dart' show AiToolType;
import '../../theme/kc_tokens.dart';

/// 卡片使用模式
enum KeyCardMode {
  /// 查看模式：点击卡片显示详情弹窗（用于密钥管理界面）
  view,
  /// 切换模式：点击卡片直接切换密钥（用于工具切换页面）
  switchKey,
}

/// 密钥卡片组件（统一卡片样式，支持不同使用场景）
class KeyCard extends StatefulWidget {
  final AIKey aiKey;
  final bool isEditMode;
  final bool isCurrent;
  final KeyCardMode cardMode; // 卡片模式
  final VoidCallback? onTap; // 主点击回调（根据 cardMode 决定行为）
  final VoidCallback? onView; // 查看详情回调（仅在 view 模式下使用）
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenManagementUrl;
  final VoidCallback? onCopyApiEndpoint;
  final VoidCallback? onCopyApiKey;
  final VoidCallback? onCopyEnvVarCommand; // 复制环境变量命令
  final VoidCallback? onMoveToTop; // 置顶回调
  final ValueChanged<bool>? onToggle; // OpenClaw 等场景：右上角显示开关滑块

  /// 点击「已启用」工具 chip：把该工具直接切到这把密钥（钥匙包视图）
  final ValueChanged<AiToolType>? onSwitchTool;

  /// 「＋」菜单选择某个未启用的工具
  final ValueChanged<AiToolType>? onEnableTool;

  /// 各工具当前生效的密钥 id；不传时从 KeyManagerViewModel 读取
  final Map<AiToolType, int?>? currentKeyIds;

  /// 工具页 lens（§5.5）：底栏改为「该工具下的模型 + 也用于」。为 null 时是钥匙包的工具状态 chip
  final AiToolType? lens;

  const KeyCard({
    super.key,
    required this.aiKey,
    this.isEditMode = false,
    this.isCurrent = false,
    this.cardMode = KeyCardMode.view, // 默认为查看模式
    this.onTap,
    this.onView,
    this.onEdit,
    this.onDelete,
    this.onOpenManagementUrl,
    this.onCopyApiEndpoint,
    this.onCopyApiKey,
    this.onCopyEnvVarCommand,
    this.onMoveToTop,
    this.onToggle,
    this.onSwitchTool,
    this.onEnableTool,
    this.lens,
    this.currentKeyIds,
  });

  @override
  State<KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<KeyCard> {
  final KeyValidationService _validationService = KeyValidationService();
  final ModelListService _modelListService = ModelListService();
  final BalanceQueryService _balanceQueryService = BalanceQueryService();
  final KeySyncService _syncService = KeySyncService();
  final KeyCacheService _cacheService = KeyCacheService();
  bool? _hasValidationConfig;
  bool? _supportsModelList;
  bool? _supportsBalanceQuery;
  bool? _supportsSync;
  Map<String, dynamic>? _cachedBalance;
  List<ModelInfo>? _cachedModels;
  bool? _cachedValidationStatus; // 缓存的校验状态
  bool _isSyncing = false;
  bool _isHovering = false;
  bool _menuOpen = false;
  String? _lastCheckedPlatformTypeId; // 记录上次检查的平台类型ID

  @override
  void initState() {
    super.initState();
    // 只在首次初始化时检查配置，避免编辑模式切换时重复检查
    _checkValidationConfig();
    // 加载缓存的余额、模型列表和校验状态
    _loadCachedBalance();
    _loadCachedModels();
    _loadCachedValidationStatus();
  }

  @override
  void didUpdateWidget(KeyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当密钥ID或平台类型变化时才重新检查配置和重新加载缓存
    // 避免因为 notifyListeners() 导致所有 KeyCard 重新加载缓存
    // 注意：即使 widget.aiKey 对象引用不同，只要 id 和 platformType 相同，就不重新加载
    final platformTypeChanged = oldWidget.aiKey.platformType != widget.aiKey.platformType;
    if (oldWidget.aiKey.id != widget.aiKey.id || platformTypeChanged) {
      // 如果平台类型变化了，清除之前的校验配置缓存，强制重新检查
      if (platformTypeChanged) {
        _hasValidationConfig = null;
        _supportsModelList = null;
        _supportsBalanceQuery = null;
        _supportsSync = null;
        _lastCheckedPlatformTypeId = null;
      }
      _checkValidationConfig();
      _loadCachedBalance();
      _loadCachedModels();
      _loadCachedValidationStatus();
    }
    // 如果只是其他字段（如 isValidated）变化，不重新加载缓存
  }

  /// 检查是否有校验配置和模型列表支持
  /// 注意：使用密钥的 platform_type_id（即 platformType.id）从已加载的配置文件中匹配校验配置
  /// 配置文件在应用启动时已加载到缓存，验证逻辑从缓存中读取配置
  Future<void> _checkValidationConfig() async {
    final currentPlatformTypeId = widget.aiKey.platformType.id;
    
    // 如果平台类型没有变化，且已经检查过，则跳过
    if (_lastCheckedPlatformTypeId == currentPlatformTypeId &&
        _hasValidationConfig != null && 
        _supportsModelList != null && 
        _supportsBalanceQuery != null &&
        _supportsSync != null) {
      return;
    }
    
    // 使用密钥的 platform_type_id（即 platformType.id）来匹配配置文件中的供应商配置
    // platformType 是从数据库恢复的，优先使用 platform_type_id 字段
    final hasValidation = await _validationService.hasValidationConfig(widget.aiKey.platformType);
    final supportsModelList = await _validationService.supportsModelList(widget.aiKey.platformType);
    final supportsBalanceQuery = await _balanceQueryService.supportsBalanceQuery(widget.aiKey.platformType);
    final supportsSync = await _syncService.supportsSync(widget.aiKey.platformType);
    
    if (mounted) {
      setState(() {
        _hasValidationConfig = hasValidation;
        _supportsModelList = supportsModelList;
        _supportsBalanceQuery = supportsBalanceQuery;
        _supportsSync = supportsSync;
        _lastCheckedPlatformTypeId = currentPlatformTypeId; // 记录当前检查的平台类型ID
      });
    }
  }

  /// 加载缓存的余额
  Future<void> _loadCachedBalance() async {
    final balance = await _cacheService.getBalance(widget.aiKey);
    if (mounted) {
      setState(() {
        _cachedBalance = balance;
      });
    }
  }

  /// 加载缓存的模型列表
  Future<void> _loadCachedModels() async {
    final models = await _cacheService.getModelList(widget.aiKey);
    if (mounted) {
      setState(() {
        _cachedModels = models;
      });
    }
  }

  /// 加载缓存的校验状态
  Future<void> _loadCachedValidationStatus() async {
    final validationStatus = await _cacheService.getValidationStatus(widget.aiKey);
    if (mounted) {
      setState(() {
        _cachedValidationStatus = validationStatus;
      });
    }
  }


  /// 查看模型列表（从缓存读取）
  Future<void> _handleViewModels() async {
    if (_cachedModels != null && _cachedModels!.isNotEmpty) {
      if (!mounted) return;
      final localizations = AppLocalizations.of(context);
      showDialog(
        context: context,
        builder: (dialogContext) => ModelListDialog(
          models: _cachedModels!,
          platformName: widget.aiKey.platform,
          keyId: widget.aiKey.id,
          onUpdateModels: () async {
            // 更新模型列表
            final viewModel = context.read<KeyManagerViewModel>();
            final decryptedKey = await viewModel.getDecryptedKey(widget.aiKey.id!);
            if (decryptedKey != null) {
              final result = await _modelListService.getModelList(key: decryptedKey);
              if (result.success && result.models != null) {
                await _cacheService.saveModelList(widget.aiKey, result.models!);
                await _loadCachedModels();
                // 刷新对话框
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                  if (mounted) {
                    showDialog(
                      context: context,
                      builder: (newContext) => ModelListDialog(
                        models: result.models!,
                        platformName: widget.aiKey.platform,
                        keyId: widget.aiKey.id,
                        onUpdateModels: () => _handleViewModels(),
                      ),
                    );
                  }
                }
              } else {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(result.error ?? localizations?.updateModelListFailed ?? '更新模型列表失败'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          },
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)?.noCachedModelsPleaseSync ?? '暂无缓存的模型列表，请先同步'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  /// 同步密钥信息
  Future<void> _handleSync() async {
    if (_isSyncing) return;
    
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    
    setState(() {
      _isSyncing = true;
    });
    
    // 创建取消标志，确保通知与调用强相关
    bool cancelled = false;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    // 显示加载提示，带取消按钮
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(localizations?.syncing ?? '同步中...'),
            ),
            TextButton(
              onPressed: () {
                cancelled = true;
                scaffoldMessenger.hideCurrentSnackBar();
                setState(() {
                  _isSyncing = false;
                });
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(localizations?.syncCancelled ?? '已取消同步'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Text(localizations?.cancel ?? '取消', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        duration: Duration(seconds: 12), // 10秒超时 + 2秒缓冲
      ),
    );

    try {
      // 获取解密后的密钥
      final decryptedKey = await viewModel.getDecryptedKey(widget.aiKey.id!);
      if (decryptedKey == null) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(localizations?.syncFailedCheckNetwork ?? '同步失败，请检查密钥或网络'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // 检查是否已取消
      if (cancelled) {
        return;
      }

      // 使用timeout确保超时后立即返回
      SyncResult result;
      try {
        result = await _syncService.syncKey(decryptedKey).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            return SyncResult.failure(
              error: localizations?.syncFailedCheckNetwork ?? '同步失败，请检查密钥或网络',
              validationSuccess: false,
            );
          },
        );
      } catch (e) {
        // 超时或其他异常，立即返回失败
        if (!cancelled && mounted) {
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(localizations?.syncFailedCheckNetwork ?? '同步失败，请检查密钥或网络'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // 再次检查是否已取消
      if (cancelled) {
        return;
      }

      scaffoldMessenger.hideCurrentSnackBar();
      
      // 更新缓存的余额、模型列表和校验状态显示（同步服务已经保存到缓存，这里重新加载）
      await _loadCachedBalance();
      await _loadCachedModels();
      await _loadCachedValidationStatus();

      // 显示结果 - 简化消息
      if (!cancelled && mounted) {
        String message;
        if (result.success) {
          // 成功时只显示：同步成功、加载模型x个、余额xx
          final messageParts = <String>[];
          if (result.modelCount != null) {
            messageParts.add(localizations?.syncLoadedModels(result.modelCount!) ?? '加载模型 ${result.modelCount} 个');
          }
          if (result.balanceData != null) {
            final balanceStr = _formatBalanceForDisplay(result.balanceData!);
            if (balanceStr != null) {
              messageParts.add(localizations?.syncBalance(balanceStr) ?? '余额：$balanceStr');
            }
          }
          if (messageParts.isEmpty) {
            messageParts.add(localizations?.syncSuccess ?? '同步成功');
          }
          message = messageParts.join(' · ');
        } else {
          // 失败时只显示简单消息
          message = localizations?.syncFailedCheckNetwork ?? '同步失败，请检查密钥或网络';
        }
        
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: result.success ? Colors.green : Colors.red,
            duration: Duration(seconds: 3),
          ),
        );

        // 更新校验状态到数据库
        // 如果平台支持校验，根据校验结果更新状态
        final hasValidation = await _validationService.hasValidationConfig(widget.aiKey.platformType);
        if (hasValidation) {
          // 有校验配置，根据校验结果更新状态
          await viewModel.updateValidationStatus(widget.aiKey.id!, result.validationSuccess);
        }
      }
    } catch (e) {
      if (!cancelled && mounted) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(localizations?.syncFailedCheckNetwork ?? '同步失败，请检查密钥或网络'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted && !cancelled) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  /// 格式化余额显示
  String? _formatBalanceForDisplay(Map<String, dynamic> balanceData) {
    try {
      // 尝试解析常见的余额字段
      if (balanceData.containsKey('data')) {
        final data = balanceData['data'] as Map<String, dynamic>?;
        if (data != null) {
          // OpenRouter 格式：limit_remaining
          if (data.containsKey('limit_remaining')) {
            final limitRemaining = data['limit_remaining'];
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
            // 余额为0时也要显示
            if (balance != null) {
              return '¥${balance.toStringAsFixed(2)}';
            } else {
              // 字段存在但值为null，显示0
              return '¥0.00';
            }
          }
        }
      }
      
      // 直接查找余额字段
      if (balanceData.containsKey('balance')) {
        final balance = balanceData['balance'] as num?;
        // 余额为0时也要显示
        if (balance != null) {
          return '¥${balance.toStringAsFixed(2)}';
        } else {
          // 字段存在但值为null，显示0
          return '¥0.00';
        }
      }
      
      // 如果余额数据存在但没有任何余额字段，也显示0
      // 这适用于某些API返回空对象但表示余额为0的情况
      return '¥0.00';
    } catch (e) {
      return null;
    }
  }

  /// 查询余额
  Future<void> _handleQueryBalance() async {
    final viewModel = context.read<KeyManagerViewModel>();
    final localizations = AppLocalizations.of(context);
    
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ShadTheme.of(context).colorScheme.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const CircularProgressIndicator(),
        ),
      ),
    );

    try {
      // 获取解密后的密钥
      final decryptedKey = await viewModel.getDecryptedKey(widget.aiKey.id!);
      if (decryptedKey == null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations?.cannotDecryptKey ?? '无法解密密钥'), backgroundColor: Colors.red),
        );
        return;
      }

      final result = await _balanceQueryService.queryBalance(key: decryptedKey);
      Navigator.pop(context);

      if (result.success && result.balanceData != null) {
        // 解析余额数据
        final balanceData = result.balanceData!;
        final data = balanceData['data'] as Map<String, dynamic>?;
        final shadTheme = ShadTheme.of(context);
        
        // 显示余额信息对话框
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.account_balance_wallet, color: shadTheme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(localizations?.accountBalance ?? '账户余额'),
              ],
            ),
            content: SingleChildScrollView(
              child: data != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildBalanceRow(
                          dialogContext,
                          localizations?.availableBalance ?? '可用余额',
                          data['available_balance']?.toString() ?? '0.00',
                          Colors.green,
                        ),
                        const SizedBox(height: 12),
                        _buildBalanceRow(
                          dialogContext,
                          localizations?.cashBalance ?? '现金余额',
                          data['cash_balance']?.toString() ?? '0.00',
                          Colors.blue,
                        ),
                        const SizedBox(height: 12),
                        _buildBalanceRow(
                          dialogContext,
                          localizations?.voucherBalance ?? '代金券余额',
                          data['voucher_balance']?.toString() ?? '0.00',
                          Colors.orange,
                        ),
                      ],
                    )
                  : Text(
                      const JsonEncoder.withIndent('  ').convert(balanceData),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(localizations?.close ?? '关闭'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? (localizations?.queryBalanceFailed ?? '查询余额失败')), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.queryBalanceFailedWithError(e.toString()) ?? '查询余额失败：${e.toString()}'), backgroundColor: Colors.red),
      );
    }
  }

  /// 构建余额行
  /// 构建余额标签组件（在标签区域内显示，悬浮显示详细余额）
  Widget _buildBalanceDisplay(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations) {
    final balanceData = _cachedBalance;
    if (balanceData == null) {
      return SizedBox.shrink();
    }


    // 解析余额数据
    String? balanceText;
    String? tooltipText;
    
    try {
      if (balanceData.containsKey('data')) {
        final data = balanceData['data'] as Map<String, dynamic>?;
        if (data != null) {
          // OpenRouter 格式：limit_remaining
          if (data.containsKey('limit_remaining')) {
            final limitRemaining = data['limit_remaining'];
            final limit = data['limit'];
            
            // 余额为0就是0，即使 limit_remaining 为 null 也显示 $0.00
            if (limitRemaining == null) {
              balanceText = '\$0.00';
            } else {
              final remaining = limitRemaining as num?;
              if (remaining != null) {
                balanceText = '\$${remaining.toStringAsFixed(2)}';
              } else {
                balanceText = '\$0.00';
              }
            }
            
            // 构建 Tooltip 明细（显示更多信息）
            final details = <String>[];
            
            // 剩余余额
            if (limitRemaining != null) {
              final remaining = limitRemaining as num?;
              if (remaining != null) {
                details.add(localizations?.remainingBalance('\$${remaining.toStringAsFixed(2)}') ?? '剩余余额: \$${remaining.toStringAsFixed(2)}');
              }
            } else {
              details.add(localizations?.remainingBalance('\$0.00') ?? '剩余余额: \$0.00');
            }
            
            // 已使用额度
            final usage = data['usage'] as num?;
            if (usage != null) {
              details.add(localizations?.usedAmount('\$${usage.toStringAsFixed(2)}') ?? '已使用: \$${usage.toStringAsFixed(2)}');
            }
            
            // 总额度（如果有）
            if (limit != null) {
              details.add(localizations?.totalQuota('\$${limit.toStringAsFixed(2)}') ?? '总额度: \$${limit.toStringAsFixed(2)}');
            } else {
              details.add(localizations?.totalQuotaUnlimited ?? '总额度: 无限制');
            }
            
            // 每日使用量
            final usageDaily = data['usage_daily'] as num?;
            if (usageDaily != null && usageDaily > 0) {
              details.add(localizations?.dailyUsage('\$${usageDaily.toStringAsFixed(2)}') ?? '今日使用: \$${usageDaily.toStringAsFixed(2)}');
            }
            
            // 每周使用量
            final usageWeekly = data['usage_weekly'] as num?;
            if (usageWeekly != null && usageWeekly > 0) {
              details.add(localizations?.weeklyUsage('\$${usageWeekly.toStringAsFixed(2)}') ?? '本周使用: \$${usageWeekly.toStringAsFixed(2)}');
            }
            
            // 每月使用量
            final usageMonthly = data['usage_monthly'] as num?;
            if (usageMonthly != null && usageMonthly > 0) {
              details.add(localizations?.monthlyUsage('\$${usageMonthly.toStringAsFixed(2)}') ?? '本月使用: \$${usageMonthly.toStringAsFixed(2)}');
            }
            
            if (details.isNotEmpty) {
              tooltipText = details.join('\n');
            }
          }
          
          // SiliconFlow 格式：data.balance, data.totalBalance, data.chargeBalance
          if (balanceText == null && data.containsKey('balance')) {
            final balance = data['balance'];
            final totalBalance = data['totalBalance'];
            final chargeBalance = data['chargeBalance'];
            
            // 优先使用 totalBalance，否则使用 balance
            final balanceValue = totalBalance ?? balance;
            if (balanceValue != null) {
              final balanceNum = double.tryParse(balanceValue.toString());
              // 余额为0时也要显示
              if (balanceNum != null) {
                balanceText = '¥${balanceNum.toStringAsFixed(2)}';
                
                // 构建 Tooltip 明细
                final details = <String>[];
                details.add(localizations?.totalBalanceDetail('¥${balanceNum.toStringAsFixed(2)}') ?? '总余额: ¥${balanceNum.toStringAsFixed(2)}');
                
                if (chargeBalance != null) {
                  final charge = double.tryParse(chargeBalance.toString());
                  if (charge != null) {
                    details.add(localizations?.rechargeBalance('¥${charge.toStringAsFixed(2)}') ?? '充值余额: ¥${charge.toStringAsFixed(2)}');
                  }
                }
                
                final balanceOnly = data['balance'];
                if (balanceOnly != null && balanceOnly != balanceValue) {
                  final balanceNumOnly = double.tryParse(balanceOnly.toString());
                  if (balanceNumOnly != null) {
                    details.add(localizations?.availableBalanceDetail('¥${balanceNumOnly.toStringAsFixed(2)}') ?? '可用余额: ¥${balanceNumOnly.toStringAsFixed(2)}');
                  }
                }
                
                if (details.isNotEmpty) {
                  tooltipText = details.join('\n');
                }
              } else {
                // 值为null但字段存在，显示0
                balanceText = '¥0.00';
              }
            } else if (data.containsKey('totalBalance') || data.containsKey('balance')) {
              // 字段存在但值为null，显示0
              balanceText = '¥0.00';
            }
          }
          
          // Moonshot/Kimi 格式
          if (balanceText == null && data != null) {
            final availableBalance = data['available_balance'] as num?;
            final cashBalance = data['cash_balance'] as num?;
            final voucherBalance = data['voucher_balance'] as num?;
            
            // 余额为0时也要显示
            if (availableBalance != null) {
              balanceText = '¥${availableBalance.toStringAsFixed(2)}';
              
              // 构建 Tooltip 明细
              final details = <String>[];
              if (cashBalance != null) {
                details.add('${localizations?.cashBalance ?? "现金余额"}: ¥${cashBalance.toStringAsFixed(2)}');
              }
              if (voucherBalance != null) {
                details.add('${localizations?.voucherBalance ?? "代金券余额"}: ¥${voucherBalance.toStringAsFixed(2)}');
              }
              
              if (details.isNotEmpty) {
                tooltipText = details.join('\n');
              }
            } else if (data.containsKey('available_balance')) {
              // 字段存在但值为null，显示0
              balanceText = '¥0.00';
            }
          }
        }
      }
      
      // DeepSeek 格式：balance_infos 数组
      if (balanceText == null && balanceData.containsKey('balance_infos')) {
        final balanceInfos = balanceData['balance_infos'] as List?;
        if (balanceInfos != null && balanceInfos.isNotEmpty) {
          final firstBalance = balanceInfos[0] as Map<String, dynamic>?;
          if (firstBalance != null) {
            final totalBalance = firstBalance['total_balance'];
            final currency = firstBalance['currency'] as String? ?? 'CNY';
            
            if (totalBalance != null) {
              final balance = double.tryParse(totalBalance.toString());
              if (balance != null) {
                // 根据货币类型选择符号
                if (currency == 'CNY' || currency == 'RMB') {
                  balanceText = '¥${balance.toStringAsFixed(2)}';
                } else if (currency == 'USD') {
                  balanceText = '\$${balance.toStringAsFixed(2)}';
                } else {
                  balanceText = '$currency ${balance.toStringAsFixed(2)}';
                }
                
                // 构建 Tooltip 明细
                final details = <String>[];
                details.add(localizations?.totalBalanceDetail(balanceText) ?? '总余额: ${balanceText}');
                
                final grantedBalance = firstBalance['granted_balance'];
                if (grantedBalance != null) {
                  final granted = double.tryParse(grantedBalance.toString());
                  if (granted != null && granted > 0) {
                    details.add(localizations?.grantedBalance('${currency == 'CNY' || currency == 'RMB' ? '¥' : '\$'}${granted.toStringAsFixed(2)}') ?? '赠送余额: ${currency == 'CNY' || currency == 'RMB' ? '¥' : '\$'}${granted.toStringAsFixed(2)}');
                  }
                }
                
                final toppedUpBalance = firstBalance['topped_up_balance'];
                if (toppedUpBalance != null) {
                  final toppedUp = double.tryParse(toppedUpBalance.toString());
                  if (toppedUp != null && toppedUp > 0) {
                    details.add(localizations?.toppedUpBalance('${currency == 'CNY' || currency == 'RMB' ? '¥' : '\$'}${toppedUp.toStringAsFixed(2)}') ?? '充值余额: ${currency == 'CNY' || currency == 'RMB' ? '¥' : '\$'}${toppedUp.toStringAsFixed(2)}');
                  }
                }
                
                if (details.isNotEmpty) {
                  tooltipText = details.join('\n');
                }
              }
            }
          }
        }
      }
      
      // 如果没有解析到，尝试直接获取 balance 字段
      if (balanceText == null && balanceData.containsKey('balance')) {
        final balance = balanceData['balance'] as num?;
        // 余额为0时也要显示
        if (balance != null) {
          balanceText = '¥${balance.toStringAsFixed(2)}';
        } else {
          // 字段存在但值为null，显示0
          balanceText = '¥0.00';
        }
      }
    } catch (e) {
      print('KeyCard: 解析余额失败: $e');
    }

    // 如果余额数据存在但解析失败，显示默认值 ¥0.00
    // 确保余额为0时也能显示
    if (balanceText == null) {
      // 如果余额数据存在（不为null），说明有余额查询支持，应该显示0
      // 如果余额数据为null，说明不支持余额查询，不显示
      if (balanceData != null && balanceData.isNotEmpty) {
        balanceText = '¥0.00';
      } else {
        return SizedBox.shrink();
      }
    }

    // 构建紧凑的余额标签，点击可查询最新余额
    final kc = context.kc;
    final tag = GestureDetector(
      onTap: _supportsBalanceQuery == true ? _handleQueryBalance : null,
      child: Container(
        height: 20,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: kc.okSoft,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          balanceText,
          style: KcType.badge.copyWith(color: kc.okText, fontFeatures: KcType.tabular),
        ),
      ),
    );

    if (tooltipText != null && tooltipText.isNotEmpty) {
      return Tooltip(message: tooltipText, child: tag);
    }
    return tag;
  }

  Widget _buildBalanceRow(BuildContext context, String label, String value, Color color) {
    final shadTheme = ShadTheme.of(context);
    final numValue = double.tryParse(value) ?? 0.0;
    final formattedValue = numValue.toStringAsFixed(2);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        Text(
          '¥$formattedValue',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ───────────────────────────── 布局层（ui_redesign_plan §5.2）─────────────────────────────
  // 140 高：顶部 36（logo + 名称 + 掩码密钥 + 右上角操作）/ 标签行 20 / 底部 34（工具状态 chip 或管理操作）。
  // 回调签名与之前一致；管理模式不渲染可点 chip、不包 InkWell，避免抢 ReorderableWrap 的拖动手势。

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final localizations = AppLocalizations.of(context);
    final isLensCurrent = widget.cardMode == KeyCardMode.switchKey && widget.isCurrent;

    final borderColor = isLensCurrent
        ? kc.ok
        : (_isHovering && !widget.isEditMode ? cs.input : cs.border);
    final bg = isLensCurrent ? Color.alphaBlend(kc.okSoft, cs.card) : cs.card;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(KcSpace.x3, KcSpace.x2 + 2, KcSpace.x3, 0),
      child: _buildCardContent(context, ShadTheme.of(context), localizations),
    );

    return Semantics(
      container: true,
      label: widget.aiKey.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: KcMotion.of(context),
          curve: KcMotion.curve,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(KcRadius.panel),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: _isHovering && !widget.isEditMode ? kc.shadowMd : kc.shadowSm,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KcRadius.panel),
            child: Material(
              type: MaterialType.transparency,
              // 编辑模式下不使用 InkWell，避免拦截拖动事件
              child: widget.isEditMode
                  ? SizedBox.expand(child: content)
                  : InkWell(
                      onTap: _handleCardTap,
                      hoverColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: SizedBox.expand(child: content),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    ShadThemeData shadTheme,
    AppLocalizations? localizations,
  ) {
    final cs = shadTheme.colorScheme;
    final kc = context.kc;
    final key = widget.aiKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 顶部：logo + 名称/★ + 平台 · 掩码密钥 + 右上角
        SizedBox(
          height: 36,
          child: Row(
            children: [
              KcPlatformLogo(platform: key.platformType, customIconFileName: key.icon, name: key.name),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            key.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KcType.strong.copyWith(color: cs.foreground),
                          ),
                        ),
                        if (key.isFavorite) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: localizations?.favoriteLabel ?? '收藏',
                            child: Icon(Icons.star_rounded, key: const ValueKey('keyCard.favorite'), size: 14, color: kc.warn),
                          ),
                        ],
                      ],
                    ),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: key.platform),
                        const TextSpan(text: '  ·  '),
                        TextSpan(text: maskKeyForCard(key), style: KcType.mono.copyWith(fontSize: 11.5)),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KcType.caption.copyWith(color: cs.mutedForeground, height: 1.25),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KcSpace.x1_5),
              _buildTopRight(context, localizations),
            ],
          ),
        ),
        const SizedBox(height: KcSpace.x2),
        // 2. 标签行：状态 badge 优先，其后分类 / 模型数 / 余额 / 用户标签（单行裁切）
        SizedBox(
          height: 20,
          width: double.infinity,
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildTagRow(context, shadTheme, localizations),
              ),
            ),
          ),
        ),
        const Spacer(),
        // 3. 底部：工具状态 chip（普通）或「n 个工具 + 置顶/编辑/删除」（管理）
        Container(
          height: 34,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.border))),
          child: widget.isEditMode
              ? _buildManageBar(context, localizations)
              : (widget.lens != null ? _LensBar(aiKey: widget.aiKey, lens: widget.lens!) : _buildToolBar(context)),
        ),
      ],
    );
  }

  /// 右上角：管理模式 = 常显拖拽手柄；OpenClaw 开关；工具页生效 badge；普通 hover = 复制 / 编辑 / ⋯
  Widget _buildTopRight(BuildContext context, AppLocalizations? localizations) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    if (widget.isEditMode) {
      return Tooltip(
        message: localizations?.manageToggleTip ?? '拖动排序',
        child: Container(
          key: const ValueKey('keyCard.dragHandle'),
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(KcRadius.control)),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Icon(Icons.drag_indicator, size: 16, color: kc.text2),
          ),
        ),
      );
    }
    if (widget.onToggle != null) {
      return Transform.scale(
        scale: 0.75,
        child: Switch(value: widget.isCurrent, onChanged: widget.onToggle, activeColor: cs.primary),
      );
    }
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          context,
          key: const ValueKey('keyCard.copy'),
          icon: Icons.copy_outlined,
          tooltip: localizations?.copyKey ?? '复制密钥',
          onPressed: widget.onCopyApiKey,
        ),
        const SizedBox(width: 2),
        _buildActionButton(
          context,
          key: const ValueKey('keyCard.hoverEdit'),
          icon: Icons.edit_outlined,
          tooltip: localizations?.edit ?? '编辑',
          onPressed: widget.onEdit,
        ),
        const SizedBox(width: 2),
        _buildMoreMenu(context, localizations),
      ],
    );
    final showActions = _isHovering || _menuOpen;
    final badge = (widget.cardMode == KeyCardMode.switchKey && widget.isCurrent)
        ? _StatusBadge(text: localizations?.statusActive ?? '生效中', fg: kc.okText, bg: kc.okSoft, dot: kc.ok)
        : null;
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        if (badge != null) AnimatedOpacity(opacity: showActions ? 0 : 1, duration: KcMotion.of(context), child: badge),
        AnimatedOpacity(
          opacity: showActions ? 1 : 0,
          duration: KcMotion.of(context),
          child: IgnorePointer(ignoring: !showActions, child: actions),
        ),
      ],
    );
  }

  Widget _buildMoreMenu(BuildContext context, AppLocalizations? localizations) {
    final cs = ShadTheme.of(context).colorScheme;
    final key = widget.aiKey;
    final items = <(String, IconData, String, VoidCallback?)>[
      ('view', Icons.visibility_outlined, localizations?.details ?? '查看', widget.onView ?? widget.onTap),
      if (key.managementUrl != null)
        ('url', Icons.open_in_new, localizations?.openManagementUrl ?? '访问后台', widget.onOpenManagementUrl),
      if (key.apiEndpoint != null)
        ('endpoint', Icons.link, localizations?.copyApiEndpoint ?? '复制请求地址', widget.onCopyApiEndpoint),
      if (key.enableCodex && widget.onCopyEnvVarCommand != null)
        ('env', Icons.terminal_outlined, localizations?.copyEnvVarCommand ?? '复制环境变量命令', widget.onCopyEnvVarCommand),
      if (_supportsSync == true)
        ('sync', Icons.sync, localizations?.sync ?? '同步', _isSyncing ? null : _handleSync),
      if (_supportsModelList == true && (_cachedModels?.isNotEmpty ?? false))
        ('models', Icons.view_list_outlined, localizations?.viewModels ?? '查看模型', _handleViewModels),
      if (widget.onMoveToTop != null)
        ('top', Icons.vertical_align_top, localizations?.moveToTop ?? '置顶', widget.onMoveToTop),
    ];
    return Tooltip(
      key: const ValueKey('keyCard.more'),
      message: localizations?.moreActions ?? '更多',
      child: PopupMenuButton<String>(
        tooltip: '',
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        color: cs.popover,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KcRadius.panel),
          side: BorderSide(color: cs.border),
        ),
        onOpened: () => setState(() => _menuOpen = true),
        onCanceled: () => setState(() => _menuOpen = false),
        onSelected: (id) {
          setState(() => _menuOpen = false);
          for (final it in items) {
            if (it.$1 == id) it.$4?.call();
          }
        },
        itemBuilder: (_) => [
          for (final it in items)
            PopupMenuItem<String>(
              value: it.$1,
              enabled: it.$4 != null,
              height: 32,
              child: Row(children: [
                Icon(it.$2, size: 15, color: cs.mutedForeground),
                const SizedBox(width: 10),
                Text(it.$3, style: KcType.body.copyWith(color: cs.popoverForeground)),
              ]),
            ),
        ],
        child: _iconBox(context, Icons.more_horiz),
      ),
    );
  }

  List<Widget> _buildTagRow(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations) {
    final kc = context.kc;
    final key = widget.aiKey;
    final out = <Widget>[];
    void add(Widget w) => out.add(Padding(padding: const EdgeInsets.only(right: KcSpace.x1_5), child: w));

    // 状态 badge 优先
    if (key.isExpired) {
      add(_StatusBadge(text: localizations?.expired ?? '已过期', fg: kc.dangerText, bg: kc.dangerSoft));
    } else if (key.isExpiringSoon && key.expiryDate != null) {
      final days = key.expiryDate!.difference(DateTime.now()).inDays.clamp(0, 999);
      add(_StatusBadge(text: localizations?.expiresInDays(days) ?? '$days 天后过期', fg: kc.warnText, bg: kc.warnSoft));
    }
    if (_hasValidationConfig == true && _cachedValidationStatus == false) {
      add(_StatusBadge(
        key: const ValueKey('keyCard.validationFailed'),
        text: localizations?.validationFailedBadge ?? '校验失败',
        fg: kc.dangerText,
        bg: kc.dangerSoft,
      ));
    }
    // 用户标签
    for (final tag in key.tags) {
      add(_buildTag(context, tag, isCategory: false, isUserTag: true));
    }
    // 模型数（可点开模型列表）
    if (_supportsModelList == true && _cachedModels != null && _cachedModels!.isNotEmpty) {
      add(GestureDetector(
        onTap: widget.isEditMode ? null : _handleViewModels,
        child: _buildTag(
          context,
          localizations?.modelsLabel(_cachedModels!.length) ?? '${_cachedModels!.length} 个模型',
          isCategory: false,
          isClickable: true,
          isModelTag: true,
        ),
      ));
    }
    // 余额（可点查询）
    if (!widget.isEditMode && _cachedBalance != null) {
      add(_buildBalanceDisplay(context, shadTheme, localizations));
    }
    // 平台分类（最后，信息量最低）
    if (key.tags.isEmpty) {
      final cats = PlatformCategoryManager.getCategoriesForPlatform(key.platformType)
          .where((c) => c != PlatformCategory.custom)
          .take(1);
      for (final c in cats) {
        add(_buildTag(context, c.getValue(context), isCategory: true));
      }
    }
    return out;
  }

  /// 普通模式底部：工具状态 chip
  Widget _buildToolBar(BuildContext context) {
    final ids = widget.currentKeyIds ?? _maybeCurrentKeyIds(context);
    return _ToolStatusChips(
      aiKey: widget.aiKey,
      currentKeyIds: ids,
      cardHovered: _isHovering,
      onSwitchTool: widget.cardMode == KeyCardMode.view ? widget.onSwitchTool : null,
      onEnableTool: widget.cardMode == KeyCardMode.view ? widget.onEnableTool : null,
    );
  }

  Map<AiToolType, int?> _maybeCurrentKeyIds(BuildContext context) {
    try {
      return Provider.of<KeyManagerViewModel>(context).currentKeyIds;
    } on ProviderNotFoundException {
      return const {};
    }
  }

  /// 管理模式底部：「n 个工具」+ 置顶 / 编辑 / 删除（回调与顺序不变）
  Widget _buildManageBar(BuildContext context, AppLocalizations? localizations) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final n = enabledToolsOf(widget.aiKey).length;
    return Row(
      children: [
        Expanded(
          child: Text(
            n == 0 ? (localizations?.segmentUnused ?? '未用到工具') : (localizations?.nTools(n) ?? '$n 个工具'),
            style: KcType.caption.copyWith(color: cs.mutedForeground),
          ),
        ),
        _buildActionButton(
          context,
          key: const ValueKey('keyCard.moveToTop'),
          icon: Icons.vertical_align_top,
          tooltip: localizations?.moveToTop ?? '置顶',
          onPressed: widget.onMoveToTop,
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          context,
          key: const ValueKey('keyCard.edit'),
          icon: Icons.edit_outlined,
          tooltip: localizations?.edit ?? '编辑',
          onPressed: widget.onEdit,
        ),
        const SizedBox(width: 4),
        _buildActionButton(
          context,
          key: const ValueKey('keyCard.delete'),
          icon: Icons.delete_outline,
          tooltip: localizations?.deleteTooltip ?? '删除',
          onPressed: widget.onDelete,
          color: kc.dangerText,
        ),
      ],
    );
  }

  Widget _buildTag(BuildContext context, String text, {required bool isCategory, bool isUserTag = false, bool isClickable = false, bool isModelTag = false}) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final fg = isClickable ? kc.actionText : kc.text2;
    final bg = isClickable ? kc.actionSoft : kc.subtle;
    return Container(
      height: 20,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: KcType.badge.copyWith(color: isCategory ? cs.mutedForeground : fg, fontFeatures: KcType.tabular),
      ),
    );
  }

  Widget _iconBox(BuildContext context, IconData icon, {Color? color}) {
    final kc = context.kc;
    return SizedBox(
      width: 26,
      height: 26,
      child: Icon(icon, size: 15, color: color ?? kc.text2),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final kc = context.kc;
    return Tooltip(
      key: key,
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(KcRadius.control),
          hoverColor: kc.subtle,
          child: _iconBox(context, icon, color: color),
        ),
      ),
    );
  }

  /// 处理卡片点击事件
  void _handleCardTap() {
    if (widget.cardMode == KeyCardMode.view) {
      // 查看模式：优先使用 onView，否则使用 onTap
      if (widget.onView != null) {
        widget.onView!();
      } else if (widget.onTap != null) {
        widget.onTap!();
      }
    } else {
      // 切换模式：直接调用 onTap
      if (widget.onTap != null) {
        widget.onTap!();
      }
    }
  }
}

/// 卡片上显示的掩码密钥：只露前缀（如 `sk-`）和后 4 位；加密存储（有 nonce）时不解密，只显示圆点。
String maskKeyForCard(AIKey key) {
  const dots = '••••';
  final v = key.keyValue.trim();
  if (key.keyNonce != null || v.length < 8) return '$dots$dots';
  final dash = v.indexOf('-');
  final prefix = (dash > 0 && dash <= 6) ? v.substring(0, dash + 1) : '';
  return '$prefix$dots${v.substring(v.length - 4)}';
}

/// 这把密钥启用了哪些工具（按 Claude Code / Desktop / Codex / Gemini / OpenClaw 顺序）
List<AiToolType> enabledToolsOf(AIKey k) => [
      if (k.enableClaudeCode) AiToolType.claudecode,
      if (k.enableClaudeDesktop) AiToolType.claudeDesktop,
      if (k.enableCodex) AiToolType.codex,
      if (k.enableGemini) AiToolType.gemini,
      if (k.enableOpenclaw) AiToolType.openclaw,
    ];

/// 切换某个工具时会写入的配置文件（HoverTip 用）
String toolConfigPathHint(AiToolType tool) {
  switch (tool) {
    case AiToolType.claudecode:
      return '~/.claude/settings.json';
    case AiToolType.claudeDesktop:
      return 'Claude Desktop config';
    case AiToolType.codex:
      return '~/.codex/auth.json';
    case AiToolType.gemini:
      return '~/.gemini/.env';
    case AiToolType.openclaw:
      return '~/.openclaw/openclaw.json';
    default:
      return '';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({super.key, required this.text, required this.fg, required this.bg, this.dot});
  final String text;
  final Color fg;
  final Color bg;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Text(text, style: KcType.badge.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// 某个工具上这把密钥的模型（展示用）
String? toolModelOf(AIKey k, AiToolType t) {
  switch (t) {
    case AiToolType.claudecode:
      return k.claudeCodeModel;
    case AiToolType.claudeDesktop:
      return k.claudeDesktopModel ?? k.claudeDesktopSonnetModel;
    case AiToolType.codex:
      return k.codexModel;
    case AiToolType.gemini:
      return k.geminiModel;
    case AiToolType.openclaw:
      return k.openclawModel;
    default:
      return null;
  }
}

/// lens 卡片底栏：左边是这把密钥在该工具下的模型，右边「也用于」其他工具的 logo
class _LensBar extends StatelessWidget {
  const _LensBar({required this.aiKey, required this.lens});
  final AIKey aiKey;
  final AiToolType lens;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final model = toolModelOf(aiKey, lens);
    final others = enabledToolsOf(aiKey).where((t) => t != lens).toList();
    return Row(
      children: [
        if (model != null && model.trim().isNotEmpty)
          Flexible(
            child: Container(
              key: const ValueKey('lens.model'),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(color: kc.subtle, borderRadius: BorderRadius.circular(KcRadius.control)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.memory_rounded, size: 12, color: kc.text2),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KcType.mono.copyWith(fontSize: 11, color: cs.foreground)),
                ),
              ]),
            ),
          )
        else
          Text(lens == AiToolType.gemini ? (l?.officialApiShort ?? '官方 API') : (l?.defaultModel ?? '默认模型'),
              style: KcType.caption.copyWith(color: cs.mutedForeground)),
        const Spacer(),
        if (others.isNotEmpty) ...[
          Text(l?.alsoUsedIn ?? '也用于', key: const ValueKey('lens.alsoUsed'), style: KcType.caption.copyWith(color: cs.mutedForeground)),
          const SizedBox(width: 4),
          for (final t in others.take(4))
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Tooltip(message: kcToolName(t), child: KcToolLogo(tool: t, size: 16)),
            ),
        ],
      ],
    );
  }
}

/// 工具状态 chip（§2.1 三态）：
/// - 生效中：绿色 soft 胶囊（logo + 短名 + 绿点）
/// - 已启用：只有 logo 的描边圆 chip，hover 变操作色描边；点击 = 直接切换（toast 里可撤销）
/// - 未启用：不出现；卡片 hover 或一个工具都没有时显示「＋」，弹出可启用工具菜单
class _ToolStatusChips extends StatelessWidget {
  const _ToolStatusChips({
    required this.aiKey,
    required this.currentKeyIds,
    required this.cardHovered,
    this.onSwitchTool,
    this.onEnableTool,
  });

  final AIKey aiKey;
  final Map<AiToolType, int?> currentKeyIds;
  final bool cardHovered;
  final ValueChanged<AiToolType>? onSwitchTool;
  final ValueChanged<AiToolType>? onEnableTool;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cs = ShadTheme.of(context).colorScheme;
    final enabled = enabledToolsOf(aiKey);
    final active = enabled.where((t) => aiKey.id != null && currentKeyIds[t] == aiKey.id).toList();
    final rest = enabled.where((t) => !active.contains(t)).toList();
    final notEnabled = kcKeyTools.where((t) => !enabled.contains(t)).toList();

    final chips = <Widget>[
      for (final t in active) _ActiveChip(tool: t),
      for (final t in rest)
        _EnabledChip(
          tool: t,
          onTap: (t == AiToolType.openclaw || onSwitchTool == null) ? null : () => onSwitchTool!(t),
          tooltip: t == AiToolType.openclaw
              ? (l?.openclawChipTip ?? '已启用到 OpenClaw')
              : (l?.switchToToolTip(kcToolName(t), toolConfigPathHint(t)) ?? '切到 ${kcToolName(t)} · 写入 ${toolConfigPathHint(t)}'),
        ),
    ];

    final hasPlus = onEnableTool != null && notEnabled.isNotEmpty;
    final showPlus = hasPlus && (cardHovered || enabled.isEmpty);
    return Row(
      children: [
        Expanded(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final c in chips) Padding(padding: const EdgeInsets.only(right: 5), child: c),
                  // 菜单弹出后鼠标离开卡片（hover 消失）时按钮必须仍然挂载，否则选中项会被 PopupMenuButton 丢弃
                  if (hasPlus)
                    Visibility(
                      visible: showPlus,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: _PlusMenu(tools: notEnabled, onSelected: onEnableTool!, withLabel: enabled.isEmpty),
                    ),
                  if (!showPlus && enabled.isEmpty)
                    Text(l?.segmentUnused ?? '未用到工具', style: KcType.caption.copyWith(color: cs.mutedForeground)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({required this.tool});
  final AiToolType tool;

  @override
  Widget build(BuildContext context) {
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    return Tooltip(
      message: l?.activeInToolTip(kcToolName(tool)) ?? '正在 ${kcToolName(tool)} 生效',
      child: Container(
        key: ValueKey('toolChip.active.${tool.value}'),
        height: 24,
        padding: const EdgeInsets.only(left: 3, right: 8),
        decoration: BoxDecoration(color: kc.okSoft, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KcToolLogo(tool: tool, size: 18),
            const SizedBox(width: 5),
            Text(kcToolShortName(tool), style: KcType.badge.copyWith(color: kc.okText)),
            const SizedBox(width: 5),
            Container(width: 6, height: 6, decoration: BoxDecoration(color: kc.ok, shape: BoxShape.circle)),
          ],
        ),
      ),
    );
  }
}

class _EnabledChip extends StatefulWidget {
  const _EnabledChip({required this.tool, required this.tooltip, this.onTap});
  final AiToolType tool;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  State<_EnabledChip> createState() => _EnabledChipState();
}

class _EnabledChipState extends State<_EnabledChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final clickable = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: clickable,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: clickable ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            key: ValueKey('toolChip.enabled.${widget.tool.value}'),
            behavior: HitTestBehavior.opaque,
            // 不可切换（OpenClaw / 工具页）时也吞掉点击，避免冒泡成「打开详情」
            onTap: widget.onTap ?? () {},
            child: AnimatedContainer(
              duration: KcMotion.of(context),
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _hover && clickable ? cs.primary : cs.border, width: _hover && clickable ? 1.5 : 1),
              ),
              child: KcToolLogo(tool: widget.tool, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusMenu extends StatelessWidget {
  const _PlusMenu({required this.tools, required this.onSelected, required this.withLabel});
  final List<AiToolType> tools;
  final ValueChanged<AiToolType> onSelected;
  final bool withLabel;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final l = AppLocalizations.of(context);
    final circle = CustomPaint(
      painter: _DashedCirclePainter(color: cs.input),
      child: SizedBox(width: 24, height: 24, child: Icon(Icons.add, size: 14, color: kc.text2)),
    );
    return PopupMenuButton<AiToolType>(
      key: const ValueKey('toolChip.plus'),
      tooltip: l?.enableMoreTools ?? '启用到更多工具',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: cs.popover,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KcRadius.panel),
        side: BorderSide(color: cs.border),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final t in tools)
          PopupMenuItem<AiToolType>(
            value: t,
            height: 32,
            child: Row(children: [
              KcToolLogo(tool: t, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(l?.enableForTool(kcToolName(t)) ?? '启用到 ${kcToolName(t)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KcType.body.copyWith(color: cs.popoverForeground)),
              ),
            ]),
          ),
      ],
      child: withLabel
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              circle,
              const SizedBox(width: 6),
              Text(l?.segmentUnused ?? '未用到工具', style: KcType.caption.copyWith(color: cs.mutedForeground)),
            ])
          : circle,
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = size.shortestSide / 2 - 0.5;
    final c = size.center(Offset.zero);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a0 = 2 * math.pi * i / n;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, math.pi / n, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}

/// 拖拽中跟随指针的卡片（mockup 02b）：同一个 KeyCard（管理态），外加 -1.5° 旋转、1.03 缩放、
/// shadow-lg 与 1px 操作色描边。系统开启「减少动态效果」时不旋转、不缩放。
class KeyCardDragFeedback extends StatelessWidget {
  const KeyCardDragFeedback({super.key, required this.constraints, required this.child});

  final BoxConstraints constraints;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final kc = context.kc;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget card = ConstrainedBox(
      constraints: constraints,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(KcRadius.panel),
          border: Border.all(color: cs.primary, width: 1),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KcRadius.panel),
            boxShadow: kc.shadowLg,
          ),
          child: child,
        ),
      ),
    );
    if (!reduce) {
      card = Transform.rotate(angle: -1.5 * math.pi / 180, child: Transform.scale(scale: 1.03, child: card));
    }
    return MouseRegion(
      cursor: SystemMouseCursors.grabbing,
      child: Material(type: MaterialType.transparency, child: card),
    );
  }
}
