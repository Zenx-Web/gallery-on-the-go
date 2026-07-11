import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';

/// Registers this install with the backend (server/src/modules/device/device.routes.ts)
/// and persists the resulting device id + token so subsequent launches skip
/// registration entirely.
class DeviceRegistrationService {
  static const _kServerUrl = 'gallery.server_url';
  static const _kDeviceId = 'gallery.device_id';
  static const _kDeviceToken = 'gallery.device_token';
  static const _kDeviceName = 'gallery.device_name';
  static const _kInstallSuffix = 'gallery.install_suffix';

  static const String defaultServerUrl = 'http://localhost:3001';

  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kServerUrl) ?? defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    // Strip a trailing slash so `$serverUrl/api/...` never double-slashes.
    final normalized = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    await prefs.setString(_kServerUrl, normalized);
  }

  Future<({String deviceId, String deviceToken})?> loadPersistedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kDeviceId);
    final token = prefs.getString(_kDeviceToken);
    if (id == null || token == null) return null;
    return (deviceId: id, deviceToken: token);
  }

  /// Registers the device if no credentials are persisted yet, otherwise
  /// returns the stored ones. Server-side dedup (by device name + model) also
  /// makes re-registration harmless, but skipping it saves a round trip.
  Future<({String deviceId, String deviceToken, bool isNew})> registerOrLoad() async {
    final existing = await loadPersistedCredentials();
    if (existing != null) {
      return (
        deviceId: existing.deviceId,
        deviceToken: existing.deviceToken,
        isNew: false,
      );
    }

    final serverUrl = await getServerUrl();
    final deviceName = await _stableDeviceName();
    final deviceModel = await _deviceModel();
    final androidVersion = await _androidVersion();

    final response = await http.post(
      Uri.parse('$serverUrl${ApiRoutes.devicesRegister}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceName': deviceName,
        'deviceModel': deviceModel,
        'androidVersion': androidVersion,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        'Device registration failed (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final device = data['device'] as Map<String, dynamic>;

    final deviceId = device['id'] as String;
    final deviceToken = data['token'] as String;
    final isNew = data['isNew'] as bool;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceId, deviceId);
    await prefs.setString(_kDeviceToken, deviceToken);
    await prefs.setString(_kDeviceName, deviceName);

    return (deviceId: deviceId, deviceToken: deviceToken, isNew: isNew);
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kDeviceId);
    await prefs.remove(_kDeviceToken);
  }

  /// `<model> (<random suffix>)`. The suffix is generated once per install
  /// and persisted, so the same install always registers under the same
  /// name+model combo (and therefore reuses the same server-side token),
  /// while a fresh install (or app data wipe) is treated as a new device.
  Future<String> _stableDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    var suffix = prefs.getString(_kInstallSuffix);
    if (suffix == null) {
      suffix = const Uuid().v4().substring(0, 8);
      await prefs.setString(_kInstallSuffix, suffix);
    }
    final model = await _deviceModel() ?? 'Android Device';
    return '$model ($suffix)';
  }

  Future<String?> _deviceModel() async {
    if (!Platform.isAndroid) return null;
    final info = await DeviceInfoPlugin().androidInfo;
    return '${info.manufacturer} ${info.model}'.trim();
  }

  Future<String?> _androidVersion() async {
    if (!Platform.isAndroid) return null;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.release;
  }
}
