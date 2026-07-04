import 'package:flutter/material.dart';
import '../../core/badge_service.dart';
import '../../core/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});

  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  final BadgeService _badgeService = BadgeService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _allBadges = [];
  Set<String> _earnedBadgeIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    // ✅ First, check and award any new badges
    await _checkAndAward(userId);

    // Then load all badges
    final allBadges = await _badgeService.getAllBadges();
    final earnedBadges = await _badgeService.getStudentBadges(userId);

    if (mounted) {
      setState(() {
        _allBadges = allBadges;
        _earnedBadgeIds = earnedBadges.map((e) => e['badge_id'] as String).toSet();
        _isLoading = false;
      });
    }
  } catch (e) {
    if (mounted) setState(() => _isLoading = false);
  }
}

Future<void> _checkAndAward(String userId) async {
  try {
    // Get current stats
    final lessonProgress = await Supabase.instance.client
        .from('lesson_progress')
        .select('id')
        .eq('student_id', userId)
        .eq('completed', true);

    final mcqAttempts = await Supabase.instance.client
        .from('exam_attempts')
        .select('percentage')
        .eq('student_id', userId)
        .not('completed_at', 'is', null);

    final paperAnswers = await Supabase.instance.client
        .from('exam_answers')
        .select('id')
        .eq('student_id', userId);

    // Calculate stats
    final completedLessons = lessonProgress.length;
    final totalMcq = mcqAttempts.length;
    double avgMcq = 0;
    if (totalMcq > 0) {
      double sum = 0;
      for (final m in mcqAttempts) {
        sum += (m['percentage'] as num?)?.toDouble() ?? 0;
      }
      avgMcq = sum / totalMcq;
    }
    final totalPapers = paperAnswers.length;

    // Calculate streak (simplified)
    int streak = 0;
    final recentActivity = await Supabase.instance.client
        .from('lesson_progress')
        .select('updated_at')
        .eq('student_id', userId)
        .order('updated_at', ascending: false)
        .limit(30);

    if (recentActivity.isNotEmpty) {
      final today = DateTime.now();
      var checkDate = DateTime(today.year, today.month, today.day);
      
      for (int i = 0; i < 30; i++) {
        final dateStr = checkDate.toIso8601String().substring(0, 10);
        final hasActivity = recentActivity.any((a) {
          final aDate = (a['updated_at'] as String?)?.substring(0, 10) ?? '';
          return aDate == dateStr;
        });
        if (hasActivity) {
          streak++;
          checkDate = checkDate.subtract(const Duration(days: 1));
        } else if (i == 0) {
          checkDate = checkDate.subtract(const Duration(days: 1));
          continue;
        } else {
          break;
        }
      }
    }

    // Award badges
    await _badgeService.checkAndAwardBadges(
      userId,
      completedLessons: completedLessons,
      totalMcq: totalMcq,
      avgMcq: avgMcq,
      totalPapers: totalPapers,
      streak: streak,
    );
  } catch (e) {
    debugPrint('Badge check error: $e');
  }
}

  @override
  Widget build(BuildContext context) {
    final earnedCount = _earnedBadgeIds.length;
    final totalCount = _allBadges.length;

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
                    colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: FlexibleSpaceBar(
                  title: Row(
                    children: [
                      const Text('🏅', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 8),
                      const Text('Achievements',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$earnedCount/$totalCount',
                            style: const TextStyle(fontSize: 12, color: Colors.white)),
                      ),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(60),
                      child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                    ))
                  else
                    ..._allBadges.map((badge) {
                      final isEarned = _earnedBadgeIds.contains(badge['id']);
                      final category = badge['category'] as String? ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isEarned ? Colors.white : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isEarned ? const Color(0xFFFFD700).withOpacity(0.5) : Colors.grey.shade200,
                            width: isEarned ? 2 : 1,
                          ),
                          boxShadow: isEarned
                              ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.15), blurRadius: 10)]
                              : [],
                        ),
                        child: Row(
                          children: [
                            // Badge icon
                            Container(
                              width: 56, height: 56,
                              decoration: BoxDecoration(
                                gradient: isEarned
                                    ? const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA000)])
                                    : LinearGradient(colors: [Colors.grey.shade300, Colors.grey.shade400]),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: isEarned
                                    ? [BoxShadow(color: const Color(0xFFFFD700).withOpacity(0.4), blurRadius: 8)]
                                    : [],
                              ),
                              child: Center(
                                child: Text(
                                  badge['icon'] ?? '🏅',
                                  style: TextStyle(fontSize: 28, color: isEarned ? null : Colors.grey),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    badge['name'] ?? '',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isEarned ? const Color(0xFF1A237E) : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    badge['description'] ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isEarned ? Colors.grey.shade600 : Colors.grey.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Status
                            Icon(
                              isEarned ? Icons.check_circle : Icons.lock_outline,
                              color: isEarned ? const Color(0xFF4CAF50) : Colors.grey.shade400,
                              size: 28,
                            ),
                          ],
                        ),
                      );
                    }),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}