import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ai_access_checker.dart';
import '../../core/auth_service.dart';
import '../premium/ai_subscription_screen.dart';

class AIPaywallScreen extends StatefulWidget {
  final String featureName;
  final VoidCallback? onSubscribe;

  const AIPaywallScreen({
    super.key,
    required this.featureName,
    this.onSubscribe,
  });

  @override
  State<AIPaywallScreen> createState() => _AIPaywallScreenState();
}

class _AIPaywallScreenState extends State<AIPaywallScreen> {
  Map<String, dynamic> _status = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await AIAccessChecker.getStatus();
    if (mounted) setState(() { _status = status; _isLoading = false; });
  }

  // inside _AIPaywallScreenState

Future<void> _handleSubscription() async {
  final subscribed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => const AISubscriptionScreen()),
  );
  
  if (subscribed == true && mounted) {
    // Notify AIFeatureGuard first
    if (widget.onSubscribe != null) {
      widget.onSubscribe!();
    }
    // Then bubble back up past the paywall layer
    Navigator.pop(context, true);
  }
}

Future<void> _handleTrialStart() async {
  await AIAccessChecker.startTrial();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🎉 Trial started!'), backgroundColor: Color(0xFF4CAF50)),
    );
    
    if (widget.onSubscribe != null) {
      widget.onSubscribe!();
    }
    
    Navigator.pop(context, true);
  }
}


  @override
  Widget build(BuildContext context) {
    final type = _status['type'] as String? ?? 'none';
    final message = _status['message'] as String? ?? '';
    final showTrialButton = type == 'no_trial';
    final showSubscribeButton = type == 'trial_expired' || type == 'expired';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      
                      Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      Text(
                        '${widget.featureName} is Premium',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 12),
                      
                      Text(
                        message.isNotEmpty ? message : 'Upgrade to unlock AI-powered learning features!',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 32),
                      
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                        child: const Column(
                          children: [
                            _PremiumFeature(icon: Icons.chat, text: 'AI Tutor Chat'),
                            SizedBox(height: 12),
                            _PremiumFeature(icon: Icons.quiz, text: 'Practice Exams with AI Feedback'),
                            SizedBox(height: 12),
                            _PremiumFeature(icon: Icons.style, text: 'AI Flashcard Generator'),
                            SizedBox(height: 12),
                            _PremiumFeature(icon: Icons.summarize, text: 'Study Summaries'),
                            SizedBox(height: 12),
                            _PremiumFeature(icon: Icons.auto_awesome, text: 'Exam Analysis & Tips'),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Trial button
                      if (showTrialButton) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withOpacity(0.2)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 10),
                              Expanded(child: Text('Start with a 3-day free trial. No payment required!', style: TextStyle(fontSize: 13, color: Color(0xFF2E7D32)))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity, height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _handleTrialStart,  // ✅ Use helper
                            icon: const Icon(Icons.rocket_launch),
                            label: const Text('Start Free Trial', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          ),
                        ),
                      ],
                      
                      // Subscribe button
                      if (showSubscribeButton) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.withOpacity(0.2)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.orange, size: 20),
                              SizedBox(width: 10),
                              Expanded(child: Text('Your trial has ended. Subscribe to continue.', style: TextStyle(fontSize: 13, color: Colors.orange))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity, height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _handleSubscription,  // ✅ Use helper
                            icon: const Icon(Icons.diamond),
                            label: const Text('Subscribe Now - \$5', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: const Color(0xFF1A237E), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      
                      // View Plans button
                      TextButton(
                        onPressed: _handleSubscription,  // ✅ Use helper
                        child: const Text('View Plans', style: TextStyle(fontSize: 14, color: Color(0xFF1A237E))),
                      ),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PremiumFeature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PremiumFeature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFFFD700), size: 22),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 15, color: Color(0xFF1A237E)))),
      ],
    );
  }
}