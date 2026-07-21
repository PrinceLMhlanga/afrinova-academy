import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'tutoring_screen.dart';


class MyTutorsScreen extends StatefulWidget {
  const MyTutorsScreen({super.key});

  @override
  State<MyTutorsScreen> createState() => _MyTutorsScreenState();
}

class _MyTutorsScreenState extends State<MyTutorsScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _enrollments = [];
  Map<String, List<Map<String, dynamic>>> _groupedBySubject = {};
  bool _isLoading = true;

  String lastMessage = '';
  String lastTime = '';

  @override
  void initState() {
    super.initState();
    _loadEnrollments();
  }

  Future<void> _loadEnrollments() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get approved/paid enrollments with teacher and subject info
      final response = await Supabase.instance.client
          .from('enrollments')
          .select('''
            id,
            teacher_id,
            subject_id,
            status,
            is_subscribed,
            subscription_expires_at,
            trial_ends_at,
            plan_features,
            level_id,
            teacher:teacher_id(
              id,
              display_name,
              full_name,
              avatar_url,
              is_subscribed
            ),
            subject:subject_id(
              id,
              name,
              color_hex,
              icon_name
            )
          ''')
          .eq('student_id', userId)
          .inFilter('status', ['approved', 'paid']);
          
      // Filter: only show tutors where student has access
      final now = DateTime.now();
      final validEnrollments = response.where((e) {
        // Check subscription
        if (e['is_subscribed'] == true && e['subscription_expires_at'] != null) {
          final expiry = DateTime.parse(e['subscription_expires_at'] as String);
          if (expiry.isAfter(now)) return true;
        }
        // Check trial
        if (e['trial_ends_at'] != null) {
          final trialEnd = DateTime.parse(e['trial_ends_at'] as String);
          if (trialEnd.isAfter(now)) return true;
        }
        return false;
      }).toList();

      // Filter for one-on-one support feature
      // Filter for one-on-one support - strict check
final oneOnOneEnrollments = validEnrollments.where((e) {
  final features = e['plan_features'];
  
  // Must have actual features
  if (features is List && features.isNotEmpty) {
    return features.any((f) => 
      f.toString().toLowerCase().contains('one-on-one') || 
      f.toString().toLowerCase().contains('support')
    );
  }
  
  // No features or empty = no access
  return false;
}).toList();

      // Group by subject
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final enrollment in oneOnOneEnrollments) {
        final subject = enrollment['subject'] as Map<String, dynamic>?;
        final subjectName = subject?['name'] ?? 'Other';
        
        if (!grouped.containsKey(subjectName)) {
          grouped[subjectName] = [];
        }
        grouped[subjectName]!.add(enrollment);
      }

      if (mounted) {
        setState(() {
          _enrollments = oneOnOneEnrollments;
          _groupedBySubject = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading tutors: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, String?>> _getLastMessage(String teacherId) async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return {'message': 'Tap to start tutoring', 'time': ''};
    
    // Find active session
    final session = await Supabase.instance.client
        .from('tutoring_sessions')
        .select('id')
        .eq('student_id', userId)
        .eq('teacher_id', teacherId)
        .eq('status', 'active')
        .maybeSingle();
    
    if (session != null) {
      // Get last message
      final messages = await Supabase.instance.client
          .from('tutoring_messages')
          .select('content, created_at')
          .eq('session_id', session['id'] as String)
          .order('created_at', ascending: false)
          .limit(1);
      
      if (messages.isNotEmpty) {
        final msg = messages.first;
        final time = DateTime.parse(msg['created_at'] as String);
        final now = DateTime.now();
        String timeStr;
        
        if (now.difference(time).inDays == 0) {
          timeStr = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
        } else if (now.difference(time).inDays == 1) {
          timeStr = 'Yesterday';
        } else {
          timeStr = '${time.day}/${time.month}';
        }
        
        return {
          'message': msg['content'] as String? ?? 'File shared',
          'time': timeStr,
        };
      }
    }
    
    return {
      'message': 'No messages yet • Tap to start',
      'time': '',
    };
  } catch (e) {
    return {'message': 'Tap to start tutoring', 'time': ''};
  }
}

  void _openChat(Map<String, dynamic> enrollment) {
    final teacher = enrollment['teacher'] as Map<String, dynamic>;
    final subject = enrollment['subject'] as Map<String, dynamic>?;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TutoringScreen(
          teacherId: teacher['id'] as String,
          studentId: _authService.currentUserId!,
          teacherName: teacher['display_name'] ?? teacher['full_name'] ?? 'Tutor',
          subjectId: subject?['id'] as String?,
          subjectName: subject?['name'] as String?,
        ),
      ),
    ).then((_) => _loadEnrollments()); // Refresh on return
  }

  bool _hasValidAccess(Map<String, dynamic> enrollment) {
    final now = DateTime.now();
    
    if (enrollment['is_subscribed'] == true && enrollment['subscription_expires_at'] != null) {
      final expiry = DateTime.parse(enrollment['subscription_expires_at'] as String);
      if (expiry.isAfter(now)) return true;
    }
    
    if (enrollment['trial_ends_at'] != null) {
      final trialEnd = DateTime.parse(enrollment['trial_ends_at'] as String);
      if (trialEnd.isAfter(now)) return true;
    }
    
    return false;
  }

  String _getAccessStatus(Map<String, dynamic> enrollment) {
    if (!_hasValidAccess(enrollment)) return 'Expired';
    
    if (enrollment['is_subscribed'] == true && enrollment['subscription_expires_at'] != null) {
      final expiry = DateTime.parse(enrollment['subscription_expires_at'] as String);
      final daysLeft = expiry.difference(DateTime.now()).inDays;
      if (daysLeft <= 3) return '$daysLeft days left';
      return 'Subscribed';
    }
    
    if (enrollment['trial_ends_at'] != null) {
      final trialEnd = DateTime.parse(enrollment['trial_ends_at'] as String);
      final daysLeft = trialEnd.difference(DateTime.now()).inDays;
      return '$daysLeft days free';
    }
    
    return 'Active';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Tutors'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadEnrollments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _enrollments.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadEnrollments,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _groupedBySubject.entries.map((entry) {
                      return _buildSubjectGroup(entry.key, entry.value);
                    }).toList(),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline, size: 48, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Tutors Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Subscribe to a teacher to unlock\none-on-one tutoring',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectGroup(String subjectName, List<Map<String, dynamic>> enrollments) {
    // Remove duplicate teachers (keep only one enrollment per teacher per subject)
    final seenTeachers = <String>{};
    final uniqueEnrollments = enrollments.where((e) {
      final teacherId = (e['teacher'] as Map<String, dynamic>)['id'] as String;
      if (seenTeachers.contains(teacherId)) return false;
      seenTeachers.add(teacherId);
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subject header
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  subjectName,
                  style: const TextStyle(
                    color: Color(0xFF1A237E),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${uniqueEnrollments.length} tutor${uniqueEnrollments.length > 1 ? 's' : ''}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        
        // Tutor cards
        ...uniqueEnrollments.map((enrollment) => _buildTutorCard(enrollment)),
        
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTutorCard(Map<String, dynamic> enrollment) {
  final teacher = enrollment['teacher'] as Map<String, dynamic>;
  final teacherId = teacher['id'] as String;
  final teacherName = teacher['display_name'] ?? teacher['full_name'] ?? 'Tutor';
  final avatarUrl = teacher['avatar_url'] as String?;
  final hasAccess = _hasValidAccess(enrollment);
  final status = _getAccessStatus(enrollment);

  return FutureBuilder<Map<String, String?>>(
    future: _getLastMessage(teacherId),
    builder: (context, snapshot) {
      final data = snapshot.data ?? {};
      final lastMessage = data['message'] ?? (hasAccess ? 'Tap to start tutoring' : 'Access required');
      final lastTime = data['time'] ?? '';

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: hasAccess ? () => _openChat(enrollment) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null
                            ? Text(
                                teacherName[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF1A237E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: hasAccess ? const Color(0xFF4CAF50) : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                teacherName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                            ),
                            if (lastTime.isNotEmpty)
                              Text(
                                lastTime,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: hasAccess ? Colors.grey.shade600 : Colors.grey.shade400,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: hasAccess
                                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: hasAccess ? const Color(0xFF4CAF50) : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  if (hasAccess)
                    Container(
                      width: 40,
                      height: 40,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        color: Color(0xFF1A237E),
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
}