import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_background.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};

/// Lists the files inside one folder/subject and lets the user open them —
/// previously subjects only showed a file count with no way to view what
/// was actually saved there.
class SubjectFilesScreen extends StatefulWidget {
  const SubjectFilesScreen({super.key, required this.folderName, required this.subjectName});

  final String folderName;
  final String subjectName;

  @override
  State<SubjectFilesScreen> createState() => _SubjectFilesScreenState();
}

class _SubjectFilesScreenState extends State<SubjectFilesScreen> {
  List<String> _filePaths = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await StudyStorage.instance.loadFolders();
    final folder = folders.where((f) => f.name == widget.folderName).firstOrNull;
    final subject = folder?.subjects.where((s) => s.name == widget.subjectName).firstOrNull;
    if (mounted) {
      setState(() {
        _filePaths = subject?.filePaths ?? [];
        _loading = false;
      });
    }
  }

  Future<void> _deleteFile(String path) async {
    final folders = await StudyStorage.instance.loadFolders();
    final folder = folders.where((f) => f.name == widget.folderName).firstOrNull;
    final subject = folder?.subjects.where((s) => s.name == widget.subjectName).firstOrNull;
    if (subject == null) return;
    subject.filePaths.remove(path);
    subject.fileCount = subject.filePaths.length;
    await StudyStorage.instance.saveFolders(folders);
    if (mounted) setState(() => _filePaths = List.of(_filePaths)..remove(path));
  }

  void _openFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (_imageExtensions.contains(ext)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FileImageViewer(path: path)));
    } else {
      // No in-app PDF renderer — hand off to whatever the user has
      // installed (Drive, Adobe, browser, ...) via the share/open sheet.
      Share.shareXFiles([XFile(path)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.subjectName)),
      body: Stack(
        children: [
          const Positioned.fill(child: GlassBackground()),
          SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filePaths.isEmpty
                    ? Center(
                        child: Text(
                          'No files yet',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: _filePaths.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final path = _filePaths[i];
                          final name = path.split(Platform.pathSeparator).last;
                          final isPdf = name.toLowerCase().endsWith('.pdf');
                          return Dismissible(
                            key: ValueKey(path),
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
                            onDismissed: (_) => _deleteFile(path),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                                  color: AppColors.accent,
                                ),
                                title: Text(name, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium),
                                onTap: () => _openFile(path),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _FileImageViewer extends StatelessWidget {
  const _FileImageViewer({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.shareXFiles([XFile(path)]),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(maxScale: 5, child: Image.file(File(path))),
      ),
    );
  }
}
