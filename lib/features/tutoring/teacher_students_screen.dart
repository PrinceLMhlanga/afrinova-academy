import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'tutoring_screen.dart';

class TeacherStudentsScreen extends StatefulWidget {
  const TeacherStudentsScreen({super.key});

  @override
  State<TeacherStudentsScreen> createState() => _TeacherStudentsScreenState();
}

class _TeacherStudentsScreenState extends State<TeacherStudentsScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _enrollments = [];
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupedData = {};
  Map<String, int> _unreadCounts = {};
  bool _isLoading = true;
  Map<String, Map<String, dynamic>> _studentInfo = {};

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get teacher's students grouped by level and subject
      final response = await Supabase.instance.client
          .from('enrollments')
          .select('''
            id,
            student_id,
            subject_id,
            level_id,
            status,
            is_subscribed,
            subscription_expires_at,
            trial_ends_at,
            plan_features,
            student:student_id(
              id,
              display_name,
              full_name,
              avatar_url
            ),
            subject:subject_id(
              id,
              name,
              color_hex,
              icon_name
            ),
            level:level_id(
              id,
              name,
              display_order
            )
          ''')
          .eq('teacher_id', userId)
          .inFilter('status', ['approved', 'paid'])
          .order('display_order', referencedTable: 'level');

      // Filter for tutoring access
      final now = DateTime.now();
      final tutoringEnrollments = response.where((e) {
        // Check access validity
        bool hasAccess = false;
        if (e['is_subscribed'] == true && e['subscription_expires_at'] != null) {
          final expiry = DateTime.parse(e['subscription_expires_at'] as String);
          if (expiry.isAfter(now)) hasAccess = true;
        }
        if (e['trial_ends_at'] != null) {
          final trialEnd = DateTime.parse(e['trial_ends_at'] as String);
          if (trialEnd.isAfter(now)) hasAccess = true;
        }
        if (!hasAccess) return false;

        // Check plan features for tutoring
        final features = e['plan_features'];
        if (features is List && features.isNotEmpty) {
          return features.any((f) =>
              f.toString().toLowerCase().contains('one-on-one') ||
              f.toString().toLowerCase().contains('support'));
        }
        return false;
      }).toList();

      // Group by level → subject
      final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
      for (final enrollment in tutoringEnrollments) {
        final level = enrollment['level'] as Map<String, dynamic>;
        final subject = enrollment['subject'] as Map<String, dynamic>;
        final levelName = level['name'] ?? 'Other';
        final subjectName = subject['name'] ?? 'Other';

        if (!grouped.containsKey(levelName)) {
          grouped[levelName] = {};
        }
        if (!grouped[levelName]!.containsKey(subjectName)) {
          grouped[levelName]![subjectName] = [];
        }
        grouped[levelName]![subjectName]!.add(enrollment);
      }

      // Load unread counts
      await _loadStudentDetails(tutoringEnrollments);

      if (mounted) {
        setState(() {
          _enrollments = tutoringEnrollments;
          _groupedData = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Change from Map<String, int> to store more info


Future<void> _loadStudentDetails(List<Map<String, dynamic>> enrollments) async {
  final userId = _authService.currentUserId;
  if (userId == null) return;

  for (final enrollment in enrollments) {
    final studentId = enrollment['student_id'] as String;
    try {
      final session = await Supabase.instance.client
          .from('tutoring_sessions')
          .select('id, teacher_last_read_at')
          .eq('student_id', studentId)
          .eq('teacher_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (session != null) {
        final sessionId = session['id'] as String;
        final lastReadAt = session['teacher_last_read_at'] as String?;
        
        // Get last message
        final messages = await Supabase.instance.client
            .from('tutoring_messages')
            .select('content, created_at, sender_id')
            .eq('session_id', sessionId)
            .order('created_at', ascending: false)
            .limit(1);
        
        String lastMsg = 'Tap to start tutoring';
        String lastTime = '';
        
        if (messages.isNotEmpty) {
          final msg = messages.first;
          final msgTime = DateTime.parse(msg['created_at'] as String).toLocal();
          final now = DateTime.now();
          
          if (now.difference(msgTime).inDays == 0) {
            lastTime = '${msgTime.hour}:${msgTime.minute.toString().padLeft(2, '0')}';
          } else if (now.difference(msgTime).inDays == 1) {
            lastTime = 'Yesterday';
          } else {
            lastTime = '${msgTime.day}/${msgTime.month}';
          }
          
          lastMsg = msg['content'] as String? ?? 'File shared';
        }
        
        // Count unread
        int count = 0;
        if (lastReadAt != null) {
          count = await Supabase.instance.client
              .from('tutoring_messages')
              .count(CountOption.exact)
              .eq('session_id', sessionId)
              .neq('sender_id', userId)
              .gt('created_at', lastReadAt);
        } else {
          count = await Supabase.instance.client
              .from('tutoring_messages')
              .count(CountOption.exact)
              .eq('session_id', sessionId)
              .neq('sender_id', userId);
        }
        
        _studentInfo[studentId] = {
          'message': lastMsg,
          'time': lastTime,
          'unread': count,
        };
      }
    } catch (e) {
      debugPrint('Error for $studentId: $e');
    }
  }
}

  Future<void> _loadUnreadCounts(List<Map<String, dynamic>> enrollments) async {
  final userId = _authService.currentUserId;
  if (userId == null) return;

  for (final enrollment in enrollments) {
    final studentId = enrollment['student_id'] as String;
    try {
      // Find active session with this student
      final session = await Supabase.instance.client
          .from('tutoring_sessions')
          .select('id, teacher_last_read_at')
          .eq('student_id', studentId)
          .eq('teacher_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (session != null) {
        final sessionId = session['id'] as String;
        final lastReadAt = session['teacher_last_read_at'] as String?;
        
        int count = 0;
        if (lastReadAt != null) {
          // Only count messages after teacher last read
          count = await Supabase.instance.client
              .from('tutoring_messages')
              .count(CountOption.exact)
              .eq('session_id', sessionId)
              .neq('sender_id', userId)  // Don't count teacher's own messages
              .gt('created_at', lastReadAt);
        } else {
          // Never read - count all from student
          count = await Supabase.instance.client
              .from('tutoring_messages')
              .count(CountOption.exact)
              .eq('session_id', sessionId)
              .neq('sender_id', userId);
        }
        
        _unreadCounts[studentId] = count;
      }
    } catch (e) {
      debugPrint('Count error for $studentId: $e');
    }
  }
}

  void _openChat(Map<String, dynamic> enrollment) async {
  final student = enrollment['student'] as Map<String, dynamic>;
  final subject = enrollment['subject'] as Map<String, dynamic>?;
  final userId = _authService.currentUserId;
  final studentId = student['id'] as String;

  // ✅ Mark as read when teacher opens chat
  if (userId != null) {
    await Supabase.instance.client
        .from('tutoring_sessions')
        .update({'teacher_last_read_at': DateTime.now().toUtc().toIso8601String()}) 
        .eq('student_id', studentId)
        .eq('teacher_id', userId)
        .eq('status', 'active');
  }

  if (mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TutoringScreen(
          teacherId: userId!,
          studentId: studentId,
          teacherName: student['display_name'] ?? student['full_name'] ?? 'Student',
          subjectId: subject?['id'] as String?,
          subjectName: subject?['name'] as String?,
        ),
      ),
    ).then((_) => _loadStudents());
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Students'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStudents,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _enrollments.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadStudents,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _groupedData.entries.map((levelEntry) {
                      return _buildLevelGroup(levelEntry.key, levelEntry.value);
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
            'No Students Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Students with tutoring access\nwill appear here',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelGroup(String levelName, Map<String, List<Map<String, dynamic>>> subjects) {
    final totalStudents = subjects.values.fold(0, (sum, list) => sum + list.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Level header
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A237E), Color(0xFF283593)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1A237E).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.school_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  levelName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$totalStudents student${totalStudents > 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // Subject sub-groups
        ...subjects.entries.map((subjectEntry) {
          return _buildSubjectGroup(subjectEntry.key, subjectEntry.value);
        }),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSubjectGroup(String subjectName, List<Map<String, dynamic>> students) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subject header
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF5C6BC0),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                subjectName,
                style: const TextStyle(
                  color: Color(0xFF1A237E),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${students.length}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),

        // Student cards
        ...students.map((enrollment) => _buildStudentCard(enrollment)),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> enrollment) {
   final student = enrollment['student'] as Map<String, dynamic>;
  final studentName = student['display_name'] ?? student['full_name'] ?? 'Student';
  final avatarUrl = student['avatar_url'] as String?;
  final studentId = student['id'] as String;
  final info = _studentInfo[studentId] ?? {};
  final unreadCount = info['unread'] as int? ?? 0;
  final lastMessage = info['message'] as String? ?? 'Tap to start tutoring';
  final lastTime = info['time'] as String? ?? '';
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
          onTap: () => _openChat(enrollment),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar with unread badge
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl == null
                          ? Text(
                              studentName[0].toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF1A237E),
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            )
                          : null,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                

                // Student info
                const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(studentName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF1A237E)))),
                  if (lastTime.isNotEmpty)
                    Text(lastTime, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      lastMessage,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: unreadCount > 0 ? const Color(0xFF4CAF50) : Colors.grey.shade600, fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.normal),
                    ),
                  ),
                  if (unreadCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Text('New', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF4CAF50))),
                    ),
                ],
              ),
            ],
          ),
        ),

                // Chat icon
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: unreadCount > 0
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : const Color(0xFF1A237E).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    unreadCount > 0 ? Icons.mark_chat_unread : Icons.chat_bubble_outline,
                    color: unreadCount > 0 ? const Color(0xFF4CAF50) : const Color(0xFF1A237E),
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}