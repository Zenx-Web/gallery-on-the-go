import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';

import 'device_registration_service.dart';
import 'media_service.dart';
import 'socket_service.dart';
import 'fcm_handler.dart';

/// Configures and starts the background service.
/// Call this once from main() before runApp().
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      // Auto-start when the app is first launched, and on device boot
      // (via flutter_background_service's built-in BOOT_COMPLETED receiver).
      autoStart: true,
      isForegroundMode: true,
      // Channel is created natively in GalleryApplication.onCreate — the
      // plugin itself only auto-creates a channel for its own default id,
      // so a custom id here must be pre-registered or startForeground
      // throws CannotPostForegroundServiceNotificationException.
      notificationChannelId: 'gallery_relay_channel',
      initialNotificationTitle: 'GalleryOnTheGo',
      initialNotificationContent: 'Starting…',
      foregroundServiceNotificationId: 101,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );

  // Ensure the service is running (idempotent if already running).
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
  }
}

/// Background isolate entry point.
/// Annotated so the Dart compiler does not tree-shake it.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  _updateNotification(service, 'Connecting to panel…');

  final registrationService = DeviceRegistrationService();
  final mediaService = MediaService();

  try {
    final serverUrl = await registrationService.getServerUrl();
    final credentials = await registrationService.registerOrLoad();

    final socketService = SocketService(
      serverUrl: serverUrl,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      mediaService: mediaService,
    );

    // Mirror socket status into the notification and broadcast to UI isolate.
    socketService.statusStream.listen((status) {
      final label = switch (status) {
        ConnectionStatus.online => 'Connected — panel is live',
        ConnectionStatus.connecting => 'Connecting to panel…',
        ConnectionStatus.offline => 'Disconnected from panel',
      };
      _updateNotification(service, label);
      service.invoke('status', {'status': status.name});
    });

    socketService.connect();

    // Register FCM token and wire up the remote-wake handler.
    await initFcmHandler(
      service: service,
      deviceId: credentials.deviceId,
      deviceToken: credentials.deviceToken,
      serverUrl: serverUrl,
    );

    // Reconnect signal — sent by FCM handler or UI isolate.
    service.on('reconnect').listen((_) {
      socketService.reconnect();
    });
  } catch (e) {
    _updateNotification(service, 'Error: $e');
  }
}

void _updateNotification(ServiceInstance service, String content) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'GalleryOnTheGo',
      content: content,
    );
  }
}
