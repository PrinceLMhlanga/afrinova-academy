import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ai_access_checker.dart';
import '../../core/auth_service.dart';
import '../../core/paynow_service.dart';
import 'dart:async';  // For Timer

class AISubscriptionScreen extends StatefulWidget {
  const AISubscriptionScreen({super.key});

  @override
  State<AISubscriptionScreen> createState() => _AISubscriptionScreenState();
}

class _AISubscriptionScreenState extends State<AISubscriptionScreen> {
  final AuthService _authService = AuthService();
  final PayNowService _payNowService = PayNowService();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  bool _isPaying = false;
  String _status = 'idle'; // idle, processing, waiting, completed, failed
  String? _pollUrl;
  String? _reference;
  Map<String, dynamic> _accessStatus = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await AIAccessChecker.getStatus();
    if (mounted) setState(() => _accessStatus = status);
  }

  Future<void> _subscribe() async {
    final rawPhone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your EcoCash number'), backgroundColor: Colors.red),
      );
      return;
    }

    // Clean phone number
    String cleanPhone = rawPhone
        .replaceAll(RegExp(r'[\s\-\(\)]+'), '')
        .replaceAll(RegExp(r'^(\+?263)'), '');
    
    if (cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.substring(1);
    }
    
    if (!RegExp(r'^\d{9}$').hasMatch(cleanPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 9-digit EcoCash number'), backgroundColor: Colors.red),
      );
      return;
    }
    
    final formattedPhone = '+263$cleanPhone';

    setState(() { _isPaying = true; _status = 'processing'; });

    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      _reference = 'AI-SUB-${DateTime.now().millisecondsSinceEpoch}';

      final response = await _payNowService.initiateMobilePayment(
        reference: _reference!,
        amount: 5,
        mobileNumber: formattedPhone,
        email: email,
        carrier: 'ecocash',
      );

      if (response.success && response.pollUrl != null) {
        setState(() { _status = 'waiting'; _pollUrl = response.pollUrl; });
        _startPolling();
      } else {
        setState(() { _status = 'failed'; _isPaying = false; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.error ?? 'Payment failed'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      setState(() { _status = 'failed'; _isPaying = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _startPolling() {
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_pollUrl == null || !mounted) {
        timer.cancel();
        return;
      }

      try {
        final status = await _payNowService.pollTransaction(_pollUrl!);
        
        if (status.paid || status.status.toLowerCase() == 'paid') {
          timer.cancel();
          
          // Activate subscription
          await Supabase.instance.client
              .from('profiles')
              .update({
                'is_subscribed': true,
                'subscription_expires_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
              })
              .eq('id', _authService.currentUserId!);

          if (mounted) {
            setState(() { _status = 'completed'; _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('🎉 AI Premium activated!'), backgroundColor: Color(0xFF4CAF50)),
            );
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) Navigator.pop(context, true);
            });
          }
        } else if (status.status.toLowerCase() == 'cancelled' || 
                   status.status.toLowerCase() == 'declined' ||
                   status.status.toLowerCase() == 'error') {
          timer.cancel();
          if (mounted) {
            setState(() { _status = 'failed'; _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment was cancelled or failed'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = _accessStatus['type'] as String? ?? 'none';
    final showTrialButton = type == 'no_trial';
    final isActive = _accessStatus['active'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('AI Premium'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _status == 'idle' || _status == 'failed'
          ? _buildSubscriptionForm(showTrialButton, isActive)
          : _status == 'processing'
              ? _buildProcessingState()
              : _status == 'waiting'
                  ? _buildWaitingState()
                  : _buildCompletedState(),
    );
  }

  Widget _buildSubscriptionForm(bool showTrialButton, bool isActive) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Status card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isActive
                    ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                    : [const Color(0xFF1A237E), const Color(0xFF283593)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(isActive ? Icons.check_circle : Icons.diamond, color: const Color(0xFFFFD700), size: 56),
                const SizedBox(height: 16),
                Text(isActive ? 'AI Premium Active' : 'Unlock AI Premium',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(_accessStatus['message'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Trial button (if eligible)
          if (showTrialButton) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.rocket_launch, color: Colors.green, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Try Before You Buy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                      Text('3-day free trial · All features', style: TextStyle(fontSize: 12, color: Colors.green)),
                    ]),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      await AIAccessChecker.startTrial();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('🎉 Trial started!'), backgroundColor: Color(0xFF4CAF50)),
                        );
                        Navigator.pop(context, true);
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    child: const Text('Start'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Plan card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFD700), width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12)],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.diamond, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('AI Premium Plan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                        Text('All AI features unlocked', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('\$5.00', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                const Text('per month', style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 20),
                
                // Features
                ..._buildFeature('🤖', 'AI Tutor Chat', '24/7 personalized tutoring'),
                ..._buildFeature('📝', 'AI Practice Exams', 'Smart exam generation'),
                ..._buildFeature('🃏', 'AI Flashcards', 'Auto-generated study cards'),
                ..._buildFeature('📚', 'AI Study Summaries', 'Comprehensive summaries'),
                ..._buildFeature('📊', 'AI Exam Analysis', 'Detailed feedback'),
                const SizedBox(height: 20),
                
                if (!isActive) ...[
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'EcoCash Number',
                      hintText: '077XXXXXXX',
                      prefixText: '+263 ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email (optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isPaying ? null : _subscribe,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('Pay \$5 with EcoCash', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: const Color(0xFF1A237E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProcessingState() {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: Color(0xFF1A237E)),
        SizedBox(height: 16),
        Text('Initiating payment...', style: TextStyle(fontSize: 16, color: Colors.grey)),
      ]),
    );
  }

  Widget _buildWaitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: const Color(0xFF1A237E).withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Icons.phone_android, size: 40, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 24),
          const Text('Check Your Phone! 📱', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 12),
          const Text('A payment prompt has been sent to your EcoCash number.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey)),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: Color(0xFF1A237E)),
          const SizedBox(height: 16),
          const Text('Waiting for payment confirmation...', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('Amount: \$5.00', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
        ]),
      ),
    );
  }

  Widget _buildCompletedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.check_circle, size: 80, color: Color(0xFF4CAF50)),
          const SizedBox(height: 20),
          const Text('Payment Successful! 🎉', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
          const SizedBox(height: 12),
          const Text('AI Premium is now active for 30 days', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
        ]),
      ),
    );
  }

  List<Widget> _buildFeature(String emoji, String title, String subtitle) {
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A237E))),
              Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
        ],
      ),
    ];
  }
}