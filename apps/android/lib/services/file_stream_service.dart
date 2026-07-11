import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:photo_manager/photo_manager.dart' show ThumbnailSize;
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
      Uint8List? thumbBytes;

      if (asset != null) {
        thumbBytes = await asset.thumbnailDataWithSize(
          ThumbnailSize(
            request.width ?? FileConstants.thumbnailWidth,
            request.height ?? FileConstants.thumbnailHeight,
          ),
        );
      } else {
        // Downloads-folder file: only meaningful for image types.
        final path = await mediaService.resolveFilePath(request.fileId);
        if (path != null) {
          thumbBytes = await FlutterImageCompress.compressWithFile(
            path,
            minWidth: request.width ?? FileConstants.thumbnailWidth,
            minHeight: request.height ?? FileConstants.thumbnailHeight,
            quality: FileConstants.thumbnailQuality,
          );
        }
      }

      if (thumbBytes == null) {
        _emitError(request.fileId, request.clientSocketId, ErrorCodes.fileNotFound,
            'Could not generate thumbnail');
        return;
      }

      socket.emit(SocketEvents.fileThumbnailResponse, {
        'fileId': request.fileId,
        'data': thumbBytes,
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
