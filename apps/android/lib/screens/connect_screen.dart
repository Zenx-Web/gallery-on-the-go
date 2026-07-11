import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/device_registration_service.dart';
import '../services/media_service.dart';
import 'status_screen.dart';

/// First-run screen: confirm the server URL, request media/downloads
/// permissions, register the device, then hand off to StatusScreen which
/// owns the actual socket connection.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _registrationService = DeviceRegistrationService();
  final _mediaService = MediaService();
  final _urlController = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _registrationService.getServerUrl().then((url) {
      if (mounted) setState(() => _urlController.text = url);
    });
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _registrationService.setServerUrl(_urlController.text.trim());

      final mediaGranted = await _mediaService.ensurePermission();
      if (!mediaGranted) {
        throw Exception('Photos & videos permission is required to browse your gallery.');
      }

      // Downloads folder access on Android 11+ requires "All files access".
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }

      await _registrationService.registerOrLoad();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StatusScreen()),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'GalleryOnTheGo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Connect this device to your GalleryOnTheGo server to browse your gallery and downloads remotely.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://gallery.example.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
