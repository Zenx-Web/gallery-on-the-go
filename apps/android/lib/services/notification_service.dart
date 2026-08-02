import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'permission_gate.dart';

/// Wraps flutter_local_notifications for study reminders (task due dates,
/// exam countdowns). Uses `inexactAllowWhileIdle` scheduling rather than
/// exact alarms — study reminders don't need to-the-second precision, and
/// avoiding SCHEDULE_EXACT_ALARM sidesteps a permission that Android 12+
/// lets users silently revoke per-app (exact alarms would then fail
/// silently), so inexact delivery is the more reliable choice here.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'study_reminders';
  static const _channelName = 'Study Reminders';
  static const _channelDesc = 'Task due dates and exam countdown reminders';

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      // Falls back to UTC if the platform timezone name isn't in the IANA
      // database (observed on some emulator images) — reminders still fire,
      // just computed against UTC offsets instead of the device's zone.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  Future<void> requestPermission() async {
    try {
      await PermissionGate.run(() async {
        return _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      });
    } catch (e) {
      debugPrint('Notification permission request failed (non-fatal): $e');
    }
  }

  /// Stable notification id derived from a string key (task/exam id) so the
  /// same reminder can be looked up and cancelled later without tracking
  /// int ids separately.
  int _idFor(String key) => key.hashCode & 0x7fffffff;

  Future<void> scheduleAt({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    await init();
    if (when.isBefore(DateTime.now())) return;

    await _plugin.zonedSchedule(
      _idFor(id),
      title,
      body,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancel(String id) async {
    await init();
    await _plugin.cancel(_idFor(id));
  }
}
