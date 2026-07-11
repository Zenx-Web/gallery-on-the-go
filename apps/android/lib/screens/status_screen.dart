import 'package:flutter/material.dart';

import '../services/device_registration_service.dart';
import '../services/media_service.dart';
import '../services/socket_service.dart';
import 'connect_screen.dart';

/// Home screen: shows live connection status (mirrors the web app's
/// DeviceStatus enum — packages/shared/src/types.ts) and owns the
/// SocketService for as long as the app is alive.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final _registrationService = DeviceRegistrationService();
  final _mediaService = MediaService();

  SocketService? _socketService;
  ConnectionStatus _status = ConnectionStatus.connecting;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final serverUrl = await _registrationService.getServerUrl();
    final credentials = await _registrationService.registerOrLoad();

    final service = SocketService(
      serverUrl: serverUrl,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      mediaService: _mediaService,
    );

    service.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });

    setState(() {
      _socketService = service;
      _deviceId = credentials.deviceId;
    });

    service.connect();
  }

  @override
  void dispose() {
    _socketService?.dispose();
    super.dispose();
  }

  Future<void> _forgetDevice() async {
    _socketService?.dispose();
    await _registrationService.clearCredentials();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectScreen()),
    );
  }

  (Color, String) get _statusVisual => switch (_status) {
        ConnectionStatus.online => (Colors.green, 'Online'),
        ConnectionStatus.connecting => (Colors.amber, 'Connecting'),
        ConnectionStatus.offline => (Colors.red, 'Offline'),
      };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusVisual;

    return Scaffold(
      appBar: AppBar(title: const Text('GalleryOnTheGo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 12),
                      Text(label, style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_deviceId != null)
                ListTile(
                  title: const Text('Device ID'),
                  subtitle: Text(_deviceId!),
                ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _socketService?.connect(),
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _forgetDevice,
                icon: const Icon(Icons.logout),
                label: const Text('Forget this device'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
