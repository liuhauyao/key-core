import 'package:flutter/material.dart';
import '../../models/platform_type.dart';
import '../../services/platform_registry.dart';
import '../../utils/app_localizations.dart';
import '../../utils/platform_icon_service.dart';

/// 平台过滤器组件
class PlatformFilter extends StatelessWidget {
  final PlatformType? selectedPlatform;
  final ValueChanged<PlatformType?> onPlatformChanged;

  const PlatformFilter({
    super.key,
    this.selectedPlatform,
    required this.onPlatformChanged,
  });

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
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
              value: selectedPlatform,
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
                ...PlatformRegistry.all.map((platform) {
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
              onChanged: (value) => onPlatformChanged(value),
            ),
          ),
        ],
      ),
    );
  }
}

