import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'teacher_content_screen.dart';

class TeachersBySubjectScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final Color subjectColor;
  final String? levelId;   // ✅ Add level
  final String? levelName; // ✅ Add level

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  Future<void> _loadTeachers() async {
    try {
      // ✅ Get student's level from profile
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

      // ✅ Get teachers for this subject AND matching level
      var query = Supabase.instance.client
          .from('teacher_subjects')
          .select('teacher_id, levels!inner(name)')
          .eq('subject_id', widget.subjectId)
          .eq('is_active', true);
      
      if (studentLevelId != null) {
        query = query.eq('level_id', studentLevelId);
      }

      final response = await query;

      final teacherIds = response.map((t) => t['teacher_id'] as String).toSet().toList();

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

      // ✅ Get existing enrollments
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
        'profile': profiles[id] ?? {'display_name': 'Unknown Teacher'},
      }).toList();

      if (mounted) {
        setState(() {
          _teachers = teachers;
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

  Future<void> _requestEnrollment(String teacherId) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    try {
      // ✅ Save enrollment with level_id
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

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: widget.subjectColor.withOpacity(0.1),
                          child: Text(
                            (profile?['display_name'] ?? 'T')[0].toUpperCase(),
                            style: TextStyle(color: widget.subjectColor, fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        title: Text(
                          profile?['display_name'] ?? profile?['full_name'] ?? 'Teacher',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text(widget.subjectName, style: TextStyle(color: widget.subjectColor, fontSize: 13)),
                        trailing: status == 'paid' || status == 'approved'
                            ? ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TeacherContentScreen(
                                        teacherId: teacherId,
                                        teacherName: profile?['display_name'] ?? profile?['full_name'] ?? 'Teacher',
                                        subjectName: widget.subjectName,
                                        subjectColor: widget.subjectColor,
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.subjectColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('View'),
                              )
                            : status == 'pending'
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text('Pending', style: TextStyle(color: Colors.orange, fontSize: 12)),
                                  )
                                : ElevatedButton(
                                    onPressed: () => _requestEnrollment(teacherId),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: widget.subjectColor,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Enroll'),
                                  ),
                      ),
                    );
                  },
                ),
    );
  }
}