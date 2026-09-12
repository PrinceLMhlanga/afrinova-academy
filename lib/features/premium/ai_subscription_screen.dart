import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ai_access_checker.dart';
import '../../core/auth_service.dart';
import '../../core/paynow_service.dart';
import 'dart:async';
import '../../core/trial_usage_service.dart';

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
  Map<String, int> _trialLimits = {};
  
  // ✅ Trial usage summary
  Map<String, dynamic>? _trialUsage;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
  final status = await AIAccessChecker.getStatus();
  final usage = await _loadTrialUsage();
  final limits = await TrialUsageService().getTrialLimits();
  if (mounted) {
    setState(() {
      _accessStatus = status;
      _trialUsage = usage;
      _trialLimits = limits;
    });
  }
}

 

  Future<Map<String, dynamic>?> _loadTrialUsage() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return null;

      final response = await Supabase.instance.client
          .from('trial_usage')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error loading trial usage: $e');
      return null;
    }
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
        'teacher_id': null,
        'enrollment_id': null,
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
        await _updatePaymentStatus(_reference!, 'failed');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.error ?? 'Payment failed'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      setState(() { _status = 'failed'; _isPaying = false; });
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
          timer.cancel(); 
          
          await _updatePaymentStatus(_reference!, 'completed');
          
          if (!mounted) return;

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
    const SnackBar(
      content: Text('🎉 AI Premium activated!'),
      backgroundColor: Color(0xFF4CAF50),
      duration: Duration(seconds: 2),
    ),
  );
  
  // ✅ Pop immediately — snackbar will still show briefly
  Navigator.of(context).pop(true);
}
        } else if (status.status.toLowerCase() == 'cancelled' || 
                   status.status.toLowerCase() == 'declined' ||
                   status.status.toLowerCase() == 'error') {
          timer.cancel(); 
          await _updatePaymentStatus(_reference!, status.status.toLowerCase());
          
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
    final isSubscribed = _accessStatus['active'] == true && type != 'trial';
    final isTrialActive = type == 'trial_active' || type == 'trial';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('AI Premium'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _status == 'idle' || _status == 'failed'
          ? _buildSubscriptionForm(showTrialButton, isSubscribed, isTrialActive)
          : _status == 'processing'
              ? _buildProcessingState()
              : _status == 'waiting'
                  ? _buildWaitingState()
                  : _buildCompletedState(),
    );
  }

  Widget _buildSubscriptionForm(bool showTrialButton, bool isSubscribed, bool isTrialActive) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // ✅ STATUS CARD — different for each state
          if (isSubscribed)
            _buildSubscribedStatusCard()
          else if (isTrialActive)
            _buildTrialStatusCard()
          else
            _buildUnlockStatusCard(),

          const SizedBox(height: 24),

          // ✅ SUBSCRIBE FORM — show whenever NOT fully subscribed
          // (this includes trial-active users)
          if (!isSubscribed) ...[
            _buildSubscribeCard(),
          ] else ...[
            // Subscribed — show account info + renew option
            _buildActiveSubscriptionCard(),
          ],

          // ✅ Trial button only for brand-new users
          if (showTrialButton) ...[
            const SizedBox(height: 16),
            _buildStartTrialCard(),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ==========================================
  // STATUS CARDS
  // ==========================================

  Widget _buildUnlockStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.diamond, color: Color(0xFFFFD700), size: 56),
          const SizedBox(height: 16),
          const Text(
            'Unlock AI Premium',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _accessStatus['message'] ?? 'Subscribe to unlock all AI features',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

 Widget _buildTrialStatusCard() {
  // ✅ Read limits from DB, fall back gracefully if not loaded yet
  final flashcardsLimit = _trialLimits['flashcards_generated'] ?? 10;
  final examsLimit = _trialLimits['exams_generated'] ?? 2;
  final summariesLimit = _trialLimits['summaries_generated'] ?? 2;
  final tutorLimit = _trialLimits['general_tutor_messages'] ?? 20;
  final expertTopicsLimit = _trialLimits['expert_tutor_topics_started'] ?? 1;
  final expertMessagesLimit = _trialLimits['expert_tutor_messages'] ?? 10;

  final flashcardsUsed = _trialUsage?['flashcards_generated'] ?? 0;
  final examsUsed = _trialUsage?['exams_generated'] ?? 0;
  final summariesUsed = _trialUsage?['summaries_generated'] ?? 0;
  final tutorUsed = _trialUsage?['general_tutor_messages'] ?? 0;
  final expertTopicsUsed = _trialUsage?['expert_tutor_topics_started'] ?? 0;
  final expertMessagesUsed = _trialUsage?['expert_tutor_messages'] ?? 0;

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFF6B00), Color(0xFFFF9800)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Free Trial Active',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _accessStatus['message'] ?? 'Limited access — subscribe to unlock everything',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Usage bars
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _trialUsageRow('AI Tutor messages', tutorUsed, tutorLimit),
              const SizedBox(height: 8),
              _trialUsageRow('Expert Tutor messages', expertMessagesUsed, expertMessagesLimit),
              const SizedBox(height: 8),
              _trialUsageRow('Expert Tutor topics', expertTopicsUsed, expertTopicsLimit),
              const SizedBox(height: 8),
              _trialUsageRow('Flashcards', flashcardsUsed, flashcardsLimit),
              const SizedBox(height: 8),
              _trialUsageRow('Summaries', summariesUsed, summariesLimit),
              const SizedBox(height: 8),
              _trialUsageRow('Exams', examsUsed, examsLimit),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '⚠️ Trial limits don\'t reset. Subscribe for unlimited access.',
          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}

  Widget _trialUsageRow(String label, int used, int limit) {
    final progress = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isExhausted = used >= limit;
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation(
              isExhausted ? Colors.red.shade300 : Colors.white,
            ),
            minHeight: 5,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$used/$limit',
          style: TextStyle(
            color: isExhausted ? Colors.red.shade100 : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscribedStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 56),
          const SizedBox(height: 16),
          const Text(
            'AI Premium Active',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _accessStatus['message'] ?? 'You have full access to all AI features',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SUBSCRIBE CARD (shown to non-subscribed users)
  // ==========================================

  Widget _buildSubscribeCard() {
    return Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Premium Plan',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                    Text('All AI features unlocked',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('\$5.00', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const Text('per month', style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 20),

          // Features
          ..._buildFeature('🤖', 'AI Tutor Chat', 'Unlimited messages'),
          ..._buildFeature('🎓', 'Expert Tutor', 'Syllabus-based teaching'),
          ..._buildFeature('📝', 'AI Practice Exams', 'Unlimited generation'),
          ..._buildFeature('🃏', 'AI Flashcards', 'Unlimited cards'),
          ..._buildFeature('📚', 'AI Study Summaries', 'Unlimited summaries'),
          ..._buildFeature('📊', 'AI Exam Analysis', 'Feedback on every exam'),
          const SizedBox(height: 20),

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

          // Fee breakdown
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Subscription', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    Text('\$5.00', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('PayNow fee (2.5%)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    Text('\$${(5.00 * 0.025).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('You will pay',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('\$${(5.00 * 1.025).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
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
                    'A 2.5% PayNow processing fee is added at checkout.',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Pay button
          SizedBox(
            width: double.infinity,
            height: 56,
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
      ),
    );
  }

  // ==========================================
  // ACTIVE SUBSCRIPTION CARD (subscribed users)
  // ==========================================

  Widget _buildActiveSubscriptionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4CAF50), width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.diamond, color: Color(0xFF4CAF50), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Premium Subscription Active',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                    Text('Enjoy unlimited access',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('Next renewal:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 6),
                Text(
                  _accessStatus['expires_at'] != null
                      ? DateTime.parse(_accessStatus['expires_at'].toString())
                          .toLocal()
                          .toString()
                          .split(' ')[0]
                      : 'In 30 days',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A237E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // START TRIAL CARD (brand-new users only)
  // ==========================================

  Widget _buildStartTrialCard() {
    return Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Try Before You Buy',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green)),
                Text('3-day free trial · Limited features',
                    style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await AIAccessChecker.startTrial();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('🎉 Trial started!'), backgroundColor: Color(0xFF4CAF50)),
                );
                await _loadStatus();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Start'),
          ),
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
          const Text('Check Your Phone! 📱',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 12),
          const Text('A payment prompt has been sent to your EcoCash number.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey)),
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
          const Text('Payment Successful! 🎉',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
          const SizedBox(height: 12),
          const Text('AI Premium is now active for 30 days',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
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
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A237E))),
              Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
        ],
      ),
    ];
  }
}