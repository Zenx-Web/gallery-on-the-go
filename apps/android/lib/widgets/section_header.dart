import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Date-group header for the All Photos timeline ("Today", "Yesterday",
/// "March 2026", ...).
class SectionHeader extends StatelessWidget {
  final String label;

  const SectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.onSurface,
            ),
      ),
    );
  }
}

/// Groups a sorted-newest-first list of items by day/week/month bucket and
/// returns the label a given DateTime falls into, matching common
/// photo-gallery conventions (Today / Yesterday / This Week / Month Year).
String dateGroupLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return 'This Week';
  if (date.year == now.year) {
    return _monthName(date.month);
  }
  return '${_monthName(date.month)} ${date.year}';
}

String _monthName(int month) {
  const names = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return names[month - 1];
}
