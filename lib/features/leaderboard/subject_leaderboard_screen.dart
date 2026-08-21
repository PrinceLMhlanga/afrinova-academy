import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'leaderboard_screen.dart';

class SubjectLeaderboardScreen extends StatefulWidget {
  const SubjectLeaderboardScreen({super.key});

  @override
  State<SubjectLeaderboardScreen> createState() => _SubjectLeaderboardScreenState();
}

class _SubjectLeaderboardScreenState extends State<SubjectLeaderboardScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  
  // Enrolled subjects (with teachers)
  List<Map<String, dynamic>> _enrolledSubjects = [];
  
  // All subjects for AI Assisted Learning (combined enrolled + manual)
  List<Map<String, dynamic>> _aiAssistedSubjects = [];
  
  String? _studentLevelId;
  String? _studentLevelName;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get student's level with name
      final profileResponse = await Supabase.instance.client
          .from('profiles')
          .select('level_id, levels(name)')
          .eq('id', userId)
          .single();
      
      _studentLevelId = profileResponse['level_id'] as String?;
      _studentLevelName = (profileResponse['levels'] as Map?)?['name'] as String? ?? 'Your level';

      // Get enrollments with teacher, subject, AND level info
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('''
            id,
            subject_id,
            teacher_id,
            level_id,
            status,
            subjects(id, name, color_hex, icon_name),
            profiles!teacher_id(full_name, display_name),
            levels(name)
          ''')
          .eq('student_id', userId)
          .inFilter('status', ['paid', 'approved']);

      // Get ALL student subjects (both manual and enrollment source)
      final allStudentSubjects = await Supabase.instance.client
          .from('student_subjects')
          .select('''
            id,
            subject_id,
            source,
            subjects(id, name, color_hex, icon_name)
          ''')
          .eq('student_id', userId);

      // Group enrolled by subject with teacher info
      final enrolledMap = <String, Map<String, dynamic>>{};
      for (final enrollment in enrollments) {
        final subjectId = enrollment['subject_id'] as String;
        final subject = enrollment['subjects'] as Map<String, dynamic>;
        final teacher = enrollment['profiles'] as Map<String, dynamic>?;
        final levelData = enrollment['levels'] as Map<String, dynamic>?;
        
        if (!enrolledMap.containsKey(subjectId)) {
          enrolledMap[subjectId] = {
            'subject_id': subjectId,
            'subject_name': subject['name'] ?? 'Unknown',
            'color_hex': subject['color_hex'] ?? '#1A237E',
            'icon_name': subject['icon_name'] ?? 'book',
            'teachers': <Map<String, dynamic>>[],
            'level_id': enrollment['level_id'] ?? _studentLevelId,
            'level_name': levelData?['name'] ?? _studentLevelName,
          };
        }
        
        (enrolledMap[subjectId]!['teachers'] as List).add({
          'teacher_id': enrollment['teacher_id'],
          'teacher_name': teacher?['display_name'] ?? teacher?['full_name'] ?? 'Teacher',
        });
      }

      // Build AI Assisted Learning subjects (ALL subjects from student_subjects)
      final aiAssistedMap = <String, Map<String, dynamic>>{};
      
      // First add all from student_subjects
      for (final ss in allStudentSubjects) {
        final subjectId = ss['subject_id'] as String;
        final subject = ss['subjects'] as Map<String, dynamic>;
        
        aiAssistedMap[subjectId] = {
          'subject_id': subjectId,
          'subject_name': subject['name'] ?? 'Unknown',
          'color_hex': subject['color_hex'] ?? '#00897B',
          'icon_name': subject['icon_name'] ?? 'book',
          'level_id': _studentLevelId,
          'level_name': _studentLevelName,
        };
      }
      
      // Also add enrolled subjects that might not be in student_subjects
      for (final enrollment in enrollments) {
        final subjectId = enrollment['subject_id'] as String;
        if (!aiAssistedMap.containsKey(subjectId)) {
          final subject = enrollment['subjects'] as Map<String, dynamic>;
          final levelData = enrollment['levels'] as Map<String, dynamic>?;
          
          aiAssistedMap[subjectId] = {
            'subject_id': subjectId,
            'subject_name': subject['name'] ?? 'Unknown',
            'color_hex': subject['color_hex'] ?? '#00897B',
            'icon_name': subject['icon_name'] ?? 'book',
            'level_id': enrollment['level_id'] ?? _studentLevelId,
            'level_name': levelData?['name'] ?? _studentLevelName,
          };
        }
      }

      if (mounted) {
        setState(() {
          _enrolledSubjects = enrolledMap.values.toList();
          _aiAssistedSubjects = aiAssistedMap.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getSubjectColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return const Color(0xFF1A237E);
    final hex = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  IconData _getSubjectIcon(String? iconName) {
    switch (iconName) {
      case 'calculate': return Icons.calculate;
      case 'science': return Icons.science;
      case 'nature': return Icons.eco;
      case 'computer': return Icons.computer;
      case 'menu_book': return Icons.menu_book;
      case 'history_edu': return Icons.history_edu;
      case 'public': return Icons.public;
      case 'business': return Icons.business;
      case 'language': return Icons.language;
      default: return Icons.book;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const BackButton(color: Colors.white),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Subject Leaderboards',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _loadSubjects,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Show student's level
            if (_studentLevelName != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school, size: 14, color: Color(0xFF1A237E)),
                    const SizedBox(width: 6),
                    Text(
                      'Your Level: $_studentLevelName',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A237E),
                      ),
                    ),
                  ],
                ),
              ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
                  : RefreshIndicator(
                      onRefresh: _loadSubjects,
                      color: const Color(0xFF1A237E),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Enrolled Subjects Section
                          if (_enrolledSubjects.isNotEmpty) ...[
                            const Text(
                              'Enrolled Subjects',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A237E),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Compete with classmates from ${_studentLevelName ?? "your level"}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            ..._enrolledSubjects.map((subject) => 
                              _buildSubjectCard(subject, isEnrolled: true)
                            ),
                            const SizedBox(height: 24),
                          ],
                          
                          // AI Assisted Learning Section
                          if (_aiAssistedSubjects.isNotEmpty) ...[
                            const Text(
                              'AI Assisted Learning',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00897B),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Practice exams & flashcards for ${_studentLevelName ?? "your level"} students',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            ..._aiAssistedSubjects.map((subject) => 
                              _buildSubjectCard(subject, isEnrolled: false)
                            ),
                          ],
                          
                          if (_enrolledSubjects.isEmpty && _aiAssistedSubjects.isEmpty)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(60),
                                child: Column(
                                  children: [
                                    Icon(Icons.leaderboard_outlined, size: 64, color: Colors.grey.shade300),
                                    const SizedBox(height: 16),
                                    const Text('No subjects yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    const Text('Add subjects to see leaderboards', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard(Map<String, dynamic> subject, {required bool isEnrolled}) {
    final color = _getSubjectColor(subject['color_hex'] as String?);
    final icon = _getSubjectIcon(subject['icon_name'] as String?);
    final teachers = subject['teachers'] as List? ?? [];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SubjectLeaderboardDetailScreen(
                  subjectId: subject['subject_id'] as String,
                  subjectName: subject['subject_name'] as String,
                  subjectColor: color,
                  isEnrolled: isEnrolled,
                  teacherIds: teachers.map((t) => t['teacher_id'] as String).toList(),
                  teacherNames: teachers.map((t) => t['teacher_name'] as String).toList(),
                  levelId: subject['level_id'] as String?,
                  levelName: subject['level_name'] as String?,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject['subject_name'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (isEnrolled && teachers.isNotEmpty)
                        Text(
                          '${teachers.map((t) => t['teacher_name']).join(', ')}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        )
                      else
                        Text(
                          subject['level_name'] ?? 'Your level',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.leaderboard, size: 14, color: color),
                      const SizedBox(width: 4),
                      Text(
                        'View',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
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