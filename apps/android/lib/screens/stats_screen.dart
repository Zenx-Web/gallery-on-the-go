import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_background.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StudyStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await StudyStorage.instance.computeStats();
    if (mounted) setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Statistics')),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          stats == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStreakCard(context, stats),
                        const SizedBox(height: AppSpacing.lg),
                        Text('This Week', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.md),
                        _buildWeeklyChart(context, stats),
                        const SizedBox(height: AppSpacing.lg),
                        Text('Overview', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.md),
                        _buildStatsGrid(context, stats),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(BuildContext context, StudyStats stats) {
    final label = stats.streakDays == 0
        ? 'Complete a task, review a card, or scan a document to start your streak.'
        : 'Keep it up! 🔥';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent, AppColors.accent.withOpacity(0.55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department, color: Colors.white, size: 44),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stats.streakDays == 1 ? '1-Day Streak' : '${stats.streakDays}-Day Streak',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  '${stats.streakDays} ${stats.streakDays == 1 ? 'day' : 'days'}',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: Colors.white, fontSize: 28),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChart(BuildContext context, StudyStats stats) {
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final activity = stats.last7DaysActivity; // oldest -> newest, last = today
    final maxActivity = activity.fold<int>(1, (m, v) => v > m ? v : m);
    final todayIndex = activity.length - 1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(7, (i) {
            final count = activity[i];
            final isToday = i == todayIndex;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    color: isToday
                        ? AppColors.accent
                        : AppColors.onSurfaceTertiary,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  width: 28,
                  height: count == 0 ? 4 : (count / maxActivity) * 80,
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColors.accent
                        : AppColors.accent.withOpacity(0.28),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Weekday letters run Mon→Sun; align them to the actual
                // weekday of each of the last 7 days (today is always last).
                Text(
                  dayLabels[(DateTime.now().subtract(Duration(days: 6 - i)).weekday - 1) % 7],
                  style: TextStyle(
                    fontSize: 11,
                    color: isToday
                        ? AppColors.accent
                        : AppColors.onSurfaceTertiary,
                    fontWeight:
                        isToday ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, StudyStats stats) {
    final tiles = [
      _Stat('${stats.scansCount}', 'Docs Scanned', Icons.document_scanner_outlined, AppColors.studyAmber),
      _Stat('${stats.filesCount}', 'Notes & Files', Icons.note_outlined, AppColors.studyGreen),
      _Stat('${stats.tasksDone}/${stats.tasksTotal}', 'Tasks Done', Icons.task_alt, AppColors.onSurface),
      _Stat('${stats.cardsMastered}/${stats.cardsTotal}', 'Cards Mastered', Icons.style_outlined, AppColors.accent),
      _Stat('${stats.decksCount}', 'Flashcard Decks', Icons.filter_none_outlined, AppColors.studyAmber),
      _Stat('${stats.last7DaysActivity.last}', 'Actions Today', Icons.bolt_outlined, AppColors.studyGreen),
    ];
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.45,
      children: tiles.map((s) => _StatCard(stat: s)).toList(),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _Stat {
  const _Stat(this.value, this.label, this.icon, this.color);
  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(stat.icon, color: stat.color, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: stat.color, fontSize: 20),
              ),
              const SizedBox(height: 2),
              Text(stat.label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
