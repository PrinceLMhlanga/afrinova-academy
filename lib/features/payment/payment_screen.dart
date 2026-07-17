import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/paynow_service.dart';
import '../../core/financial_service.dart';
import '../../core/auth_service.dart';
import '../../core/trial_service.dart';

class PaymentScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String subjectName;
  final String enrollmentId;
  final String? subjectId;   // ✅ For loading teacher pricing
  final String? levelId;     // ✅ For loading teacher pricing

  const PaymentScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.subjectName,
    required this.enrollmentId,
    this.subjectId,
    this.levelId,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final PayNowService _payNowService = PayNowService();
  final FinancialService _financialService = FinancialService();
  final AuthService _authService = AuthService();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isPaying = false;
  bool _isLoadingPricing = true;
  String _status = 'idle';
  String? _instructions;
  String? _pollUrl;
  String? _reference;
  
  // Pricing
  List<Map<String, dynamic>> _teacherPlans = [];
  double _monthlyPrice = 10;
  double _termlyPrice = 25;
  double _amount = 10;
  String? _selectedPlanId;
  int _selectedDuration = 30; // 30 or 90
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    try {
      // First check if teacher has custom pricing
      var pricingQuery = Supabase.instance.client
          .from('teacher_pricing')
          .select()
          .eq('teacher_id', widget.teacherId)
          .eq('is_active', true);

      if (widget.subjectId != null) {
        pricingQuery = pricingQuery.or('subject_id.eq.${widget.subjectId},subject_id.is.null');
      }
      if (widget.levelId != null) {
        pricingQuery = pricingQuery.or('level_id.eq.${widget.levelId},level_id.is.null');
      }

      final teacherPlans = await pricingQuery;

      if (teacherPlans.isNotEmpty && mounted) {
        // Use teacher's custom pricing
        final firstPlan = teacherPlans.first;
        setState(() {
          _teacherPlans = List<Map<String, dynamic>>.from(teacherPlans);
          _monthlyPrice = (firstPlan['price_monthly'] as num?)?.toDouble() ?? 10;
          _termlyPrice = (firstPlan['price_termly'] as num?)?.toDouble() ?? 25;
          _amount = _monthlyPrice;
          _selectedPlanId = firstPlan['id'] as String?;
          _selectedDuration = 30;
          _isLoadingPricing = false;
        });
      } else {
        // Fall back to platform pricing
        final pricing = await _financialService.getPricing();
        if (mounted) {
          setState(() {
            _monthlyPrice = pricing['monthly'] ?? 10;
            _termlyPrice = pricing['termly'] ?? 25;
            _amount = _monthlyPrice;
            _isLoadingPricing = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingPricing = false);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _initiatePayment() async {
    final rawPhone = _phoneController.text.trim();
    final email = _emailController.text.trim();

    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your EcoCash number'), backgroundColor: Colors.red),
      );
      return;
    }

    // Remove the +263 prefix and any spaces to get just the local number
    String cleanPhone = rawPhone
        .replaceAll(RegExp(r'[\s\-\(\)]+'), '')
        .replaceAll(RegExp(r'^(\+?263)'), ''); // Remove +263 or 263 prefix
    
    // Remove leading zero if present (since we already have +263)
    if (cleanPhone.startsWith('0')) {
      cleanPhone = cleanPhone.substring(1);
    }
    
    // Now check if we have exactly 9 digits (Zimbabwe mobile number without prefix)
    if (!RegExp(r'^\d{9}$').hasMatch(cleanPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid 9-digit mobile number\n(e.g., 77XXXXXXX or 78XXXXXXX)'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }
    
    // Format the full number with country code
    final formattedPhone = '+263$cleanPhone';
    
    // Optional: Validate network prefix (77, 78, 71, 73)
    if (!cleanPhone.startsWith('77') && 
        !cleanPhone.startsWith('78') && 
        !cleanPhone.startsWith('71') && 
        !cleanPhone.startsWith('73')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid EcoCash number (starts with 77, 78, 71, or 73)'), backgroundColor: Colors.red),
      );
      return;
    }

    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_isPaying) return;

    setState(() { _isPaying = true; _status = 'processing'; });

    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final reference = await _payNowService.createPendingPayment(
        studentId: userId,
        teacherId: widget.teacherId,
        amount: _amount,
        enrollmentId: widget.enrollmentId,
        pricingPlanId: _selectedPlanId,  // ✅ Pass plan
      );

      _reference = reference;

      final response = await _payNowService.initiateMobilePayment(
        reference: reference,
        amount: _amount,
        mobileNumber: formattedPhone, // Use the cleaned number
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
  debugPrint('🔴 Initiate payment error: $e');
  setState(() { _status = 'failed'; _isPaying = false; });
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error: ${e.toString()}'),  // ✅ Show actual error
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 8),  // ✅ Longer to read
      ),
    );
  }
}
  }

  void _startPolling() {
    _pollTimer?.cancel();
    int attempts = 0;
    const maxAttempts = 60; // Poll for up to 5 minutes (60 * 5 seconds)
    int consecutiveFailures = 0;
    
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_pollUrl == null || !mounted) {
        timer.cancel();
        return;
      }

      attempts++;
      
      // Check if we've exceeded max polling attempts
      if (attempts > maxAttempts) {
        timer.cancel();
        _pollTimer = null;
        if (mounted) {
          setState(() { _isPaying = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment is taking longer than expected. We\'ll notify you when it\'s confirmed.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      try {
        final status = await _payNowService.pollTransaction(_pollUrl!);
        consecutiveFailures = 0; // Reset failure count on successful poll
        final currentStatus = status.status.toLowerCase();

        if (status.paid || currentStatus == 'paid' || currentStatus == 'awaiting delivery') {
          timer.cancel();
          _pollTimer = null;
          
          debugPrint('🟡 Payment detected! Calling process-payment...');
          debugPrint('   reference: $_reference');
          debugPrint('   userId: ${_authService.currentUserId}');
          debugPrint('   teacherId: ${widget.teacherId}');
          debugPrint('   amount: $_amount');

          final userId = _authService.currentUserId;
          if (userId != null && _reference != null) {
            // ✅ Process payment in database
            await _financialService.processPayment(
              studentId: userId,
              teacherId: widget.teacherId,
              amount: _amount,
              gatewayReference: _reference!,
            );
            debugPrint('🟢 process-payment completed successfully');
          }

          // ✅ Activate subscription
          final trialService = TrialService();
          await trialService.activateSubscription(
            widget.enrollmentId,
            pricingPlanId: _selectedPlanId,
          );

          if (mounted) {
            setState(() { _status = 'completed'; _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment successful! ✅'), backgroundColor: Color(0xFF4CAF50)),
            );
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) Navigator.pop(context, true);
            });
          }
        } else if (currentStatus == 'sent' || currentStatus == 'created' || currentStatus == 'pending') {
          // Payment is still being processed - this is normal, keep waiting
          debugPrint('Poll attempt $attempts: Status is $currentStatus - waiting for user to confirm...');
        } else if (currentStatus == 'cancelled' || currentStatus == 'declined') {
          timer.cancel();
          _pollTimer = null;
          if (mounted) {
            setState(() { _status = 'failed'; _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment was cancelled or declined'), backgroundColor: Colors.red),
            );
          }
        } else if (currentStatus == 'error' || currentStatus == 'failed') {
          // Payment failed on PayNow's side
          timer.cancel();
          _pollTimer = null;
          if (mounted) {
            setState(() { _status = 'failed'; _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment failed. Please try again.'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        // Network error during poll - don't fail immediately
        consecutiveFailures++;
        debugPrint('Polling error (${consecutiveFailures} consecutive): $e');
        
        // Only show error after 12 consecutive network failures (60 seconds of no connection)
        if (consecutiveFailures > 12) {
          timer.cancel();
          _pollTimer = null;
          if (mounted) {
            setState(() { _isPaying = false; });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Poor connection. Your payment may still be processing. Check status later.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    final termlySavings = (_monthlyPrice * 3 - _termlyPrice).toStringAsFixed(0);
    final hasCustomPlans = _teacherPlans.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscribe'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoadingPricing
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Teacher + Subject info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                      child: Text(widget.teacherName.isNotEmpty ? widget.teacherName[0].toUpperCase() : 'T',
                          style: const TextStyle(color: Color(0xFF1A237E), fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.teacherName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(widget.subjectName, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ])),
                  ]),
                ),
                const SizedBox(height: 24),

                if (_status == 'idle' || _status == 'failed') ...[
                  const Text('Choose Your Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                  const SizedBox(height: 4),
                  Text('For ${widget.subjectName} with ${widget.teacherName}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 16),

                  // ✅ Show teacher's custom plans
                  if (hasCustomPlans)
                    ..._teacherPlans.map((plan) => _buildCustomPlanCard(plan, termlySavings))
                  else ...[
                    // Platform default plans
                    _buildDefaultMonthlyCard(),
                    _buildDefaultTermlyCard(termlySavings),
                  ],
                  const SizedBox(height: 16),
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
        children: [
          const Text('Subscription', style: TextStyle(fontSize: 13)),
          Text('\$${_amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13)),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('PayNow processing fee', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const Text('Paid by customer', style: TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
      const Divider(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('You pay (approx.)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          Text('≈ \$${(_amount * 1.025).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1A237E))),
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
          'PayNow processing fees are added at checkout. The amount shown on your phone will include the fee.',
          style: TextStyle(fontSize: 11, color: Colors.orange),
        ),
      ),
    ],
  ),
),

                  const SizedBox(height: 20),
                  // Phone + Email fields (same as before)
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'EcoCash Number', 
                      hintText: '77XXXXXXX',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.phone_android), 
                      prefixText: '+263 ',
                    ),
                    onChanged: (value) {
                      String clean = value.replaceAll(RegExp(r'[\s\-]'), '');
                      if (clean.startsWith('0')) {
                        clean = clean.substring(1);
                        _phoneController.value = TextEditingValue(
                          text: clean,
                          selection: TextSelection.collapsed(offset: clean.length),
                        );
                      }
                      if (clean.replaceAll(RegExp(r'[\s\-]'), '').length > 9) {
                        _phoneController.value = TextEditingValue(
                          text: clean.substring(0, 9),
                          selection: TextSelection.collapsed(offset: 9),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email (optional)', hintText: 'For payment receipt',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isPaying ? null : _initiatePayment,
                      icon: const Icon(Icons.payment),
                      label: Text('Pay \$${(_amount * 1.025).toStringAsFixed(2)} with EcoCash',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],

                // ... processing, waiting, completed states (same as before)
                if (_status == 'processing')
                  const Center(child: Padding(padding: EdgeInsets.all(60), child: Column(children: [
                    CircularProgressIndicator(color: Color(0xFF1A237E)),
                    SizedBox(height: 16), Text('Initiating payment...'),
                  ]))),

                if (_status == 'waiting')
                  Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [
                    Container(width: 80, height: 80,
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
                    Text('Amount: \$${_amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
                  ]))),

                if (_status == 'completed')
                  Center(child: Padding(padding: const EdgeInsets.all(60), child: Column(children: [
                    const Icon(Icons.check_circle, size: 80, color: Color(0xFF4CAF50)),
                    const SizedBox(height: 20),
                    const Text('Payment Successful! 🎉', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                    const SizedBox(height: 12),
                    Text('You now have full access to ${widget.subjectName}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  ]))),

              ]),
            ),
    );
  }

  Widget _buildCustomPlanCard(Map<String, dynamic> plan, String termlySavings) {
    final planName = plan['plan_name'] ?? 'Plan';
    final description = plan['description'] as String?;
    final features = List<String>.from(plan['features'] ?? []);
    final monthly = (plan['price_monthly'] as num?)?.toDouble() ?? 0;
    final termly = (plan['price_termly'] as num?)?.toDouble() ?? 0;
    final isSelected = _selectedPlanId == plan['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1A237E).withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(planName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          ),
          if (plan['is_default'] == true) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: const Text('Recommended', style: TextStyle(fontSize: 9, color: Color(0xFF4CAF50))),
            ),
          ],
        ]),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
        const SizedBox(height: 12),
        // Pricing options
        Row(children: [
          if (monthly > 0)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _amount = monthly;
                    _selectedPlanId = plan['id'] as String?;
                    _selectedDuration = 30;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _amount == monthly && _selectedDuration == 30
                        ? const Color(0xFF1A237E).withOpacity(0.08)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _amount == monthly && _selectedDuration == 30
                          ? const Color(0xFF1A237E)
                          : Colors.grey.shade300,
                      width: _amount == monthly && _selectedDuration == 30 ? 2 : 1,
                    ),
                  ),
                  child: Column(children: [
                    Text('\$${monthly.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF1A237E))),
                    const Text('/month', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                ),
              ),
            ),
          if (monthly > 0 && termly > 0) const SizedBox(width: 10),
          if (termly > 0)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _amount = termly;
                    _selectedPlanId = plan['id'] as String?;
                    _selectedDuration = 90;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _amount == termly && _selectedDuration == 90
                        ? const Color(0xFF4CAF50).withOpacity(0.08)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _amount == termly && _selectedDuration == 90
                          ? const Color(0xFF4CAF50)
                          : Colors.grey.shade300,
                      width: _amount == termly && _selectedDuration == 90 ? 2 : 1,
                    ),
                  ),
                  child: Column(children: [
                    Text('\$${termly.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                    const Text('/term', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('Save \$${(monthly * 3 - termly).toStringAsFixed(2)}', style: const TextStyle(fontSize: 9, color: Color(0xFF4CAF50))),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 4, runSpacing: 4,
            children: features.map((f) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check, size: 10, color: Color(0xFF4CAF50)),
                const SizedBox(width: 3),
                Text(f, style: const TextStyle(fontSize: 10)),
              ]),
            )).toList(),
          ),
        ],
      ]),
    );
  }

  Widget _buildDefaultMonthlyCard() {
    return GestureDetector(
      onTap: () => setState(() { _amount = _monthlyPrice; _selectedDuration = 30; }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _amount == _monthlyPrice && _selectedDuration == 30
              ? const Color(0xFF1A237E).withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _amount == _monthlyPrice && _selectedDuration == 30
                ? const Color(0xFF1A237E)
                : Colors.grey.shade300,
            width: _amount == _monthlyPrice && _selectedDuration == 30 ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Radio<double>(value: _monthlyPrice, groupValue: _amount,
              onChanged: (v) => setState(() { _amount = v ?? _monthlyPrice; _selectedDuration = 30; }),
              activeColor: const Color(0xFF1A237E)),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly Plan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text('30 days access', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ])),
          Text('\$${_monthlyPrice.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        ]),
      ),
    );
  }

  Widget _buildDefaultTermlyCard(String termlySavings) {
    return GestureDetector(
      onTap: () => setState(() { _amount = _termlyPrice; _selectedDuration = 90; }),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _amount == _termlyPrice && _selectedDuration == 90
              ? const Color(0xFF4CAF50).withOpacity(0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _amount == _termlyPrice && _selectedDuration == 90
                ? const Color(0xFF4CAF50)
                : Colors.grey.shade300,
            width: _amount == _termlyPrice && _selectedDuration == 90 ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Radio<double>(value: _termlyPrice, groupValue: _amount,
              onChanged: (v) => setState(() { _amount = v ?? _termlyPrice; _selectedDuration = 90; }),
              activeColor: const Color(0xFF4CAF50)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Termly Plan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF4CAF50), borderRadius: BorderRadius.circular(4)),
                child: Text('SAVE \$$termlySavings',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ]),
            const Text('90 days access', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ])),
          Text('\$${_termlyPrice.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
        ]),
      ),
    );
  }
}