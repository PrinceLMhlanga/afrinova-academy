import 'package:flutter/material.dart';
import '../core/ai_access_checker.dart';
import '../features/ai/ai_paywall_screen.dart';
import '../features/premium/ai_subscription_screen.dart';

class AIFeatureGuard extends StatefulWidget {
  final Widget child;
  final String featureName;

  /// When true, renders loading and paywall states without their
  /// own Scaffold so they slot into the shell's panel viewport.
  final bool embedded;

  const AIFeatureGuard({
    super.key,
    required this.child,
    required this.featureName,
    this.embedded = false,
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

  Future<void> _handleSubscription() async {
    final subscribed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AISubscriptionScreen()),
    );
    if (subscribed == true && mounted) {
      await _checkAccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      const loading = Center(
        child: CircularProgressIndicator(color: Color(0xFF1A237E)),
      );
      return widget.embedded
          ? const Material(color: Color(0xFFF5F7FA), child: loading)
          : const Scaffold(body: loading);
    }

    if (_hasAccess) {
      return widget.child;
    }

    // Hand off to the paywall — it handles its own embedded state.
    return AIPaywallScreen(
      featureName: widget.featureName,
      onSubscribe: _handleSubscription,
      embedded: widget.embedded,
    );
  }
}