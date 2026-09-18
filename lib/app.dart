import 'package:flutter/material.dart';
import 'features/auth/welcome_screen.dart';
import 'features/auth/signup_screen.dart';
import 'core/referral_tracker.dart';
import 'core/theme/app_theme.dart';

class AfriNovaApp extends StatelessWidget {
  const AfriNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AfriNova Academy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
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