import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:reorderables/reorderables.dart';
import '../../viewmodels/mcp_viewmodel.dart';
import '../../models/mcp_server.dart';
import '../widgets/mcp_card.dart';
import '../widgets/confirm_dialog.dart';
import 'mcp_sync_page.dart';
import 'mcp_form_page.dart';
import '../../utils/app_localizations.dart';
import '../../services/url_launcher_service.dart';
import '../../services/clipboard_service.dart';
import 'dart:convert';

/// MCP 配置管理页面
class McpConfigScreen extends StatefulWidget {
  const McpConfigScreen({super.key});

  @override
  State<McpConfigScreen> createState() => _McpConfigScreenState();
}

class _McpConfigScreenState extends State<McpConfigScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<McpViewModel>().init();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: shadTheme.colorScheme.background,
      body: Consumer<McpViewModel>(
        builder: (context, viewModel, child) {
          return Column(
            children: [
              // 工具栏：搜索、编辑、添加按钮
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.background,
                  border: Border(
                    bottom: BorderSide(
                      color: shadTheme.colorScheme.border,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // 搜索栏
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.only(right: 12),
                        height: 38, // 固定高度，避免输入时高度变化
                        child: ClipRect(
                          clipBehavior: Clip.hardEdge,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: ShadInput(
                              controller: _searchController,
                              onChanged: (query) => viewModel.setSearchQuery(query),
                              placeholder: Text(localizations?.mcpSearchPlaceholder ?? '搜索 MCP 服务器...'),
                              leading: Icon(
                                Icons.search,
                                size: 18,
                                color: shadTheme.colorScheme.mutedForeground,
                              ),
                              trailing: _searchController.text.isNotEmpty
                                  ? ShadButton(
                                      width: 20,
                                      height: 20,
                                      padding: EdgeInsets.zero,
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: shadTheme.colorScheme.mutedForeground,
                                      hoverBackgroundColor: Colors.transparent,
                                      onPressed: () {
                                        _searchController.clear();
                                        viewModel.setSearchQuery('');
                                      },
                                      child: const Icon(Icons.clear, size: 14),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 按钮组：同步、编辑、添加
                    Container(
                      height: 38, // 与输入框高度一致
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: shadTheme.colorScheme.border,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 同步按钮
                          Tooltip(
                            message: localizations?.mcpSync ?? '同步',
                            child: ShadButton.ghost(
                              width: 38,
                              height: 38,
                              padding: EdgeInsets.zero,
                              onPressed: () => _showSyncDialog(context),
                              child: Icon(
                                Icons.swap_horiz,
                                size: 18,
                                color: shadTheme.colorScheme.primary,
                              ),
                            ),
                          ),
                          // 分隔线
                          Container(
                            width: 1,
                            height: 20,
                            color: shadTheme.colorScheme.border,
                          ),
                          // 拖动模式按钮
                          Tooltip(
                            message: _isEditMode 
                                ? (localizations?.mcpFinishEdit ?? '完成编辑')
                                : (localizations?.edit ?? '编辑'),
                            child: _isEditMode
                                ? ShadButton.ghost(
                                    width: 38,
                                    height: 38,
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      setState(() {
                                        _isEditMode = !_isEditMode;
                                      });
                                    },
                                    child: Icon(
                                      Icons.check,
                                      size: 18,
                                      color: shadTheme.colorScheme.primary,
                                    ),
                                  )
                                : ShadButton.ghost(
                                    width: 38,
                                    height: 38,
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      setState(() {
                                        _isEditMode = !_isEditMode;
                                      });
                                    },
                                    child: Icon(
                                      Icons.drag_handle,
                                      size: 18,
                                      color: shadTheme.colorScheme.primary,
                                    ),
                                  ),
                          ),
                          // 分隔线
                          Container(
                            width: 1,
                            height: 20,
                            color: shadTheme.colorScheme.border,
                          ),
                          // 刷新按钮
                          Tooltip(
                            message: localizations?.refreshKeyList ?? '刷新列表',
                            child: ShadButton.ghost(
                              width: 38,
                              height: 38,
                              padding: EdgeInsets.zero,
                              onPressed: () => viewModel.refresh(),
                              child: Icon(
                                Icons.refresh,
                                size: 18,
                                color: shadTheme.colorScheme.primary,
                              ),
                            ),
                          ),
                          // 分隔线
                          Container(
                            width: 1,
                            height: 20,
                            color: shadTheme.colorScheme.border,
                          ),
                          // 添加按钮
                          Tooltip(
                            message: localizations?.mcpAddServer ?? '添加 MCP 服务器',
                            child: ShadButton.ghost(
                              width: 38,
                              height: 38,
                              padding: EdgeInsets.zero,
                              onPressed: () => _showAddMcpPage(context),
                              child: Icon(
                                Icons.add,
                                size: 18,
                                color: shadTheme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // MCP 服务器列表
              Expanded(
                child: viewModel.isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: shadTheme.colorScheme.primary,
                        ),
                      )
                    : viewModel.servers.isEmpty
                        ? _buildEmptyState(context, viewModel)
                        : _buildServerList(context, viewModel, _isEditMode),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, McpViewModel viewModel) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);

    if (viewModel.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
            const SizedBox(height: 16),
            Text(
              localizations?.mcpNoSearchResults ?? '未找到匹配的 MCP 服务器',
              style: shadTheme.textTheme.h4.copyWith(
                color: shadTheme.colorScheme.foreground,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: shadTheme.colorScheme.muted,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.dns_outlined,
              size: 64,
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations?.mcpNoServers ?? '暂无 MCP 服务器',
            style: shadTheme.textTheme.h4.copyWith(
              color: shadTheme.colorScheme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            localizations?.mcpAddFirstServer ?? '点击上方按钮添加您的第一个 MCP 服务器',
            style: shadTheme.textTheme.p.copyWith(
              color: shadTheme.colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerList(
    BuildContext context,
    McpViewModel viewModel,
    bool isEditMode,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double minCardWidth = 240; // 减小最小宽度，让一列显示更多卡片
        const double cardSpacing = 10;
        const double padding = 16;
        const double cardHeight = 140; // 固定卡片高度

        final availableWidth = constraints.maxWidth - padding * 2;
        int crossAxisCount = (availableWidth / (minCardWidth + cardSpacing)).floor();
        crossAxisCount = crossAxisCount.clamp(1, 5);

        final cardWidth = (availableWidth - (crossAxisCount - 1) * cardSpacing) / crossAxisCount;
        if (cardWidth < minCardWidth && crossAxisCount > 1) {
          crossAxisCount -= 1;
        }

        final servers = List<McpServer>.from(viewModel.servers);

        // 构建卡片列表
        final cardWidgets = servers.map((server) {
          return McpCard(
            key: ValueKey(server.id), // 使用稳定的key，不包含isActive状态
            server: server,
            isEditMode: isEditMode,
            onTap: () => _showMcpDetails(context, server),
            onEdit: () => _showEditMcpPage(context, server, viewModel),
            onDelete: () => _deleteServer(context, server, viewModel),
            onToggleActive: (isActive) => _toggleActive(context, server, isActive, viewModel),
            onViewDetails: () => _showMcpDetails(context, server),
            onOpenHomepage: server.homepage != null && server.homepage!.isNotEmpty
                ? () => UrlLauncherService().openUrl(server.homepage!)
                : null,
            onOpenDocs: server.docs != null && server.docs!.isNotEmpty
                ? () => UrlLauncherService().openUrl(server.docs!)
                : null,
          );
        }).toList();

        // 编辑模式下使用 ReorderableWrap
        if (isEditMode) {
          return Padding(
            padding: const EdgeInsets.all(padding),
            child: ReorderableWrap(
              spacing: cardSpacing,
              runSpacing: cardSpacing,
              needsLongPressDraggable: false, // 禁用长按拖动，允许直接拖动
              onReorder: (oldIndex, newIndex) {
                // ReorderableWrap 的索引计算
                // 根据官方示例，ReorderableWrap 的 newIndex 已经是正确的插入位置
                // 不需要再调整
                final reorderedServers = List<McpServer>.from(viewModel.servers);
                
                // 先移除拖动项
                final draggedServer = reorderedServers.removeAt(oldIndex);
                
                // 直接使用 newIndex 作为插入位置
                // ReorderableWrap 已经处理了索引调整
                final insertIndex = newIndex.clamp(0, reorderedServers.length);
                
                reorderedServers.insert(insertIndex, draggedServer);
                viewModel.reorderServers(reorderedServers);
              },
              onNoReorder: (index) {
                // 拖动取消时的回调
              },
              children: cardWidgets.asMap().entries.map((entry) {
                final index = entry.key;
                final card = entry.value;
                return SizedBox(
                  key: ValueKey(servers[index].id),
                  width: cardWidth,
                  height: cardHeight,
                  child: card,
                );
              }).toList(),
            ),
          );
        }

        // 非编辑模式使用普通 GridView
        return GridView.builder(
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: cardSpacing,
            mainAxisSpacing: cardSpacing,
            childAspectRatio: (cardWidth / cardHeight), // 固定高度，动态宽度
          ),
          itemCount: cardWidgets.length,
          itemBuilder: (context, index) => cardWidgets[index],
        );
      },
    );
  }

  Future<void> _showAddMcpPage(BuildContext context) async {
    final viewModel = context.read<McpViewModel>();
    final localizations = AppLocalizations.of(context);

    final result = await Navigator.of(context).push<McpServer>(
      MaterialPageRoute(
        builder: (context) => const McpFormPage(),
      ),
    );

    if (result != null) {
      final success = await viewModel.addServer(result);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      if (success) {
        _showSnackBar(context, localizations?.mcpServerAdded ?? 'MCP 服务器添加成功');
      } else {
        _showSnackBar(
          context,
          viewModel.errorMessage ?? (localizations?.mcpAddFailed ?? '添加失败'),
          isError: true,
        );
      }
    }
  }

  Future<void> _showEditMcpPage(
    BuildContext context,
    McpServer server,
    McpViewModel viewModel,
  ) async {
    final localizations = AppLocalizations.of(context);

    final result = await Navigator.of(context).push<McpServer>(
      MaterialPageRoute(
        builder: (context) => McpFormPage(editingServer: server),
      ),
    );

    if (result != null) {
      // 保存 ScaffoldMessenger 引用，避免异步操作后 context 失效
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final success = await viewModel.updateServer(result);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      if (success) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(localizations?.mcpServerUpdated ?? 'MCP 服务器更新成功'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(viewModel.errorMessage ?? (localizations?.mcpUpdateFailed ?? '更新失败')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _deleteServer(
    BuildContext context,
    McpServer server,
    McpViewModel viewModel,
  ) async {
    final localizations = AppLocalizations.of(context);
    final confirmed = await ConfirmDialog.show(
      context: context,
      title: localizations?.confirmDelete ?? '确认删除',
      message: localizations?.mcpDeleteConfirmMessage(server.name) ?? 
          '确定要删除 MCP 服务器"${server.name}"吗？此操作不可撤销。',
      confirmText: localizations?.delete ?? '删除',
    );

    if (confirmed == true) {
      final success = await viewModel.deleteServer(server.id!);
      if (!mounted) return; // 检查 widget 是否仍然挂载
      
      // 使用 WidgetsBinding.instance.addPostFrameCallback 确保在下一帧显示 SnackBar
      // 这样可以避免在 widget 重建过程中访问失效的 context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return; // 再次检查
        if (success) {
          _showSnackBarSafe(context, localizations?.mcpServerDeleted ?? 'MCP 服务器已删除');
        } else {
          _showSnackBarSafe(
            context,
            viewModel.errorMessage ?? (localizations?.mcpDeleteFailed ?? '删除失败'),
            isError: true,
          );
        }
      });
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    McpServer server,
    bool isActive,
    McpViewModel viewModel,
  ) async {
    final success = await viewModel.toggleActive(server.id!, isActive);
    if (!mounted) return; // 检查 widget 是否仍然挂载
    final localizations = AppLocalizations.of(context);
    if (success) {
      _showSnackBar(
        context,
        isActive 
            ? (localizations?.mcpServerActivated ?? 'MCP 服务器已激活')
            : (localizations?.mcpServerDeactivated ?? 'MCP 服务器已停用'),
      );
    } else {
      _showSnackBar(
        context,
        viewModel.errorMessage ?? (localizations?.mcpOperationFailed ?? '操作失败'),
        isError: true,
      );
    }
  }

  void _showSyncDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const McpSyncPage(),
      ),
    );
  }

  void _showMcpDetails(BuildContext context, McpServer server) {
    showDialog(
      context: context,
      builder: (context) => _McpDetailsDialog(
        server: server,
        onEdit: () {
          Navigator.pop(context);
          _showEditMcpPage(context, server, context.read<McpViewModel>());
        },
        onCopyJson: () {
          final jsonConfig = _generateJsonConfig(server);
          ClipboardService().copyToClipboard(jsonConfig);
          final loc = AppLocalizations.of(context);
          _showSnackBar(context, loc?.mcpJsonCopied ?? 'JSON配置已复制');
        },
        onOpenHomepage: server.homepage != null && server.homepage!.isNotEmpty
            ? () => UrlLauncherService().openUrl(server.homepage!)
            : null,
        onOpenDocs: server.docs != null && server.docs!.isNotEmpty
            ? () => UrlLauncherService().openUrl(server.docs!)
            : null,
      ),
    );
  }

  String _generateJsonConfig(McpServer server) {
    final config = <String, dynamic>{};
    
    if (server.serverType == McpServerType.stdio) {
      if (server.command != null && server.command!.isNotEmpty) {
        config['command'] = server.command;
      }
      if (server.args != null && server.args!.isNotEmpty) {
        config['args'] = server.args;
      }
      if (server.env != null && server.env!.isNotEmpty) {
        config['env'] = server.env;
      }
      if (server.cwd != null && server.cwd!.isNotEmpty) {
        config['cwd'] = server.cwd;
      }
    } else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) {
      if (server.url != null && server.url!.isNotEmpty) {
        config['url'] = server.url;
      }
      if (server.headers != null && server.headers!.isNotEmpty) {
        config['headers'] = server.headers;
      }
    }
    
    final jsonWithId = <String, dynamic>{
      server.serverId: config,
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    if (!mounted) return; // 检查 widget 是否仍然挂载
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 安全地显示 SnackBar，避免在 widget 销毁时访问失效的 context
  void _showSnackBarSafe(BuildContext context, String message, {bool isError = false}) {
    if (!mounted) return; // 检查 widget 是否仍然挂载
    
    try {
      // 尝试查找最近的 ScaffoldMessenger
      final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
      if (scaffoldMessenger != null) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red : null,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        // 如果找不到 ScaffoldMessenger，打印日志而不是崩溃
        print('无法显示 SnackBar: $message');
      }
    } catch (e) {
      // 捕获任何异常，避免崩溃
      print('显示 SnackBar 时出错: $e, 消息: $message');
    }
  }
}

/// MCP 服务器详情弹窗
class _McpDetailsDialog extends StatelessWidget {
  final McpServer server;
  final VoidCallback onEdit;
  final VoidCallback onCopyJson;
  final VoidCallback? onOpenHomepage;
  final VoidCallback? onOpenDocs;

  const _McpDetailsDialog({
    required this.server,
    required this.onEdit,
    required this.onCopyJson,
    this.onOpenHomepage,
    this.onOpenDocs,
  });

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: shadTheme.colorScheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: shadTheme.colorScheme.border,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: shadTheme.colorScheme.muted,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/icons/platforms/${server.icon ?? 'mcp.svg'}',
                        width: 20,
                        height: 20,
                        allowDrawingOutsideViewBox: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      server.name,
                      style: shadTheme.textTheme.h4.copyWith(
                        color: shadTheme.colorScheme.foreground,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: localizations?.edit ?? '编辑',
                    child: ShadButton.ghost(
                      width: 30,
                      height: 30,
                      padding: EdgeInsets.zero,
                      child: Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: shadTheme.colorScheme.mutedForeground,
                      ),
                      onPressed: onEdit,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.ghost(
                    width: 30,
                    height: 30,
                    padding: EdgeInsets.zero,
                    child: Icon(
                      Icons.close,
                      size: 20,
                      color: shadTheme.colorScheme.mutedForeground,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 内容区域
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDetailRow(
                      context,
                      localizations?.mcpServerIdLabel ?? '服务器ID',
                      server.serverId,
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      context,
                      localizations?.mcpServerType ?? '服务器类型',
                      server.serverType.value.toUpperCase(),
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      context,
                      localizations?.mcpStatus ?? '状态',
                      server.isActive
                          ? (localizations?.mcpActive ?? '已激活')
                          : (localizations?.mcpInactive ?? '未激活'),
                    ),
                    const SizedBox(height: 10),
                    // 根据服务器类型显示不同字段
                    if (server.serverType == McpServerType.stdio) ...[
                      if (server.command != null && server.command!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpCommandLabel ?? '命令',
                          server.command!,
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.args != null && server.args!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpArgsLabel ?? '参数',
                          server.args!.join(' '),
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.env != null && server.env!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpEnv ?? '环境变量',
                          server.env!.entries.map((e) => '${e.key}=${e.value}').join('\n'),
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.cwd != null && server.cwd!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpCwd ?? '工作目录',
                          server.cwd!,
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ] else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) ...[
                      if (server.url != null && server.url!.isNotEmpty) ...[
                        _buildActionRow(
                          context,
                          localizations?.mcpUrlLabel ?? 'URL',
                          server.url!,
                          Icons.language,
                          localizations?.open ?? '打开',
                          () {
                            if (server.url != null) {
                              UrlLauncherService().openUrl(server.url!);
                            }
                          },
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (server.headers != null && server.headers!.isNotEmpty) ...[
                        _buildDetailRow(
                          context,
                          localizations?.mcpHeaders ?? '请求头',
                          server.headers!.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                          isMonospace: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                    // 管理地址
                    if (onOpenHomepage != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.mcpHomepage ?? '管理地址',
                        server.homepage!,
                        Icons.language,
                        localizations?.open ?? '打开',
                        onOpenHomepage!,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 文档地址
                    if (onOpenDocs != null) ...[
                      _buildActionRow(
                        context,
                        localizations?.mcpDocs ?? '文档地址',
                        server.docs!,
                        Icons.description_outlined,
                        localizations?.open ?? '打开',
                        onOpenDocs!,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 描述
                    if (server.description != null && server.description!.isNotEmpty) ...[
                      _buildDetailRow(
                        context,
                        localizations?.mcpDescription ?? '描述',
                        server.description!,
                      ),
                      const SizedBox(height: 10),
                    ],
                    // 标签
                    if (server.tags != null && server.tags!.isNotEmpty) ...[
                      _buildDetailRow(
                        context,
                        localizations?.mcpTags ?? '标签',
                        server.tags!.join(', '),
                      ),
                      const SizedBox(height: 10),
                    ],
                    // JSON配置
                    _buildJsonConfigRow(context),
                    const SizedBox(height: 10),
                    // 创建时间和更新时间在同一行
                    _buildTimeRow(
                      context,
                      localizations?.createdTime ?? '创建时间',
                      _formatDateTime(server.createdAt),
                      localizations?.updatedTime ?? '更新时间',
                      _formatDateTime(server.updatedAt),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {bool isMonospace = false}) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
            fontFamily: isMonospace ? 'monospace' : null,
            fontSize: isMonospace ? 13 : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    bool isMonospace = false,
  }) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: shadTheme.textTheme.small.copyWith(
                  color: shadTheme.colorScheme.primary,
                  fontFamily: isMonospace ? 'monospace' : null,
                  fontSize: isMonospace ? 13 : null,
                ),
              ),
            ),
            Tooltip(
              message: tooltip,
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                onPressed: onPressed,
                child: Icon(icon, size: 18, color: shadTheme.colorScheme.mutedForeground),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJsonConfigRow(BuildContext context) {
    final shadTheme = ShadTheme.of(context);
    final localizations = AppLocalizations.of(context);
    
    final jsonConfig = _generateJsonConfig();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${localizations?.mcpJsonConfigLabel ?? 'JSON配置'}:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: shadTheme.colorScheme.muted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText(
                  jsonConfig,
                  style: shadTheme.textTheme.small.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: shadTheme.colorScheme.foreground,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: localizations?.mcpCopyJson ?? '复制JSON配置',
              child: ShadButton.ghost(
                width: 32,
                height: 32,
                padding: const EdgeInsets.all(6),
                onPressed: onCopyJson,
                child: Icon(
                  Icons.copy_outlined,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeRow(
    BuildContext context,
    String createdLabel,
    String createdValue,
    String updatedLabel,
    String updatedValue,
  ) {
    final shadTheme = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$createdLabel / $updatedLabel:',
          style: shadTheme.textTheme.small.copyWith(
            fontWeight: FontWeight.w500,
            color: shadTheme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$createdValue / $updatedValue',
          style: shadTheme.textTheme.small.copyWith(
            color: shadTheme.colorScheme.foreground,
          ),
        ),
      ],
    );
  }

  String _generateJsonConfig() {
    final config = <String, dynamic>{};
    
    if (server.serverType == McpServerType.stdio) {
      if (server.command != null && server.command!.isNotEmpty) {
        config['command'] = server.command;
      }
      if (server.args != null && server.args!.isNotEmpty) {
        config['args'] = server.args;
      }
      if (server.env != null && server.env!.isNotEmpty) {
        config['env'] = server.env;
      }
      if (server.cwd != null && server.cwd!.isNotEmpty) {
        config['cwd'] = server.cwd;
      }
    } else if (server.serverType == McpServerType.http || server.serverType == McpServerType.sse) {
      if (server.url != null && server.url!.isNotEmpty) {
        config['url'] = server.url;
      }
      if (server.headers != null && server.headers!.isNotEmpty) {
        config['headers'] = server.headers;
      }
    }
    
    final jsonWithId = <String, dynamic>{
      server.serverId: config,
    };
    
    return const JsonEncoder.withIndent('  ').convert(jsonWithId);
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

