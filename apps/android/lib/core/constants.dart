/// Mirrors packages/shared/src/constants.ts — keep names/values identical
/// to the TypeScript source so the two are easy to diff against each other.
library;

class ApiRoutes {
  static const String devicesRegister = '/api/devices/register';
  static String devicesFcmToken(String id) => '/api/devices/$id/fcm-token';
}

class SocketEvents {
  // Connection
  static const String connect = 'connect';
  static const String disconnect = 'disconnect';
  static const String error = 'error';

  // Device namespace events
  static const String deviceRegister = 'device:register';
  static const String deviceHeartbeat = 'device:heartbeat';
  static const String deviceStatusChange = 'device:status-change';

  // Gallery events
  static const String galleryList = 'gallery:list';
  static const String galleryListResponse = 'gallery:list-response';
  static const String galleryAlbums = 'gallery:albums';
  static const String galleryAlbumsResponse = 'gallery:albums-response';
  static const String galleryAlbumFiles = 'gallery:album-files';
  static const String galleryAlbumFilesResponse = 'gallery:album-files-response';

  // Downloads events
  static const String downloadsList = 'downloads:list';
  static const String downloadsListResponse = 'downloads:list-response';

  // File streaming events
  static const String fileRequest = 'file:request';
  static const String fileChunk = 'file:chunk';
  static const String fileComplete = 'file:complete';
  static const String fileError = 'file:error';
  static const String fileThumbnailRequest = 'file:thumbnail-request';
  static const String fileThumbnailResponse = 'file:thumbnail-response';

  // Search events
  static const String searchQuery = 'search:query';
  static const String searchResults = 'search:results';
}

class Pagination {
  static const int defaultPage = 1;
  static const int defaultPageSize = 50;
  static const int maxPageSize = 200;
  static const int thumbnailBatchSize = 20;
}

class Timeouts {
  static const int deviceHeartbeatIntervalMs = 30000;
  static const int deviceOfflineThresholdMs = 90000;
  static const int fileStreamTimeoutMs = 120000;
  static const int reconnectDelayMs = 5000;
  static const int maxReconnectAttempts = 2147483647;
}

class FileConstants {
  static const int chunkSize = 64 * 1024; // 64KB
  static const int maxFileSize = 500 * 1024 * 1024; // 500MB
  static const int thumbnailWidth = 300;
  static const int thumbnailHeight = 300;
  static const int thumbnailQuality = 80;

  static const List<String> supportedImageTypes = [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
  ];

  static const List<String> supportedVideoTypes = [
    'video/mp4',
    'video/3gpp',
    'video/webm',
    'video/quicktime',
  ];
}

class ErrorCodes {
  static const String deviceNotFound = 'DEVICE_NOT_FOUND';
  static const String deviceOffline = 'DEVICE_OFFLINE';
  static const String deviceAlreadyRegistered = 'DEVICE_ALREADY_REGISTERED';

  static const String fileNotFound = 'FILE_NOT_FOUND';
  static const String fileTooLarge = 'FILE_TOO_LARGE';
  static const String fileStreamTimeout = 'FILE_STREAM_TIMEOUT';
  static const String fileStreamError = 'FILE_STREAM_ERROR';

  static const String internalError = 'INTERNAL_ERROR';
  static const String rateLimited = 'RATE_LIMITED';
  static const String validationError = 'VALIDATION_ERROR';
}
