import 'package:flutter/material.dart';
import 'features/auth/welcome_screen.dart';
import 'features/auth/signup_screen.dart';
import 'core/referral_tracker.dart';

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
      // ✅ Home stays as WelcomeScreen
      home: const WelcomeScreen(),
      
      // ✅ Add route handling for referral links
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');
        
        // Check if this is a referral link
        if (uri.pathSegments.length >= 2 && 
            uri.pathSegments[0].toLowerCase() == 'ref') {
          final code = uri.pathSegments[1];
          
          // Store the referral code
          ReferralTracker.storeReferralCode(code);
          
          // Navigate to WelcomeScreen (user can then go to signup)
          return MaterialPageRoute(
            builder: (_) => const WelcomeScreen(),
            settings: const RouteSettings(name: '/'),
          );
        }
        
        // Handle signup route
        if (settings.name == '/signup') {
          return MaterialPageRoute(
            builder: (_) => const SignupScreen(),
          );
        }
        
        return null;
      },
    );
  }
}