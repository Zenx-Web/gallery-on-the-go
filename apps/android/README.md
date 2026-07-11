# GalleryOnTheGo — Android App

> Flutter app that runs on the Android phone, reads media storage, and streams files on-demand to the server.

## What's implemented

- Device auto-registration + token persistence (`lib/services/device_registration_service.dart`)
- Socket.IO connection to the server's `/device` namespace with auto-reconnect + heartbeat (`lib/services/socket_service.dart`)
- Gallery + Downloads listing via MediaStore (`lib/services/media_service.dart`)
- Chunked file + thumbnail streaming (`lib/services/file_stream_service.dart`)
- Connect / status UI (`lib/screens/`)

Not yet implemented (later phase): FCM wake-from-sleep, persistent foreground background service. Right now the socket connection stays alive only while the app process is alive (foreground or backgrounded-but-not-killed).

## Setup

This repo only contains the Dart application code (`pubspec.yaml`, `lib/`). The native Android project scaffold (`android/`, Gradle wrapper, `AndroidManifest.xml`) isn't checked in — generate it locally:

```bash
cd apps/android
flutter create --org com.zenxorg --project-name gallery_on_the_go .
flutter pub get
```

`flutter create .` will not overwrite the existing `pubspec.yaml`/`lib/` — it only fills in the missing native scaffolding (`android/`, `ios/`, etc.).

### Required manifest permissions

After scaffolding, add these to `android/app/src/main/AndroidManifest.xml` (inside `<manifest>`, above `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- Android 13+ granular media permissions -->
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />

<!-- Android 12 and below fallback -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />

<!-- Downloads folder access (Android 11+) -->
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

`compileSdkVersion`/`targetSdkVersion` should be 34+ for the Android 13 media permissions to take effect; `photo_manager` and `permission_handler` both document minimum SDK requirements in their own READMEs — check those against whatever `flutter create` generates.

### Pointing at the server

On first launch the app asks for a server URL (defaults to `http://localhost:3001` for local development against `server/` — see the root `.env.example` for `NEXT_PUBLIC_API_URL`, which the web app points at the same server). For a real device, use the server's LAN IP or public URL, not `localhost`.

### Testing end-to-end

1. Start the backend: `npm run dev` from the repo root (or however `server/` is run).
2. Build and install this app on a device or emulator with the manifest permissions above added.
3. Enter the server URL, grant permissions, tap Connect.
4. Confirm the device shows up as online in the web dashboard's device list (`apps/web`).
5. Open the gallery in the web dashboard and confirm a photo streams through.

## Core Responsibilities

- Connect to backend via Socket.IO (no login required)
- Auto-register device on first connection
- Read gallery using Android MediaStore API
- Read Downloads folder
- Stream requested files via WebSocket chunks
- Maintain background connection
- Handle FCM push notifications to wake from sleep (not yet implemented)
