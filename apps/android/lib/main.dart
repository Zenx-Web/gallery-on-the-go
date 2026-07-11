import 'package:flutter/material.dart';

import 'services/device_registration_service.dart';
import 'screens/connect_screen.dart';
import 'screens/status_screen.dart';

void main() {
  runApp(const GalleryOnTheGoApp());
}

class GalleryOnTheGoApp extends StatelessWidget {
  const GalleryOnTheGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GalleryOnTheGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _StartupGate(),
    );
  }
}

/// If credentials are already persisted, skip straight to StatusScreen (and
/// auto-connect there); otherwise show the first-run ConnectScreen.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: DeviceRegistrationService().loadPersistedCredentials(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data != null ? const StatusScreen() : const ConnectScreen();
      },
    );
  }
}
