import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../payment/payment_screen.dart';
import 'teacher_content_screen.dart';

class TeachersBySubjectScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final Color subjectColor;
  final String? levelId;
  final String? levelName;

  const TeachersBySubjectScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.subjectColor,
    this.levelId,
    this.levelName,
  });

  @override
  State<TeachersBySubjectScreen> createState() => _TeachersBySubjectScreenState();
}

class _TeachersBySubjectScreenState extends State<TeachersBySubjectScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _enrollments = [];
  Map<String, List<Map<String, dynamic>>> _teacherPricing = {}; // teacherId -> plans
  Map<String, dynamic>? _platformPricing;
  String? _selectedPlanId; // For showing plan details
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    try {
      final userId = _authService.currentUserId;
      String? studentLevelId = widget.levelId;
      
      if (studentLevelId == null && userId != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('level_id')
            .eq('id', userId)
            .maybeSingle();
        studentLevelId = profile?['level_id'] as String?;
      }

      // Load platform pricing
      final platformSettings = await Supabase.instance.client
          .from('platform_settings')
          .select('key, value')
          .inFilter('key', ['price_monthly', 'price_termly']);
      
      double monthly = 10, termly = 25;
      for (final s in platformSettings) {
        if (s['key'] == 'price_monthly') monthly = double.tryParse(s['value'] ?? '10') ?? 10;
        if (s['key'] == 'price_termly') termly = double.tryParse(s['value'] ?? '25') ?? 25;
      }

      // Get teachers for this subject AND matching level
      var query = Supabase.instance.client
          .from('teacher_subjects')
          .select('teacher_id')
          .eq('subject_id', widget.subjectId)
          .eq('is_active', true);
      
      if (studentLevelId != null) {
        query = query.eq('level_id', studentLevelId);
      }

      final response = await query;
      final teacherIds = response.map((t) => t['teacher_id'] as String).toSet().toList();

      // Load teacher profiles
      Map<String, Map<String, dynamic>> profiles = {};
      if (teacherIds.isNotEmpty) {
        final profilesResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, display_name, avatar_url')
            .inFilter('id', teacherIds)
            .eq('is_approved', true);

        for (final p in profilesResponse) {
          profiles[p['id'] as String] = p;
        }
      }

      // Load teacher pricing plans
      // Load teacher pricing plans - ✅ Filter by subject
Map<String, List<Map<String, dynamic>>> teacherPricing = {};
if (teacherIds.isNotEmpty) {
  var pricingQuery = Supabase.instance.client
      .from('teacher_pricing')
      .select()
      .inFilter('teacher_id', teacherIds)
      .eq('is_active', true);

  // ✅ Only show plans for this subject (or plans with no subject = applies to all)
  pricingQuery = pricingQuery.or('subject_id.eq.${widget.subjectId},subject_id.is.null');

  final pricingResponse = await pricingQuery;

  for (final plan in pricingResponse) {
    final tid = plan['teacher_id'] as String;
    teacherPricing.putIfAbsent(tid, () => []);
    teacherPricing[tid]!.add(plan);
  }
}
      // Load enrollments
      if (userId != null) {
        final enrollments = await Supabase.instance.client
            .from('enrollments')
            .select()
            .eq('student_id', userId)
            .eq('subject_id', widget.subjectId);

        if (mounted) setState(() => _enrollments = List<Map<String, dynamic>>.from(enrollments));
      }

      final teachers = teacherIds.map((id) => {
        'teacher_id': id,
        'profile': profiles[id] ?? {'display_name': 'Unknown Teacher', 'full_name': 'Unknown Teacher'},
      }).toList();

      if (mounted) {
        setState(() {
          _teachers = teachers;
          _teacherPricing = teacherPricing;
          _platformPricing = {'monthly': monthly, 'termly': termly};
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading teachers: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getEnrollmentStatus(String teacherId) {
    final enrollment = _enrollments.where((e) => e['teacher_id'] == teacherId).firstOrNull;
    return enrollment?['status'] ?? 'none';
  }

  String? _getEnrollmentId(String teacherId) {
    final enrollment = _enrollments.where((e) => e['teacher_id'] == teacherId).firstOrNull;
    return enrollment?['id'] as String?;
  }

  Future<void> _requestEnrollment(String teacherId) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    try {
      final studentLevelId = widget.levelId ?? await _getStudentLevel(userId);

      await Supabase.instance.client.from('enrollments').insert({
        'student_id': userId,
        'teacher_id': teacherId,
        'subject_id': widget.subjectId,
        'level_id': studentLevelId,
        'status': 'pending',
      });

      _loadTeachers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enrollment requested! ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _getStudentLevel(String userId) async {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('level_id')
        .eq('id', userId)
        .maybeSingle();
    return profile?['level_id'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.levelName != null 
            ? '${widget.subjectName} Teachers (${widget.levelName})'
            : '${widget.subjectName} Teachers'),
        backgroundColor: widget.subjectColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: widget.subjectColor))
          : _teachers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_off, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('No teachers for ${widget.subjectName} yet',
                          style: const TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _teachers.length,
                  itemBuilder: (context, index) {
                    final teacher = _teachers[index];
                    final teacherId = teacher['teacher_id'] as String;
                    final profile = teacher['profile'] as Map<String, dynamic>?;
                    final status = _getEnrollmentStatus(teacherId);
                    final plans = _teacherPricing[teacherId] ?? [];
                    final hasCustomPricing = plans.isNotEmpty;

                    return _buildTeacherCard(
                      teacherId: teacherId,
                      profile: profile,
                      status: status,
                      plans: plans,
                      hasCustomPricing: hasCustomPricing,
                    );
                  },
                ),
    );
  }

  // Get enrollment details for a teacher
Map<String, dynamic>? _getEnrollment(String teacherId) {
  return _enrollments.where((e) => e['teacher_id'] == teacherId).firstOrNull;
}

// Check subscription/trial status and return the right button
Widget _buildActionButton({
  required String teacherId,
  required String displayName,
  required String status,
}) {
  final enrollment = _getEnrollment(teacherId);
  
  // Not enrolled at all
  if (status == 'none') {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: () => _requestEnrollment(teacherId),
        icon: const Icon(Icons.school_rounded, size: 18),
        label: const Text('Enroll Now'),
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.subjectColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // Pending
  if (status == 'pending') {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.hourglass_empty, size: 18),
        label: const Text('Enrollment Pending...'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  // Approved (trial active) or Paid (subscribed)
  if (enrollment != null) {
    final isSubscribed = enrollment['is_subscribed'] == true;
    final trialEndsAt = enrollment['trial_ends_at'] as String?;
    final subscriptionExpiresAt = enrollment['subscription_expires_at'] as String?;
    final enrollmentId = enrollment['id'] as String? ?? '';

    // Check subscription expiry
    if (isSubscribed && subscriptionExpiresAt != null) {
      final expiry = DateTime.parse(subscriptionExpiresAt);
      final daysLeft = expiry.difference(DateTime.now()).inDays;

      if (daysLeft <= 0) {
        // Subscription expired
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber, color: Colors.red, size: 16),
                SizedBox(width: 6),
                Text('Subscription Ended', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    teacherId: teacherId,
                    teacherName: displayName,
                    subjectName: widget.subjectName,
                    enrollmentId: enrollmentId,
                    subjectId: widget.subjectId,
                    levelId: widget.levelId,
                  ),
                ));
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Renew'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]);
      } else if (daysLeft <= 3) {
        // Expiring soon warning
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text('$daysLeft day(s) left ⚠️', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TeacherContentScreen(
                    teacherId: teacherId,
                    teacherName: displayName,
                    subjectName: widget.subjectName,
                    subjectColor: widget.subjectColor,
                  ),
                ));
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Access Content'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.subjectColor,
                side: BorderSide(color: widget.subjectColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]);
      } else {
        // Active subscription
        return SizedBox(
          width: double.infinity, height: 48,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => TeacherContentScreen(
                  teacherId: teacherId,
                  teacherName: displayName,
                  subjectName: widget.subjectName,
                  subjectColor: widget.subjectColor,
                ),
              ));
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Access Content'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.subjectColor,
              side: BorderSide(color: widget.subjectColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        );
      }
    }

    // Check trial expiry
    if (!isSubscribed && trialEndsAt != null) {
      final trialEnd = DateTime.parse(trialEndsAt);
      final daysLeft = trialEnd.difference(DateTime.now()).inDays;

      if (daysLeft <= 0) {
        // Trial ended
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber, color: Colors.red, size: 16),
                SizedBox(width: 6),
                Text('Trial Ended', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity, height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    teacherId: teacherId,
                    teacherName: displayName,
                    subjectName: widget.subjectName,
                    enrollmentId: enrollmentId,
                    subjectId: widget.subjectId,
                    levelId: widget.levelId,
                  ),
                ));
              },
              icon: const Icon(Icons.payment, size: 18),
              label: const Text('Subscribe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.subjectColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]);
      } else if (daysLeft <= 3) {
        // Trial expiring soon
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer, color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text('$daysLeft day(s) free left ⚠️', style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TeacherContentScreen(
                    teacherId: teacherId,
                    teacherName: displayName,
                    subjectName: widget.subjectName,
                    subjectColor: widget.subjectColor,
                  ),
                ));
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Access Content'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.subjectColor,
                side: BorderSide(color: widget.subjectColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ]);
      } else {
        // Active trial
        return SizedBox(
          width: double.infinity, height: 48,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => TeacherContentScreen(
                  teacherId: teacherId,
                  teacherName: displayName,
                  subjectName: widget.subjectName,
                  subjectColor: widget.subjectColor,
                ),
              ));
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Access Content'),
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.subjectColor,
              side: BorderSide(color: widget.subjectColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        );
      }
    }
  }

  // Fallback
  return SizedBox(
    width: double.infinity, height: 48,
    child: OutlinedButton.icon(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TeacherContentScreen(
            teacherId: teacherId,
            teacherName: displayName,
            subjectName: widget.subjectName,
            subjectColor: widget.subjectColor,
          ),
        ));
      },
      icon: const Icon(Icons.play_arrow_rounded, size: 18),
      label: const Text('Access Content'),
      style: OutlinedButton.styleFrom(
        foregroundColor: widget.subjectColor,
        side: BorderSide(color: widget.subjectColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

  Widget _buildTeacherCard({
    required String teacherId,
    required Map<String, dynamic>? profile,
    required String status,
    required List<Map<String, dynamic>> plans,
    required bool hasCustomPricing,
  }) {
    final displayName = profile?['display_name']?.isNotEmpty == true 
        ? profile!['display_name'] 
        : profile?['full_name'] ?? 'Teacher';
    final monthly = _platformPricing?['monthly'] ?? 10;
    final termly = _platformPricing?['termly'] ?? 25;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: widget.subjectColor.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Teacher header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.subjectColor.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: widget.subjectColor.withOpacity(0.1),
                  child: Text(
                    (displayName)[0].toUpperCase(),
                    style: TextStyle(color: widget.subjectColor, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(widget.subjectName, style: TextStyle(color: widget.subjectColor, fontSize: 13)),
                  ]),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: status == 'paid' || status == 'approved'
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : status == 'pending'
                            ? Colors.orange.withOpacity(0.1)
                            : widget.subjectColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status == 'paid' || status == 'approved' ? 'Enrolled' : status == 'pending' ? 'Pending' : 'Available',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: status == 'paid' || status == 'approved'
                          ? const Color(0xFF4CAF50)
                          : status == 'pending' ? Colors.orange : widget.subjectColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Pricing section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (hasCustomPricing) ...[
                // Show custom plans
                const Text('Pricing Plans', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                const SizedBox(height: 10),
                ...plans.map((plan) => _buildPlanCard(plan, teacherId, displayName, status)),
              ] else ...[
                // Show platform default pricing
                const Text('Pricing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                const SizedBox(height: 10),
                _buildDefaultPricingCard(monthly, termly, teacherId, displayName, status),
              ],
            ]),
          ),

          // Action button
          // Action button - with proper trial/subscription logic
Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  child: _buildActionButton(
    teacherId: teacherId,
    displayName: displayName,
    status: status,
  ),
),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, String teacherId, String teacherName, String status) {
    final monthly = (plan['price_monthly'] as num?)?.toDouble() ?? 0;
    final termly = (plan['price_termly'] as num?)?.toDouble() ?? 0;
    final features = List<String>.from(plan['features'] ?? []);
    final planName = plan['plan_name'] ?? 'Plan';
    final description = plan['description'] as String?;
    final enrollmentId = _getEnrollmentId(teacherId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [widget.subjectColor.withOpacity(0.05), widget.subjectColor.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.subjectColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.subjectColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(planName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: widget.subjectColor)),
          ),
          if (plan['is_default'] == true) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Recommended', style: TextStyle(fontSize: 9, color: Color(0xFF4CAF50))),
            ),
          ],
        ]),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
        const SizedBox(height: 10),
        // Pricing
        Row(children: [
          if (monthly > 0)
            Expanded(
              child: GestureDetector(
                onTap: status == 'paid' || status == 'approved' ? null : () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                      teacherId: teacherId,
                      teacherName: teacherName,
                      subjectName: widget.subjectName,
                      enrollmentId: enrollmentId ?? '',
                    ),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.subjectColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: widget.subjectColor.withOpacity(0.15)),
                  ),
                  child: Column(children: [
                    Text('\$${monthly.toStringAsFixed(0)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: widget.subjectColor)),
                    const Text('/month', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                ),
              ),
            ),
          if (monthly > 0 && termly > 0) const SizedBox(width: 10),
          if (termly > 0)
            Expanded(
              child: GestureDetector(
                onTap: status == 'paid' || status == 'approved' ? null : () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                      teacherId: teacherId,
                      teacherName: teacherName,
                      subjectName: widget.subjectName,
                      enrollmentId: enrollmentId ?? '',
                    ),
                  ));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
                  ),
                  child: Column(children: [
                    Text('\$${termly.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                    const Text('/term', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text('Save \$${(monthly * 3 - termly).toStringAsFixed(0)}', style: const TextStyle(fontSize: 9, color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
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
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
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

  Widget _buildDefaultPricingCard(double monthly, double termly, String teacherId, String teacherName, String status) {
    final enrollmentId = _getEnrollmentId(teacherId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [widget.subjectColor.withOpacity(0.05), widget.subjectColor.withOpacity(0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.subjectColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: widget.subjectColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Standard Plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: widget.subjectColor)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: widget.subjectColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.subjectColor.withOpacity(0.15)),
              ),
              child: Column(children: [
                Text('\$${monthly.toStringAsFixed(0)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: widget.subjectColor)),
                const Text('/month', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
              ),
              child: Column(children: [
                Text('\$${termly.toStringAsFixed(0)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
                const Text('/term', style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text('Save \$${(monthly * 3 - termly).toStringAsFixed(0)}', style: const TextStyle(fontSize: 9, color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}