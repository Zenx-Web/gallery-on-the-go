import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';

/// Registers with FCM, uploads our token to the server, and wires up
/// the message listener that sends a 'reconnect' IPC event to the
/// background service isolate when a gallery_wake push arrives.
///
/// Must be called from within the background isolate ([onStart]).
Future<void> initFcmHandler({
  required ServiceInstance service,
  required String deviceId,
  required String deviceToken,
  required String serverUrl,
}) async {
  try {
    // Firebase must be initialised in every isolate that uses it.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    final messaging = FirebaseMessaging.instance;

    // Request permission (no-op on Android 12 and below; needed for 13+).
    await messaging.requestPermission(alert: false, badge: false, sound: false);

    // Upload current token.
    final token = await messaging.getToken();
    if (token != null) {
      await _registerFcmToken(
        serverUrl: serverUrl,
        deviceId: deviceId,
        deviceToken: deviceToken,
        fcmToken: token,
      );
    }

    // Keep token fresh — FCM rotates it occasionally.
    messaging.onTokenRefresh.listen((newToken) {
      _registerFcmToken(
        serverUrl: serverUrl,
        deviceId: deviceId,
        deviceToken: deviceToken,
        fcmToken: newToken,
      );
    });

    // Foreground FCM data message — forward reconnect signal to socket.
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['type'] == 'gallery_wake') {
        service.invoke('reconnect');
      }
    });
  } catch (e) {
    // FCM failure must not crash the socket service.
    print('[FCM] initFcmHandler error: $e');
  }
}

/// Top-level background FCM handler.
/// Called by Firebase when a data message arrives and the app is terminated.
/// Must be a top-level (not class) function annotated with vm:entry-point.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }

  if (message.data['type'] == 'gallery_wake') {
    final bgService = FlutterBackgroundService();
    final isRunning = await bgService.isRunning();
    if (isRunning) {
      // Background isolate is alive — tell it to reconnect.
      bgService.invoke('reconnect');
    } else {
      // Service was killed — restart it; onStart() will call socket.connect().
      await bgService.startService();
    }
  }
}

Future<void> _registerFcmToken({
  required String serverUrl,
  required String deviceId,
  required String deviceToken,
  required String fcmToken,
}) async {
  try {
    final uri = Uri.parse('$serverUrl${ApiRoutes.devicesFcmToken(deviceId)}');
    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-device-token': deviceToken,
      },
      body: jsonEncode({'fcmToken': fcmToken}),
    );
    if (response.statusCode == 200) {
      print('[FCM] Token registered successfully');
    } else {
      print('[FCM] Token registration failed (${response.statusCode}): ${response.body}');
    }
  } catch (e) {
    print('[FCM] Token registration error: $e');
  }
}
