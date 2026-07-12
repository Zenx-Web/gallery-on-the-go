/// Mirrors packages/shared/src/types.ts — field names/casing match the
/// TypeScript interfaces exactly since these payloads cross the wire as-is.
library;

enum DeviceStatus { online, connecting, offline }

class FileItem {
  final String id;
  final String name;
  final String path;
  final int size;
  final String mimeType;
  final int? width;
  final int? height;
  final int? duration; // video duration in ms
  final String? thumbnailId;
  final String createdAt;
  final String modifiedAt;

  FileItem({
    required this.id,
    required this.name,
    required this.path,
    required this.size,
    required this.mimeType,
    this.width,
    this.height,
    this.duration,
    this.thumbnailId,
    required this.createdAt,
    required this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'size': size,
        'mimeType': mimeType,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (duration != null) 'duration': duration,
        if (thumbnailId != null) 'thumbnailId': thumbnailId,
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
      };
}

class GalleryAlbum {
  final String id;
  final String name;
  final String? coverThumbnailId;
  final int fileCount;

  GalleryAlbum({
    required this.id,
    required this.name,
    this.coverThumbnailId,
    required this.fileCount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (coverThumbnailId != null) 'coverThumbnailId': coverThumbnailId,
        'fileCount': fileCount,
      };
}

class GalleryListResponse {
  final List<GalleryAlbum> albums;
  final int totalFiles;

  GalleryListResponse({required this.albums, required this.totalFiles});

  Map<String, dynamic> toJson() => {
        'albums': albums.map((a) => a.toJson()).toList(),
        'totalFiles': totalFiles,
      };
}

class PagedFilesResponse {
  final List<FileItem> files;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  PagedFilesResponse({
    required this.files,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  Map<String, dynamic> toJson() => {
        'files': files.map((f) => f.toJson()).toList(),
        'total': total,
        'page': page,
        'pageSize': pageSize,
        'hasMore': hasMore,
      };
}

class SearchRequest {
  final String query;
  final String? type; // 'filename' | 'date' | 'folder'
  final int page;
  final int pageSize;

  SearchRequest({
    required this.query,
    this.type,
    required this.page,
    required this.pageSize,
  });

  factory SearchRequest.fromJson(Map<String, dynamic> json) => SearchRequest(
        query: json['query'] as String,
        type: json['type'] as String?,
        page: (json['page'] as num?)?.toInt() ?? 1,
        pageSize: (json['pageSize'] as num?)?.toInt() ?? 50,
      );
}

class FileRequestPayload {
  final String fileId;
  final String deviceId;
  final String clientSocketId;

  FileRequestPayload({
    required this.fileId,
    required this.deviceId,
    required this.clientSocketId,
  });

  factory FileRequestPayload.fromJson(Map<String, dynamic> json) =>
      FileRequestPayload(
        fileId: json['fileId'] as String,
        deviceId: json['deviceId'] as String,
        clientSocketId: json['_clientSocketId'] as String,
      );
}

class DeleteRequestPayload {
  final String fileId;
  final String deviceId;
  final String clientSocketId;

  DeleteRequestPayload({
    required this.fileId,
    required this.deviceId,
    required this.clientSocketId,
  });

  factory DeleteRequestPayload.fromJson(Map<String, dynamic> json) =>
      DeleteRequestPayload(
        fileId: json['fileId'] as String,
        deviceId: json['deviceId'] as String,
        clientSocketId: json['_clientSocketId'] as String,
      );
}

class RenameRequestPayload {
  final String fileId;
  final String deviceId;
  final String newName;
  final String clientSocketId;

  RenameRequestPayload({
    required this.fileId,
    required this.deviceId,
    required this.newName,
    required this.clientSocketId,
  });

  factory RenameRequestPayload.fromJson(Map<String, dynamic> json) =>
      RenameRequestPayload(
        fileId: json['fileId'] as String,
        deviceId: json['deviceId'] as String,
        newName: json['newName'] as String,
        clientSocketId: json['_clientSocketId'] as String,
      );
}

/// Edit operations are applied in order: rotate, then crop, then
/// brightness/contrast. All fields optional — omit an op to skip it.
/// Crop coordinates are normalized (0.0-1.0) relative to the source image.
/// brightness/contrast are multipliers where 1.0 means "unchanged" (matches
/// the `image` package's `adjustColor` semantics directly).
class EditRequestPayload {
  final String fileId;
  final String deviceId;
  final int? rotateDegrees;
  final double? cropX;
  final double? cropY;
  final double? cropWidth;
  final double? cropHeight;
  final double? brightness;
  final double? contrast;
  final String clientSocketId;

  EditRequestPayload({
    required this.fileId,
    required this.deviceId,
    this.rotateDegrees,
    this.cropX,
    this.cropY,
    this.cropWidth,
    this.cropHeight,
    this.brightness,
    this.contrast,
    required this.clientSocketId,
  });

  factory EditRequestPayload.fromJson(Map<String, dynamic> json) =>
      EditRequestPayload(
        fileId: json['fileId'] as String,
        deviceId: json['deviceId'] as String,
        rotateDegrees: (json['rotateDegrees'] as num?)?.toInt(),
        cropX: (json['cropX'] as num?)?.toDouble(),
        cropY: (json['cropY'] as num?)?.toDouble(),
        cropWidth: (json['cropWidth'] as num?)?.toDouble(),
        cropHeight: (json['cropHeight'] as num?)?.toDouble(),
        brightness: (json['brightness'] as num?)?.toDouble(),
        contrast: (json['contrast'] as num?)?.toDouble(),
        clientSocketId: json['_clientSocketId'] as String,
      );
}

class ThumbnailRequestPayload {
  final String fileId;
  final String deviceId;
  final int? width;
  final int? height;
  final String clientSocketId;

  ThumbnailRequestPayload({
    required this.fileId,
    required this.deviceId,
    this.width,
    this.height,
    required this.clientSocketId,
  });

  factory ThumbnailRequestPayload.fromJson(Map<String, dynamic> json) =>
      ThumbnailRequestPayload(
        fileId: json['fileId'] as String,
        deviceId: json['deviceId'] as String,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        clientSocketId: json['_clientSocketId'] as String,
      );
}
