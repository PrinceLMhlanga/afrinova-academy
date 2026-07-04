import 'package:supabase_flutter/supabase_flutter.dart';

class BadgeService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get all badges
  Future<List<Map<String, dynamic>>> getAllBadges() async {
    final response = await _client.from('badges').select();
    return List<Map<String, dynamic>>.from(response);
  }

  // Get badges earned by a student
  Future<List<Map<String, dynamic>>> getStudentBadges(String studentId) async {
    final response = await _client
        .from('student_badges')
        .select('badge_id, earned_at, badges(*)')
        .eq('student_id', studentId);

    return List<Map<String, dynamic>>.from(response);
  }

  // Award a badge to a student
  Future<void> awardBadge(String studentId, String badgeName) async {
    try {
      // Find badge ID
      final badge = await _client
          .from('badges')
          .select('id')
          .eq('name', badgeName)
          .single();

      if (badge != null) {
        await _client.from('student_badges').upsert({
          'student_id': studentId,
          'badge_id': badge['id'],
        });
      }
    } catch (_) {
      // Badge might already exist (unique constraint)
    }
  }

  // Check and award badges based on stats
  Future<void> checkAndAwardBadges(String studentId, {
    required int completedLessons,
    required int totalMcq,
    required double avgMcq,
    required int totalPapers,
    required int streak,
    int? leaderboardRank,
  }) async {
    // Lesson badges
    if (completedLessons >= 1) await awardBadge(studentId, 'First Lesson');
    if (completedLessons >= 10) await awardBadge(studentId, 'Bookworm');
    if (completedLessons >= 50) await awardBadge(studentId, 'Scholar');

    // MCQ badges
    if (totalMcq > 0 && avgMcq >= 100) await awardBadge(studentId, 'Perfect Score');
    if (totalMcq >= 3 && avgMcq >= 90) await awardBadge(studentId, 'Sharpshooter');

    // Streak badges
    if (streak >= 3) await awardBadge(studentId, '3-Day Streak');
    if (streak >= 7) await awardBadge(studentId, '7-Day Streak');

    // Paper badges
    if (totalPapers >= 1) await awardBadge(studentId, 'First Paper');

    // Leaderboard badges
    if (leaderboardRank != null) {
      if (leaderboardRank <= 10) await awardBadge(studentId, 'Top 10');
      if (leaderboardRank <= 3) await awardBadge(studentId, 'Top 3');
    }
  }
}