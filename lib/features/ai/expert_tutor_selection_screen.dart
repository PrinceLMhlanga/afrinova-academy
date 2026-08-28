import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/expert_tutor_service.dart';
import 'expert_tutor_screen.dart';

class ExpertTutorSelectionScreen extends StatefulWidget {
  const ExpertTutorSelectionScreen({super.key});

  @override
  State<ExpertTutorSelectionScreen> createState() => _ExpertTutorSelectionScreenState();
}

class _ExpertTutorSelectionScreenState extends State<ExpertTutorSelectionScreen> {
  final AuthService _authService = AuthService();
  final ExpertTutorService _expertService = ExpertTutorService();
  
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  List<Map<String, dynamic>> _activeSessions = [];
  
  String? _studentLevelId;
  String? _studentLevelName;
  String? _selectedSubjectId;
  String? _selectedTopicId;
  
  bool _isLoading = true;
  bool _isLoadingTopics = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // ✅ Get student's level from profiles
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('level_id, levels(name)')
          .eq('id', userId)
          .single();
      
      _studentLevelId = profile['level_id'] as String?;
      _studentLevelName = (profile['levels'] as Map?)?['name'] as String? ?? 'Your Level';

      // Load subjects
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .eq('is_active', true)
          .order('name');
      
      // Load active sessions for this student
      final activeSessions = await _expertService.getStudentSessions(userId);
      
      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _activeSessions = activeSessions.where((s) => s['session_status'] == 'active').toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopics(String subjectId) async {
  setState(() => _isLoadingTopics = true);
  
  try {
    final levelId = _studentLevelId;  // ✅ Local variable
    
    if (levelId == null) {
      setState(() => _isLoadingTopics = false);
      return;
    }
    
    // Load topics that have syllabus outline
    final topics = await Supabase.instance.client
        .from('topics')
        .select('*')
        .eq('subject_id', subjectId)
        .eq('level_id', levelId)  // ✅ Use local non-null variable
        .not('syllabus_outline', 'is', null)
        .order('display_order');
    
    if (mounted) {
      setState(() {
        _topics = List<Map<String, dynamic>>.from(topics);
        _selectedTopicId = null;
        _isLoadingTopics = false;
      });
    }
  } catch (e) {
    debugPrint('Error loading topics: $e');
    if (mounted) setState(() => _isLoadingTopics = false);
  }
}

  // ✅ Check if student has active session for this topic
  Map<String, dynamic>? _getActiveSessionForTopic(String topicId) {
    for (final session in _activeSessions) {
      if (session['topic_id'] == topicId) {
        return session;
      }
    }
    return null;
  }

  // ✅ Start or resume session
  void _startOrResumeSession(Map<String, dynamic> topic, Map<String, dynamic> subject) {
    final existingSession = _getActiveSessionForTopic(topic['id'] as String);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExpertTutorScreen(
          topicId: topic['id'] as String,
          topicName: topic['name'] as String,
          subjectId: subject['id'] as String,
          subjectName: subject['name'] as String,
          levelId: _studentLevelId,
          levelName: _studentLevelName,
          sessionId: existingSession?['id'] as String?, // ✅ Pass existing session if any
        ),
      ),
    ).then((_) {
      // Reload sessions when returning
      _loadInitialData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Expert Tutor'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A237E), Color(0xFF283593)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Expert Tutor Mode',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Teacher-led learning with syllabus mastery',
                                style: TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // ✅ Student level badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.grade, color: Color(0xFF1A237E), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Level: $_studentLevelName',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // Active sessions section
                  if (_activeSessions.isNotEmpty) ...[
                    const Text(
                      'Continue Learning',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Resume where you left off',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ..._activeSessions.map((session) {
                      final topicName = session['topics']?['name'] as String? ?? 'Topic';
                      final subjectName = session['subjects']?['name'] as String? ?? 'Subject';
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withOpacity(0.3)),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.play_arrow, color: Colors.green, size: 20),
                          ),
                          title: Text(topicName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(subjectName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ExpertTutorScreen(
                                  topicId: session['topic_id'] as String,
                                  topicName: topicName,
                                  subjectId: session['subject_id'] as String?,
                                  subjectName: subjectName,
                                  levelId: _studentLevelId,
                                  levelName: _studentLevelName,
                                  sessionId: session['id'] as String,
                                ),
                              ),
                            ).then((_) => _loadInitialData());
                          },
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                  ],
                  
                  // Subject selection
                  const Text(
                    'Start New Topic',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select a subject to see available topics',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  
                  // Subjects grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: _subjects.length,
                    itemBuilder: (context, index) {
                      final subject = _subjects[index];
                      final isSelected = _selectedSubjectId == subject['id'];
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedSubjectId = subject['id'] as String;
                          });
                          _loadTopics(subject['id'] as String);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1A237E) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade200,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _getSubjectIcon(subject['icon_name'] as String?),
                                color: isSelected ? Colors.white : const Color(0xFF1A237E),
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                subject['name'] as String,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Topics list
                  if (_isLoadingTopics)
                    const Center(child: CircularProgressIndicator())
                  else if (_topics.isNotEmpty) ...[
                    const Text(
                      'Available Topics',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    ..._topics.map((topic) {
                      final existingSession = _getActiveSessionForTopic(topic['id'] as String);
                      final isSelected = _selectedTopicId == topic['id'];
                      final objectiveCount = _countObjectives(topic['syllabus_outline'] as String?);
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF1A237E).withOpacity(0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade200,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: existingSession != null
                                  ? Colors.green.withOpacity(0.1)
                                  : const Color(0xFF1A237E).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              existingSession != null ? Icons.play_arrow : Icons.menu_book,
                              color: existingSession != null ? Colors.green : const Color(0xFF1A237E),
                              size: 20,
                            ),
                          ),
                          title: Text(topic['name'] as String),
                          subtitle: Text(
                            existingSession != null
                                ? 'Continue session • $objectiveCount objectives'
                                : '$objectiveCount objectives',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          trailing: existingSession != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'IN PROGRESS',
                                    style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                )
                              : const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () {
                            final subject = _subjects.firstWhere((s) => s['id'] == _selectedSubjectId);
                            _startOrResumeSession(topic, subject);
                          },
                        ),
                      );
                    }),
                  ] else if (_selectedSubjectId != null && !_isLoadingTopics)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey, size: 32),
                          SizedBox(height: 8),
                          Text(
                            'No topics with syllabus available for this subject',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // Helper: Count objectives in syllabus outline
  int _countObjectives(String? syllabusOutline) {
    if (syllabusOutline == null || syllabusOutline.isEmpty) return 0;
    final lines = syllabusOutline.split('\n');
    return lines.where((line) => line.trim().startsWith('OBJ:')).length;
  }

  // Helper: Get subject icon
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
}