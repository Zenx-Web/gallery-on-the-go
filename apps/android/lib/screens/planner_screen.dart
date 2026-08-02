import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late int _selectedDay;

  List<TaskItem> _tasks = [];
  List<ExamItem> _exams = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
    _selectedDay = DateTime.now().weekday - 1;
    NotificationService.instance.requestPermission();
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final tasks = await StudyStorage.instance.loadTasks();
    final exams = await StudyStorage.instance.loadExams();
    if (mounted) setState(() { _tasks = tasks; _exams = exams; _loading = false; });
  }

  Future<void> _saveTasks() => StudyStorage.instance.saveTasks(_tasks);
  Future<void> _saveExams() => StudyStorage.instance.saveExams(_exams);

  void _toggle(String id) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i == -1) return;
    final nowDone = !_tasks[i].done;
    setState(() => _tasks[i] = _tasks[i].copyWith(done: nowDone));
    _saveTasks();
    if (nowDone) {
      NotificationService.instance.cancel(id);
      StudyStorage.instance.recordActivity();
    } else {
      _scheduleTaskReminder(_tasks[i]);
    }
  }

  void _delete(String id) {
    setState(() => _tasks.removeWhere((t) => t.id == id));
    _saveTasks();
    NotificationService.instance.cancel(id);
  }

  void _addTask(String title, String subject, String priority, DateTime? dueAt) {
    final task = TaskItem(
      id: StudyStorage.instance.newId,
      title: title,
      subject: subject,
      priority: priority,
      dueAt: dueAt,
    );
    setState(() => _tasks.add(task));
    _saveTasks();
    _scheduleTaskReminder(task);
  }

  void _scheduleTaskReminder(TaskItem task) {
    if (task.dueAt == null || task.done) return;
    NotificationService.instance.scheduleAt(
      id: task.id,
      title: 'Task due: ${task.title}',
      body: task.subject.isNotEmpty ? task.subject : 'Study task reminder',
      when: task.dueAt!,
    );
  }

  void _addExam(String title, String subject, DateTime date) {
    final exam = ExamItem(id: StudyStorage.instance.newId, title: title, subject: subject, date: date);
    setState(() => _exams.add(exam));
    _saveExams();
    // Reminder on the morning of the exam — the countdown card already
    // conveys urgency day-to-day, this just nudges same-day.
    final reminderTime = DateTime(date.year, date.month, date.day, 8);
    NotificationService.instance.scheduleAt(
      id: exam.id,
      title: 'Exam today: ${exam.title}',
      body: exam.subject.isNotEmpty ? exam.subject : 'Good luck!',
      when: reminderTime,
    );
  }

  void _deleteExam(String id) {
    setState(() => _exams.removeWhere((e) => e.id == id));
    _saveExams();
    NotificationService.instance.cancel(id);
  }

  void _handleAddPressed(BuildContext context) {
    switch (_tabController.index) {
      case 0:
        _showAddTaskSheet(context);
        break;
      case 1:
        _showAddExamSheet(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _handleAddPressed(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWeekStrip(),
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.onSurface,
            unselectedLabelColor: AppColors.onSurfaceTertiary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            tabs: const [
              Tab(text: 'Tasks'),
              Tab(text: 'Exams'),
              Tab(text: 'Assignments'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTasksList(),
                _buildExamsList(),
                _buildEmptyState(Icons.assignment_outlined, 'No assignments yet'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 2
          ? null
          : FloatingActionButton(
              heroTag: null,
              backgroundColor: AppColors.accent,
              onPressed: () => _handleAddPressed(context),
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }

  Widget _buildWeekStrip() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (i) {
          final day = startOfWeek.add(Duration(days: i));
          final isSelected = i == _selectedDay;
          final isToday =
              day.day == now.day && day.month == now.month && day.year == now.year;

          return GestureDetector(
            onTap: () => setState(() => _selectedDay = i),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dayLabels[i],
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? AppColors.accent
                        : AppColors.onSurfaceTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.accent : Colors.transparent,
                    border: isToday && !isSelected
                        ? Border.all(color: AppColors.accent)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : isToday
                                ? AppColors.accent
                                : AppColors.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTasksList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_tasks.isEmpty) {
      return _buildEmptyState(Icons.task_outlined, 'No tasks yet — tap + to add one');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final task = _tasks[i];
        return Dismissible(
          key: ValueKey(task.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.18),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
          onDismissed: (_) => _delete(task.id),
          child: _TaskCard(task: task, onToggle: () => _toggle(task.id)),
        );
      },
    );
  }

  Widget _buildExamsList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_exams.isEmpty) {
      return _buildEmptyState(Icons.school_outlined, 'No exams yet — tap + to add one');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _exams.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final exam = _exams[i];
        return Dismissible(
          key: ValueKey(exam.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.18),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
          onDismissed: (_) => _deleteExam(exam.id),
          child: _ExamCard(exam: exam),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.onSurfaceTertiary),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: const TextStyle(color: AppColors.onSurfaceSecondary),
          ),
        ],
      ),
    );
  }

  void _showAddTaskSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    String priority = 'medium';
    DateTime? dueAt;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Task', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              TextField(controller: titleCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'Task name')),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(hintText: 'Subject (e.g. Mathematics)')),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                children: ['high', 'medium', 'low'].map((p) {
                  final c = _priorityColor(p);
                  return ChoiceChip(
                    label: Text(p[0].toUpperCase() + p.substring(1)),
                    selected: priority == p,
                    onSelected: (_) => setSheet(() => priority = p),
                    selectedColor: c.withOpacity(0.2),
                    side: BorderSide(color: priority == p ? c : AppColors.divider),
                    labelStyle: TextStyle(color: priority == p ? c : AppColors.onSurfaceSecondary, fontWeight: priority == p ? FontWeight.w600 : FontWeight.normal),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await _pickDueDateTime(ctx, dueAt);
                  if (picked != null) setSheet(() => dueAt = picked);
                },
                icon: const Icon(Icons.alarm_outlined, size: 18),
                label: Text(
                  dueAt == null ? 'Set reminder (optional)' : _dueLabel(dueAt!),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: dueAt == null ? AppColors.onSurfaceSecondary : AppColors.accent,
                  side: BorderSide(color: dueAt == null ? AppColors.divider : AppColors.accent),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (titleCtrl.text.trim().isNotEmpty) {
                      _addTask(titleCtrl.text.trim(), subjectCtrl.text.trim(), priority, dueAt);
                      Navigator.pop(ctx);
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  child: const Text('Add Task'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<DateTime?> _pickDueDateTime(BuildContext context, DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _showAddExamSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    DateTime examDate = DateTime.now().add(const Duration(days: 7));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Exam', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.lg),
              TextField(controller: titleCtrl, autofocus: true, decoration: const InputDecoration(hintText: 'Exam name')),
              const SizedBox(height: AppSpacing.md),
              TextField(controller: subjectCtrl, decoration: const InputDecoration(hintText: 'Subject')),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: examDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) setSheet(() => examDate = picked);
                },
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text('${examDate.month}/${examDate.day}/${examDate.year}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (titleCtrl.text.trim().isNotEmpty) {
                      _addExam(titleCtrl.text.trim(), subjectCtrl.text.trim(), examDate);
                      Navigator.pop(ctx);
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  child: const Text('Add Exam'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(String p) => switch (p) {
    'high' => AppColors.error,
    'low' => AppColors.studyGreen,
    _ => AppColors.studyAmber,
  };
}

// ─── Data models ──────────────────────────────────────────────────────────────

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

String _dueLabel(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour >= 12 ? 'PM' : 'AM';
  final minute = d.minute.toString().padLeft(2, '0');
  return '${d.month}/${d.day} · $hour:$minute $period';
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onToggle});

  final TaskItem task;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (task.priority) {
      'high' => AppColors.error,
      'low' => AppColors.studyGreen,
      _ => AppColors.studyAmber,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 44, decoration: BoxDecoration(color: priorityColor, borderRadius: BorderRadius.circular(99))),
          const SizedBox(width: AppSpacing.md),
          Checkbox(
            value: task.done,
            onChanged: (_) => onToggle(),
            activeColor: AppColors.accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    decoration: task.done ? TextDecoration.lineThrough : null,
                    color: task.done ? AppColors.onSurfaceTertiary : AppColors.onSurface,
                  ),
                ),
                if (task.subject.isNotEmpty)
                  Text(task.subject, style: Theme.of(context).textTheme.bodySmall),
                if (task.dueAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.alarm_outlined, size: 12, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Text(
                          _dueLabel(task.dueAt!),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.accent),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});
  final ExamItem exam;

  @override
  Widget build(BuildContext context) {
    final daysLeft = exam.date.difference(DateTime.now()).inDays;
    final urgencyColor = daysLeft <= 5
        ? AppColors.error
        : daysLeft <= 10
            ? AppColors.studyAmber
            : AppColors.studyGreen;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: urgencyColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.school_outlined, color: urgencyColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(exam.subject, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$daysLeft days',
                style: TextStyle(
                  color: urgencyColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text('left', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
