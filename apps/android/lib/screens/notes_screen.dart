import 'dart:io';
import 'package:flutter/material.dart';
import '../services/notes_storage.dart';
import '../theme/app_theme.dart';

// ─── Notes Screen (Subject list) ──────────────────────────────────────────────

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<String> _subjects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final subjects = await NotesStorage.loadSubjects();
    if (mounted) setState(() { _subjects = subjects; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _subjects.isEmpty
              ? _buildEmpty()
              : _buildSubjectList(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.menu_book_outlined,
              size: 64,
              color: AppColors.onSurfaceTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No notes yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Go to the Scanner tab, photograph your pages,\nhit Next, and name your note.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectList() {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _subjects.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) {
        final subject = _subjects[i];
        return _SubjectTile(
          subject: subject,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _TopicsScreen(subject: subject),
              ),
            );
            _reload(); // refresh in case topic was deleted
          },
        );
      },
    );
  }
}

// ─── Subject Tile ─────────────────────────────────────────────────────────────

class _SubjectTile extends StatefulWidget {
  const _SubjectTile({required this.subject, required this.onTap});
  final String subject;
  final VoidCallback onTap;

  @override
  State<_SubjectTile> createState() => _SubjectTileState();
}

class _SubjectTileState extends State<_SubjectTile> {
  int _topicCount = 0;
  String? _thumbnailPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final topics = await NotesStorage.loadTopics(widget.subject);
    if (!mounted) return;
    setState(() {
      _topicCount = topics.length;
      _thumbnailPath = topics.isNotEmpty ? topics.first.thumbnailPath : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 56,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: _thumbnailPath != null
                    ? Image.file(
                        File(_thumbnailPath!),
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                      )
                    : const Icon(
                        Icons.menu_book_outlined,
                        color: AppColors.onSurfaceTertiary,
                        size: 28,
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.subject,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$_topicCount topic${_topicCount == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.onSurfaceSecondary,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.onSurfaceTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Topics Screen ────────────────────────────────────────────────────────────

class _TopicsScreen extends StatefulWidget {
  const _TopicsScreen({required this.subject});
  final String subject;

  @override
  State<_TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<_TopicsScreen> {
  List<NotesTopic> _topics = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final topics = await NotesStorage.loadTopics(widget.subject);
    if (mounted) setState(() { _topics = topics; _loading = false; });
  }

  Future<void> _confirmDelete(NotesTopic topic) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Delete note?'),
        content: Text(
          'This will permanently delete "${topic.topic}" (${topic.pageCount} pages).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await NotesStorage.deleteTopic(widget.subject, topic.topic);
      await _reload();
      if (mounted && _topics.isEmpty) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.subject)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _topics.isEmpty
              ? Center(
                  child: Text(
                    'No topics in this subject.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: _topics.length,
                  itemBuilder: (_, i) => _TopicCard(
                    topic: _topics[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _PageViewerScreen(topic: _topics[i]),
                      ),
                    ),
                    onDelete: () => _confirmDelete(_topics[i]),
                  ),
                ),
    );
  }
}

// ─── Topic Card ───────────────────────────────────────────────────────────────

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.onTap,
    required this.onDelete,
  });

  final NotesTopic topic;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image (first page)
            Expanded(
              child: topic.thumbnailPath != null
                  ? Image.file(
                      File(topic.thumbnailPath!),
                      fit: BoxFit.cover,
                      cacheWidth: 320,
                    )
                  : const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.onSurfaceTertiary,
                        size: 36,
                      ),
                    ),
            ),
            // Topic name + page count
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.topic,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${topic.pageCount} page${topic.pageCount == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurfaceSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page Viewer Screen ───────────────────────────────────────────────────────

/// Swipeable full-screen viewer for the pages of a single topic.
class _PageViewerScreen extends StatefulWidget {
  const _PageViewerScreen({required this.topic, this.initialPage = 0});
  final NotesTopic topic;
  final int initialPage;

  @override
  State<_PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends State<_PageViewerScreen> {
  late final PageController _pageCtrl;
  int _currentPage = 0;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageCtrl = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.topic.pagePaths;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          children: [
            // Page viewer
            PageView.builder(
              controller: _pageCtrl,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.file(
                  File(pages[i]),
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // Top bar
            AnimatedOpacity(
              opacity: _showUI ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      // Back button
                      Material(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.topic.topic,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              widget.topic.subject,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom page counter
            AnimatedOpacity(
              opacity: _showUI ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'Page ${_currentPage + 1} of ${pages.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
