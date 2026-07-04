import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ProgressService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get overall stats for a student
  Future<Map<String, dynamic>> getStudentStats(String studentId) async {
    // Total lessons completed
    final lessonsCompleted = await _client
        .from('lesson_progress')
        .select('id')
        .eq('student_id', studentId)
        .eq('completed', true);

    // Total exams taken
    final examsTaken = await _client
        .from('exam_attempts')
        .select('id')
        .eq('student_id', studentId)
        .not('completed_at', 'is', null);

    // Average exam score
    final examScores = await _client
        .from('exam_attempts')
        .select('percentage')
        .eq('student_id', studentId)
        .not('completed_at', 'is', null);

    double averageScore = 0;
    if (examScores.isNotEmpty) {
      double total = 0;
      for (final e in examScores) {
        total += (e['percentage'] as num?)?.toDouble() ?? 0;
      }
      averageScore = total / examScores.length;
    }

    // Total resources downloaded
    final resourcesDownloaded = await _client
        .from('resources')
        .select('id');

    // Current streak (consecutive days with activity)
    final recentActivity = await _getRecentActivity(studentId);
    final streak = _calculateStreak(recentActivity);

    return {
      'lessons_completed': lessonsCompleted.length,
      'exams_taken': examsTaken.length,
      'average_score': averageScore,
      'streak_days': streak,
      'total_resources': resourcesDownloaded.length,
    };
  }

  // Get quick stats for home screen
Future<Map<String, dynamic>> getQuickStats(String studentId) async {
  // Lessons completed
  final lessonsCompleted = await _client
      .from('lesson_progress')
      .select('id')
      .eq('student_id', studentId)
      .eq('completed', true);

  // MCQ exams taken
  final mcqExams = await _client
      .from('exam_attempts')
      .select('id')
      .eq('student_id', studentId)
      .not('completed_at', 'is', null);

  // Exam papers attempted
  final papersAttempted = await _client
      .from('exam_answers')
      .select('paper_id')
      .eq('student_id', studentId);

  // Unique papers (distinct paper_ids)
  final uniquePapers = papersAttempted
      .map((e) => e['paper_id'])
      .toSet()
      .length;

  // Average MCQ score
  double avgScore = 0;
  final mcqScores = await _client
      .from('exam_attempts')
      .select('percentage')
      .eq('student_id', studentId)
      .not('completed_at', 'is', null);

  if (mcqScores.isNotEmpty) {
    double total = 0;
    for (final e in mcqScores) {
      total += (e['percentage'] as num?)?.toDouble() ?? 0;
    }
    avgScore = total / mcqScores.length;
  }

  return {
    'lessons_completed': lessonsCompleted.length,
    'mcq_exams_taken': mcqExams.length,
    'papers_attempted': uniquePapers,
    'avg_mcq_score': avgScore,
  };
}

  // Get progress per subject
  // Get progress per subject
// Get progress per subject — updated for teacher_topics
Future<List<Map<String, dynamic>>> getSubjectProgress(String studentId) async {
  try {
    final enrollments = await _client
        .from('enrollments')
        .select('subject_id, subjects(id, name, color_hex, icon_name)')
        .eq('student_id', studentId)
        .inFilter('status', ['approved', 'paid']);

    // ✅ Deduplicate by subject_id
    final seen = <String>{};
    final uniqueSubjects = <Map<String, dynamic>>[];
    
    for (final e in enrollments) {
      final subject = e['subjects'] as Map<String, dynamic>?;
      if (subject == null) continue;
      final subjectId = subject['id'] as String;
      if (!seen.contains(subjectId)) {
        seen.add(subjectId);
        uniqueSubjects.add(subject);
      }
    }

    // If no enrollments, fallback to all active subjects
    if (uniqueSubjects.isEmpty) {
      final allSubjects = await _client
          .from('subjects')
          .select()
          .eq('is_active', true);
      uniqueSubjects.addAll(List<Map<String, dynamic>>.from(allSubjects));
    }

    final result = <Map<String, dynamic>>[];

    for (final subject in uniqueSubjects) {
      final subjectId = subject['id'] as String;
      final subjectName = subject['name'] as String? ?? 'Unknown';
      var totalLessons = 0;
      var completedLessons = 0;

      try {
        final topics = await _client
            .from('teacher_topics')
            .select('id')
            .eq('subject_id', subjectId);

        final topicIds = topics.map((t) => t['id'] as String).toList();

        if (topicIds.isNotEmpty) {
          final lessons = await _client
              .from('lessons')
              .select('id')
              .inFilter('teacher_topic_id', topicIds)
              .eq('is_published', true);

          totalLessons = lessons.length;

          if (lessons.isNotEmpty) {
            final lessonIds = lessons.map((l) => l['id'] as String).toList();
            final completed = await _client
                .from('lesson_progress')
                .select('id')
                .eq('student_id', studentId)
                .eq('completed', true)
                .inFilter('lesson_id', lessonIds);

            completedLessons = completed.length;
          }
        }
      } catch (e) {
        debugPrint('Error counting for $subjectName: $e');
      }

      result.add({
        'subject_name': subjectName,
        'total_lessons': totalLessons > 0 ? totalLessons : 0,
        'completed_lessons': completedLessons,
        'color': subject['color_hex'] ?? '#1A237E',
        'icon': subject['icon_name'] ?? 'school',
      });
    }

    return result;
  } catch (e) {
    debugPrint('getSubjectProgress error: $e');
    return [];
  }
}
  // Get recent activity
  Future<List<Map<String, dynamic>>> getRecentActivity(
      String studentId) async {
    final activities = <Map<String, dynamic>>[];

    // Recent lesson progress
    final lessons = await _client
        .from('lesson_progress')
        .select('*, lessons(title)')
        .eq('student_id', studentId)
        .order('updated_at', ascending: false)
        .limit(10);

    for (final l in lessons) {
      activities.add({
        'type': 'lesson',
        'title': l['lessons']?['title'] ?? 'Lesson',
        'completed': l['completed'] ?? false,
        'date': l['updated_at'],
        'percentage': l['watched_percentage'] ?? 0,
      });
    }

    final exams = await _client
    .from('exam_attempts')
    .select('id, score, total_marks, percentage, passed, completed_at, exam_id, exams(title)')
    .eq('student_id', studentId)
    .order('completed_at', ascending: false)
    .limit(10);

    for (final e in exams) {
      if (e['completed_at'] != null) {
        activities.add({
          'type': 'exam',
          'title': e['exams']?['title'] ?? 'Exam',
          'score': e['score'],
          'total_marks': e['total_marks'],
          'percentage': e['percentage'],
          'passed': e['passed'],
          'date': e['completed_at'],
        });
      }
    }

    // Sort by date
    activities.sort((a, b) => (b['date'] as String?)?.compareTo(a['date'] as String) ?? 0);

    return activities.take(15).toList();
  }

  // Get detailed exam history
  Future<List<Map<String, dynamic>>> getExamHistory(String studentId) async {
    final response = await _client
        .from('exam_attempts')
        .select('*, exams(title, topics(name, subject_offerings(subjects(name))))')
        .eq('student_id', studentId)
        .not('completed_at', 'is', null)
        .order('completed_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Helper: Get recent activity dates
  Future<List<DateTime>> _getRecentActivity(String studentId) async {
    final dates = <DateTime>[];

    // Recent lesson progress
// Recent lesson progress — updated for teacher_topic_id
final lessons = await _client
    .from('lesson_progress')
    .select('id, completed, watched_percentage, updated_at, lesson_id, lessons!inner(title)')
    .eq('student_id', studentId)
    .order('updated_at', ascending: false)
    .limit(10);

    for (final l in lessons) {
      try {
        dates.add(DateTime.parse(l['updated_at'] as String));
      } catch (_) {}
    }

    return dates;
  }

  // Helper: Calculate consecutive day streak
  int _calculateStreak(List<DateTime> dates) {
    if (dates.isEmpty) return 0;

    final uniqueDays = dates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    int streak = 1;
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);

    // Must have activity today or yesterday to start streak
    if (!uniqueDays.contains(todayStart) &&
        !uniqueDays.contains(todayStart.subtract(const Duration(days: 1)))) {
      return 0;
    }

    for (int i = 1; i < uniqueDays.length; i++) {
      final diff = uniqueDays[i - 1].difference(uniqueDays[i]).inDays;
      if (diff == 1) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }
}