import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
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

  io.Socket? _socket;
  FileStreamService? _fileStreamService;
  Timer? _heartbeatTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  final _statusController = StreamController<ConnectionStatus>.broadcast();
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus _status = ConnectionStatus.offline;
  ConnectionStatus get status => _status;

  static const _channel = MethodChannel('com.zenxorg.gallery_on_the_go/foreground_service');

  Future<void> _startForegroundService() async {
    try {
      await _channel.invokeMethod('startService');
    } catch (e) {
      print('Failed to start foreground service: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      await _channel.invokeMethod('stopService');
    } catch (e) {
      print('Failed to stop foreground service: $e');
    }
  }

  SocketService({
    required this.serverUrl,
    required this.deviceId,
    required this.deviceToken,
    required this.mediaService,
  });

  void connect() {
    _setStatus(ConnectionStatus.connecting);
    _startForegroundService();

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
    socket.onConnectError((_) => _setStatus(ConnectionStatus.connecting));

    _registerHandlers(socket);
    _watchConnectivity();

    socket.connect();
  }

  void disconnect() {
    _stopHeartbeat();
    _connectivitySub?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _setStatus(ConnectionStatus.offline);
    _stopForegroundService();
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
  }

  void dispose() {
    disconnect();
    _statusController.close();
  }
}
