import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:convert';

/// 图标选择器组件
/// 从 assets/icons/platforms/ 目录选择 SVG 图标
class IconPicker extends StatefulWidget {
  final String? selectedIcon;
  final ValueChanged<String?> onIconSelected;

  const IconPicker({
    super.key,
    this.selectedIcon,
    required this.onIconSelected,
  });

  @override
  State<IconPicker> createState() => _IconPickerState();
}

class _IconPickerState extends State<IconPicker> {
  String? _selectedIcon;
  List<String> _availableIcons = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.selectedIcon;
    _loadIcons();
  }

  Future<void> _loadIcons() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 从 AssetManifest 自动读取所有 assets/icons/platforms/ 目录下的 SVG 文件
      // 注意：AssetManifest.json 是在构建时生成的，路径可能需要调整
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      // 过滤出所有 platforms 目录下的 SVG 文件
      final platformIcons = manifestMap.keys
          .where((key) => 
              key.startsWith('assets/icons/platforms/') && 
              key.endsWith('.svg'))
          .map((key) => key.replaceFirst('assets/icons/platforms/', ''))
          .toList();
      
      // 按文件名排序
      platformIcons.sort();
      
      if (platformIcons.isNotEmpty) {
        _availableIcons = platformIcons;
      } else {
        // 如果从manifest读取失败，使用fallback列表
        _availableIcons = _getFallbackIconList();
      }
    } catch (e) {
      print('加载图标列表失败: $e');
      // 如果加载失败，使用fallback列表
      _availableIcons = _getFallbackIconList();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 获取fallback图标列表（当AssetManifest读取失败时使用）
  List<String> _getFallbackIconList() {
    return [
      'Weaviate-icon.svg',
      'aihubmix-color.svg',
      'alibabacloud-color.svg',
      'anthropic.svg',
      'anyrouter-color.svg',
      'aws-color.svg',
      'baichuan-color.svg',
      'baiducloud-color.svg',
      'bailian-color.svg',
      'brave.svg',
      'bytedance-color.svg',
      'claude-color.svg',
      'codegeex-color.svg',
      'cohere-color.svg',
      'coze.svg',
      'cursor.svg',
      'deepseek-color.svg',
      'dify-color.svg',
      'figma-color.svg',
      'filesystem.svg',
      'gemini-color.svg',
      'git.svg',
      'giteeai.svg',
      'github.svg',
      'githubcopilot.svg',
      'google-color.svg',
      'grok.svg',
      'huggingface-color.svg',
      'jimeng-color.svg',
      'jinaai.svg',
      'kimi-color.svg',
      'kolors-color.svg',
      'longcat-color.svg',
      'mcp.svg',
      'microsoft-color.svg',
      'minimax-color.svg',
      'mistral-color.svg',
      'modelscope-color.svg',
      'monica-color.svg',
      'moonshot.svg',
      'mysql.svg',
      'n8n-color.svg',
      'notion.svg',
      'nova-color.svg',
      'ollama.svg',
      'openai.svg',
      'openrouter.svg',
      'perplexity-color.svg',
      'pinecone-icon.svg',
      'postgres.svg',
      'qdrant-icon.svg',
      'qwen-color.svg',
      'siliconcloud-color.svg',
      'slack.svg',
      'supabase-icon.svg',
      'tencentcloud-color.svg',
      'trae-color.svg',
      'v0.svg',
      'volcengine-color.svg',
      'wenxin-color.svg',
      'windsurf.svg',
      'xai.svg',
      'yi-color.svg',
      'zai.svg',
      'zhipu-color.svg',
    ];
  }

  List<String> get _filteredIcons {
    if (_searchQuery.isEmpty) {
      return _availableIcons;
    }
    final query = _searchQuery.toLowerCase();
    return _availableIcons
        .where((icon) => icon.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final shadTheme = ShadTheme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        height: 500,
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
            // 搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: ShadInputFormField(
                id: 'icon_search',
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
                placeholder: const Text('搜索图标...'),
                leading: Icon(
                  Icons.search,
                  size: 18,
                  color: shadTheme.colorScheme.mutedForeground,
                ),
              ),
            ),
            // 图标网格
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: shadTheme.colorScheme.primary,
                      ),
                    )
                  : _filteredIcons.isEmpty
                      ? Center(
                          child: Text(
                            '未找到图标',
                            style: shadTheme.textTheme.p.copyWith(
                              color: shadTheme.colorScheme.mutedForeground,
                            ),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1,
                          ),
                          itemCount: _filteredIcons.length,
                          itemBuilder: (context, index) {
                            final icon = _filteredIcons[index];
                            final isSelected = _selectedIcon == icon;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedIcon = icon;
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? shadTheme.colorScheme.primary.withOpacity(0.1)
                                      : shadTheme.colorScheme.muted,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? shadTheme.colorScheme.primary
                                        : shadTheme.colorScheme.border,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: SvgPicture.asset(
                                    'assets/icons/platforms/$icon',
                                    width: 32,
                                    height: 32,
                                    // 所有图标都显示原始颜色，不使用colorFilter
                                    allowDrawingOutsideViewBox: true,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // 底部按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: shadTheme.colorScheme.border,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ShadButton.outline(
                    onPressed: () {
                      widget.onIconSelected(null);
                      Navigator.of(context).pop(null);
                    },
                    child: const Text('清除'),
                  ),
                  const SizedBox(width: 12),
                  ShadButton.outline(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  ShadButton(
                    onPressed: () {
                      widget.onIconSelected(_selectedIcon);
                      Navigator.of(context).pop(_selectedIcon);
                    },
                    child: const Text('确定'),
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

