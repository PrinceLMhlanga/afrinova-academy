import 'package:flutter/material.dart';
import '../core/ai_access_checker.dart';
import '../features/ai/ai_paywall_screen.dart';

class AIFeatureGuard extends StatelessWidget {
  final Widget child;
  final String featureName;

  const AIFeatureGuard({
    super.key,
    required this.child,
    required this.featureName,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: AIAccessChecker.canAccessAIFeatures(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
          );
        }

        // Error
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Could not verify access', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
              ]),
            ),
          );
        }

        // Access granted
        if (snapshot.data == true) {
          return child;
        }

        // Access denied - show paywall
        return AIPaywallScreen(
          featureName: featureName,
          onSubscribe: () {
            // Navigate to payment/subscription screen
          },
        );
      },
    );
  }
}