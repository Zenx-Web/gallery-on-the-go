import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Inline search box — filters the currently loaded asset list by name as
/// you type. Purely client-side/on-device; unrelated to the server-facing
/// socket search protocol used by the web panel.
class SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hintText;

  const SearchField({
    super.key,
    required this.onChanged,
    this.hintText = 'Search by name…',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.divider),
        ),
        child: TextField(
          onChanged: onChanged,
          style: const TextStyle(color: AppColors.onSurface, fontSize: 14),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: AppColors.onSurfaceTertiary, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.onSurfaceTertiary, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }
}
