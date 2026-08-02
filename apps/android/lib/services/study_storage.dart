import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class TaskItem {
  TaskItem({
    required this.id,
    required this.title,
    this.subject = '',
    this.done = false,
    this.priority = 'medium',
    this.dueAt,
  });

  final String id;
  final String title;
  final String subject;
  final bool done;
  final String priority; // 'high' | 'medium' | 'low'
  final DateTime? dueAt;

  TaskItem copyWith({bool? done}) => TaskItem(
        id: id,
        title: title,
        subject: subject,
        done: done ?? this.done,
        priority: priority,
        dueAt: dueAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'done': done,
        'priority': priority,
        if (dueAt != null) 'dueAt': dueAt!.toIso8601String(),
      };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        id: j['id'] as String,
        title: j['title'] as String,
        subject: (j['subject'] as String?) ?? '',
        done: (j['done'] as bool?) ?? false,
        priority: (j['priority'] as String?) ?? 'medium',
        dueAt: (j['dueAt'] as String?) != null ? DateTime.tryParse(j['dueAt'] as String) : null,
      );
}

class ExamItem {
  ExamItem({
    required this.id,
    required this.title,
    required this.date,
    this.subject = '',
  });

  final String id;
  final String title;
  final DateTime date;
  final String subject;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'subject': subject,
      };

  factory ExamItem.fromJson(Map<String, dynamic> j) => ExamItem(
        id: j['id'] as String,
        title: j['title'] as String,
        date: DateTime.parse(j['date'] as String),
        subject: (j['subject'] as String?) ?? '',
      );
}


class FlashCard {
  FlashCard({required this.front, required this.back, this.mastered = false});

  final String front;
  final String back;
  bool mastered;

  Map<String, dynamic> toJson() =>
      {'front': front, 'back': back, 'mastered': mastered};

  factory FlashCard.fromJson(Map<String, dynamic> j) => FlashCard(
        front: j['front'] as String,
        back: j['back'] as String,
        mastered: (j['mastered'] as bool?) ?? false,
      );
}

class DeckItem {
  DeckItem({
    required this.id,
    required this.name,
    this.subject = '',
    List<FlashCard>? cards,
  }) : cards = cards ?? [];

  final String id;
  final String name;
  final String subject;
  final List<FlashCard> cards;

  int get total => cards.length;
  int get mastered => cards.where((c) => c.mastered).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'cards': cards.map((c) => c.toJson()).toList(),
      };

  factory DeckItem.fromJson(Map<String, dynamic> j) => DeckItem(
        id: j['id'] as String,
        name: j['name'] as String,
        subject: (j['subject'] as String?) ?? '',
        cards: (j['cards'] as List? ?? [])
            .map((c) => FlashCard.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class SubjectItem {
  SubjectItem({
    required this.name,
    this.fileCount = 0,
    List<String>? filePaths,
  }) : filePaths = filePaths ?? [];

  final String name;
  int fileCount;
  final List<String> filePaths;

  Map<String, dynamic> toJson() =>
      {'name': name, 'fileCount': fileCount, 'filePaths': filePaths};

  factory SubjectItem.fromJson(Map<String, dynamic> j) => SubjectItem(
        name: j['name'] as String,
        fileCount: (j['fileCount'] as int?) ?? 0,
        filePaths: (j['filePaths'] as List?)?.cast<String>() ?? [],
      );
}

class FolderItem {
  FolderItem({required this.name, List<SubjectItem>? subjects})
      : subjects = subjects ?? [];

  final String name;
  final List<SubjectItem> subjects;

  Map<String, dynamic> toJson() => {
        'name': name,
        'subjects': subjects.map((s) => s.toJson()).toList(),
      };

  factory FolderItem.fromJson(Map<String, dynamic> j) => FolderItem(
        name: j['name'] as String,
        subjects: (j['subjects'] as List? ?? [])
            .map((s) => SubjectItem.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// ─── Storage service (singleton) ─────────────────────────────────────────────

class StudyStorage {
  StudyStorage._();
  static final instance = StudyStorage._();

  static const _uuid = Uuid();
  static const _tasksKey = 'sv_tasks';
  static const _decksKey = 'sv_decks';
  static const _foldersKey = 'sv_folders';
  static const _examsKey = 'sv_exams';

  String get newId => _uuid.v4();

  // ── Tasks ──────────────────────────────────────────────────────────────────

  Future<List<TaskItem>> loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tasksKey);
      if (raw == null) return _defaultTasks();
      return (jsonDecode(raw) as List)
          .map((e) => TaskItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _defaultTasks();
    }
  }

  Future<void> saveTasks(List<TaskItem> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tasksKey,
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
  }

  List<TaskItem> _defaultTasks() => [];

  // ── Exams ──────────────────────────────────────────────────────────────────

  Future<List<ExamItem>> loadExams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_examsKey);
      if (raw == null) return _defaultExams();
      return (jsonDecode(raw) as List)
          .map((e) => ExamItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _defaultExams();
    }
  }

  Future<void> saveExams(List<ExamItem> exams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _examsKey,
      jsonEncode(exams.map((e) => e.toJson()).toList()),
    );
  }

  List<ExamItem> _defaultExams() => [];

  // ── Decks ──────────────────────────────────────────────────────────────────

  Future<List<DeckItem>> loadDecks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_decksKey);
      if (raw == null) return _defaultDecks();
      return (jsonDecode(raw) as List)
          .map((e) => DeckItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _defaultDecks();
    }
  }

  Future<void> saveDecks(List<DeckItem> decks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _decksKey,
      jsonEncode(decks.map((d) => d.toJson()).toList()),
    );
  }

  List<DeckItem> _defaultDecks() => [];

  // ── Folders ────────────────────────────────────────────────────────────────

  Future<List<FolderItem>> loadFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_foldersKey);
      if (raw == null) return _defaultFolders();
      return (jsonDecode(raw) as List)
          .map((e) => FolderItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return _defaultFolders();
    }
  }

  Future<void> saveFolders(List<FolderItem> folders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _foldersKey,
      jsonEncode(folders.map((f) => f.toJson()).toList()),
    );
  }

  List<FolderItem> _defaultFolders() => [];

  /// Files a path into the named folder/subject, creating either if they
  /// don't exist yet — used by the scanner so saved scans show up in the
  /// Library without a separate "choose a subject" step.
  Future<void> addFileToLibrary({
    required String folderName,
    required String subjectName,
    required String filePath,
  }) async {
    final folders = await loadFolders();
    var folder = folders.where((f) => f.name == folderName).firstOrNull;
    if (folder == null) {
      folder = FolderItem(name: folderName);
      folders.add(folder);
    }
    var subject = folder.subjects.where((s) => s.name == subjectName).firstOrNull;
    if (subject == null) {
      subject = SubjectItem(name: subjectName);
      folder.subjects.add(subject);
    }
    subject.filePaths.add(filePath);
    subject.fileCount = subject.filePaths.length;
    await saveFolders(folders);
  }

  // ── Activity tracking (streak + weekly chart) ─────────────────────────────

  static const _activityKey = 'sv_activity';
  static const _scansCountKey = 'sv_scans_count';

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, int>> _loadActivityMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_activityKey);
      if (raw == null) return {};
      return Map<String, dynamic>.from(jsonDecode(raw) as Map)
          .map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveActivityMap(Map<String, int> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activityKey, jsonEncode(map));
  }

  /// Marks today as an active study day — called from real user actions
  /// (task completed, flashcard graded, document scanned, file imported)
  /// so the streak/weekly chart reflect actual usage, never fabricated data.
  Future<void> recordActivity() async {
    final map = await _loadActivityMap();
    final key = _dateKey(DateTime.now());
    map[key] = (map[key] ?? 0) + 1;
    await _saveActivityMap(map);
  }

  Future<void> incrementScansCount() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_scansCountKey) ?? 0;
    await prefs.setInt(_scansCountKey, current + 1);
  }

  Future<int> loadScansCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_scansCountKey) ?? 0;
  }

  /// Aggregates every real, persisted signal in the app into one snapshot —
  /// used by both the Home and Statistics screens so they never diverge or
  /// show numbers that aren't actually backed by stored data.
  Future<StudyStats> computeStats() async {
    final tasks = await loadTasks();
    final decks = await loadDecks();
    final folders = await loadFolders();
    final activity = await _loadActivityMap();
    final scans = await loadScansCount();

    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if ((activity[_dateKey(cursor)] ?? 0) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while ((activity[_dateKey(cursor)] ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final last7Days = List<int>.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      return activity[_dateKey(day)] ?? 0;
    });

    final filesCount = folders.fold<int>(
      0,
      (sum, f) => sum + f.subjects.fold<int>(0, (s, sub) => s + sub.fileCount),
    );
    final cardsTotal = decks.fold<int>(0, (sum, d) => sum + d.total);
    final cardsMastered = decks.fold<int>(0, (sum, d) => sum + d.mastered);

    return StudyStats(
      streakDays: streak,
      last7DaysActivity: last7Days,
      scansCount: scans,
      filesCount: filesCount,
      decksCount: decks.length,
      cardsTotal: cardsTotal,
      cardsMastered: cardsMastered,
      tasksDone: tasks.where((t) => t.done).length,
      tasksTotal: tasks.length,
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Snapshot of every real metric the app tracks — nothing here is
/// fabricated; each field is either a stored counter or computed live from
/// persisted tasks/decks/folders.
class StudyStats {
  const StudyStats({
    required this.streakDays,
    required this.last7DaysActivity,
    required this.scansCount,
    required this.filesCount,
    required this.decksCount,
    required this.cardsTotal,
    required this.cardsMastered,
    required this.tasksDone,
    required this.tasksTotal,
  });

  final int streakDays;
  final List<int> last7DaysActivity; // oldest -> newest, last entry is today
  final int scansCount;
  final int filesCount;
  final int decksCount;
  final int cardsTotal;
  final int cardsMastered;
  final int tasksDone;
  final int tasksTotal;
}
