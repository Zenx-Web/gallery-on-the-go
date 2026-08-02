import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models.dart';
import '../services/media_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Full-device file browser — lists ANY folder under shared storage (not
/// just MediaStore-indexed photos/videos), using the MANAGE_EXTERNAL_STORAGE
/// permission already granted at app startup. Breadcrumb navigation is
/// tracked client-side as a simple path stack rather than relying on
/// server-computed parent paths, so "up"/breadcrumb taps can never drift out
/// of sync with what's actually on screen.
class FolderBrowserScreen extends StatefulWidget {
  const FolderBrowserScreen({super.key});

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  final _mediaService = MediaService();
  List<String> _pathStack = [MediaService.storageRootPath];

  List<FolderEntry> _entries = [];
  bool _loading = true;
  String? _error;

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final response = await _mediaService.listDirectory(
      path: _currentPath,
      page: 1,
      pageSize: 1000,
    );
    if (!mounted) return;
    setState(() {
      _entries = response.entries;
      _error = response.error;
      _loading = false;
    });
  }

  void _openFolder(FolderEntry entry) {
    setState(() => _pathStack = [..._pathStack, entry.path]);
    _load();
  }

  void _goUp() {
    if (_pathStack.length <= 1) return;
    setState(() => _pathStack = _pathStack.sublist(0, _pathStack.length - 1));
    _load();
  }

  void _goToIndex(int index) {
    if (index >= _pathStack.length - 1) return;
    setState(() => _pathStack = _pathStack.sublist(0, index + 1));
    _load();
  }

  void _openEntry(FolderEntry entry) {
    if (entry.isDirectory) {
      _openFolder(entry);
      return;
    }
    final mime = entry.mimeType ?? '';
    if (mime.startsWith('image/')) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _ImagePreviewScreen(path: entry.path, name: entry.name),
      ));
    } else {
      _showFileSheet(entry);
    }
  }

  void _showFileSheet(FolderEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_iconFor(entry), color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    entry.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(_formatSize(entry.size), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Share.shareXFiles([XFile(entry.path)]);
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open / Share'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildBreadcrumbs(),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: _pathStack.length > 1 ? _goUp : null,
            color: _pathStack.length > 1 ? AppColors.onSurface : AppColors.onSurfaceTertiary,
            tooltip: 'Up one level',
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              itemCount: _pathStack.length,
              separatorBuilder: (_, __) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.chevron_right, size: 14, color: AppColors.onSurfaceTertiary),
              ),
              itemBuilder: (context, i) {
                final isLast = i == _pathStack.length - 1;
                final label = i == 0 ? 'Internal Storage' : _pathStack[i].split('/').last;
                return Center(
                  child: GestureDetector(
                    onTap: isLast ? null : () => _goToIndex(i),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                        color: isLast ? AppColors.onSurface : AppColors.accent,
                      ),
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

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'Can\u2019t open this folder',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    if (_entries.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_outlined,
        title: 'Empty folder',
        message: 'There are no files or folders here.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: _entries.length,
        itemBuilder: (context, i) {
          final entry = _entries[i];
          return ListTile(
            leading: Icon(_iconFor(entry), color: entry.isDirectory ? AppColors.accent : AppColors.onSurfaceSecondary),
            title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: entry.isDirectory ? null : Text(_formatSize(entry.size)),
            trailing: entry.isDirectory ? const Icon(Icons.chevron_right, color: AppColors.onSurfaceTertiary) : null,
            onTap: () => _openEntry(entry),
          );
        },
      ),
    );
  }

  IconData _iconFor(FolderEntry e) {
    if (e.isDirectory) return Icons.folder;
    final mime = e.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.videocam_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.contains('zip')) return Icons.folder_zip_outlined;
    if (mime.contains('package-archive')) return Icons.android_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(size < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  const _ImagePreviewScreen({required this.path, required this.name});

  final String path;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () => Share.shareXFiles([XFile(path)]),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
