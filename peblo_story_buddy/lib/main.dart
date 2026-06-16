// lib/main.dart
// Entry point for Peblo Story Buddy.
// Sets up Provider state management and launches the single-screen app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/story_provider.dart';
import 'screens/story_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait — children's app, always portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Immersive look — hide status bar background
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const PebloApp());
}

class PebloApp extends StatelessWidget {
  const PebloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // Create a single StoryProvider instance for the whole app.
      // This manages TTS lifecycle, audio states, and quiz state.
      create: (_) => StoryProvider(),
      child: MaterialApp(
        title: 'Peblo Story Buddy',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1565C0),
          useMaterial3: true,
          fontFamily: 'Nunito', // Falls back to system sans-serif
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const StoryScreen(),
      ),
    );
  }
}