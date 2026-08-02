import 'dart:async';

/// Serializes permission requests app-wide.
///
/// Android only allows one requestPermissions() call in flight per Activity.
/// Every shell tab is mounted simultaneously (IndexedStack keeps them all
/// alive), so each tab's initState() firing its own permission request at
/// cold start (camera, notifications, storage, photos) would otherwise race
/// and throw PlatformException("A request for permissions is already
/// running"), crashing whichever request lost the race.
class PermissionGate {
  static Future<void> _chain = Future.value();

  static Future<T> run<T>(Future<T> Function() request) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        completer.complete(await request());
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }
}
