import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;
import '../../core/progress_service.dart';

class StudentPerformanceScreen extends StatefulWidget {
  const StudentPerformanceScreen({super.key});

  @override
  State<StudentPerformanceScreen> createState() => _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends State<StudentPerformanceScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  Map<String, dynamic> _studentStats = {};
  List<Map<String, dynamic>> _recentActivity = [];
  List<Map<String, dynamic>> _subjectBreakdown = [];
  List<Map<String, dynamic>> _subjectStats = []; // New: per-subject stats
  bool _isLoading = true;
  bool _isLoadingDetails = false;
  late AnimationController _animationController;
  final ProgressService _progressService = ProgressService(); // Add at top
  // Replace the subject breakdown section with:
  List<Map<String, dynamic>> _groupedStudentList = [];





  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadStudents();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _animationController.forward();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

 Future<void> _loadStudents() async {
    try {
      final teacherId = Supabase.instance.client.auth.currentUser?.id;
      if (teacherId == null) return;

      // ✅ Load with level info
      final response = await Supabase.instance.client
          .from('enrollments')
          .select('student_id, level_id, profiles!student_id(id, full_name, email), levels(name)')
          .eq('teacher_id', teacherId)
          .inFilter('status', ['approved', 'paid']);

      // ✅ Group by level
      final Map<String, Map<String, dynamic>> levelGroups = {};
      final seen = <String>{};

      for (final row in response) {
        final studentId = row['student_id'] as String;
        final levelData = row['levels'] as Map<String, dynamic>?;
        final levelName = levelData?['name'] as String? ?? 'Unknown Level';
        final levelId = row['level_id'] as String? ?? 'unknown';
        
        if (seen.contains(studentId)) continue;
        seen.add(studentId);

        if (!levelGroups.containsKey(levelId)) {
          levelGroups[levelId] = {
            'level_name': levelName,
            'students': <Map<String, dynamic>>[],
          };
        }

        (levelGroups[levelId]!['students'] as List).add({
          'student_id': studentId,
          'full_name': row['profiles']?['full_name'] ?? 'Unknown',
          'email': row['profiles']?['email'] ?? '',
          'level_name': levelName,
        });
      }

      // Convert to sorted list
      final uniqueStudents = levelGroups.entries.map((entry) => {
        'level_name': entry.key != 'unknown' ? entry.value['level_name'] : 'No Level',
        'students': entry.value['students'] as List<Map<String, dynamic>>,
      }).toList()
        ..sort((a, b) => (a['level_name'] as String).compareTo(b['level_name'] as String));

      if (mounted) {
        setState(() {
          _groupedStudentList = uniqueStudents;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading students: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

Future<void> _selectStudent(Map<String, dynamic> student) async {
  setState(() {
    _selectedStudent = student;
    _isLoadingDetails = true;
  });

  try {
    final studentId = student['student_id'] as String;
    final teacherId = Supabase.instance.client.auth.currentUser?.id;
    if (teacherId == null) return;

    // ===== LESSON PROGRESS =====
    final lessonProgress = await Supabase.instance.client
        .from('lesson_progress')
        .select('lesson_id, completed')
        .eq('student_id', studentId);

    final completedLessonIds = lessonProgress
        .where((p) => p['completed'] == true)
        .map((p) => p['lesson_id'] as String)
        .toSet();

    // ===== MCQ EXAMS =====
    final mcqExams = await Supabase.instance.client
        .from('exam_attempts')
        .select('''
          score, 
          total_marks, 
          percentage, 
          completed_at,
          exams!inner (
            id,
            title,
            subject_id,
            subjects!inner (
              id,
              name,
              color_hex
            )
          )
        ''')
        .eq('student_id', studentId)
        .not('completed_at', 'is', null)
        .order('completed_at', ascending: false);

    // ===== PAPER ANSWERS =====
    final rawPaperAnswers = await Supabase.instance.client
        .from('exam_answers')
        .select('''
          paper_id, 
          marks_awarded, 
          status, 
          exam_papers!inner (
            id,
            title, 
            total_marks,
            subject_id,
            subjects!inner (
              id,
              name,
              color_hex
            )
          ),
          submitted_at
        ''')
        .eq('student_id', studentId)
        .order('submitted_at', ascending: false);

    // Group paper answers by paper_id
    final Map<String, Map<String, dynamic>> groupedPapers = {};
    for (final p in rawPaperAnswers) {
      final paperId = p['paper_id'] as String;
      final paperData = p['exam_papers'] as Map<String, dynamic>?;
      final subjectData = paperData?['subjects'] as Map<String, dynamic>?;
      
      if (!groupedPapers.containsKey(paperId)) {
        groupedPapers[paperId] = {
          'paper_id': paperId,
          'title': paperData?['title'] ?? 'Exam Paper',
          'total_marks': paperData?['total_marks'] ?? 0,
          'marks_awarded': 0,
          'status': p['status'],
          'submitted_at': p['submitted_at'],
          'subject_id': paperData?['subject_id'] ?? '',
          'subject_name': subjectData?['name'] ?? '',
          'subject_color': subjectData?['color_hex'] ?? '#00897B',
        };
      }
      groupedPapers[paperId]!['marks_awarded'] = 
          (groupedPapers[paperId]!['marks_awarded'] as int) + ((p['marks_awarded'] as int?) ?? 0);
      if (p['status'] == 'marked') {
        groupedPapers[paperId]!['status'] = 'marked';
      }
    }

    // ===== GET TEACHER'S SUBJECTS =====
    final teacherSubjects = await Supabase.instance.client
        .from('teacher_subjects')
        .select('subject_id, subjects(id, name, color_hex)')
        .eq('teacher_id', teacherId)
        .eq('is_active', true);

    // ===== GET STUDENT ENROLLMENTS =====
    final studentEnrollments = await Supabase.instance.client
        .from('enrollments')
        .select('subject_id')
        .eq('student_id', studentId)
        .inFilter('status', ['approved', 'paid']);

    final studentSubjectIds = studentEnrollments
        .map((e) => e['subject_id'] as String)
        .toSet();

    // ===== BUILD SUBJECT BREAKDOWN AND STATS =====
    final subjectBreakdown = <Map<String, dynamic>>[];
    final subjectStats = <Map<String, dynamic>>[];

    for (final ts in teacherSubjects) {
      final subject = ts['subjects'] as Map<String, dynamic>?;
      if (subject == null) continue;
      
      final subjectId = subject['id'] as String;
      if (!studentSubjectIds.contains(subjectId)) continue;

      final subjectName = subject['name'] as String? ?? 'Unknown';
      final colorHex = subject['color_hex'] as String? ?? '#1A237E';

      // Get topics for this subject
      final topics = await Supabase.instance.client
          .from('teacher_topics')
          .select('id')
          .eq('subject_id', subjectId)
          .eq('teacher_id', teacherId);

      final topicIds = topics.map((t) => t['id'] as String).toList();

      // Get lessons and count completed
      int totalLessons = 0;
      int completedLessons = 0;

      if (topicIds.isNotEmpty) {
        final lessons = await Supabase.instance.client
            .from('lessons')
            .select('id')
            .inFilter('teacher_topic_id', topicIds)
            .eq('is_published', true);

        totalLessons = lessons.length;
        for (final lesson in lessons) {
          if (completedLessonIds.contains(lesson['id'] as String)) {
            completedLessons++;
          }
        }
      }

      // Calculate MCQ stats for this subject
      int mcqTaken = 0;
      double mcqTotal = 0;
      
      for (final attempt in mcqExams) {
        final examData = attempt['exams'] as Map<String, dynamic>?;
        if (examData == null) continue;
        
        final examSubjectId = examData['subject_id'] as String?;
        if (examSubjectId == subjectId) {
          mcqTaken++;
          final pct = attempt['percentage'];
          if (pct != null) {
            mcqTotal += (pct as num).toDouble();
          }
        }
      }

      // Calculate paper stats for this subject
      int papersAttempted = 0;
      int papersMarked = 0;
      int papersAwarded = 0;
      int papersTotal = 0;

      for (final paper in groupedPapers.values) {
        final paperSubjectId = paper['subject_id'] as String?;
        if (paperSubjectId == subjectId) {
          papersAttempted++;
          if (paper['status'] == 'marked') {
            papersMarked++;
            papersAwarded += paper['marks_awarded'] as int;
            papersTotal += paper['total_marks'] as int;
          }
        }
      }

      final mcqAvg = mcqTaken > 0 ? mcqTotal / mcqTaken : 0.0;
      final paperAvg = papersTotal > 0 ? (papersAwarded / papersTotal) * 100 : 0.0;

      // Add to breakdown
      subjectBreakdown.add({
        'subject_name': subjectName,
        'color': colorHex,
        'completed_lessons': completedLessons,
        'total_lessons': totalLessons,
      });

      // Add to stats
      subjectStats.add({
        'subject_name': subjectName,
        'color': colorHex,
        'lessons_completed': completedLessons,
        'lessons_total': totalLessons,
        'mcq_taken': mcqTaken,
        'mcq_avg': mcqAvg,
        'papers_attempted': papersAttempted,
        'papers_marked': papersMarked,
        'paper_avg': paperAvg,
        'papers_awarded': papersAwarded,
        'papers_total': papersTotal,
      });
    }

    // Sort by total lessons
    subjectBreakdown.sort((a, b) => 
        (b['total_lessons'] as int).compareTo(a['total_lessons'] as int));
    subjectStats.sort((a, b) => 
        (b['lessons_total'] as int).compareTo(a['lessons_total'] as int));

    // ===== TOTALS =====
    int totalCompletedLessons = completedLessonIds.length;
    int totalMcqExams = 0;
    int totalPapersAttempted = 0;
    
    // Count only intersection subjects
    for (final attempt in mcqExams) {
      final examData = attempt['exams'] as Map<String, dynamic>?;
      final examSubjectId = examData?['subject_id'] as String?;
      if (examSubjectId != null && studentSubjectIds.contains(examSubjectId)) {
        totalMcqExams++;
      }
    }
    
    for (final paper in groupedPapers.values) {
      final paperSubjectId = paper['subject_id'] as String?;
      if (paperSubjectId != null && studentSubjectIds.contains(paperSubjectId)) {
        totalPapersAttempted++;
      }
    }

    // ===== RECENT ACTIVITY (Filtered to intersection subjects) =====
    final activity = <Map<String, dynamic>>[];

    // Add MCQ exams — only for intersection subjects
    for (final e in mcqExams) {
      final examData = e['exams'] as Map<String, dynamic>?;
      final examSubjectId = examData?['subject_id'] as String?;
      
      // ✅ Only include if this exam's subject is in the intersection
      if (examSubjectId != null && studentSubjectIds.contains(examSubjectId)) {
        activity.add({
          'type': 'mcq',
          'title': examData?['title'] ?? 'MCQ Exam',
          'score': '${e['score']}/${e['total_marks']}',
          'percentage': (e['percentage'] as num?)?.toDouble() ?? 0,
          'date': e['completed_at'] ?? '',
        });
      }
    }

    // Add paper answers — only for intersection subjects
    for (final p in groupedPapers.values) {
      final paperSubjectId = p['subject_id'] as String?;
      
      // ✅ Only include if this paper's subject is in the intersection
      if (paperSubjectId != null && studentSubjectIds.contains(paperSubjectId)) {
        final totalMarks = p['total_marks'] as int;
        final marks = p['marks_awarded'] as int;
        activity.add({
          'type': 'paper',
          'title': p['title'] ?? 'Exam Paper',
          'score': '${marks}/$totalMarks',
          'percentage': totalMarks > 0 ? (marks / totalMarks) * 100 : 0.0,
          'date': p['submitted_at'] ?? '',
          'status': p['status'],
        });
      }
    }

    // Sort by date
    activity.sort((a, b) {
      final dateA = (a['date'] as String?) ?? '';
      final dateB = (b['date'] as String?) ?? '';
      return dateB.compareTo(dateA);
    });

    if (mounted) {
      setState(() {
        _studentStats = {
          'lessons_completed': totalCompletedLessons,
          'mcq_exams_taken': totalMcqExams,
          'papers_attempted': totalPapersAttempted,
        };
        _recentActivity = activity;
        _subjectBreakdown = subjectBreakdown;
        _subjectStats = subjectStats;
        _isLoadingDetails = false;
      });
    }
  } catch (e) {
    debugPrint('Error loading student details: $e');
    if (mounted) setState(() => _isLoadingDetails = false);
  }
}

Color _getLevelColor(String level) {
  switch (level) {
    case 'Form 1': return Colors.blue;
    case 'Form 2': return Colors.teal;
    case 'O-Level': return const Color(0xFFFF9800);
    case 'A-Level': return Colors.purple;
    default: return const Color(0xFF1A237E);
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
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: FlexibleSpaceBar(
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.analytics_rounded, size: 20, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      const Text('Student Performance',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Student selector
                  // Student selector
FadeTransition(
  opacity: _animationController,
  child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Student', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        const SizedBox(height: 12),
        _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _groupedStudentList.isEmpty
                ? const Text('No students enrolled yet', style: TextStyle(color: Colors.grey))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _groupedStudentList.map((levelGroup) {
                      final levelName = levelGroup['level_name'] as String;
                      final students = levelGroup['students'] as List<Map<String, dynamic>>;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Level label
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 4, height: 16,
                                  decoration: BoxDecoration(
                                    color: _getLevelColor(levelName),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(levelName,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _getLevelColor(levelName))),
                                const SizedBox(width: 8),
                                Text('${students.length} student(s)',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                          // Students in this level
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: students.map((student) {
                              final isSelected = _selectedStudent?['student_id'] == student['student_id'];
                              return GestureDetector(
                                onTap: () => _selectStudent(student),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: isSelected ? Colors.white24 : _getLevelColor(levelName).withOpacity(0.15),
                                        child: Text(
                                          (student['full_name'] as String)[0].toUpperCase(),
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : _getLevelColor(levelName),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        student['full_name'] ?? '',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.black87,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    }).toList(),
                  ),
      ],
    ),
  ),
),

                  if (_selectedStudent != null) ...[
                    const SizedBox(height: 20),

                    // Stats overview
                    if (_isLoadingDetails)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                      ))
                    else ...[
  // Per-Subject Stats Cards
  if (_subjectStats.isNotEmpty)
    FadeTransition(
      opacity: _animationController,
      child: Column(
        children: [
          const Text('Performance by Subject',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 12),
          ..._subjectStats.map((s) {
            final color = _parseColor(s['color'] as String?);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
                border: Border.all(color: color.withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(s['subject_name'] ?? '',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _MiniStatItem(icon: Icons.play_circle_rounded, label: 'Lessons',
                        value: '${s['lessons_completed']}/${s['lessons_total']}', color: color)),
                    Expanded(child: _MiniStatItem(icon: Icons.quiz_rounded, label: 'MCQ Avg',
                        value: s['mcq_taken'] > 0 ? '${(s['mcq_avg'] as double).toStringAsFixed(0)}%' : '--', color: color)),
                    Expanded(child: _MiniStatItem(icon: Icons.assignment_rounded, label: 'Paper Avg',
                        value: s['papers_marked'] > 0 ? '${(s['paper_avg'] as double).toStringAsFixed(0)}%' : '--', color: color)),
                    Expanded(child: _MiniStatItem(icon: Icons.grading_rounded, label: 'Papers',
                        value: '${s['papers_attempted']}', color: color)),
                  ]),
                ],
              ),
            );
          }),
        ],
      ),
    ),
                      const SizedBox(height: 20),

                      // Subject progress - FIXED: display like ProgressDashboard
                      if (_subjectBreakdown.isNotEmpty)
                        FadeTransition(
                          opacity: _animationController,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Subject Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                                const SizedBox(height: 12),
                                ..._subjectBreakdown.map((s) {
                                  final completed = s['completed_lessons'] as int? ?? 0;
                                  final total = s['total_lessons'] as int? ?? 0;
                                  final progress = total > 0 ? completed / total : 0.0;
                                  final color = _parseColor(s['color'] as String?);
                                  final progressPercent = (progress * 100).toInt();

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: color,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    s['subject_name'] ?? '',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: color,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                '$completed / $total',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: LinearProgressIndicator(
                                              value: progress,
                                              backgroundColor: Colors.grey.shade200,
                                              color: color,
                                              minHeight: 8,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$progressPercent% complete',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Recent activity - FIXED: include lessons
                      if (_recentActivity.isNotEmpty)
                        FadeTransition(
                          opacity: _animationController,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8)],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Recent Activity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                                const SizedBox(height: 12),
                                ..._recentActivity.take(10).map((a) {
                                  final type = a['type'] as String? ?? '';
                                  final isMcq = type == 'mcq';
                                  final isLesson = type == 'lesson';
                                  final isPaper = type == 'paper';
                                  final pct = (a['percentage'] as num?)?.toDouble() ?? 0;
                                  
                                  IconData icon;
                                  Color iconColor;
                                  Color bgColor;
                                  
                                  if (isMcq) {
                                    icon = Icons.quiz_rounded;
                                    iconColor = const Color(0xFFFF9800);
                                    bgColor = const Color(0xFFFF9800).withOpacity(0.1);
                                  } else if (isLesson) {
                                    icon = Icons.play_circle_rounded;
                                    iconColor = const Color(0xFF1A237E);
                                    bgColor = const Color(0xFF1A237E).withOpacity(0.1);
                                  } else {
                                    icon = Icons.assignment_rounded;
                                    iconColor = const Color(0xFF00897B);
                                    bgColor = const Color(0xFF00897B).withOpacity(0.1);
                                  }
                                  
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: bgColor,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(icon, color: iconColor, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                a['title'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isLesson 
                                                    ? 'Completed ✓' 
                                                    : (isMcq 
                                                        ? 'Score: ${a['score'] ?? '--'}' 
                                                        : (a['status'] == 'marked' 
                                                            ? 'Score: ${a['score'] ?? '--'}' 
                                                            : 'Pending review')),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isLesson 
                                                      ? Colors.green 
                                                      : Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          _formatDate(a['date'] as String?),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],

                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== HELPERS =====
  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF1A237E);
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }
}

class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
class _MiniStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MiniStatItem({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }
}