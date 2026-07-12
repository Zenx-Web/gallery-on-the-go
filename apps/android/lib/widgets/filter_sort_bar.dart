import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../theme/app_theme.dart';

enum MediaTypeFilter { all, photos, videos }

enum SortOption { newest, oldest, name }

extension MediaTypeFilterX on MediaTypeFilter {
  String get label => switch (this) {
        MediaTypeFilter.all => 'All',
        MediaTypeFilter.photos => 'Photos',
        MediaTypeFilter.videos => 'Videos',
      };

  bool matches(AssetEntity asset) => switch (this) {
        MediaTypeFilter.all => true,
        MediaTypeFilter.photos => asset.type == AssetType.image,
        MediaTypeFilter.videos => asset.type == AssetType.video,
      };
}

extension SortOptionX on SortOption {
  String get label => switch (this) {
        SortOption.newest => 'Newest',
        SortOption.oldest => 'Oldest',
        SortOption.name => 'Name',
      };

  IconData get icon => switch (this) {
        SortOption.newest => Icons.arrow_downward_rounded,
        SortOption.oldest => Icons.arrow_upward_rounded,
        SortOption.name => Icons.sort_by_alpha_rounded,
      };

  int compare(AssetEntity a, AssetEntity b) => switch (this) {
        SortOption.newest => b.createDateTime.compareTo(a.createDateTime),
        SortOption.oldest => a.createDateTime.compareTo(b.createDateTime),
        SortOption.name => (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()),
      };
}

/// Type-filter chips + a sort dropdown, shared by the Photos tab and album
/// detail screen.
class FilterSortBar extends StatelessWidget {
  final MediaTypeFilter typeFilter;
  final ValueChanged<MediaTypeFilter> onTypeChanged;
  final SortOption sortOption;
  final ValueChanged<SortOption> onSortChanged;

  const FilterSortBar({
    super.key,
    required this.typeFilter,
    required this.onTypeChanged,
    required this.sortOption,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MediaTypeFilter.values.map((f) {
                  final selected = f == typeFilter;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: selected,
                      showCheckmark: false,
                      onSelected: (_) => onTypeChanged(f),
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.onSurfaceSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PopupMenuButton<SortOption>(
            initialValue: sortOption,
            onSelected: onSortChanged,
            color: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            itemBuilder: (context) => SortOption.values
                .map((s) => PopupMenuItem(
                      value: s,
                      child: Row(
                        children: [
                          Icon(s.icon, size: 16, color: AppColors.onSurfaceSecondary),
                          const SizedBox(width: AppSpacing.sm),
                          Text(s.label),
                        ],
                      ),
                    ))
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(sortOption.icon, size: 15, color: AppColors.onSurfaceSecondary),
                  const SizedBox(width: 6),
                  Text(
                    sortOption.label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
