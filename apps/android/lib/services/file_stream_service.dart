import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/constants.dart';
import '../core/models.dart';
import 'media_service.dart';

/// Handles `file:request` / `file:thumbnail-request` by reading the resolved
/// file straight off disk and streaming it back in FILE_CONSTANTS.chunkSize
/// (64KB) slices. Nothing is ever written to a temp/cache copy first — bytes
/// are read and emitted directly, and never persisted server-side either
/// (see relay.gateway.ts, which only relays chunks through, it never stores).
class FileStreamService {
  final io.Socket socket;
  final MediaService mediaService;

  FileStreamService({required this.socket, required this.mediaService});

  Future<void> handleFileRequest(FileRequestPayload request) async {
    try {
      final path = await mediaService.resolveFilePath(request.fileId);
      if (path == null) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'File not found on device');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'File no longer exists on device');
        return;
      }

      final length = await file.length();
      if (length > FileConstants.maxFileSize) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileTooLarge,
            'File exceeds maximum transferable size');
        return;
      }

      final mimeType = _guessMimeType(path);
      final fileName = file.uri.pathSegments.last;
      final totalChunks = (length / FileConstants.chunkSize).ceil().clamp(1, 1 << 31);

      var chunkIndex = 0;
      final stream = file.openRead();
      var buffer = BytesBuilder();

      await for (final part in stream) {
        buffer.add(part);
        while (buffer.length >= FileConstants.chunkSize) {
          final bytes = buffer.takeBytes();
          final chunk = bytes.sublist(0, FileConstants.chunkSize);
          final rest = bytes.sublist(FileConstants.chunkSize);
          buffer = BytesBuilder()..add(rest);

          _emitChunk(
            fileId: request.fileId,
            clientSocketId: request.clientSocketId,
            chunkIndex: chunkIndex,
            totalChunks: totalChunks,
            data: chunk,
            mimeType: mimeType,
            fileName: fileName,
          );
          chunkIndex++;
        }
      }

      if (buffer.length > 0) {
        _emitChunk(
          fileId: request.fileId,
          clientSocketId: request.clientSocketId,
          chunkIndex: chunkIndex,
          totalChunks: totalChunks,
          data: buffer.takeBytes(),
          mimeType: mimeType,
          fileName: fileName,
        );
        chunkIndex++;
      }

      socket.emit(SocketEvents.fileComplete, {
        'fileId': request.fileId,
        '_clientSocketId': request.clientSocketId,
      });
    } catch (e) {
      _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError, e.toString());
    }
  }

  Future<void> handleThumbnailRequest(ThumbnailRequestPayload request) async {
    try {
      final asset = await mediaService.resolveAsset(request.fileId);
      final width = request.width ?? FileConstants.thumbnailWidth;
      final height = request.height ?? FileConstants.thumbnailHeight;
      Uint8List? thumbBytes;

      if (asset != null && asset.type == AssetType.video) {
        // No direct file-based path for video frames — this is the only
        // asset kind that has to go through photo_manager's thumbnail API.
        thumbBytes = await asset.thumbnailDataWithSize(ThumbnailSize(width, height));
        if (thumbBytes != null) {
          // Some OEMs (observed on Vivo/some Xiaomi devices) return WebP
          // bytes from thumbnailDataWithSize even though ThumbnailFormat.jpeg
          // is the default — the web client builds the preview Blob as
          // image/jpeg, so a mislabeled WebP payload silently fails to decode
          // in the browser with no error anywhere. Re-encode to guarantee
          // the bytes are actually JPEG regardless of source format.
          thumbBytes = await FlutterImageCompress.compressWithList(
            thumbBytes,
            minWidth: width,
            minHeight: height,
            quality: FileConstants.thumbnailQuality,
            format: CompressFormat.jpeg,
          );
        }
      } else {
        // Images (gallery or Downloads-folder): compress directly from the
        // real source file instead of trusting photo_manager's OEM-backed
        // thumbnail cache — sidesteps the WebP-mislabeled-as-JPEG bug at the
        // root rather than papering over its output.
        final path = asset != null
            ? (await asset.file)?.path
            : await mediaService.resolveFilePath(request.fileId);
        if (path != null) {
          thumbBytes = await FlutterImageCompress.compressWithFile(
            path,
            minWidth: width,
            minHeight: height,
            quality: FileConstants.thumbnailQuality,
            format: CompressFormat.jpeg,
          );
        }
      }

      if (thumbBytes == null) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'Could not generate thumbnail');
        return;
      }

      // Plugin-returned Uint8Lists can be views into a larger native buffer
      // with a nonzero offsetInBytes. Something downstream in the socket
      // binary-attachment path reads the raw underlying buffer rather than
      // respecting that view's offset/length, leaking a few bytes from
      // before the real data onto the front of every thumbnail (observed:
      // a constant 5-byte garbage prefix ahead of a perfectly valid JPEG
      // header). Copying into a fresh, offset-0 Uint8List guarantees there's
      // nothing before byte 0 for that code path to leak.
      thumbBytes = Uint8List.fromList(thumbBytes);

      socket.emit(SocketEvents.fileThumbnailResponse, {
        'fileId': request.fileId,
        'data': thumbBytes,
        '_clientSocketId': request.clientSocketId,
      });
    } catch (e) {
      _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError, e.toString());
    }
  }

  /// Moves an asset to the system trash (recoverable, matches native Gallery
  /// "Delete" behavior) — falls back to a permanent delete on API
  /// levels/OEMs where trash isn't available (moveToTrash requires
  /// Android 11+; deleteWithIds still needs system delete-confirmation UI
  /// which photo_manager handles internally).
  Future<void> handleDeleteRequest(DeleteRequestPayload request) async {
    try {
      final asset = await mediaService.resolveAsset(request.fileId);
      if (asset == null) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'File not found on device');
        return;
      }

      if (Platform.isAndroid) {
        try {
          await PhotoManager.editor.android.moveToTrash([asset]);
        } catch (_) {
          await PhotoManager.editor.deleteWithIds([asset.id]);
        }
      } else {
        await PhotoManager.editor.deleteWithIds([asset.id]);
      }

      mediaService.invalidateAsset(request.fileId);

      socket.emit(SocketEvents.fileDeleteResponse, {
        'fileId': request.fileId,
        '_clientSocketId': request.clientSocketId,
      });
    } catch (e) {
      _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError, e.toString());
    }
  }

  /// Renames the underlying file on disk. photo_manager (as of the version
  /// pinned in pubspec.yaml) has no MediaStore rename API, so this renames
  /// the file directly and purges photo_manager's stale cache entry —
  /// MediaStore picks up the new name from the filesystem on its next scan,
  /// and clearing the cache forces this app's own listings to reflect it
  /// immediately rather than waiting for that scan.
  Future<void> handleRenameRequest(RenameRequestPayload request) async {
    try {
      final path = await mediaService.resolveFilePath(request.fileId);
      if (path == null) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'File not found on device');
        return;
      }

      final file = File(path);
      if (!await file.exists()) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'File no longer exists on device');
        return;
      }

      final dotIndex = file.path.lastIndexOf('.');
      final ext = dotIndex >= 0 ? file.path.substring(dotIndex) : '';
      final requestedName = request.newName.trim();
      final sanitized = requestedName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final hasExt = ext.isNotEmpty && sanitized.toLowerCase().endsWith(ext.toLowerCase());
      final finalName = hasExt || ext.isEmpty ? sanitized : '$sanitized$ext';

      final slashIndex = file.path.lastIndexOf('/');
      final dirPath = slashIndex >= 0 ? file.path.substring(0, slashIndex) : '';
      final newPath = '$dirPath/$finalName';

      if (await File(newPath).exists()) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError,
            'A file named "$finalName" already exists');
        return;
      }

      await file.rename(newPath);
      await PhotoManager.editor.android.removeAllNoExistsAsset();
      mediaService.invalidateAsset(request.fileId);

      socket.emit(SocketEvents.fileRenameResponse, {
        'fileId': request.fileId,
        'newName': finalName,
        '_clientSocketId': request.clientSocketId,
      });
    } catch (e) {
      _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError, e.toString());
    }
  }

  /// Applies rotate/crop/brightness-contrast and saves the result.
  /// photo_manager's saveImage always creates a NEW MediaStore asset rather
  /// than overwriting in place (a scoped-storage restriction), so this
  /// deletes the original after the edited copy is saved successfully — net
  /// effect matches "overwrite," but the fileId changes, which the response
  /// carries back so the client can update its reference.
  Future<void> handleEditRequest(EditRequestPayload request) async {
    try {
      final asset = await mediaService.resolveAsset(request.fileId);
      final path = await mediaService.resolveFilePath(request.fileId);
      if (asset == null || path == null || asset.type != AssetType.image) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'Image not found on device, or edit is only supported for photos');
        return;
      }

      final bytes = await File(path).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError,
            'Could not decode image');
        return;
      }

      if (request.rotateDegrees != null && request.rotateDegrees != 0) {
        image = img.copyRotate(image, angle: request.rotateDegrees!);
      }

      if (request.cropWidth != null && request.cropHeight != null) {
        final x = ((request.cropX ?? 0) * image.width).round().clamp(0, image.width - 1);
        final y = ((request.cropY ?? 0) * image.height).round().clamp(0, image.height - 1);
        final w = (request.cropWidth! * image.width).round().clamp(1, image.width - x);
        final h = (request.cropHeight! * image.height).round().clamp(1, image.height - y);
        image = img.copyCrop(image, x: x, y: y, width: w, height: h);
      }

      if (request.brightness != null || request.contrast != null) {
        image = img.adjustColor(
          image,
          brightness: request.brightness ?? 1.0,
          contrast: request.contrast ?? 1.0,
        );
      }

      final ext = _guessMimeType(path) == 'image/png' ? 'png' : 'jpg';
      final encoded = ext == 'png' ? img.encodePng(image) : img.encodeJpg(image, quality: 92);
      final title = asset.title ?? 'edited.$ext';

      final newAsset = await PhotoManager.editor.saveImage(
        Uint8List.fromList(encoded),
        filename: title,
        title: title,
      );

      // Best-effort — the edit already succeeded and saved; failing to
      // clean up the original shouldn't fail the whole operation.
      try {
        if (Platform.isAndroid) {
          await PhotoManager.editor.android.moveToTrash([asset]);
        } else {
          await PhotoManager.editor.deleteWithIds([asset.id]);
        }
      } catch (_) {}

      mediaService.invalidateAsset(request.fileId);
      mediaService.cacheAsset(newAsset.id, newAsset);
      final newFile = await mediaService.toFileItem(newAsset);

      socket.emit(SocketEvents.fileEditResponse, {
        'fileId': request.fileId,
        'newFile': newFile.toJson(),
        '_clientSocketId': request.clientSocketId,
      });
    } catch (e) {
      _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileStreamError, e.toString());
    }
  }

  void _emitChunk({
    required String fileId,
    required String clientSocketId,
    required int chunkIndex,
    required int totalChunks,
    required Uint8List data,
    required String mimeType,
    required String fileName,
  }) {
    socket.emit(SocketEvents.fileChunk, {
      'fileId': fileId,
      'chunkIndex': chunkIndex,
      'totalChunks': totalChunks,
      'data': data,
      'mimeType': mimeType,
      'fileName': fileName,
      '_clientSocketId': clientSocketId,
    });
  }

  void _emitError(String fileId, String clientSocketId, String code, String message) {
    socket.emit(SocketEvents.fileError, {
      'fileId': fileId,
      'code': code,
      'message': message,
      '_clientSocketId': clientSocketId,
    });
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
