import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/model_info.dart';
import '../../services/clipboard_service.dart';
import '../../utils/app_localizations.dart';

/// 模型卡片组件
/// 支持灵活的标签展示，采用 key-value 格式，可以根据不同供应商的形式兼容适配
class ModelCard extends StatelessWidget {
  final ModelInfo model;
  final VoidCallback? onCopy; // 点击回调（用于选择模式或复制模式）

  const ModelCard({
    super.key,
    required this.model,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final clipboardService = ClipboardService();
    final localizations = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: shadTheme.colorScheme.border,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () async {
          // 如果提供了 onCopy 回调，使用回调（选择模式）
          if (onCopy != null) {
            onCopy!();
            return;
          }
          // 否则使用默认的复制行为（查看模式）
          await clipboardService.copyToClipboard(model.id);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations?.modelIdCopiedWithId(model.id) ?? '模型 ID 已复制：${model.id}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 标题和描述区域（顶部）
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题行
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.name,
                          style: shadTheme.textTheme.p.copyWith(
                            fontWeight: FontWeight.w600,
                            color: shadTheme.colorScheme.foreground,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        onCopy != null ? Icons.check_circle_outline : Icons.copy_outlined,
                        size: 14,
                        color: onCopy != null 
                            ? shadTheme.colorScheme.primary 
                            : shadTheme.colorScheme.mutedForeground,
                      ),
                    ],
                  ),
                  // 描述（小字，固定两行，鼠标悬浮显示完整）- 只在有描述时显示
                  if (model.description != null && model.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    TooltipTheme(
                      data: TooltipThemeData(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[900],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        textStyle: const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      child: Tooltip(
                        message: _formatDescriptionForTooltip(model.description!),
                        waitDuration: const Duration(milliseconds: 500),
                        preferBelow: false,
                        child: Text(
                          model.description!,
                          style: shadTheme.textTheme.small.copyWith(
                            color: shadTheme.colorScheme.mutedForeground,
                            fontSize: 11,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // 标签区域（底部对齐）
              const SizedBox(height: 4),
              _buildTagsRow(shadTheme, localizations),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建标签行（单行显示，不换行）
  Widget _buildTagsRow(ShadThemeData shadTheme, AppLocalizations? localizations) {
    final allTags = _buildAllTags(shadTheme, localizations);
    
    // 如果标签为空，返回空容器
    if (allTags.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 构建所有标签的文本内容（用于 Tooltip）
    final allTagsText = allTags.map((tag) {
      final key = tag['key'] as String;
      final value = tag['value'] as String;
      return '$key: $value';
    }).join('\n');
    
    return Tooltip(
      message: allTagsText,
      waitDuration: const Duration(milliseconds: 500),
      preferBelow: false,
      textStyle: TextStyle(fontSize: 11),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRect(
        child: SizedBox(
          height: 20, // 固定高度，确保单行
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: allTags.asMap().entries.map((entry) {
              final index = entry.key;
              final tag = entry.value;
              return Padding(
                padding: EdgeInsets.only(right: index < allTags.length - 1 ? 3 : 0),
                child: _buildTag(
                  shadTheme,
                  tag['key'] as String,
                  tag['value'] as String,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// 构建所有标签数据（返回 Map 列表，包含 key 和 value）
  /// 采用 key-value 格式，根据不同供应商的字段灵活适配
  /// 优先显示最重要的信息，限制标签数量以保持紧凑
  List<Map<String, String>> _buildAllTags(ShadThemeData shadTheme, AppLocalizations? localizations) {
    final tags = <Map<String, String>>[];
    final maxTags = 6; // 最多显示6个标签，保持紧凑

    // 1. 上下文长度（最重要）
    if (model.contextLength != null && tags.length < maxTags) {
      tags.add({
        'key': localizations?.contextLength ?? '上下文',
        'value': _formatNumber(model.contextLength!),
      });
    }

    // 2. 定价信息（优先显示输入和输出，格式化为 /m 单位）
    if (model.pricing != null && tags.length < maxTags) {
      if (model.pricing!.prompt != null && model.pricing!.prompt != '0' && tags.length < maxTags) {
        final formattedPrice = _formatPricePerMillion(model.pricing!.prompt!);
        if (formattedPrice != null) {
          tags.add({
            'key': localizations?.inputModalities ?? '输入',
            'value': formattedPrice,
          });
        }
      }
      if (model.pricing!.completion != null && model.pricing!.completion != '0' && tags.length < maxTags) {
        final formattedPrice = _formatPricePerMillion(model.pricing!.completion!);
        if (formattedPrice != null) {
          tags.add({
            'key': localizations?.outputModalities ?? '输出',
            'value': formattedPrice,
          });
        }
      }
    }

    // 3. 架构信息（简化显示，只显示输入类型）
    if (model.architecture != null && tags.length < maxTags) {
      if (model.architecture!.inputModalities != null &&
          model.architecture!.inputModalities!.isNotEmpty) {
        final modalities = model.architecture!.inputModalities!;
        if (modalities.length == 1 && tags.length < maxTags) {
          tags.add({
            'key': localizations?.inputModalities ?? '输入',
            'value': modalities.first,
          });
        } else if (modalities.length > 1 && modalities.length <= 3 && tags.length < maxTags) {
          tags.add({
            'key': localizations?.inputModalities ?? '输入',
            'value': '${modalities.length}种',
          });
        }
      }
    }

    // 4. 提供商信息（最大输出）
    if (model.topProvider != null && tags.length < maxTags) {
      if (model.topProvider!.maxCompletionTokens != null) {
        tags.add({
          'key': localizations?.maxOutputTokens ?? '最大输出',
          'value': _formatNumber(model.topProvider!.maxCompletionTokens!),
        });
      }
    }

    // 5. 支持的参数数量（如果还有空间）
    if (model.supportedParameters != null && 
        model.supportedParameters!.isNotEmpty && 
        tags.length < maxTags) {
      tags.add({
        'key': localizations?.parameters ?? '参数',
        'value': '${model.supportedParameters!.length}个',
      });
    }

    // 6. 从原始数据中提取其他重要字段（如果还有空间）
    if (model.rawData != null && tags.length < maxTags) {
      final raw = model.rawData!;
      final processedKeys = {
        'id', 'name', 'description', 'canonical_slug', 'created', 'context_length',
        'architecture', 'pricing', 'top_provider', 'supported_parameters', 'per_request_limits'
      };
      
      // 优先提取常见的重要字段
      final priorityFields = ['max_tokens', 'temperature', 'top_p', 'stream'];
      for (final key in priorityFields) {
        if (tags.length >= maxTags) break;
        if (processedKeys.contains(key)) continue;
        if (!raw.containsKey(key)) continue;
        
        final value = raw[key];
        if (value is String && value.isNotEmpty && value.length <= 12) {
          tags.add({
            'key': _formatKeyName(key, localizations),
            'value': value,
          });
        } else if (value is num && value is int && value >= 0 && value < 1000000) {
          tags.add({
            'key': _formatKeyName(key, localizations),
            'value': _formatNumber(value),
          });
        } else if (value is bool) {
          tags.add({
            'key': _formatKeyName(key, localizations),
            'value': value ? (localizations?.yes ?? '是') : (localizations?.no ?? '否'),
          });
        }
      }
    }

    return tags;
  }

  /// 构建标签列表（已废弃，改用 _buildAllTags）
  /// 采用 key-value 格式，根据不同供应商的字段灵活适配
  /// 优先显示最重要的信息，限制标签数量以保持紧凑
  List<Widget> _buildTags(ShadThemeData shadTheme, AppLocalizations? localizations) {
    final tags = <Widget>[];
    final maxTags = 6; // 最多显示6个标签，保持紧凑

    // 1. 上下文长度（最重要）
    if (model.contextLength != null && tags.length < maxTags) {
      tags.add(_buildTag(
        shadTheme,
        localizations?.contextLength ?? '上下文',
        _formatNumber(model.contextLength!),
      ));
    }

    // 2. 定价信息（优先显示输入和输出，格式化为 /m 单位）
    if (model.pricing != null && tags.length < maxTags) {
      if (model.pricing!.prompt != null && model.pricing!.prompt != '0' && tags.length < maxTags) {
        final formattedPrice = _formatPricePerMillion(model.pricing!.prompt!);
        if (formattedPrice != null) {
          tags.add(_buildTag(
            shadTheme,
            localizations?.inputModalities ?? '输入',
            formattedPrice,
          ));
        }
      }
      if (model.pricing!.completion != null && model.pricing!.completion != '0' && tags.length < maxTags) {
        final formattedPrice = _formatPricePerMillion(model.pricing!.completion!);
        if (formattedPrice != null) {
          tags.add(_buildTag(
            shadTheme,
            localizations?.outputModalities ?? '输出',
            formattedPrice,
          ));
        }
      }
    }

    // 3. 架构信息（简化显示，只显示输入类型）
    if (model.architecture != null && tags.length < maxTags) {
      if (model.architecture!.inputModalities != null &&
          model.architecture!.inputModalities!.isNotEmpty) {
        final modalities = model.architecture!.inputModalities!;
        if (modalities.length == 1 && tags.length < maxTags) {
          tags.add(_buildTag(
            shadTheme,
            localizations?.inputModalities ?? '输入',
            modalities.first,
          ));
        } else if (modalities.length > 1 && modalities.length <= 3 && tags.length < maxTags) {
          tags.add(_buildTag(
            shadTheme,
            localizations?.inputModalities ?? '输入',
            '${modalities.length}种',
          ));
        }
      }
    }

    // 4. 提供商信息（最大输出）
    if (model.topProvider != null && tags.length < maxTags) {
      if (model.topProvider!.maxCompletionTokens != null) {
        tags.add(_buildTag(
          shadTheme,
          localizations?.maxOutputTokens ?? '最大输出',
          _formatNumber(model.topProvider!.maxCompletionTokens!),
        ));
      }
    }

    // 5. 支持的参数数量（如果还有空间）
    if (model.supportedParameters != null && 
        model.supportedParameters!.isNotEmpty && 
        tags.length < maxTags) {
      tags.add(_buildTag(
        shadTheme,
        localizations?.parameters ?? '参数',
        '${model.supportedParameters!.length}个',
      ));
    }

    // 6. 从原始数据中提取其他重要字段（如果还有空间）
    if (model.rawData != null && tags.length < maxTags) {
      final raw = model.rawData!;
      final processedKeys = {
        'id', 'name', 'description', 'canonical_slug', 'created', 'context_length',
        'architecture', 'pricing', 'top_provider', 'supported_parameters', 'per_request_limits'
      };
      
      // 优先提取常见的重要字段
      final priorityFields = ['max_tokens', 'temperature', 'top_p', 'stream'];
      for (final key in priorityFields) {
        if (tags.length >= maxTags) break;
        if (processedKeys.contains(key)) continue;
        if (!raw.containsKey(key)) continue;
        
        final value = raw[key];
        if (value is String && value.isNotEmpty && value.length <= 12) {
          tags.add(_buildTag(
            shadTheme,
            _formatKeyName(key, localizations),
            value,
          ));
        } else if (value is num && value is int && value >= 0 && value < 1000000) {
          tags.add(_buildTag(
            shadTheme,
            _formatKeyName(key, localizations),
            _formatNumber(value),
          ));
        } else if (value is bool) {
          tags.add(_buildTag(
            shadTheme,
            _formatKeyName(key, localizations),
            value ? (localizations?.yes ?? '是') : (localizations?.no ?? '否'),
          ));
        }
      }
    }

    return tags;
  }

  /// 构建单个标签
  Widget _buildTag(ShadThemeData shadTheme, String key, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: shadTheme.colorScheme.muted,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$key: ',
            style: shadTheme.textTheme.small.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: shadTheme.textTheme.small.copyWith(
                color: shadTheme.colorScheme.foreground,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化价格：从 /1K 转换为 /m（每百万 tokens）
  /// OpenRouter API 返回的价格是每1K tokens的价格，需要乘以1000转换为每M tokens的价格
  /// 例如：0.001/1K -> $1.0/m, 0.0001/1K -> $0.1/m
  String? _formatPricePerMillion(String priceStr) {
    try {
      // 移除可能的 $ 符号、空格、逗号，以及可能的单位标识（/1K, /K等）
      String cleanPrice = priceStr.replaceAll(RegExp(r'[\$,\s]'), '');
      // 移除可能的单位后缀（如 /1K, /K, /1k等）
      cleanPrice = cleanPrice.replaceAll(RegExp(r'/[0-9]*[KkMm]', caseSensitive: false), '');
      cleanPrice = cleanPrice.replaceAll(RegExp(r'[KkMm]$', caseSensitive: false), '');
      
      // 解析为数字（这是每1K tokens的价格）
      final pricePer1K = double.tryParse(cleanPrice);
      if (pricePer1K == null || pricePer1K <= 0) {
        return null;
      }
      
      // 转换为每百万 tokens 的价格（1M = 1000K，所以需要乘以1000）
      final pricePerMillion = pricePer1K * 1000;
      
      // 格式化显示
      if (pricePerMillion >= 1000) {
        // 大于等于1000，显示为整数或一位小数
        return '\$${pricePerMillion.toStringAsFixed(pricePerMillion % 1 == 0 ? 0 : 1)}/m';
      } else if (pricePerMillion >= 1) {
        // 1-1000之间，显示一位小数
        return '\$${pricePerMillion.toStringAsFixed(1)}/m';
      } else if (pricePerMillion >= 0.1) {
        // 0.1-1之间，显示一位小数
        return '\$${pricePerMillion.toStringAsFixed(1)}/m';
      } else {
        // 小于0.1，显示两位小数
        return '\$${pricePerMillion.toStringAsFixed(2)}/m';
      }
    } catch (e) {
      // 解析失败，返回 null
      return null;
    }
  }

  /// 格式化数字
  String _formatNumber(int number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return number.toString();
  }

  /// 格式化描述文本用于 Tooltip（限制宽度，添加换行）
  String _formatDescriptionForTooltip(String description) {
    // 限制每行大约 40 个字符，添加换行符来限制宽度
    const maxCharsPerLine = 40;
    if (description.length <= maxCharsPerLine) {
      return description;
    }
    
    final buffer = StringBuffer();
    for (int i = 0; i < description.length; i += maxCharsPerLine) {
      if (i > 0) buffer.write('\n');
      final end = (i + maxCharsPerLine < description.length) 
          ? i + maxCharsPerLine 
          : description.length;
      buffer.write(description.substring(i, end));
    }
    return buffer.toString();
  }

  /// 格式化字段名（将 snake_case 转换为中文）
  String _formatKeyName(String key, AppLocalizations? localizations) {
    // 常见字段的中文映射
    final keyMap = {
      'canonical_slug': localizations?.identifier ?? '标识',
      'created': localizations?.createdTime ?? '创建',
      'context_length': localizations?.contextLength ?? '上下文',
      'max_tokens': localizations?.maxTokens ?? '最大Token',
      'temperature': localizations?.temperature ?? '温度',
      'top_p': localizations?.topP ?? 'Top P',
      'frequency_penalty': localizations?.frequencyPenalty ?? '频率惩罚',
      'presence_penalty': localizations?.presencePenalty ?? '存在惩罚',
      'stop': localizations?.stop ?? '停止',
      'stream': localizations?.stream ?? '流式',
      'n': localizations?.n ?? '数量',
      'logprobs': localizations?.logprobs ?? '对数概率',
      'echo': localizations?.echo ?? '回显',
      'best_of': localizations?.bestOf ?? '最佳',
    };
    
    if (keyMap.containsKey(key)) {
      return keyMap[key]!;
    }
    
    // 如果没有映射，尝试将 snake_case 转换为可读格式
    return key.replaceAll('_', ' ').split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }
}
