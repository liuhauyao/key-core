import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../../models/ai_key.dart';
import '../../models/model_info.dart';
import '../../models/platform_category.dart';
import '../../models/platform_type.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_helper.dart';
import '../../services/key_validation_service.dart';
import '../../services/model_list_service.dart';
import '../../services/balance_query_service.dart';
import '../../services/key_sync_service.dart';
import '../../services/key_cache_service.dart';
import '../../viewmodels/key_manager_viewmodel.dart';
import 'package:provider/provider.dart';
import 'model_list_dialog.dart';

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
  bool _isSyncing = false;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    // 只在首次初始化时检查配置，避免编辑模式切换时重复检查
    _checkValidationConfig();
    // 加载缓存的余额和模型列表
    _loadCachedBalance();
    _loadCachedModels();
  }

  @override
  void didUpdateWidget(KeyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当密钥ID或平台类型变化时才重新检查配置和重新加载缓存
    // 避免因为 notifyListeners() 导致所有 KeyCard 重新加载缓存
    // 注意：即使 widget.aiKey 对象引用不同，只要 id 和 platformType 相同，就不重新加载
    if (oldWidget.aiKey.id != widget.aiKey.id ||
        oldWidget.aiKey.platformType != widget.aiKey.platformType) {
      _checkValidationConfig();
      _loadCachedBalance();
      _loadCachedModels();
    }
    // 如果只是其他字段（如 isValidated）变化，不重新加载缓存
  }

  /// 检查是否有校验配置和模型列表支持
  Future<void> _checkValidationConfig() async {
    // 避免重复检查：如果已经有值了，就不再检查
    if (_hasValidationConfig != null && 
        _supportsModelList != null && 
        _supportsBalanceQuery != null &&
        _supportsSync != null) {
      return;
    }
    
    print('KeyCard: 检查校验配置，平台类型: ${widget.aiKey.platformType.id}');
    final hasValidation = await _validationService.hasValidationConfig(widget.aiKey.platformType);
    final supportsModelList = await _validationService.supportsModelList(widget.aiKey.platformType);
    final supportsBalanceQuery = await _balanceQueryService.supportsBalanceQuery(widget.aiKey.platformType);
    final supportsSync = await _syncService.supportsSync(widget.aiKey.platformType);
    
    print('KeyCard: 校验配置结果 - hasValidation: $hasValidation, supportsModelList: $supportsModelList, supportsBalanceQuery: $supportsBalanceQuery, supportsSync: $supportsSync');
    
    if (mounted) {
      setState(() {
        _hasValidationConfig = hasValidation;
        _supportsModelList = supportsModelList;
        _supportsBalanceQuery = supportsBalanceQuery;
        _supportsSync = supportsSync;
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
    
    // 创建取消标志
    bool cancelled = false;
    
    // 显示加载提示，带取消按钮
    final scaffoldMessenger = ScaffoldMessenger.of(context);
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
        duration: Duration(seconds: 60),
      ),
    );

    try {
      // 获取解密后的密钥
      final decryptedKey = await viewModel.getDecryptedKey(widget.aiKey.id!);
      if (decryptedKey == null) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(localizations?.cannotDecryptKey ?? '无法解密密钥'), backgroundColor: Colors.red),
        );
        return;
      }

      // 检查是否已取消
      if (cancelled) {
        return;
      }

      final result = await _syncService.syncKey(decryptedKey);
      
      // 再次检查是否已取消
      if (cancelled) {
        return;
      }

      scaffoldMessenger.hideCurrentSnackBar();
      
      // 更新缓存的余额和模型列表显示（同步服务已经保存到缓存，这里重新加载）
      await _loadCachedBalance();
      await _loadCachedModels();

      // 显示结果
      if (!cancelled) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? (localizations?.syncSuccessMessage(result.message) ?? '同步成功：${result.message}')
                  : (localizations?.syncFailedMessage(result.error ?? (localizations?.unknownError ?? '未知错误')) ?? '同步失败：${result.error ?? (localizations?.unknownError ?? '未知错误')}'),
            ),
            backgroundColor: result.success ? Colors.green : Colors.red,
            duration: Duration(seconds: 4),
          ),
        );

        // 更新校验状态到数据库
        // 如果平台支持校验，根据校验结果更新状态
        final hasValidation = await _validationService.hasValidationConfig(widget.aiKey.platformType);
        if (hasValidation) {
          // 有校验配置，根据校验结果更新状态
          await viewModel.updateValidationStatus(widget.aiKey.id!, result.validationSuccess);
          print('KeyCard: 更新校验状态，密钥ID: ${widget.aiKey.id}, 校验成功: ${result.validationSuccess}');
        }
      }
    } catch (e) {
      if (!cancelled) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(localizations?.syncFailedWithError(e.toString()) ?? '同步失败：${e.toString()}'),
            backgroundColor: Colors.red,
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
  /// 构建余额显示组件（右上角）
  Widget _buildBalanceDisplay(BuildContext context, ShadThemeData shadTheme, AppLocalizations? localizations) {
    final balanceData = _cachedBalance;
    if (balanceData == null) {
      print('KeyCard: 余额数据为空，不显示余额');
      return SizedBox.shrink();
    }

    print('KeyCard: 开始解析余额，数据: $balanceData');

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
              }
            }
          }
          
          // Moonshot/Kimi 格式
          if (balanceText == null) {
            final availableBalance = data['available_balance'] as num?;
            final cashBalance = data['cash_balance'] as num?;
            final voucherBalance = data['voucher_balance'] as num?;
            
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
        if (balance != null) {
          balanceText = '¥${balance.toStringAsFixed(2)}';
        }
      }
    } catch (e) {
      print('KeyCard: 解析余额失败: $e');
    }

    print('KeyCard: 解析后的余额文本: $balanceText');
    if (balanceText == null) {
      print('KeyCard: 余额文本为 null，不显示余额');
      return SizedBox.shrink();
    }

    // 解析余额文本，分离货币符号和金额
    // 余额格式通常是 "¥100.00" 或 "$100.00"
    String currencySymbol = '';
    String amount = balanceText;
    if (balanceText.isNotEmpty) {
      final match = RegExp(r'^([^\d]+)(\d+\.?\d*)$').firstMatch(balanceText);
      if (match != null) {
        currencySymbol = match.group(1) ?? '';
        amount = match.group(2) ?? balanceText;
      } else {
        // 如果没有匹配到，尝试查找第一个数字的位置
        final firstDigitIndex = balanceText.indexOf(RegExp(r'\d'));
        if (firstDigitIndex > 0) {
          currencySymbol = balanceText.substring(0, firstDigitIndex);
          amount = balanceText.substring(firstDigitIndex);
        }
      }
    }
    
    final balanceWidget = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end, // 整体底部对齐
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          localizations?.balance ?? '余额',
          style: shadTheme.textTheme.small.copyWith(
            fontSize: 10,
            color: shadTheme.colorScheme.mutedForeground,
            height: 1.0, // 紧凑行高
          ),
        ),
        const SizedBox(height: 6), // 稍微添加间距
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currencySymbol,
              style: shadTheme.textTheme.p.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.green.shade700,
                height: 1.0, // 紧凑行高
              ),
            ),
            Text(
              amount,
              style: shadTheme.textTheme.p.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.green.shade700,
                height: 1.0, // 紧凑行高
              ),
            ),
          ],
        ),
      ],
    );

    if (tooltipText != null && tooltipText.isNotEmpty) {
      return Tooltip(
        message: tooltipText,
        child: balanceWidget,
      );
    }

    return balanceWidget;
  }

  /// 构建校验通过标签（绿色呼吸圆点）
  Widget _buildValidationSuccessLabel(BuildContext context, ShadThemeData shadTheme) {
    return _ValidationIndicator();
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

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        // transform: Matrix4.identity()..translate(0.0, _isHovering ? -4.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // 基础背景色
          color: widget.isCurrent
              ? Color.alphaBlend(
                  shadTheme.colorScheme.primary.withOpacity(0.04),
                  shadTheme.colorScheme.card,
                )
              : shadTheme.colorScheme.card,
          border: Border.all(
            color: widget.isCurrent
                ? shadTheme.colorScheme.primary
                : shadTheme.colorScheme.border, // 完全不透明
            width: widget.isCurrent ? 2 : 1.5, // 增加边框宽度
          ),
          boxShadow: [
            if (_isHovering)
              BoxShadow(
                color: Colors.black.withOpacity(0.25), // 更深的阴影
                blurRadius: 24, // 更大的模糊半径
                offset: const Offset(0, 12), // 更大的偏移量，增加悬浮高度感
                spreadRadius: 0,
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
                spreadRadius: 0,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              // 1. 柔和的流光渐变（模拟环境光）
              // 左上角的高光
              Positioned(
                top: -100,
                left: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        shadTheme.colorScheme.primary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              // 右下角的反光
              Positioned(
                bottom: -100,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        shadTheme.colorScheme.secondary.withOpacity(0.05),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),

              // 2. 噪点纹理（提供磨砂质感）
              Positioned.fill(
                child: Opacity(
                  opacity: 0.04, // 极低的透明度，只保留微妙质感
                  child: CustomPaint(
                    painter: _NoisePainter(
                      color: shadTheme.colorScheme.foreground,
                    ),
                  ),
                ),
              ),
              
              // 3. 内容层
              // 编辑模式下不使用 InkWell，避免拦截拖动事件
              widget.isEditMode
                  ? SizedBox.expand(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _buildCardContent(context, shadTheme, localizations),
                      ),
                    )
                  : InkWell(
                      onTap: _handleCardTap,
                      borderRadius: BorderRadius.circular(12),
                      hoverColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: SizedBox.expand(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _buildCardContent(context, shadTheme, localizations),
                        ),
                      ),
                    ),
                    
              // 4. 悬浮在右上角的校验通过标签和"当前"标签
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 校验通过标签（绿色呼吸圆点）- 移回右上角
                    // 仅在没有余额显示时展示，避免信息冗余
                    if (widget.aiKey.isValidated && !widget.isEditMode && _cachedBalance == null) ...[
                      _buildValidationSuccessLabel(context, shadTheme),
                      if (widget.isCurrent) const SizedBox(height: 6),
                    ],
                    // "当前"标签
                    if (widget.isCurrent) ...[
                      if ((_cachedBalance != null || widget.aiKey.isValidated) && !widget.isEditMode)
                        const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: shadTheme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          localizations?.current ?? '当前',
                          style: shadTheme.textTheme.small.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max, // 允许 Column 填充可用空间
      children: [
        // 顶部：Logo + 标题区域 + 拖动手柄
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: shadTheme.colorScheme.muted,
              ),
              child: Center(
                child: PlatformIconHelper.buildIcon(
                  platform: widget.aiKey.platformType,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // 标题和副标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.aiKey.name,
                    style: shadTheme.textTheme.p.copyWith(
                      fontWeight: FontWeight.bold,
                      color: shadTheme.colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${widget.aiKey.platform}',
                    style: shadTheme.textTheme.small.copyWith(
                      fontSize: 11,
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            
              // 余额显示（非编辑模式，靠右对齐，底部对齐）
              if (!widget.isEditMode && _cachedBalance != null) ...[
                const SizedBox(width: 8),
                Container(
                  height: 44, // 与 Logo 高度一致
                  alignment: Alignment.bottomRight, // 底部对齐
                  child: _buildBalanceDisplay(context, shadTheme, localizations),
                ),
              ],

            // 拖动手柄（仅在编辑模式显示，作为视觉提示）
            if (widget.isEditMode)
              Container(
                margin: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.drag_handle,
                  size: 20,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // 中间：标签区域（单行显示，超出部分隐藏）
        SizedBox(
          height: 24, // 固定高度，避免换行
          width: double.infinity, // 确保使用全部可用宽度
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: Row(
              children: [
                // 平台分类标签
                ...PlatformCategoryManager.getCategoriesForPlatform(widget.aiKey.platformType)
                    .take(2)
                    .map((category) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildTag(
                        context,
                        category.getValue(context),
                        isCategory: true,
                      ),
                    )),
                // 模型数量标签（如果支持模型列表且有缓存）
                if (_supportsModelList == true && _cachedModels != null && _cachedModels!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: _handleViewModels,
                      child: _buildTag(
                        context,
                        localizations?.modelsLabel(_cachedModels!.length) ?? '${_cachedModels!.length} 个模型',
                        isCategory: false,
                        isUserTag: false,
                        isClickable: true,
                        isModelTag: true,
                      ),
                    ),
                  ),
                // 用户自定义标签（显示为紫色）
                ...widget.aiKey.tags.map((tag) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildTag(context, tag, isCategory: false, isUserTag: true),
                )),
              ],
            ),
          ),
        ),
        // 底部：操作按钮组（带滑动动画）- 使用 Spacer 推到底部
        const Spacer(),
        AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (Widget child, Animation<double> animation) {
              // 获取子组件的 key，判断是编辑模式还是普通模式
              final isEditMode = (child.key as ValueKey<String>).value == 'edit';
              
              // 根据模式设置不同的滑动方向
              final offsetAnimation = Tween<Offset>(
                begin: isEditMode 
                    ? const Offset(1.0, 0.0)  // 编辑按钮从右侧滑入
                    : const Offset(-1.0, 0.0), // 普通按钮从左侧滑入
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));

              return ClipRect(
                child: SlideTransition(
                  position: offsetAnimation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                ),
              );
            },
            child: widget.isEditMode
                ? SizedBox(
                    key: const ValueKey<String>('edit'),
                    width: double.infinity,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildActionButton(
                          context,
                          icon: Icons.edit_outlined,
                          tooltip: localizations?.edit ?? '编辑',
                          onPressed: widget.onEdit,
                        ),
                        const SizedBox(width: 8),
                        _buildActionButton(
                          context,
                          icon: Icons.delete_outline,
                          tooltip: localizations?.deleteTooltip ?? '删除',
                          onPressed: widget.onDelete,
                          color: Colors.red,
                        ),
                      ],
                    ),
                  )
                : SizedBox(
                    key: const ValueKey<String>('normal'),
                    width: double.infinity,
                    child: Row(
                      children: [
                        _buildActionButton(
                          context,
                          icon: Icons.visibility_outlined,
                          tooltip: localizations?.details ?? '查看',
                          onPressed: widget.onView ?? widget.onTap,
                        ),
                        const SizedBox(width: 8),
                        if (widget.aiKey.managementUrl != null) ...[
                          _buildActionButton(
                            context,
                            icon: Icons.language,
                            tooltip: localizations?.openManagementUrl ?? '管理地址',
                            onPressed: widget.onOpenManagementUrl,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (widget.aiKey.apiEndpoint != null) ...[
                          _buildActionButton(
                            context,
                            icon: Icons.code,
                            tooltip: localizations?.copyApiEndpoint ?? 'API地址',
                            onPressed: widget.onCopyApiEndpoint,
                          ),
                          const SizedBox(width: 8),
                        ],
                        _buildActionButton(
                          context,
                          icon: Icons.copy_outlined,
                          tooltip: localizations?.copyKey ?? '复制',
                          onPressed: widget.onCopyApiKey,
                        ),
                        // 如果启用 Codex 且提供了复制环境变量命令回调，显示按钮
                        if (widget.aiKey.enableCodex && widget.onCopyEnvVarCommand != null) ...[
                          const SizedBox(width: 8),
                          _buildActionButton(
                            context,
                            icon: Icons.terminal_outlined,
                            tooltip: localizations?.copyEnvVarCommand ?? '复制环境变量命令',
                            onPressed: widget.onCopyEnvVarCommand,
                          ),
                        ],
                        // 同步按钮和编辑按钮居右
                        const Spacer(),
                        if (_supportsSync == true) ...[
                          _buildActionButton(
                            context,
                            icon: _isSyncing ? Icons.sync : Icons.sync_outlined,
                            tooltip: localizations?.sync ?? '同步',
                            onPressed: _isSyncing ? null : _handleSync,
                          ),
                          const SizedBox(width: 8),
                        ],
                        _buildActionButton(
                          context,
                          icon: Icons.edit_outlined,
                          tooltip: localizations?.edit ?? '编辑',
                          onPressed: widget.onEdit,
                        ),
                      ],
                    ),
                  ),
        ),
      ],
    );
  }

  Widget _buildTag(BuildContext context, String text, {required bool isCategory, bool isUserTag = false, bool isClickable = false, bool isModelTag = false}) {
    final shadTheme = ShadTheme.of(context);
    // 用户标签使用紫色，模型标签使用橙色
    final isPurple = isUserTag && !isCategory;
    final isOrange = isModelTag && !isCategory;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCategory
            ? shadTheme.colorScheme.primary.withOpacity(0.1)
            : isPurple
                ? Colors.purple.withOpacity(0.1)
                : isOrange
                    ? Colors.orange.withOpacity(0.1)
                    : isClickable
                        ? Colors.blue.withOpacity(0.1)
                : shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: shadTheme.textTheme.small.copyWith(
          fontSize: 11,
          color: isCategory
              ? shadTheme.colorScheme.primary
              : isPurple
                  ? Colors.purple
                  : isOrange
                      ? Colors.orange
                  : shadTheme.colorScheme.mutedForeground,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.muted,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: 15,
              color: color ?? shadTheme.colorScheme.mutedForeground,
            ),
          ),
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

/// 校验状态指示器（绿色呼吸小圆点）
class _ValidationIndicator extends StatefulWidget {
  @override
  State<_ValidationIndicator> createState() => _ValidationIndicatorState();
}

class _ValidationIndicatorState extends State<_ValidationIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
          width: 12, // 放大尺寸
          height: 12, // 放大尺寸
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withOpacity(_animation.value),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          );
        },
    );
  }
}

/// 噪点纹理绘制器
class _NoisePainter extends CustomPainter {
  final Color color;
  final double density; // 密度 0.0 - 1.0

  _NoisePainter({
    required this.color,
    this.density = 0.8, // 较高的密度
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    final random = math.Random(42); // 固定种子，保持纹理一致

    // 绘制随机点
    for (int i = 0; i < size.width * size.height * 0.05 * density; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      
      // 随机透明度，增加层次感
      paint.color = color.withOpacity(random.nextDouble() * 0.5);
      canvas.drawPoints(ui.PointMode.points, [Offset(x, y)], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) {
    return false; // 静态纹理不需要重绘
  }
}
