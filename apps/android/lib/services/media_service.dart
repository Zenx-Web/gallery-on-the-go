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

  final Map<String, AssetEntity> _assetCache = {};
  final Map<String, File> _downloadFileCache = {};

  Future<bool> ensurePermission() async {
    final result = await PhotoManager.requestPermissionExtend();
    return result.isAuth || result.hasAccess;
  }

  // ─── Gallery ───

  Future<GalleryListResponse> listAlbums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
    );

    var totalFiles = 0;
    final albums = <GalleryAlbum>[];
    for (final path in paths) {
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
    // photo_manager pages are 0-indexed; our wire protocol is 1-indexed.
    final assets = await album.getAssetListPaged(page: page - 1, size: pageSize);

    final files = <FileItem>[];
    for (final asset in assets) {
      _assetCache[asset.id] = asset;
      files.add(await _toFileItem(asset));
    }

    return PagedFilesResponse(
      files: files,
      total: total,
      page: page,
      pageSize: pageSize,
      hasMore: (page - 1) * pageSize + assets.length < total,
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
