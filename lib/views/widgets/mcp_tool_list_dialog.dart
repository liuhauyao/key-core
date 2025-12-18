import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../models/mcp_tool.dart';
import '../../utils/app_localizations.dart';

class McpToolListDialog extends StatefulWidget {
  final List<McpTool> tools;
  final String serverName;

  const McpToolListDialog({
    super.key,
    required this.tools,
    required this.serverName,
  });

  @override
  State<McpToolListDialog> createState() => _McpToolListDialogState();
}

class _McpToolListDialogState extends State<McpToolListDialog> {
  List<McpTool> _filteredTools = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredTools = widget.tools;
  }

  void _filterTools(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredTools = widget.tools;
      } else {
        final queryLower = query.toLowerCase();
        _filteredTools = widget.tools.where((tool) {
          return tool.name.toLowerCase().contains(queryLower) ||
              (tool.description?.toLowerCase().contains(queryLower) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 900,
        height: 700,
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.border,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localizations?.mcpToolsListTitle(widget.serverName, widget.tools.length) ?? '${widget.serverName} 工具列表 (${widget.tools.length})',
                    style: theme.textTheme.h4,
                  ),
                  ShadButton.ghost(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // 搜索框（次行）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ShadInputFormField(
                id: 'tool_search',
                onChanged: (value) {
                  _filterTools(value);
                },
                placeholder: Text(localizations?.mcpSearchTools ?? '搜索工具...'),
                leading: Icon(
                  Icons.search,
                  size: 18,
                  color: theme.colorScheme.mutedForeground,
                ),
                trailing: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _filterTools('');
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.clear,
                            size: 14,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
            // 工具列表
            Expanded(
              child: _filteredTools.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? localizations?.mcpNoTools ?? '暂无工具'
                            : localizations?.mcpNoToolsFound ?? '未找到匹配的工具',
                        style: theme.textTheme.p.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filteredTools.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tool = _filteredTools[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.muted.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: theme.colorScheme.border.withOpacity(0.5),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tool.name,
                                  style: theme.textTheme.large.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (tool.description != null && tool.description!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    tool.description!,
                                    style: theme.textTheme.small.copyWith(
                                      color: theme.colorScheme.mutedForeground,
                                    ),
                                  ),
                                ],
                                if (tool.inputSchema != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    localizations?.mcpToolInputSchema ?? '参数结构:',
                                    style: theme.textTheme.muted.copyWith(fontSize: 10),
                                  ),
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      // 简单的 JSON 格式化
                                      tool.inputSchema.toString(),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        color: theme.colorScheme.foreground.withOpacity(0.7),
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            // 底部信息栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localizations?.mcpTotalTools(_filteredTools.length, localizations?.mcpTools ?? '个工具') ?? '共 ${_filteredTools.length} ${localizations?.mcpTools ?? '个工具'}',
                    style: theme.textTheme.small.copyWith(
                      color: theme.colorScheme.mutedForeground,
                    ),
                  ),
                  ShadButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(localizations?.close ?? '关闭'),
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

