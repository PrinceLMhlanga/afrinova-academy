import 'package:flutter/material.dart';
import 'features/auth/welcome_screen.dart';
import 'features/auth/signup_screen.dart';
import 'core/referral_tracker.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation.dart';

class AfriNovaApp extends StatelessWidget {
  const AfriNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'AfriNova Academy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const WelcomeScreen(),

      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        if (uri.pathSegments.length >= 2 &&
            uri.pathSegments[0].toLowerCase() == 'ref') {
          final code = uri.pathSegments[1];
          ReferralTracker.storeReferralCode(code);
          return MaterialPageRoute(
            builder: (_) => const WelcomeScreen(),
            settings: const RouteSettings(name: '/'),
          );
        }

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