import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/voice_profile_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VoiceProfileProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const NenaApp(),
    ),
  );
}

class NenaApp extends StatelessWidget {
  const NenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp(
      title: 'Nena – Sign to Swahili',
      debugShowCheckedModeBanner: false,
      themeMode: themeProvider.themeMode,

      // ── Dark theme (default) ────────────────────────────────────────────
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0F1A),
        cardColor: const Color(0xFF0D1829),
        dividerColor: Colors.white12,
        useMaterial3: true,
      ),

      // ── Light theme ─────────────────────────────────────────────────────
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        cardColor: Colors.white,
        dividerColor: Colors.black12,
        useMaterial3: true,
      ),

      home: const HomeScreen(),
    );
  }
}
