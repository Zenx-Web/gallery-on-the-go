import 'dart:io';

import 'package:photo_manager/photo_manager.dart';

import '../core/models.dart';

/// Reads the phone's gallery via MediaStore (through `photo_manager`) and the
/// Downloads folder via plain `dart:io` directory listing. Everything here is
/// read-only — files are only ever opened for streaming when explicitly
/// requested (see file_stream_service.dart), never copied or uploaded ahead
/// of time.
class MediaService {
  static const String downloadsAlbumId = '__downloads__';
  static const String downloadsPath = '/storage/emulated/0/Download';

  /// Root of shared storage — browsable via MANAGE_EXTERNAL_STORAGE, the
  /// same "All files access" permission already granted at startup (see
  /// status_screen.dart). This is the more reliable choice for full-device
  /// folder browsing versus the Storage Access Framework: SAF only grants
  /// one user-picked tree at a time via a system dialog with no arbitrary
  /// recursive navigation, whereas MANAGE_EXTERNAL_STORAGE — already in use
  /// here for Downloads — gives direct, permission-already-granted
  /// dart:io access to the entire partition in one grant.
  static const String storageRootPath = '/storage/emulated/0';

  final Map<String, AssetEntity> _assetCache = {};
  final Map<String, File> _downloadFileCache = {};
  final Map<String, File> _fsFileCache = {};

  static final FilterOptionGroup _newestFirst = FilterOptionGroup(
    orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
  );

  Future<bool> ensurePermission() async {
    final result = await PhotoManager.requestPermissionExtend();
    return result.isAuth || result.hasAccess;
  }

  // ─── Gallery ───

  Future<GalleryListResponse> listAlbums() async {
    // The background service runs continuously (see socket_service.dart),
    // so if the user grants full media access from system Settings while
    // the app was already running, photo_manager's own MediaStore/
    // permission-scope cache is never invalidated — every query keeps
    // returning whatever subset was visible under the previous (often
    // limited/partial) grant until the process restarts. Clearing the
    // cache before every listing forces it to re-check current permission
    // state and re-query MediaStore fresh, without requiring a restart.
    await PhotoManager.clearFileCache();

    // NOTE: no filterOption here. Passing a FilterOptionGroup with an
    // OrderOption into getAssetPathList makes photo_manager order at the asset
    // level and drop its per-bucket DISTINCT, so the same folder comes back
    // more than once — which is exactly why the web panel showed duplicate
    // folders while the on-device gallery screen (which calls getAssetPathList
    // WITHOUT a filterOption) never did. Ordering the album *list* by photo
    // date is meaningless anyway; file ordering is applied per-album in
    // listAlbumFiles below.
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
    );

    var totalFiles = 0;
    final albums = <GalleryAlbum>[];
    // Defensive dedupe by bucket id — cheap insurance so a duplicate from any
    // future query change can't reach the UI as a repeated folder.
    final seenAlbumIds = <String>{};
    for (final path in paths) {
      if (!seenAlbumIds.add(path.id)) continue;
      final count = await path.assetCountAsync;
      totalFiles += count;
      albums.add(GalleryAlbum(
        id: path.id,
        name: path.name,
        fileCount: count,
      ));
    }

    return GalleryListResponse(albums: albums, totalFiles: totalFiles);
  }

  Future<PagedFilesResponse> listAlbumFiles({
    required String albumId,
    required int page,
    required int pageSize,
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
      filterOption: _newestFirst,
    );
    final album = paths.where((p) => p.id == albumId).firstOrNull;

    if (album == null) {
      return PagedFilesResponse(
        files: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        hasMore: false,
      );
    }

    final total = await album.assetCountAsync;
    // getAssetListRange (absolute offsets) instead of getAssetListPaged
    // (internal per-page cursor) — the cursor-based paging can re-query
    // MediaStore per page and drift if it changes between calls, silently
    // skipping assets across page boundaries. Range queries are stable
    // against a single ordering. Our wire protocol is 1-indexed.
    final start = (page - 1) * pageSize;
    final assets = await album.getAssetListRange(start: start, end: start + pageSize);

    final files = <FileItem>[];
    // Dedupe within the page — createDate ordering is non-unique (bulk imports,
    // screenshots, etc. share timestamps), so a range query can occasionally
    // surface the same asset twice. Keep the first occurrence.
    final seenAssetIds = <String>{};
    for (final asset in assets) {
      if (!seenAssetIds.add(asset.id)) continue;
      _assetCache[asset.id] = asset;
      files.add(await _toFileItem(asset));
    }

    return PagedFilesResponse(
      files: files,
      total: total,
      page: page,
      pageSize: pageSize,
      // Base hasMore on how far the range reached into the album (raw
      // assets.length), NOT files.length — otherwise dropping an in-page
      // duplicate could shrink the count below pageSize and prematurely
      // report "end of folder" while assets remain.
      hasMore: start + assets.length < total,
    );
  }

  // ─── Downloads ───

  Future<PagedFilesResponse> listDownloads({
    required int page,
    required int pageSize,
  }) async {
    final dir = Directory(downloadsPath);
    if (!await dir.exists()) {
      return PagedFilesResponse(
        files: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        hasMore: false,
      );
    }

    final entries = await dir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    entries.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    final total = entries.length;
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, total);
    final pageEntries = start < total ? entries.sublist(start, end) : <File>[];

    final files = <FileItem>[];
    for (final file in pageEntries) {
      final id = 'dl_${file.path.hashCode}';
      _downloadFileCache[id] = file;
      final stat = await file.stat();
      files.add(FileItem(
        id: id,
        name: file.uri.pathSegments.last,
        path: file.path,
        size: stat.size,
        mimeType: _guessMimeType(file.path),
        createdAt: stat.changed.toIso8601String(),
        modifiedAt: stat.modified.toIso8601String(),
      ));
    }

    return PagedFilesResponse(
      files: files,
      total: total,
      page: page,
      pageSize: pageSize,
      hasMore: end < total,
    );
  }

  // ─── Folder browser (any device folder, not just gallery/downloads) ───

  /// Lists one level of an arbitrary directory under shared storage —
  /// folders first (alphabetical), then files (alphabetical). Every entry
  /// and the whole directory read is individually try/caught: Android
  /// blocks direct access to other apps' `Android/data` and `Android/obb`
  /// even under MANAGE_EXTERNAL_STORAGE (an OS-level restriction, not a
  /// permission gap), and broken symlinks/edge-case entries can throw on
  /// `stat()` — both are surfaced gracefully instead of crashing the browser.
  Future<DirectoryListResponse> listDirectory({
    String? path,
    required int page,
    required int pageSize,
  }) async {
    final targetPath = (path == null || path.isEmpty) ? storageRootPath : path;
    final dir = Directory(targetPath);

    if (!await dir.exists()) {
      return DirectoryListResponse(
        path: targetPath,
        parentPath: _parentOf(targetPath),
        entries: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        hasMore: false,
        error: 'Folder not found',
      );
    }

    final folders = <FolderEntry>[];
    final files = <FolderEntry>[];
    try {
      await for (final entity in dir.list(followLinks: false)) {
        try {
          final stat = await entity.stat();
          final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty);
          final name = segments.isEmpty ? entity.path : segments.last;
          final isDir = stat.type == FileSystemEntityType.directory;
          final entry = FolderEntry(
            id: _fsIdFor(entity.path),
            name: name,
            path: entity.path,
            isDirectory: isDir,
            size: isDir ? 0 : stat.size,
            mimeType: isDir ? null : _guessMimeType(entity.path),
            modifiedAt: stat.modified.toIso8601String(),
          );
          (isDir ? folders : files).add(entry);
        } catch (_) {
          continue;
        }
      }
    } on FileSystemException {
      return DirectoryListResponse(
        path: targetPath,
        parentPath: _parentOf(targetPath),
        entries: const [],
        total: 0,
        page: page,
        pageSize: pageSize,
        hasMore: false,
        error: "Couldn't read this folder — it may be restricted by Android, "
            "or storage permission hasn't been granted yet.",
      );
    }

    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final combined = [...folders, ...files];

    final total = combined.length;
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, total);
    final pageEntries = start < total ? combined.sublist(start, end) : <FolderEntry>[];

    for (final entry in pageEntries) {
      if (!entry.isDirectory) _fsFileCache[entry.id] = File(entry.path);
    }

    return DirectoryListResponse(
      path: targetPath,
      parentPath: _parentOf(targetPath),
      entries: pageEntries,
      total: total,
      page: page,
      pageSize: pageSize,
      hasMore: end < total,
    );
  }

  String _fsIdFor(String path) => 'fs_${path.hashCode}';

  /// Null at the storage root (nothing to navigate up to).
  String? _parentOf(String path) {
    final normalized = path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
    if (normalized == storageRootPath || normalized.isEmpty) return null;
    final idx = normalized.lastIndexOf('/');
    if (idx <= 0) return null;
    final parent = normalized.substring(0, idx);
    return parent.length < storageRootPath.length ? null : parent;
  }

  // ─── Search ───

  Future<PagedFilesResponse> search(SearchRequest request) async {
    // Pull a reasonably large window from both sources and filter in-memory —
    // acceptable for a phone-local file count; avoids reimplementing MediaStore
    // query building for the (small) filename/date/folder filter surface.
    final gallery = await _allGalleryFiles();
    final downloads = await listDownloads(page: 1, pageSize: 500);

    final all = [...gallery, ...downloads.files];
    final query = request.query.toLowerCase();

    Iterable<FileItem> filtered;
    switch (request.type) {
      case 'date':
        filtered = all.where((f) => f.createdAt.startsWith(query) || f.modifiedAt.startsWith(query));
        break;
      case 'folder':
        filtered = all.where((f) => f.path.toLowerCase().contains(query));
        break;
      case 'filename':
      default:
        filtered = all.where((f) => f.name.toLowerCase().contains(query));
    }

    final results = filtered.toList();
    final page = request.page;
    final pageSize = request.pageSize;
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, results.length);
    final pageResults = start < results.length ? results.sublist(start, end) : <FileItem>[];

    return PagedFilesResponse(
      files: pageResults,
      total: results.length,
      page: page,
      pageSize: pageSize,
      hasMore: end < results.length,
    );
  }

  Future<List<FileItem>> _allGalleryFiles() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: _newestFirst,
    );
    if (paths.isEmpty) return [];
    final all = paths.first;
    final count = await all.assetCountAsync;
    final assets = await all.getAssetListPaged(page: 0, size: count);
    final items = <FileItem>[];
    for (final asset in assets) {
      _assetCache[asset.id] = asset;
      items.add(await _toFileItem(asset));
    }
    return items;
  }

  // ─── File resolution (used by file_stream_service) ───

  /// Resolves a `fileId` (from either the gallery cache or the downloads
  /// cache) to an absolute path readable via `dart:io`.
  Future<String?> resolveFilePath(String fileId) async {
    final fsFile = _fsFileCache[fileId];
    if (fsFile != null) return fsFile.path;

    final downloadFile = _downloadFileCache[fileId];
    if (downloadFile != null) return downloadFile.path;

    final asset = _assetCache[fileId];
    if (asset != null) {
      final file = await asset.file;
      return file?.path;
    }
    return null;
  }

  Future<AssetEntity?> resolveAsset(String fileId) async {
    return _assetCache[fileId];
  }

  /// Registers an asset under `fileId` — used after delete/rename/edit
  /// operations produce a new or updated [AssetEntity] that subsequent
  /// requests need to resolve without waiting for the next full listing.
  void cacheAsset(String fileId, AssetEntity asset) {
    _assetCache[fileId] = asset;
  }

  /// Drops a stale cache entry — used after delete/rename so a lingering
  /// reference to the old asset can't be resolved anymore.
  void invalidateAsset(String fileId) {
    _assetCache.remove(fileId);
  }

  /// Public wrapper around [_toFileItem] — used by file_stream_service to
  /// build the updated FileItem returned in rename/edit responses.
  Future<FileItem> toFileItem(AssetEntity asset) => _toFileItem(asset);

  Future<FileItem> _toFileItem(AssetEntity asset) async {
    final file = await asset.file;
    final size = await file?.length() ?? 0;
    return FileItem(
      id: asset.id,
      name: asset.title ?? asset.id,
      path: file?.path ?? '',
      size: size,
      mimeType: asset.mimeType ?? _guessMimeType(asset.title ?? ''),
      width: asset.width,
      height: asset.height,
      duration: asset.type == AssetType.video ? asset.duration * 1000 : null,
      createdAt: asset.createDateTime.toIso8601String(),
      modifiedAt: asset.modifiedDateTime.toIso8601String(),
    );
  }

  String _guessMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'mp4': 'video/mp4',
      '3gp': 'video/3gpp',
      'webm': 'video/webm',
      'mov': 'video/quicktime',
      'pdf': 'application/pdf',
      'zip': 'application/zip',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[ext] ?? 'application/octet-stream';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
