import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
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
    // Also remove from recents so Home screen stays consistent.
    await StudyStorage.instance.removeRecentFile(path);
    if (mounted) setState(() => _filePaths = List.of(_filePaths)..remove(path));
  }

  void _openFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (_imageExtensions.contains(ext)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _FileImageViewer(path: path)));
    } else {
      // PDF — open in the in-app viewer; fall back to share if it fails.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            filePath: path,
            title: path.split(Platform.pathSeparator).last,
          ),
        ),
      );
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

/// Full-screen, in-app PDF viewer backed by flutter_pdfview (native PDFium).
///
/// Shows a loading spinner until the first page renders, and a
/// page-indicator pill ("3 / 12") once ready. The AppBar has a share button.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.filePath, required this.title});

  final String filePath;
  final String title;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  int _currentPage = 1;
  int _totalPages = 0;
  bool _ready = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0E),
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share',
            onPressed: () => Share.shareXFiles([XFile(widget.filePath)]),
          ),
        ],
      ),
      body: Stack(
        children: [
          PDFView(
            filePath: widget.filePath,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: false,
            pageSnap: false,
            defaultPage: 0,
            fitPolicy: FitPolicy.WIDTH,
            onRender: (pages) {
              if (mounted) setState(() { _totalPages = pages ?? 0; _ready = true; });
            },
            onPageChanged: (page, total) {
              if (mounted) setState(() {
                _currentPage = (page ?? 0) + 1;
                _totalPages = total ?? _totalPages;
              });
            },
            onError: (err) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not render PDF: $err')),
                );
              }
            },
          ),
          if (!_ready)
            const Center(child: CircularProgressIndicator(color: Color(0xFF6C63FF))),
          if (_ready && _totalPages > 0)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xE01E1E27),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF26262F)),
                  ),
                  child: Text(
                    '$_currentPage / $_totalPages',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
