import 'package:flutter/material.dart';
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
      home: const StatusScreen(),
    );
  }
}
