import 'package:flutter/material.dart';
import '../../core/trial_service.dart';
import '../../core/auth_service.dart';
import '../payment/payment_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TrialBanner extends StatefulWidget {
  const TrialBanner({super.key});

  @override
  State<TrialBanner> createState() => _TrialBannerState();
}

class _TrialBannerState extends State<TrialBanner> {
  final TrialService _trialService = TrialService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _warnings = [];
  int _currentWarningIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadWarnings();
  }

  Future<void> _loadWarnings() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Load both trial and subscription warnings
      final trialWarnings = await _trialService.getTrialWarnings(userId);
      final subscriptionWarnings = await _trialService.getSubscriptionWarnings(userId);

      // Combine and sort: expired first, then closest to expiry
      final allWarnings = [...subscriptionWarnings, ...trialWarnings];
      allWarnings.sort((a, b) {
        // Expired first
        if ((a['is_expired'] == true) && (b['is_expired'] != true)) return -1;
        if ((a['is_expired'] != true) && (b['is_expired'] == true)) return 1;
        // Then by days left
        return (a['days_left'] as int).compareTo(b['days_left'] as int);
      });

      if (mounted) setState(() => _warnings = allWarnings);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_warnings.isEmpty) return const SizedBox.shrink();

    // Reset index if out of bounds
    if (_currentWarningIndex >= _warnings.length) {
      _currentWarningIndex = 0;
    }

    final warning = _warnings[_currentWarningIndex];
    final isExpired = warning['is_expired'] == true;
    final daysLeft = warning['days_left'] as int;
    final teacherName = warning['teacher_name'] as String;
    final subjectName = warning['subject_name'] as String;
    final type = warning['type'] as String? ?? 'trial';

    // ✅ Different colors and messages based on type and status
    final bool isSubscription = type == 'subscription';
    
    Color bgColor;
    String message;
    String buttonText;
    IconData icon;

    if (isExpired) {
  bgColor = Colors.red.shade800;
  icon = Icons.lock_outline;
  // ✅ Fix: Trial ended = Subscribe, Subscription ended = Renew
  buttonText = isSubscription ? 'Renew' : 'Subscribe';
  message = isSubscription
      ? '$subjectName — Subscription expired'
      : '$subjectName with $teacherName — Trial ended';
} else if (daysLeft <= 3) {
  bgColor = daysLeft == 0 ? Colors.red.shade700 : Colors.orange.shade800;
  icon = Icons.warning_amber_rounded;
  // ✅ Fix: Trial expiring = Subscribe Now, Subscription expiring = Renew
  buttonText = isSubscription ? 'Renew' : 'Subscribe Now';
  message = isSubscription
      ? '$subjectName — Subscription ends in $daysLeft day(s)'
      : '$subjectName with $teacherName — $daysLeft day(s) left';
} else {
  bgColor = Colors.amber.shade800;
  icon = Icons.timer_outlined;
  // ✅ Fix: More than 3 days
  buttonText = isSubscription ? 'Renew Early' : 'Subscribe Now';
  message = isSubscription
      ? '$subjectName — Subscription ends in $daysLeft days'
      : '$subjectName with $teacherName — $daysLeft day(s) left';
}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgColor, bgColor.withOpacity(0.8)],
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
  onPressed: () async {
    // ✅ Load enrollment details to get subjectId and levelId
    final enrollmentId = warning['enrollment_id'] as String;
    
    Map<String, dynamic>? enrollment;
    try {
      final response = await Supabase.instance.client
          .from('enrollments')
          .select('subject_id, level_id, teacher_id')
          .eq('id', enrollmentId)
          .maybeSingle();
      enrollment = response;
    } catch (_) {}

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            teacherId: warning['teacher_id'] as String,
            teacherName: teacherName,
            subjectName: subjectName,
            enrollmentId: enrollmentId,
            subjectId: enrollment?['subject_id'] as String?,  // ✅ Pass
            levelId: enrollment?['level_id'] as String?,      // ✅ Pass
          ),
        ),
      ).then((_) => _loadWarnings());
    }
  },
  style: TextButton.styleFrom(
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    backgroundColor: Colors.white.withOpacity(0.15),
  ),
  child: Text(
    buttonText,
    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
  ),
),
              if (_warnings.length > 1)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentWarningIndex = (_currentWarningIndex + 1) % _warnings.length;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      '${_currentWarningIndex + 1}/${_warnings.length}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _warnings.removeAt(_currentWarningIndex);
                    if (_currentWarningIndex >= _warnings.length) {
                      _currentWarningIndex = 0;
                    }
                  });
                },
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}