import 'package:flutter/material.dart';
import '../../models/platform_type.dart';
import '../../services/platform_registry.dart';
import '../../services/region_filter_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_service.dart';

/// 平台过滤器组件
class PlatformFilter extends StatefulWidget {
  final PlatformType? selectedPlatform;
  final ValueChanged<PlatformType?> onPlatformChanged;

  const PlatformFilter({
    super.key,
    this.selectedPlatform,
    required this.onPlatformChanged,
  });

  @override
  State<PlatformFilter> createState() => _PlatformFilterState();
}

class _PlatformFilterState extends State<PlatformFilter> {
  List<PlatformType> _filteredPlatforms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFilteredPlatforms();
  }

  Future<void> _loadFilteredPlatforms() async {
    try {
      final isChinaFilterEnabled = await RegionFilterService.isChinaRegionFilterEnabled();

      if (isChinaFilterEnabled) {
        // 如果启用中国地区过滤，过滤受限平台
        final allPlatforms = PlatformRegistry.all;
        _filteredPlatforms = allPlatforms.where((platform) =>
          !RegionFilterService.isPlatformRestrictedInChina(platform.id) &&
          !RegionFilterService.isPlatformRestrictedInChina(platform.value)
        ).toList();
      } else {
        // 如果未启用过滤，显示所有平台
        _filteredPlatforms = PlatformRegistry.all;
      }
    } catch (e) {
      // 加载失败时显示所有平台
      _filteredPlatforms = PlatformRegistry.all;
      print('PlatformFilter: 加载过滤平台失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              '${localizations?.platformLabel ?? '平台'}: ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${localizations?.platformLabel ?? '平台'}: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<PlatformType>(
              value: widget.selectedPlatform,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              hint: Text(localizations?.allPlatforms ?? '全部平台'),
              items: [
                DropdownMenuItem<PlatformType>(
                  value: null,
                  child: Text(localizations?.allPlatforms ?? '全部平台'),
                ),
                ..._filteredPlatforms.map((platform) {
                  return DropdownMenuItem<PlatformType>(
                    value: platform,
                    child: Row(
                      children: [
                        PlatformIconService.buildIcon(
                          platform: platform,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(platform.value),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (value) => widget.onPlatformChanged(value),
            ),
          ),
        ],
      ),
    );
  }
}

