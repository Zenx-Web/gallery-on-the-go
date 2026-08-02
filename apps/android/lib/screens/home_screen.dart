import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/dashboard_card.dart';
import 'flashcards_screen.dart';
import 'scanner_screen.dart';
import 'stats_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.onNavigate});

  // Callback to switch the shell's bottom-nav tab.
  final void Function(int tabIndex)? onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StudyStats? _stats;
  List<TaskItem> _tasks = [];
  List<FolderItem> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await StudyStorage.instance.computeStats();
    final tasks = await StudyStorage.instance.loadTasks();
    final folders = await StudyStorage.instance.loadFolders();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _tasks = tasks;
      _folders = folders;
      _loading = false;
    });
  }

  Future<void> _toggleTask(String id) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final nowDone = !_tasks[i].done;
    setState(() => _tasks[i] = _tasks[i].copyWith(done: nowDone));
    await StudyStorage.instance.saveTasks(_tasks);
    if (nowDone) await StudyStorage.instance.recordActivity();
    _load(); // refresh derived stats (tasksDone, streak) after the change
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
                child: CustomScrollView(
                  slivers: [
                    _buildAppBar(context),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildGreeting(context),
                          const SizedBox(height: AppSpacing.xl),
                          _buildProgressRow(context),
                          const SizedBox(height: AppSpacing.xl),
                          _sectionTitle(context, 'Quick Actions'),
                          const SizedBox(height: AppSpacing.md),
                          _buildQuickActions(context),
                          const SizedBox(height: AppSpacing.xl),
                          _sectionTitle(context, 'Recent Notes'),
                          const SizedBox(height: AppSpacing.md),
                          _buildRecentNotes(context),
                          const SizedBox(height: AppSpacing.xl),
                          _sectionTitle(context, "Today's Tasks"),
                          const SizedBox(height: AppSpacing.md),
                          _buildTodaysTasks(context),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      floating: true,
      titleSpacing: AppSpacing.lg,
      title: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.menu_book, color: Colors.white, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('StudyVault', style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StatsScreen()),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  Widget _buildGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting 👋',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 26),
        ),
        const SizedBox(height: 4),
        Text(
          'Ready to study today?',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.onSurfaceSecondary),
        ),
      ],
    );
  }

  Widget _buildProgressRow(BuildContext context) {
    final stats = _stats!;
    return Row(
      children: [
        _StatChip(
          icon: Icons.local_fire_department,
          value: '${stats.streakDays}',
          label: 'day streak',
          color: AppColors.studyAmber,
        ),
        const SizedBox(width: AppSpacing.md),
        _StatChip(
          icon: Icons.task_alt,
          value: '${stats.tasksDone}/${stats.tasksTotal}',
          label: 'tasks done',
          color: AppColors.studyGreen,
        ),
        const SizedBox(width: AppSpacing.md),
        _StatChip(
          icon: Icons.style_outlined,
          value: '${stats.cardsMastered}/${stats.cardsTotal}',
          label: 'cards mastered',
          color: AppColors.accent,
        ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }

  Widget _buildQuickActions(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.6,
      children: [
        DashboardCard(
          icon: Icons.document_scanner_outlined,
          title: 'Scanner',
          subtitle: 'Scan a document',
          color: AppColors.accent,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScannerScreen()),
            );
            _load();
          },
        ),
        DashboardCard(
          icon: Icons.style_outlined,
          title: 'Flashcards',
          subtitle: 'Review your decks',
          color: AppColors.studyAmber,
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FlashcardsScreen()),
            );
            _load();
          },
        ),
        DashboardCard(
          icon: Icons.event_note_outlined,
          title: 'Planner',
          subtitle: "See today's plan",
          color: AppColors.studyGreen,
          onTap: () => widget.onNavigate?.call(3),
        ),
        DashboardCard(
          icon: Icons.bar_chart_rounded,
          title: 'Statistics',
          subtitle: 'Track your progress',
          color: AppColors.onSurfaceSecondary,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StatsScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentNotes(BuildContext context) {
    final entries = <_NoteEntry>[];
    for (final folder in _folders) {
      for (final subject in folder.subjects) {
        if (subject.fileCount > 0) {
          entries.add(_NoteEntry(folder: folder.name, subject: subject.name, count: subject.fileCount));
        }
      }
    }

    if (entries.isEmpty) {
      return _buildEmptyHint(
        context,
        icon: Icons.description_outlined,
        message: 'No notes yet — scan a document or import a file to get started.',
      );
    }

    return Column(
      children: entries.take(3).map((e) => _NoteTile(entry: e)).toList(),
    );
  }

  Widget _buildTodaysTasks(BuildContext context) {
    if (_tasks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEmptyHint(
            context,
            icon: Icons.task_outlined,
            message: 'No tasks yet — add one in Planner.',
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: TextButton(
              onPressed: () => widget.onNavigate?.call(3),
              child: Text('Open Planner →', style: TextStyle(color: AppColors.accent)),
            ),
          ),
        ],
      );
    }

    final incomplete = _tasks.where((t) => !t.done).toList();
    final shown = (incomplete.isNotEmpty ? incomplete : _tasks).take(3).toList();

    return Column(
      children: [
        for (final t in shown) _TaskTile(task: t, onToggle: () => _toggleTask(t.id)),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: TextButton(
            onPressed: () => widget.onNavigate?.call(3),
            child: Text(
              'See all tasks →',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyHint(BuildContext context, {required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.onSurfaceTertiary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 14, color: color),
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteEntry {
  const _NoteEntry({required this.folder, required this.subject, required this.count});
  final String folder;
  final String subject;
  final int count;
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.entry});
  final _NoteEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: AppColors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.subject,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(entry.folder, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Text('${entry.count} file${entry.count == 1 ? '' : 's'}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onToggle});

  final TaskItem task;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Checkbox(
            value: task.done,
            onChanged: (_) => onToggle(),
            activeColor: AppColors.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        decoration:
                            task.done ? TextDecoration.lineThrough : null,
                        color: task.done
                            ? AppColors.onSurfaceTertiary
                            : AppColors.onSurface,
                      ),
                ),
                if (task.subject.isNotEmpty)
                  Text(
                    task.subject,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
