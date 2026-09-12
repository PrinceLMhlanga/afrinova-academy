import 'package:flutter/material.dart';
import '../../features/premium/ai_subscription_screen.dart';

class TrialLimitDialog extends StatelessWidget {
  final String featureName;
  final String? customMessage;

  const TrialLimitDialog({
    super.key,
    required this.featureName,
    this.customMessage,
  });

  /// Shows the trial limit dialog.
  /// 
  /// Returns:
  /// - `true` if the user subscribed successfully
  /// - `false` if the user subscribed but the flow was incomplete (rare)
  /// - `null` if the user dismissed the dialog without subscribing
  static Future<bool?> show(
    BuildContext context, {
    required String featureName,
    String? customMessage,
  }) async {
    // Show dialog first
    final wantsToSubscribe = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TrialLimitDialog(
        featureName: featureName,
        customMessage: customMessage,
      ),
    );

    // If user tapped "Subscribe", navigate from the parent context
    if (wantsToSubscribe == true && context.mounted) {
      final subscribed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const AISubscriptionScreen(),
        ),
      );
      return subscribed;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.all(24),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Trial Limit Reached',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Message
            Text(
              customMessage ??
                  'You have reached your free trial limit for $featureName. Subscribe to unlock unlimited access.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // Benefits
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: const [
                  _BenefitRow(text: 'Unlimited AI Tutor messages'),
                  _BenefitRow(text: 'Unlimited Expert Tutor'),
                  _BenefitRow(text: 'Unlimited Flashcards'),
                  _BenefitRow(text: 'Unlimited Summaries'),
                  _BenefitRow(text: 'Unlimited Exam Generation'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Subscribe Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  // ✅ Just close the dialog with 'true'
                  // Navigation is handled in show()
                  Navigator.pop(context, true);
                },
                icon: const Icon(Icons.diamond),
                label: const Text(
                  'Subscribe for \$5/month',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: const Color(0xFF1A237E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Not Now
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final String text;
  const _BenefitRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}