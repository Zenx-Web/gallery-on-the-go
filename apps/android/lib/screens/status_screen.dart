import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/media_service.dart';
import 'gallery_home_screen.dart';

/// Shown once (tracked via SharedPreferences) to point the user at their
/// phone's OEM-specific autostart/background-restriction toggle — Vivo,
/// Xiaomi, Oppo and similar ship a proprietary battery manager on top of
/// stock Android that throttles background network access with no public
/// API to grant an exemption for, so the standard
/// ignoreBatteryOptimizations request alone isn't always enough.
const _oemHintShownKey = 'oem_autostart_hint_shown';

/// Main screen — the WebSocket connection runs in the background service
/// isolate, silently. No connection status is surfaced in this UI; the
/// relay just works or it doesn't, and the user interacts with their photos
/// either way.
class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  final _mediaService = MediaService();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Requested first — the background service's foreground notification
    // (background_service.dart, isForegroundMode: true) needs this granted
    // on Android 13+ or it silently fails to display.
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    await _mediaService.ensurePermission();
    if (await Permission.manageExternalStorage.isDenied) {
      await Permission.manageExternalStorage.request();
    }
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }
    await _maybeShowOemAutostartHint();
  }

  Future<void> _maybeShowOemAutostartHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_oemHintShownKey) ?? false) return;
    await prefs.setBool(_oemHintShownKey, true);

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 8),
          content: Text(
            'For the most reliable background connection, also allow '
            'auto-start and disable background restrictions for this app '
            "in your phone's battery settings.",
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GalleryOnTheGo')),
      body: const SafeArea(
        child: GalleryHomeScreen(),
      ),
    );
  }
}
