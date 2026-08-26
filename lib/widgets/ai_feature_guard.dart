import 'package:flutter/material.dart';
import '../core/ai_access_checker.dart';
import '../features/ai/ai_paywall_screen.dart';
import '../features/premium/ai_subscription_screen.dart';

class AIFeatureGuard extends StatefulWidget {
  final Widget child;
  final String featureName;

  const AIFeatureGuard({
    super.key,
    required this.child,
    required this.featureName,
  });

  @override
  State<AIFeatureGuard> createState() => _AIFeatureGuardState();
}

class _AIFeatureGuardState extends State<AIFeatureGuard> {
  bool _hasAccess = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    final hasAccess = await AIAccessChecker.canAccessAIFeatures();
    if (mounted) {
      setState(() {
        _hasAccess = hasAccess;
        _isLoading = false;
      });
    }
  }

  // inside _AIFeatureGuardState

Future<void> _handleSubscription() async {
  final subscribed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => const AISubscriptionScreen(),
    ),
  );
  
  if (subscribed == true && mounted) {
    // 1. Force await the access checker to finish network validation
    await _checkAccess();
    
    // 2. State has now changed inside _checkAccess via setState(), 
    // widget.build() will automatically swap AIPaywallScreen with widget.child!
  }
}


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
      );
    }

    // Access granted - show the feature directly
    if (_hasAccess) {
      return widget.child;
    }

    // Access denied - show paywall
    return AIPaywallScreen(
      featureName: widget.featureName,
      onSubscribe: _handleSubscription,
    );
  }
}