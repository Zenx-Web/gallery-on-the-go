import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../core/constants.dart';
import '../core/models.dart';
import 'file_stream_service.dart';
import 'media_service.dart';

enum ConnectionStatus { offline, connecting, online }

/// Owns the single Socket.IO connection to the server's `/device` namespace
/// (server/src/modules/relay/relay.gateway.ts), keeps it alive with a
/// heartbeat + auto-reconnect, and dispatches every inbound relay event to
/// the media/file-stream services — always echoing `_clientSocketId` back on
/// the response, since the server strips it before forwarding to the browser.
class SocketService {
  final String serverUrl;
  final String deviceId;
  final String deviceToken;
  final MediaService mediaService;

  /// Called when the server explicitly rejects this device's token
  /// (e.g. the device was removed from the web dashboard).
  /// The caller should clear persisted credentials and re-register.
  final Future<void> Function()? onAuthFailed;

  io.Socket? _socket;
  FileStreamService? _fileStreamService;
  Timer? _heartbeatTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus _status = ConnectionStatus.offline;
  ConnectionStatus get status => _status;

  SocketService({
    required this.serverUrl,
    required this.deviceId,
    required this.deviceToken,
    required this.mediaService,
    this.onAuthFailed,
  });

  void connect() {
    _setStatus(ConnectionStatus.connecting);

    final socket = io.io(
      '$serverUrl/device',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': deviceToken})
          .enableReconnection()
          .setReconnectionDelay(Timeouts.reconnectDelayMs)
          .setReconnectionAttempts(Timeouts.maxReconnectAttempts)
          .build(),
    );
    _socket = socket;
    _fileStreamService = FileStreamService(socket: socket, mediaService: mediaService);

    socket.onConnect((_) {
      _setStatus(ConnectionStatus.online);
      _startHeartbeat();
    });

    socket.onDisconnect((_) {
      _setStatus(ConnectionStatus.offline);
      _stopHeartbeat();
    });

    socket.onReconnectAttempt((_) => _setStatus(ConnectionStatus.connecting));
    socket.onConnectError((err) {
      _setStatus(ConnectionStatus.connecting);
      // If the server explicitly rejected our token (device was deleted from
      // the web dashboard), stop retrying and notify the caller so it can
      // clear stale credentials and trigger a fresh registration.
      final message = err is Map ? err['message'] : err.toString();
      if (message != null &&
          (message.toString().contains('Invalid device token') ||
           message.toString().contains('Device token required'))) {
        _socket?.dispose();
        _setStatus(ConnectionStatus.offline);
        onAuthFailed?.call();
      }
    });

    _registerHandlers(socket);
    _watchConnectivity();

    socket.connect();
  }

  /// Forces an immediate reconnect attempt.
  /// Called by the background isolate when an FCM wake signal arrives.
  void reconnect() {
    if (_socket == null) {
      connect();
    } else if (!_socket!.connected) {
      // Dispose stale socket and create a fresh one — the old instance may
      // have exhausted its internal reconnection state or hold a dead TCP pipe.
      _stopHeartbeat();
      _connectivitySub?.cancel();
      _socket!.dispose();
      _socket = null;
      connect();
    }
    // If already connected, no-op.
  }

  void disconnect() {
    _stopHeartbeat();
    _connectivitySub?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _setStatus(ConnectionStatus.offline);
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    _statusController.add(status);
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      Duration(milliseconds: Timeouts.deviceHeartbeatIntervalMs),
      (_) => _socket?.emit(SocketEvents.deviceHeartbeat),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Forces a reconnect attempt as soon as connectivity is restored, rather
  /// than waiting for socket.io's own backoff timer to come around.
  void _watchConnectivity() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork && _socket != null && !_socket!.connected) {
        _socket!.connect();
      }
    });
  }

  void _registerHandlers(io.Socket socket) {
    socket.on(SocketEvents.galleryList, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final clientSocketId = map['_clientSocketId'] as String;
      final response = await mediaService.listAlbums();
      socket.emit(SocketEvents.galleryListResponse, {
        ...response.toJson(),
        '_clientSocketId': clientSocketId,
      });
    });

    socket.on(SocketEvents.galleryAlbums, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final clientSocketId = map['_clientSocketId'] as String;
      final response = await mediaService.listAlbums();
      socket.emit(SocketEvents.galleryAlbumsResponse, {
        ...response.toJson(),
        '_clientSocketId': clientSocketId,
      });
    });

    socket.on(SocketEvents.galleryAlbumFiles, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final clientSocketId = map['_clientSocketId'] as String;
      final response = await mediaService.listAlbumFiles(
        albumId: map['albumId'] as String,
        page: (map['page'] as num?)?.toInt() ?? Pagination.defaultPage,
        pageSize: (map['pageSize'] as num?)?.toInt() ?? Pagination.defaultPageSize,
      );
      socket.emit(SocketEvents.galleryAlbumFilesResponse, {
        ...response.toJson(),
        '_clientSocketId': clientSocketId,
      });
    });

    socket.on(SocketEvents.downloadsList, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final clientSocketId = map['_clientSocketId'] as String;
      final response = await mediaService.listDownloads(
        page: (map['page'] as num?)?.toInt() ?? Pagination.defaultPage,
        pageSize: (map['pageSize'] as num?)?.toInt() ?? Pagination.defaultPageSize,
      );
      socket.emit(SocketEvents.downloadsListResponse, {
        ...response.toJson(),
        '_clientSocketId': clientSocketId,
      });
    });

    socket.on(SocketEvents.folderList, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final clientSocketId = map['_clientSocketId'] as String;
      final response = await mediaService.listDirectory(
        path: map['path'] as String?,
        page: (map['page'] as num?)?.toInt() ?? Pagination.defaultPage,
        pageSize: (map['pageSize'] as num?)?.toInt() ?? Pagination.defaultPageSize,
      );
      socket.emit(SocketEvents.folderListResponse, {
        ...response.toJson(),
        '_clientSocketId': clientSocketId,
      });
    });

    socket.on(SocketEvents.searchQuery, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final clientSocketId = map['_clientSocketId'] as String;
      final request = SearchRequest.fromJson(map);
      final response = await mediaService.search(request);
      socket.emit(SocketEvents.searchResults, {
        ...response.toJson(),
        '_clientSocketId': clientSocketId,
      });
    });

    socket.on(SocketEvents.fileRequest, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final request = FileRequestPayload.fromJson(map);
      await _fileStreamService?.handleFileRequest(request);
    });

    socket.on(SocketEvents.fileThumbnailRequest, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final request = ThumbnailRequestPayload.fromJson(map);
      await _fileStreamService?.handleThumbnailRequest(request);
    });

    socket.on(SocketEvents.fileDelete, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final request = DeleteRequestPayload.fromJson(map);
      await _fileStreamService?.handleDeleteRequest(request);
    });

    socket.on(SocketEvents.fileRename, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final request = RenameRequestPayload.fromJson(map);
      await _fileStreamService?.handleRenameRequest(request);
    });

    socket.on(SocketEvents.fileEdit, (data) async {
      final map = Map<String, dynamic>.from(data as Map);
      final request = EditRequestPayload.fromJson(map);
      await _fileStreamService?.handleEditRequest(request);
    });
  }

  void dispose() {
    disconnect();
    _statusController.close();
  }
}
