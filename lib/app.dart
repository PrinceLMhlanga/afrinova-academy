import 'package:flutter/material.dart';
import 'features/auth/welcome_screen.dart';
import 'features/auth/signup_screen.dart';
import 'core/referral_tracker.dart';
import 'core/theme/app_theme.dart';
import 'core/navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/home/home_screen.dart';



class AfriNovaApp extends StatelessWidget {
  const AfriNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'AfriNova Academy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      
      // 🚀 DYNAMIC AUTH GATEWAY
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          // While loading the initial session from disk, show a generic loading bar
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
            );
          }

          // Check if an active session exists
          final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;

          if (session != null) {
            // User is authenticated! Send them directly to their personalized layout shell
            return const HomeScreen();
          } else {
            // No session found. Send them to register or sign in
            return const WelcomeScreen();
          }
        },
      ),


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