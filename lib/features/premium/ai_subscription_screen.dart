import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ai_access_checker.dart';
import '../../core/auth_service.dart';
import '../../core/paynow_service.dart';
import 'dart:async';

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
  String _status = 'idle';
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

  // ✅ NEW: Record payment in payments table
  Future<void> _recordPayment({
    required String studentId,
    required double amount,
    required String gatewayReference,
    required String status,
    required String paymentMethod,
  }) async {
    try {
      await Supabase.instance.client.from('payments').insert({
        'student_id': studentId,
        'teacher_id': null, // No teacher for AI subscription
        'enrollment_id': null, // No enrollment for AI subscription
        'amount': amount,
        'currency': 'USD',
        'gateway': 'paynow',
        'gateway_reference': gatewayReference,
        'status': status,
        'payment_type': 'ai_subscription',
        'subscription_type': 'ai_premium_monthly',
        'payment_method': paymentMethod,
        'metadata': {
          'payment_category': 'platform_subscription',
          'feature': 'ai_premium',
          'duration_days': 30,
        },
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      
      print('✅ Payment recorded successfully');
    } catch (e) {
      print('❌ Error recording payment: $e');
    }
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

      // ✅ Record pending payment before initiating
      await _recordPayment(
        studentId: userId,
        amount: 5.0,
        gatewayReference: _reference!,
        status: 'pending',
        paymentMethod: 'ecocash',
      );

      final response = await _payNowService.initiateMobilePayment(
        reference: _reference!,
        amount: 5.0,
        mobileNumber: formattedPhone,
        email: email,
        carrier: 'ecocash',
      );

      if (response.success && response.pollUrl != null) {
        setState(() { _status = 'waiting'; _pollUrl = response.pollUrl; });
        _startPolling();
      } else {
        setState(() { _status = 'failed'; _isPaying = false; });
        
        // ✅ Update payment status to failed
        await _updatePaymentStatus(_reference!, 'failed');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.error ?? 'Payment failed'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      setState(() { _status = 'failed'; _isPaying = false; });
      
      // ✅ Update payment status to failed
      if (_reference != null) {
        await _updatePaymentStatus(_reference!, 'failed');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ✅ NEW: Update payment status
  Future<void> _updatePaymentStatus(String gatewayReference, String status) async {
    try {
      await Supabase.instance.client
          .from('payments')
          .update({
            'status': status,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('gateway_reference', gatewayReference);
      
      print('✅ Payment status updated to: $status');
    } catch (e) {
      print('❌ Error updating payment status: $e');
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
          // 🛑 CRITICAL FIX: Cancel the timer FIRST before any await calls
          timer.cancel(); 
          
          // ✅ Update payment status to completed
          await _updatePaymentStatus(_reference!, 'completed');
          
          // Check if widget is still in the tree before updating State/UI
          if (!mounted) return;

          // Activate subscription
          await Supabase.instance.client
              .from('profiles')
              .update({
                'is_subscribed': true,
                'subscription_plan': 'ai_premium',
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
          // 🛑 CRITICAL FIX: Cancel the timer FIRST here too
          timer.cancel(); 
          
          // ✅ Update payment status
          await _updatePaymentStatus(_reference!, status.status.toLowerCase());
          
          if (mounted) {
            setState(() { _status = 'failed'; _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment was cancelled or failed'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (_) {
        // Optional: clear timer if a persistent error happens to avoid endless loop
      }
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
                  // Phone field
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

// Email field
TextField(
  controller: _emailController,
  keyboardType: TextInputType.emailAddress,
  decoration: InputDecoration(
    labelText: 'Email (optional)',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  ),
),
const SizedBox(height: 16),

// ✅ PayNow Fee Breakdown
Container(
  padding: const EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: Colors.grey.shade50,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.grey.shade200),
  ),
  child: Column(
    children: [
      // Subscription amount
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Subscription', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const Text('\$5.00', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
      const SizedBox(height: 6),
      
      // PayNow fee
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('PayNow fee (2.5%)', style: TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            '\$${(5.00 * 0.025).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      
      const Divider(height: 16),
      
      // Total
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('You will pay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text(
            '\$${(5.00 * 1.025).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
          ),
        ],
      ),
    ],
  ),
),
const SizedBox(height: 8),

// Info note
Container(
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(
    color: Colors.orange.shade50,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: Colors.orange.shade200),
  ),
  child: const Row(
    children: [
      Icon(Icons.info_outline, color: Colors.orange, size: 16),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          'A 2.5% PayNow processing fee is added at checkout. The amount shown on your phone will include this fee.',
          style: TextStyle(fontSize: 11, color: Colors.orange),
        ),
      ),
    ],
  ),
),
const SizedBox(height: 20),

// Pay button
SizedBox(
  width: double.infinity, height: 56,
  child: ElevatedButton.icon(
    onPressed: _isPaying ? null : _subscribe,
    icon: const Icon(Icons.lock_open),
    label: Text(
      'Pay \$${(5.00 * 1.025).toStringAsFixed(2)} with EcoCash',
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    ),
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
        Text(
          'Amount: \$${(5.00 * 1.025).toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
        ),
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