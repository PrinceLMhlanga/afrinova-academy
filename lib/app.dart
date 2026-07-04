import 'package:flutter/material.dart';
import 'features/auth/welcome_screen.dart';

class AfriNovaApp extends StatelessWidget {
  const AfriNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AfriNova Academy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1A237E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          secondary: const Color(0xFFFF9800),
          brightness: Brightness.light,
        ),
        fontFamily: 'Poppins',
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const WelcomeScreen(),  // ← Changed to WelcomeScreen
    );
  }
}