import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/media_service.dart';
import 'local_gallery_screen.dart';

/// Main screen — the WebSocket connection runs in the background service
/// isolate. This screen only reads status via IPC and shows the indicator.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

enum _ConnectionStatus { connecting, online, offline }

class _StatusScreenState extends State<StatusScreen> {
  final _mediaService = MediaService();
  _ConnectionStatus _status = _ConnectionStatus.connecting;
  StreamSubscription<Map<String, dynamic>?>? _statusSub;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _listenToBackgroundStatus();
  }

  Future<void> _requestPermissions() async {
    await _mediaService.ensurePermission();
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
  }

  void _listenToBackgroundStatus() {
    _statusSub = FlutterBackgroundService()
        .on('status')
        .listen((event) {
      if (!mounted) return;
      final raw = event?['status'] as String?;
      final next = switch (raw) {
        'online' => _ConnectionStatus.online,
        'connecting' => _ConnectionStatus.connecting,
        _ => _ConnectionStatus.offline,
      };
      setState(() => _status = next);
    });
  }

  void _sendReconnect() {
    FlutterBackgroundService().invoke('reconnect');
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  Widget _buildConnectionIndicator() {
    switch (_status) {
      case _ConnectionStatus.online:
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.cloud_done, color: Colors.greenAccent, size: 20),
        );
      case _ConnectionStatus.connecting:
        return const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _ConnectionStatus.offline:
        return IconButton(
          icon: const Icon(Icons.cloud_off, color: Colors.white38),
          tooltip: 'Disconnected — tap to reconnect',
          onPressed: _sendReconnect,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        centerTitle: true,
        elevation: 0,
        actions: [_buildConnectionIndicator()],
      ),
      body: const SafeArea(
        child: LocalGalleryScreen(),
      ),
    );
  }
}
