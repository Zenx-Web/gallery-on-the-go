import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

class NotesTopic {
  const NotesTopic({
    required this.subject,
    required this.topic,
    required this.directoryPath,
    required this.pagePaths,
    required this.savedAt,
  });

  final String subject;
  final String topic;
  final String directoryPath;
  final List<String> pagePaths;
  final DateTime savedAt;

  int get pageCount => pagePaths.length;
  String? get thumbnailPath => pagePaths.isNotEmpty ? pagePaths.first : null;
}

// ─── Storage Service ──────────────────────────────────────────────────────────

/// Manages scanned notes stored as image files:
///   <docsDir>/StudyNotes/<Subject>/<Topic>/page_001.jpg …
///
/// Directory names are the display names with only reserved filesystem
/// characters replaced by underscores; everything else is kept as-is so
/// "Math - Ch. 1" stays readable.
class NotesStorage {
  NotesStorage._();
  static const _root = 'StudyNotes';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Save [pagePaths] (JPEG files) under [subject]/[topic].
  /// Creates the directories if they don't exist.
  static Future<void> saveTopic({
    required String subject,
    required String topic,
    required List<String> pagePaths,
  }) async {
    final dir = await _topicDir(subject, topic, create: true);
    for (var i = 0; i < pagePaths.length; i++) {
      final pageNum = (i + 1).toString().padLeft(3, '0');
      final dest = File('${dir.path}/page_$pageNum.jpg');
      await File(pagePaths[i]).copy(dest.path);
    }
  }

  /// All subjects that have at least one saved topic.
  static Future<List<String>> loadSubjects() async {
    final root = await _rootDir();
    if (!await root.exists()) return [];
    final dirs = <String>[];
    await for (final e in root.list()) {
      if (e is Directory) {
        final name = _lastName(e.path);
        if (name.isNotEmpty) dirs.add(name);
      }
    }
    dirs.sort();
    return dirs;
  }

  /// All topics for [subject], newest first.
  static Future<List<NotesTopic>> loadTopics(String subject) async {
    final subjectDir = await _subjectDir(subject);
    if (!await subjectDir.exists()) return [];
    final topics = <NotesTopic>[];
    await for (final e in subjectDir.list()) {
      if (e is Directory) {
        final topicName = _lastName(e.path);
        final pages = await _listPages(e.path);
        final stat = await e.stat();
        topics.add(NotesTopic(
          subject: subject,
          topic: topicName,
          directoryPath: e.path,
          pagePaths: pages,
          savedAt: stat.modified,
        ));
      }
    }
    topics.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return topics;
  }

  /// All topics across all subjects, newest first (for the home screen).
  static Future<List<NotesTopic>> loadAllTopics() async {
    final subjects = await loadSubjects();
    final all = <NotesTopic>[];
    for (final s in subjects) {
      all.addAll(await loadTopics(s));
    }
    all.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return all;
  }

  /// Permanently deletes a topic (all its pages).
  static Future<void> deleteTopic(String subject, String topic) async {
    final dir = await _topicDir(subject, topic);
    if (await dir.exists()) await dir.delete(recursive: true);

    // Remove subject folder if it's now empty
    final subjectDir = await _subjectDir(subject);
    if (await subjectDir.exists()) {
      final children = await subjectDir.list().length;
      if (children == 0) await subjectDir.delete();
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  static Future<Directory> _rootDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_root');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _subjectDir(String subject) async {
    final root = await _rootDir();
    return Directory('${root.path}/${_sanitize(subject)}');
  }

  static Future<Directory> _topicDir(
    String subject,
    String topic, {
    bool create = false,
  }) async {
    final root = await _rootDir();
    final dir = Directory(
      '${root.path}/${_sanitize(subject)}/${_sanitize(topic)}',
    );
    if (create && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<String>> _listPages(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];
    final files = <String>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.jpg')) {
        files.add(e.path);
      }
    }
    files.sort();
    return files;
  }

  static String _lastName(String path) {
    final segments = path.replaceAll(r'\', '/').split('/');
    return segments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
  }

  static String _sanitize(String name) {
    return name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}
