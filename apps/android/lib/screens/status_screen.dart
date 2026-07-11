import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/device_registration_service.dart';
import '../services/media_service.dart';
import '../services/socket_service.dart';
import 'local_gallery_screen.dart';

/// Main screen: runs the WebSocket connection silently in the background
/// while presenting a simple, clean local gallery UI on the frontend.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final _registrationService = DeviceRegistrationService();
  final _mediaService = MediaService();

  SocketService? _socketService;
  String? _backgroundError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _backgroundError = null);
    try {
      // 1. Ensure permissions
      final mediaGranted = await _mediaService.ensurePermission();
      if (!mediaGranted) return;

      // Request Manage External Storage (Downloads folder)
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }

      // 2. Auto register/load credentials
      final serverUrl = await _registrationService.getServerUrl();
      final credentials = await _registrationService.registerOrLoad();

      // 3. Start socket service in the background
      final service = SocketService(
        serverUrl: serverUrl,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        mediaService: _mediaService,
      );

      if (mounted) {
        setState(() {
          _socketService = service;
        });
      }

      service.connect();
    } catch (e) {
      // Doesn't block the local gallery UI, but the panel connection is
      // surfaced via the AppBar indicator below instead of failing silently.
      if (mounted) {
        setState(() => _backgroundError = e.toString());
      }
    }
  }

  @override
  void dispose() {
    _socketService?.dispose();
    super.dispose();
  }

  Widget _buildConnectionIndicator() {
    if (_backgroundError != null) {
      return IconButton(
        icon: const Icon(Icons.cloud_off, color: Colors.redAccent),
        tooltip: 'Panel connection failed. Tap to retry.',
        onPressed: _init,
      );
    }
    if (_socketService == null) {
      return const SizedBox(width: 48);
    }
    return StreamBuilder<ConnectionStatus>(
      stream: _socketService!.statusStream,
      initialData: _socketService!.status,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ConnectionStatus.offline;
        switch (status) {
          case ConnectionStatus.online:
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.cloud_done, color: Colors.greenAccent, size: 20),
            );
          case ConnectionStatus.connecting:
            return const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          case ConnectionStatus.offline:
            return IconButton(
              icon: const Icon(Icons.cloud_off, color: Colors.white38),
              tooltip: 'Not connected to panel. Tap to retry.',
              onPressed: _init,
            );
        }
      },
    );
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
