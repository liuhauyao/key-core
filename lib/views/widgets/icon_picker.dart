import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:convert';
import 'dart:async' show Future;
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

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
      // 在开发模式下，优先重新生成配置文件以确保最新
      if (_isDevelopmentMode()) {
        await _regenerateConfigInDevelopment();
      }

      // 首先尝试从构建时生成的配置文件加载图标列表
      final configIcons = await _loadIconsFromConfig();

      if (configIcons.isNotEmpty) {
        // 验证配置文件是否与实际文件数量匹配
        final actualIconCount = await _getActualIconCount();

        if (configIcons.length == actualIconCount) {
          _availableIcons = configIcons;
          print('成功从配置文件加载 ${configIcons.length} 个图标文件');
        } else {
          print('配置文件图标数量(${configIcons.length})与实际文件数量(${actualIconCount})不匹配，重新生成配置');
          await _regenerateConfigInDevelopment();
          // 重新加载配置
          final updatedConfigIcons = await _loadIconsFromConfig();
          _availableIcons = updatedConfigIcons.isNotEmpty ? updatedConfigIcons : _getFallbackIconList();
          print('重新生成后加载 ${updatedConfigIcons.length} 个图标文件');
        }
      } else {
        // 如果配置文件加载失败，尝试重新生成
        print('配置文件加载失败，尝试重新生成');
        await _regenerateConfigInDevelopment();
        final regeneratedIcons = await _loadIconsFromConfig();
        _availableIcons = regeneratedIcons.isNotEmpty ? regeneratedIcons : _getFallbackIconList();
      }

    } catch (e) {
      print('图标加载失败: $e，使用基础列表');
      _availableIcons = _getFallbackIconList();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 从构建时生成的配置文件加载图标列表
  Future<List<String>> _loadIconsFromConfig() async {
    try {
      final configString = await rootBundle.loadString('assets/config/icon_list.json');
      final configData = json.decode(configString) as Map<String, dynamic>;

      final icons = (configData['icons'] as List<dynamic>)
          .map((icon) => icon as String)
          .toList();

      return icons;
    } catch (e) {
      print('加载图标配置文件失败: $e');
      return [];
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

  /// 检测是否为开发模式
  bool _isDevelopmentMode() {
    // 在Flutter中，kDebugMode表示是否为调试模式（开发环境）
    // 生产环境的release构建中kDebugMode为false
    return kDebugMode;
  }

  /// 获取实际的图标文件数量
  Future<int> _getActualIconCount() async {
    try {
      // 尝试通过测试资源存在性来统计实际图标数量
      final fallbackIcons = _getFallbackIconList();
      int actualCount = 0;

      // 并发测试前50个图标（为了性能）
      const int testLimit = 50;
      final List<Future<void>> futures = [];

      for (int i = 0; i < fallbackIcons.length && i < testLimit; i++) {
        final iconName = fallbackIcons[i];
        futures.add(_testIconExists(iconName).then((exists) {
          if (exists) actualCount++;
        }));
      }

      await Future.wait(futures);

      // 如果测试的数量足够多，返回测试结果，否则返回fallback数量
      if (fallbackIcons.length <= testLimit) {
        return actualCount;
      } else {
        // 如果有很多图标，假设配置是正确的，除非明显不匹配
        return actualCount > 0 ? actualCount : fallbackIcons.length;
      }
    } catch (e) {
      print('获取实际图标数量失败: $e');
      return _getFallbackIconList().length;
    }
  }

  /// 测试图标文件是否存在
  Future<bool> _testIconExists(String iconName) async {
    try {
      await rootBundle.load('assets/icons/platforms/$iconName');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 在开发模式下重新生成配置文件
  Future<void> _regenerateConfigInDevelopment() async {
    try {
      print('重新生成图标配置文件...');

      // 执行图标生成脚本
      final result = await Process.run('dart', ['scripts/generate_icon_list.dart'],
          workingDirectory: Directory.current.path);

      if (result.exitCode == 0) {
        print('图标配置文件重新生成成功');
      } else {
        print('图标配置文件重新生成失败: ${result.stderr}');
      }
    } catch (e) {
      print('执行图标生成脚本时出错: $e');
      // 即使出错也不要影响应用启动
    }
  }
}

