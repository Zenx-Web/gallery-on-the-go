import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/study_storage.dart';
import '../theme/app_theme.dart';
import '../widgets/search_field.dart';
import 'subject_files_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _query = '';
  List<FolderItem> _folders = [];
  List<RecentFileEntry> _recentFiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFolders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    final folders = await StudyStorage.instance.loadFolders();
    final recentFiles = await StudyStorage.instance.loadRecentFiles();
    if (mounted) setState(() {
      _folders = folders;
      _recentFiles = recentFiles;
      _loading = false;
    });
  }

  Future<void> _save() => StudyStorage.instance.saveFolders(_folders);

  void _addFolder(String name) {
    setState(() => _folders.add(FolderItem(name: name)));
    _save();
  }

  void _addSubject(FolderItem folder, String name) {
    folder.subjects.add(SubjectItem(name: name));
    _save();
    setState(() {});
  }

  Future<void> _importFile(SubjectItem subject) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      if (file.path != null) subject.filePaths.add(file.path!);
    }
    subject.fileCount = subject.filePaths.length;
    _save();
    StudyStorage.instance.recordActivity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _showNewFolderDialog(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm,
            ),
            child: SearchField(
              hintText: 'Search notes and folders…',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          TabBar(
            controller: _tabController,
            indicatorColor: AppColors.accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: AppColors.onSurface,
            unselectedLabelColor: AppColors.onSurfaceTertiary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Favorites'),
              Tab(text: 'Recent'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllTab(),
                _buildEmptyState(Icons.star_border, 'No favorites yet'),
                _buildRecentTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        backgroundColor: AppColors.accent,
        onPressed: () => _showNewFolderDialog(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildAllTab() {
    if (_folders.isEmpty) return _buildEmptyState(Icons.folder_off_outlined, 'No folders yet');
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _folders.length,
      itemBuilder: (context, i) => _FolderTile(
        folder: _folders[i],
        query: _query,
        onAddSubject: (name) => _addSubject(_folders[i], name),
        onImportFile: _importFile,
      ),
    );
  }

  Widget _buildRecentTab() {
    if (_recentFiles.isEmpty) {
      return _buildEmptyState(Icons.history, 'No recent files yet');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _recentFiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final entry = _recentFiles[i];
        final diff = DateTime.now().difference(entry.savedAt);
        final timeLabel = diff.inMinutes < 60
            ? '${diff.inMinutes}m ago'
            : diff.inHours < 24
                ? '${diff.inHours}h ago'
                : diff.inDays == 1
                    ? 'Yesterday'
                    : '${entry.savedAt.day}/${entry.savedAt.month}/${entry.savedAt.year}';
        return GestureDetector(
          onTap: () {
            if (entry.isPdf) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PdfViewerScreen(filePath: entry.filePath, title: entry.fileName),
              ));
            } else {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _RecentImageViewer(path: entry.filePath),
              ));
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.divider),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (entry.isPdf ? AppColors.studyAmber : AppColors.accent).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  entry.isPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                  color: entry.isPdf ? AppColors.studyAmber : AppColors.accent,
                  size: 18,
                ),
              ),
              title: Text(
                entry.fileName,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: Text(
                '${entry.subjectName} · ${entry.folderName}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Text(
                timeLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.onSurfaceTertiary,
                ),
              ),
            ),
          ),
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

  void _showNewFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name (e.g. Semester 3)'),
          style: const TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _addFolder(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.folder, required this.query, required this.onAddSubject, required this.onImportFile});

  final FolderItem folder;
  final String query;
  final void Function(String name) onAddSubject;
  final Future<void> Function(SubjectItem) onImportFile;

  @override
  Widget build(BuildContext context) {
    final filtered = query.isEmpty
        ? folder.subjects
        : folder.subjects.where((s) => s.name.toLowerCase().contains(query.toLowerCase())).toList();

    if (filtered.isEmpty && query.isNotEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        iconColor: AppColors.accent,
        collapsedIconColor: AppColors.onSurfaceTertiary,
        leading: const Icon(Icons.folder_outlined, color: AppColors.accent),
        title: Text(folder.name, style: Theme.of(context).textTheme.titleMedium),
        children: [
          ...filtered.map((s) => _SubjectTile(folderName: folder.name, subject: s, onImport: () => onImportFile(s))),
          ListTile(
            leading: const Icon(Icons.add, color: AppColors.onSurfaceTertiary, size: 18),
            title: Text('Add subject', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceTertiary)),
            onTap: () => _showAddSubjectDialog(context),
          ),
        ],
      ),
    );
  }

  void _showAddSubjectDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text('Add subject to “${folder.name}”'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'Subject name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) { onAddSubject(ctrl.text.trim()); Navigator.pop(ctx); }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.folderName, required this.subject, required this.onImport});
  final String folderName;
  final SubjectItem subject;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: const Icon(Icons.subject, color: AppColors.accent, size: 16),
      ),
      title: Text(subject.name, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${subject.fileCount} files', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined, size: 18, color: AppColors.accent),
            onPressed: onImport,
            tooltip: 'Import file',
          ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubjectFilesScreen(folderName: folderName, subjectName: subject.name),
        ),
      ),
    );
  }
}

/// Lightweight image viewer used by the Library's Recent tab.
class _RecentImageViewer extends StatelessWidget {
  const _RecentImageViewer({required this.path});
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
      body: Center(child: InteractiveViewer(maxScale: 5, child: Image.file(File(path)))),
    );
  }
}
