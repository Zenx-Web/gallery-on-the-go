import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'screens/status_screen.dart';
import 'services/background_service.dart';
import 'services/fcm_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase/background-service setup must never prevent the app from
  // rendering — a failure here used to crash the app before runApp().
  try {
    // Firebase must be initialised before any Firebase call.
    await Firebase.initializeApp();

    // Register the top-level FCM background handler (before runApp).
    // This is called by Firebase when a data message arrives and the process
    // is not running — it must be a top-level function.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Configure and start the background service (socket lives in there).
    await initializeBackgroundService();
  } catch (e, stackTrace) {
    debugPrint('Startup init failed: $e\n$stackTrace');
  }

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
      home: const StatusScreen(),
    );
  }
}
