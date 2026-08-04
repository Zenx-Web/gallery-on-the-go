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
      // Static, generic content — Android requires a visible notification
      // for a foreground service, but it doesn't need to expose live
      // connection state (previously "Connected — panel is live" /
      // "Disconnected from panel", updated on every status change).
      initialNotificationTitle: 'StudyVault',
      initialNotificationContent: 'Running in background',
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
  final registrationService = DeviceRegistrationService();
  final mediaService = MediaService();
  SocketService? socketService;

  // Cached so a UI isolate that starts listening after registration
  // already happened (the common case — the service auto-starts before
  // any screen exists) can still ask for the current status on demand.
  Map<String, dynamic> lastStatus = {'state': 'connecting'};
  service.on('get_device_status').listen((_) => service.invoke('device_status', lastStatus));

  Future<void> connect({int attempt = 1}) async {
    try {
      final serverUrl = await registrationService.getServerUrl();
      final credentials = await registrationService.registerOrLoad();

      lastStatus = {'state': 'registered', 'isNew': credentials.isNew};
      service.invoke('device_status', lastStatus);

      socketService = SocketService(
        serverUrl: serverUrl,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        mediaService: mediaService,
        onAuthFailed: () async {
          // The server rejected our token — the device was likely removed from
          // the web dashboard. Clear stale credentials so the next connect()
          // call triggers a fresh registration.
          await registrationService.clearCredentials();
          lastStatus = {'state': 'connecting'};
          service.invoke('device_status', lastStatus);
          // Small delay before retrying so the server-side delete can propagate.
          await Future.delayed(const Duration(seconds: 3));
          await connect();
        },
      );
      socketService!.connect();

      // Register FCM token and wire up the remote-wake handler.
      await initFcmHandler(
        service: service,
        deviceId: credentials.deviceId,
        deviceToken: credentials.deviceToken,
        serverUrl: serverUrl,
      );
    } catch (e) {
      lastStatus = {'state': 'error', 'message': e.toString()};
      service.invoke('device_status', lastStatus);
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'GalleryOnTheGo',
          content: 'Error: $e',
        );
      }

      // Auto-retry with exponential backoff (caps at 60s).
      final delay = Duration(seconds: attempt.clamp(1, 6) * 10);
      await Future.delayed(delay);
      await connect(attempt: attempt + 1);
    }
  }

  // Reconnect signal — sent by FCM handler or UI isolate when a wake push
  // arrives. If the socket service was never initialized (e.g. startup
  // failed before socketService was assigned), fall back to a full connect().
  service.on('reconnect').listen((_) {
    if (socketService != null) {
      socketService!.reconnect();
    } else {
      connect();
    }
  });

  // Sent from the UI when the user taps "Retry" on a registration error —
  // registration/socket setup never ran past the failure point, so a plain
  // socket reconnect wouldn't help; re-run the whole connect sequence.
  service.on('retry_registration').listen((_) => connect());

  await connect();
}
