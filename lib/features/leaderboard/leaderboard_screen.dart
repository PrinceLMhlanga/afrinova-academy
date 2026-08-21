import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class SubjectLeaderboardDetailScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final Color subjectColor;
  final bool isEnrolled;
  final List<String> teacherIds; // Empty for self-study
  final List<String> teacherNames;
  final String? levelId; // null for self-study
  final String? levelName;

  const SubjectLeaderboardDetailScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.subjectColor,
    required this.isEnrolled,
    required this.teacherIds,
    this.teacherNames = const [],
    this.levelId,
    this.levelName,
  });

  @override
  State<SubjectLeaderboardDetailScreen> createState() => _SubjectLeaderboardDetailScreenState();
}

class _SubjectLeaderboardDetailScreenState extends State<SubjectLeaderboardDetailScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  
  List<Map<String, dynamic>> _leaders = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _selectedMetric = 'overall'; // 'overall', 'lessons', 'mcqs', 'papers', 'flashcards'
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.isEnrolled ? 4 : 2, vsync: this);
    _loadLeaderboard();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

Future<void> _loadLeaderboard() async {
  if (!_isRefreshing) {
    setState(() => _isLoading = true);
  }
  
  try {
    final userId = _authService.currentUserId;
    
    // Get current student's level
    String? currentStudentLevelId;
    if (userId != null) {
      final currentProfile = await Supabase.instance.client
          .from('profiles')
          .select('level_id')
          .eq('id', userId)
          .single();
      currentStudentLevelId = currentProfile['level_id'] as String?;
    }
    
    if (currentStudentLevelId == null) {
      if (mounted) {
        setState(() {
          _leaders = [];
          _isLoading = false;
          _isRefreshing = false;
        });
      }
      return;
    }
    
    List<String> studentIds = [];
    
    if (widget.isEnrolled) {
      // ===== ENROLLED SUBJECT =====
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('student_id')
          .eq('subject_id', widget.subjectId)
          .inFilter('teacher_id', widget.teacherIds)
          .inFilter('status', ['paid', 'approved']);
      
      final allStudentIds = enrollments.map((e) => e['student_id'] as String).toSet().toList();
      
      if (allStudentIds.isNotEmpty) {
        final levelIdToUse = widget.levelId ?? currentStudentLevelId;
        
        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id')
            .inFilter('id', allStudentIds)
            .eq('level_id', levelIdToUse);
        
        studentIds = profiles.map((p) => p['id'] as String).toList();
      }
    } else {
      // ===== AI ASSISTED LEARNING =====
      // Get ALL students with this subject (both enrolled and self-study)
      final studentSubjects = await Supabase.instance.client
          .from('student_subjects')
          .select('student_id')
          .eq('subject_id', widget.subjectId);
      
      final allStudentIds = studentSubjects.map((s) => s['student_id'] as String).toSet().toList();
      
      if (allStudentIds.isNotEmpty) {
        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id')
            .inFilter('id', allStudentIds)
            .eq('level_id', currentStudentLevelId);
        
        studentIds = profiles.map((p) => p['id'] as String).toList();
      }
    }

    if (studentIds.isEmpty) {
      if (mounted) {
        setState(() {
          _leaders = [];
          _isLoading = false;
          _isRefreshing = false;
        });
      }
      return;
    }

    // Get profiles for filtered students
    final profiles = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name, avatar_url, school_name, level_id')
        .inFilter('id', studentIds);

    final leaders = <Map<String, dynamic>>[];

    for (final profile in profiles) {
      final studentId = profile['id'] as String;
      
      // ===== OPTIMIZED: Use Future.wait for parallel queries =====
      
      if (widget.isEnrolled) {
        // ========== ENROLLED SUBJECT METRICS ==========
final results = await Future.wait([
  // 1. Lessons completed
  Supabase.instance.client
      .from('lesson_progress')
      .select('id')
      .eq('student_id', studentId)
      .eq('completed', true),
  
  // 2. MCQ exam attempts
  Supabase.instance.client
      .from('exam_attempts')
      .select('percentage')
      .eq('student_id', studentId)
      .not('completed_at', 'is', null),
  
  // 3. Exam papers
  Supabase.instance.client
      .from('exam_answers')
      .select('paper_id, marks_awarded, status, exam_papers!inner(total_marks)')
      .eq('student_id', studentId)
      .eq('status', 'marked'),
]);

// Process lessons
final lessonProgress = results[0] as List;
int completedLessons = lessonProgress.length;
final lessonPoints = completedLessons * 10; // ✅ 10 points per lesson

// Process MCQs
final mcqAttempts = results[1] as List;
double mcqSum = 0;
int mcqCount = mcqAttempts.length;
for (final m in mcqAttempts) {
  mcqSum += (m['percentage'] as num?)?.toDouble() ?? 0;
}
final avgMcq = mcqCount > 0 ? mcqSum / mcqCount : 0.0;
final mcqPoints = (avgMcq * 0.5).round(); // ✅ 50% of average as points

// Process exam papers
final paperAnswers = results[2] as List;
double paperSum = 0;
int paperCount = 0;
final groupedPapers = <String, Map<String, dynamic>>{};

for (final p in paperAnswers) {
  final paperId = p['paper_id'] as String;
  if (!groupedPapers.containsKey(paperId)) {
    groupedPapers[paperId] = {
      'total_marks': p['exam_papers']?['total_marks'] ?? 0,
      'marks_awarded': 0,
    };
  }
  groupedPapers[paperId]!['marks_awarded'] = 
      (groupedPapers[paperId]!['marks_awarded'] as int) + ((p['marks_awarded'] as int?) ?? 0);
}

for (final paper in groupedPapers.values) {
  final marks = paper['marks_awarded'] as int;
  final total = paper['total_marks'] as int;
  if (total > 0) {
    paperSum += (marks / total) * 100;
    paperCount++;
  }
}
final avgPaper = paperCount > 0 ? paperSum / paperCount : 0.0;
final paperPoints = (avgPaper * 0.5).round(); // ✅ 50% of average as points

// Participation points (capped)
final participationPoints = (mcqCount + paperCount) > 10 ? 20 : (mcqCount + paperCount) * 2;

final overallPoints = lessonPoints + mcqPoints + paperPoints + participationPoints;

leaders.add({
  'student_id': studentId,
  'name': profile['full_name'] ?? 'Student',
  'avatar_url': profile['avatar_url'],
  'school_name': profile['school_name'],
  'points': overallPoints,
  'completed_lessons': completedLessons,
  'lesson_points': lessonPoints, // ✅ Store points
  'avg_mcq': avgMcq,
  'mcq_points': mcqPoints, // ✅ Store points
  'avg_paper': avgPaper,
  'paper_points': paperPoints, // ✅ Store points
  'participation_points': participationPoints, // ✅ Store points
  'is_current_user': studentId == userId,
});
      } else {
        // ========== AI ASSISTED LEARNING METRICS ==========
final results = await Future.wait([
  // 1. Practice exam history
  Supabase.instance.client
      .from('practice_exam_history')
      .select('is_correct')
      .eq('student_id', studentId)
      .eq('subject_id', widget.subjectId)
      .eq('level_id', currentStudentLevelId),
  
  // 2. Flashcards mastery
  Supabase.instance.client
      .from('ai_flashcards')
      .select('times_reviewed, times_correct')
      .eq('student_id', studentId)
      .eq('subject_id', widget.subjectId),
]);

// Process practice exams
final practiceAttempts = results[0] as List;
int correct = 0;
int practiceCount = practiceAttempts.length;
for (final p in practiceAttempts) {
  if (p['is_correct'] == true) correct++;
}
final practiceScore = practiceCount > 0 ? (correct / practiceCount) * 100 : 0.0;

// Process flashcards
final flashcards = results[1] as List;
int flashcardsReviewed = 0;
int flashcardsCorrect = 0;
for (final f in flashcards) {
  flashcardsReviewed += (f['times_reviewed'] as int?) ?? 0;
  flashcardsCorrect += (f['times_correct'] as int?) ?? 0;
}
final flashcardMastery = flashcardsReviewed > 0 
    ? (flashcardsCorrect / flashcardsReviewed) * 100 
    : 0.0;

// ✅ Calculate POINTS for each metric
final practicePoints = (practiceScore * 0.5).round(); // 50% of score as points
final flashcardPoints = (flashcardMastery * 0.5).round(); // 50% of mastery as points
final participationPoints = practiceCount > 10 ? 20 : practiceCount * 2; // Capped at 20

final overallPoints = practicePoints + flashcardPoints + participationPoints;

leaders.add({
  'student_id': studentId,
  'name': profile['full_name'] ?? 'Student',
  'avatar_url': profile['avatar_url'],
  'school_name': profile['school_name'],
  'points': overallPoints,
  'practice_score': practiceScore,
  'practice_points': practicePoints, // ✅ Store points
  'flashcard_mastery': flashcardMastery,
  'flashcard_points': flashcardPoints, // ✅ Store points
  'participation_points': participationPoints, // ✅ Store points
  'is_current_user': studentId == userId,
});
      }
    }

    // Sort by selected metric
    // In _loadLeaderboard, update the sort section:
leaders.sort((a, b) {
  switch (_selectedMetric) {
    case 'lessons':
      return (b['lesson_points'] as int).compareTo(a['lesson_points'] as int);
    case 'mcqs':
      return (b['mcq_points'] as int).compareTo(a['mcq_points'] as int);
    case 'papers':
      return (b['paper_points'] as int).compareTo(a['paper_points'] as int);
    case 'practice':
      return (b['practice_points'] as int).compareTo(a['practice_points'] as int);
    case 'flashcards':
      return (b['flashcard_points'] as int).compareTo(a['flashcard_points'] as int);
    case 'participation':
      return (b['participation_points'] as int).compareTo(a['participation_points'] as int);
    default:
      return (b['points'] as int).compareTo(a['points'] as int);
  }
});

    if (mounted) {
      setState(() {
        _leaders = leaders;
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  } catch (e) {
    debugPrint('Leaderboard error: $e');
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
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
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.subjectColor.withOpacity(0.8),
                    widget.subjectColor,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const BackButton(color: Colors.white),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.subjectName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
  widget.isEnrolled 
      ? '${widget.levelName ?? 'Your level'} • ${widget.teacherNames.isEmpty ? 'Your teachers' : widget.teacherNames.join(', ')}'
      : '${widget.levelName ?? 'Your level'} • Self-study',
  style: const TextStyle(
    fontSize: 11,
    color: Colors.white70,
  ),
  overflow: TextOverflow.ellipsis,
  maxLines: 2,
),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            onPressed: _loadLeaderboard,
                          ),
                        ],
                      ),
                    ),
                    // Metric chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: _buildMetricChips(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _leaders.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                const Text(
                                  'No students yet',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Students will appear here once they start learning',
                                  style: TextStyle(color: Colors.grey),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadLeaderboard,
                          color: widget.subjectColor,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _leaders.length,
                            itemBuilder: (context, index) {
                              final leader = _leaders[index];
                              final rank = index + 1;
                              return _buildLeaderCard(rank, leader);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

 List<Widget> _buildMetricChips() {
  if (widget.isEnrolled) {
    // Enrolled: 5 tabs
    return [
      _buildChip('overall', 'Overall'),
      _buildChip('lessons', 'Lessons'),
      _buildChip('mcqs', 'MCQs'),
      _buildChip('papers', 'Papers'),
      _buildChip('participation', 'Participation'),
    ];
  } else {
    // AI Assisted: 4 tabs
    return [
      _buildChip('overall', 'Overall'),
      _buildChip('practice', 'Practice'),
      _buildChip('flashcards', 'Flashcards'),
      _buildChip('participation', 'Participation'),
    ];
  }
}

// ✅ Add this helper method
Widget _buildChip(String value, String label) {
  final isSelected = _selectedMetric == value;
  return GestureDetector(
    onTap: () {
      setState(() {
        _selectedMetric = value;
        _loadLeaderboard();
      });
    },
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? widget.subjectColor : Colors.white70,
        ),
      ),
    ),
  );
}

  Widget _buildLeaderCard(int rank, Map<String, dynamic> leader) {
  final isCurrentUser = leader['is_current_user'] as bool;
  
  // Get highlighted value based on selected metric
  // In _buildLeaderCard, update the switch statement:
String value;
String label;
switch (_selectedMetric) {
  case 'lessons':
    value = '${leader['lesson_points'] ?? 0}';
    label = 'Lesson Pts';
    break;
  case 'mcqs':
    value = '${leader['mcq_points'] ?? 0}';
    label = 'MCQ Pts';
    break;
  case 'papers':
    value = '${leader['paper_points'] ?? 0}';
    label = 'Paper Pts';
    break;
  case 'practice':
    value = '${leader['practice_points'] ?? 0}';
    label = 'Practice Pts';
    break;
  case 'flashcards':
    value = '${leader['flashcard_points'] ?? 0}';
    label = 'Flashcard Pts';
    break;
  case 'participation':
    value = '${leader['participation_points'] ?? 0}';
    label = 'Participation';
    break;
  default:
    value = '${leader['points']}';
    label = 'Total Pts';
    break;
}

  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isCurrentUser ? widget.subjectColor.withOpacity(0.06) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: isCurrentUser
          ? Border.all(color: widget.subjectColor, width: 2)
          : Border.all(color: Colors.grey.shade100),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.06),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        Row(
          children: [
            // Rank
            SizedBox(
              width: 36,
              child: rank <= 3
                  ? Text(['🥇', '🥈', '🥉'][rank - 1], style: const TextStyle(fontSize: 24))
                  : Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: widget.subjectColor.withOpacity(0.15),
              backgroundImage: leader['avatar_url'] != null
                  ? NetworkImage(leader['avatar_url'])
                  : null,
              child: leader['avatar_url'] == null
                  ? Text(
                      (leader['name'] as String)[0].toUpperCase(),
                      style: TextStyle(
                        color: widget.subjectColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            // Name and school
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          leader['name'] ?? '',
                          style: TextStyle(
                            fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                            color: isCurrentUser ? widget.subjectColor : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: widget.subjectColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'You',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (leader['school_name'] != null)
                    Text(
                      leader['school_name'] as String,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Score badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.subjectColor,
                    widget.subjectColor.withOpacity(0.7),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 7,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        
        // ✅ Show breakdown of points (expandable or always visible)
        const SizedBox(height: 8),
        const Divider(height: 1),
        const SizedBox(height: 8),
        
        // Points breakdown row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (widget.isEnrolled) ...[
              _buildPointsChip('Lessons', leader['lesson_points'] ?? 0, Colors.blue),
              _buildPointsChip('MCQs', leader['mcq_points'] ?? 0, Colors.orange),
              _buildPointsChip('Papers', leader['paper_points'] ?? 0, Colors.teal),
              _buildPointsChip('Participation', leader['participation_points'] ?? 0, Colors.purple),
            ] else ...[
              _buildPointsChip('Practice', leader['practice_points'] ?? 0, Colors.green),
              _buildPointsChip('Flashcards', leader['flashcard_points'] ?? 0, Colors.indigo),
              _buildPointsChip('Participation', leader['participation_points'] ?? 0, Colors.purple),
            ],
          ],
        ),
      ],
    ),
  );
}

Widget _buildPointsChip(String label, int points, Color color) {
  return Column(
    children: [
      Text(
        '$points',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 7, color: Colors.grey),
      ),
    ],
  );
}
}