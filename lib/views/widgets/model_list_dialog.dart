import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/model_info.dart';
import '../../services/clipboard_service.dart';
import '../../utils/app_localizations.dart';
import 'model_card.dart';

/// 模型列表对话框
class ModelListDialog extends StatefulWidget {
  final List<ModelInfo> models;
  final String platformName;
  final int? keyId;
  final VoidCallback? onUpdateModels;
  final Function(ModelInfo)? onSelectModel; // 选择模型回调（用于选择模式）

  const ModelListDialog({
    super.key,
    required this.models,
    required this.platformName,
    this.keyId,
    this.onUpdateModels,
    this.onSelectModel, // 如果提供了此回调，则进入选择模式
  });

  @override
  State<ModelListDialog> createState() => _ModelListDialogState();
}

class _ModelListDialogState extends State<ModelListDialog> {
  final ClipboardService _clipboardService = ClipboardService();
  List<ModelInfo> _filteredModels = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredModels = widget.models;
  }

  void _filterModels(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredModels = widget.models;
      } else {
        final queryLower = query.toLowerCase();
        _filteredModels = widget.models.where((model) {
          return model.id.toLowerCase().contains(queryLower) ||
              model.name.toLowerCase().contains(queryLower) ||
              (model.description?.toLowerCase().contains(queryLower) ?? false) ||
              (model.canonicalSlug?.toLowerCase().contains(queryLower) ?? false) ||
              (model.architecture?.inputModalities?.any((m) => m.toLowerCase().contains(queryLower)) ?? false) ||
              (model.architecture?.outputModalities?.any((m) => m.toLowerCase().contains(queryLower)) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _copyModelId(String modelId) async {
    final localizations = AppLocalizations.of(context);
    await _clipboardService.copyToClipboard(modelId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations?.modelIdCopied ?? '模型 ID 已复制：$modelId')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 700,
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // 搜索框（首行）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: ShadInputFormField(
                id: 'model_search',
                onChanged: (value) {
                  _filterModels(value);
                },
                placeholder: Text(localizations?.searchModels ?? '搜索模型...'),
                leading: Icon(
                  Icons.search,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
                trailing: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _filterModels('');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.clear,
                            size: 14,
                            color: shadTheme.colorScheme.mutedForeground,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            // 模型列表（两列Grid布局）
            Expanded(
              child: _filteredModels.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? (localizations?.noModels ?? '暂无模型')
                            : (localizations?.noMatchingModels ?? '未找到匹配的模型'),
                        style: shadTheme.textTheme.p.copyWith(
                          color: shadTheme.colorScheme.mutedForeground,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // 计算每列的宽度：可用宽度 - padding - 间距，除以2
                        final availableWidth = constraints.maxWidth - 32; // 减去左右 padding
                        final columnWidth = (availableWidth - 12) / 2; // 减去间距，除以2
                        
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: _filteredModels.map((model) {
                              return SizedBox(
                                width: columnWidth,
                                child: ModelCard(
                                  model: model,
                                  onCopy: widget.onSelectModel != null
                                      ? () {
                                          // 选择模式下，点击卡片选择模型
                                          // 调用回调，让调用者处理关闭对话框的逻辑
                                          widget.onSelectModel!(model);
                                        }
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
            ),
            // 底部信息栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localizations?.modelsCount(_filteredModels.length) ?? '共 ${_filteredModels.length} 个模型',
                    style: shadTheme.textTheme.small.copyWith(
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 更新模型列表按钮（如果提供了回调）
                      if (widget.onUpdateModels != null) ...[
                        ShadButton.outline(
                          onPressed: widget.onUpdateModels,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh,
                                size: 16,
                                color: shadTheme.colorScheme.foreground,
                              ),
                              const SizedBox(width: 6),
                              Text(localizations?.updateModelList ?? '更新模型列表'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      ShadButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(localizations?.close ?? '关闭'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}


