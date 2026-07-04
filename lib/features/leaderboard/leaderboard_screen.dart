import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _leaders = [];
  List<Map<String, dynamic>> _subjects = [];
  String _selectedSubject = 'All';
  String _selectedCategory = 'overall';
  bool _isLoading = true;
  bool _isRefreshing = false;

  final List<String> _categories = ['overall', 'lessons', 'mcqs', 'papers'];
  final List<String> _categoryLabels = ['Overall', 'Lessons', 'MCQs', 'Papers'];
  final List<IconData> _categoryIcons = [
    Icons.emoji_events_rounded,
    Icons.book_rounded,
    Icons.quiz_rounded,
    Icons.assignment_rounded,
  ];
  
  String _getActiveStatLabel() {
    switch (_selectedCategory) {
      case 'lessons': return 'Lessons Completed';
      case 'mcqs': return 'MCQ Average';
      case 'papers': return 'Paper Average';
      default: return 'Overall Points';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSubjects();
    _loadLeaderboard();
  }

  Future<void> _loadSubjects() async {
    try {
      final response = await Supabase.instance.client
          .from('subjects')
          .select('id, name')
          .eq('is_active', true)
          .order('display_order');
      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLeaderboard() async {
    if (!_isRefreshing) {
      setState(() => _isLoading = true);
    }
    
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, avatar_url')
          .eq('role', 'student');

      final leaders = <Map<String, dynamic>>[];

      for (final student in response) {
        final studentId = student['id'] as String;
        final name = student['full_name'] as String? ?? 'Student';
        final avatarUrl = student['avatar_url'] as String?;

        // ===== LESSONS =====
        int completedLessons = 0;
        final lessonProgress = await Supabase.instance.client
            .from('lesson_progress')
            .select('completed')
            .eq('student_id', studentId)
            .eq('completed', true);
        completedLessons = lessonProgress.length;

        final totalAvailable = await Supabase.instance.client
            .from('lessons')
            .select('id')
            .eq('is_published', true);
        final totalLessons = totalAvailable.length;

        // ===== MCQ EXAMS =====
        int totalMcq = 0;
        double mcqScoreSum = 0;
        final mcqAttempts = await Supabase.instance.client
            .from('exam_attempts')
            .select('percentage')
            .eq('student_id', studentId)
            .not('completed_at', 'is', null);

        for (final m in mcqAttempts) {
          totalMcq++;
          final pct = (m['percentage'] as num?)?.toDouble() ?? 0;
          mcqScoreSum += pct;
        }

        // ===== EXAM PAPERS =====
        int totalPapers = 0;
        int markedPapers = 0;
        double paperScoreSum = 0;

        final paperAnswers = await Supabase.instance.client
            .from('exam_answers')
            .select('paper_id, marks_awarded, status, exam_papers!inner(total_marks)')
            .eq('student_id', studentId);

        final Map<String, Map<String, dynamic>> groupedPapers = {};
        for (final p in paperAnswers) {
          final paperId = p['paper_id'] as String;
          if (!groupedPapers.containsKey(paperId)) {
            groupedPapers[paperId] = {
              'total_marks': p['exam_papers']?['total_marks'] ?? 0,
              'marks_awarded': 0,
              'status': p['status'],
              'question_count': 0,
            };
          }
          groupedPapers[paperId]!['marks_awarded'] = 
              (groupedPapers[paperId]!['marks_awarded'] as int) + ((p['marks_awarded'] as int?) ?? 0);
          groupedPapers[paperId]!['question_count'] = 
              (groupedPapers[paperId]!['question_count'] as int) + 1;
          
          if (p['status'] == 'marked') {
            groupedPapers[paperId]!['status'] = 'marked';
          }
        }

        totalPapers = groupedPapers.length;
        for (final paper in groupedPapers.values) {
          if (paper['status'] == 'marked') {
            markedPapers++;
            final marks = paper['marks_awarded'] as int;
            final maxMarks = paper['total_marks'] as int;
            if (maxMarks > 0) {
              paperScoreSum += (marks / maxMarks) * 100;
            }
          }
        }

        final avgMcq = totalMcq > 0 ? mcqScoreSum / totalMcq : 0.0;
        final avgPaper = markedPapers > 0 ? paperScoreSum / markedPapers : 0.0;
        
        final lessonPoints = completedLessons * 10;
        final mcqPoints = avgMcq * 0.5;
        final paperPoints = avgPaper * 0.5;
        final participationPoints = (totalMcq + markedPapers) * 2;
        final points = lessonPoints + mcqPoints + paperPoints + participationPoints;

        leaders.add({
          'student_id': studentId,
          'name': name,
          'avatar_url': avatarUrl,
          'points': points.round(),
          'total_lessons': totalLessons,
          'completed_lessons': completedLessons,
          'total_mcq': totalMcq,
          'avg_mcq': avgMcq,
          'total_papers': totalPapers,
          'marked_papers': markedPapers,
          'avg_paper': avgPaper,
          'is_current_user': studentId == userId,
        });
      }

      leaders.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));

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

  List<Map<String, dynamic>> get _filteredLeaders {
    final sorted = List<Map<String, dynamic>>.from(_leaders);
    
    switch (_selectedCategory) {
      case 'lessons':
        sorted.sort((a, b) => (b['completed_lessons'] as int).compareTo(a['completed_lessons'] as int));
        break;
      case 'mcqs':
        sorted.sort((a, b) => (b['avg_mcq'] as double).compareTo(a['avg_mcq'] as double));
        break;
      case 'papers':
        sorted.sort((a, b) => (b['avg_paper'] as double).compareTo(a['avg_paper'] as double));
        break;
      default:
        sorted.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
        break;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;

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
              expandedHeight: 160,
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
                  title: const Row(
                    children: [
                      Text('🏆', style: TextStyle(fontSize: 24)),
                      SizedBox(width: 8),
                      Text('Leaderboard',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                  background: Padding(
                    padding: const EdgeInsets.fromLTRB(80, 0, 16, 100),
                    child: Row(
                      children: [
                        _TopTrophy(rank: 2, size: 32, color: Colors.grey.shade300),
                        const SizedBox(width: 8),
                        _TopTrophy(rank: 1, size: 42, color: const Color(0xFFFFD700)),
                        const SizedBox(width: 8),
                        _TopTrophy(rank: 3, size: 32, color: const Color(0xFFCD7F32)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Category chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.asMap().entries.map((entry) {
                        final index = entry.key;
                        final cat = entry.value;
                        final isSelected = _selectedCategory == cat;
                        final label = _categoryLabels[index];
                        final icon = _categoryIcons[index];
                        
                        return GestureDetector(
                          onTap: () => setState(() => _selectedCategory = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [Color(0xFF1A237E), Color(0xFF283593)],
                                    )
                                  : null,
                              color: isSelected ? null : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected 
                                      ? const Color(0xFF1A237E).withOpacity(0.3)
                                      : Colors.grey.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: isSelected
                                  ? null
                                  : Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 14,
                                  color: isSelected ? Colors.white : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.trending_up_rounded,
                          size: 14,
                          color: Color(0xFF1A237E),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ranking by: ${_getActiveStatLabel()}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1A237E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: Column(
                          children: [
                            CircularProgressIndicator(color: Color(0xFF1A237E)),
                            SizedBox(height: 16),
                            Text('Loading leaderboard...', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else if (_filteredLeaders.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(60),
                        child: Column(
                          children: [
                            Icon(Icons.emoji_events_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('No students yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('Students will appear here once they start learning', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._filteredLeaders.asMap().entries.map((entry) {
                      final index = entry.key;
                      final leader = entry.value;
                      final rank = index + 1;
                      final isCurrentUser = leader['is_current_user'] ?? false;

                      String highlightedValue;
                      String highlightedLabel;
                      Color highlightColor;
                      
                      switch (_selectedCategory) {
                        case 'lessons':
                          highlightedValue = '${leader['completed_lessons']}/${leader['total_lessons']}';
                          highlightedLabel = 'Lessons';
                          highlightColor = const Color(0xFF1A237E);
                          break;
                        case 'mcqs':
                          highlightedValue = '${(leader['avg_mcq'] as double).toStringAsFixed(0)}%';
                          highlightedLabel = 'MCQ';
                          highlightColor = const Color(0xFFFF9800);
                          break;
                        case 'papers':
                          highlightedValue = '${(leader['avg_paper'] as double).toStringAsFixed(0)}%';
                          highlightedLabel = 'Papers';
                          highlightColor = const Color(0xFF00897B);
                          break;
                        default:
                          highlightedValue = '${leader['points']}';
                          highlightedLabel = 'PTS';
                          highlightColor = const Color(0xFFFFD700);
                          break;
                      }

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isCurrentUser
                              ? const Color(0xFF1A237E).withOpacity(0.06)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: isCurrentUser
                              ? Border.all(color: const Color(0xFF1A237E), width: 2)
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
                            // Main row - simplified for mobile
                            Row(
                              children: [
                                // Rank
                                SizedBox(
                                  width: isSmallScreen ? 30 : 36,
                                  child: rank <= 3
                                      ? Text(['🥇', '🥈', '🥉'][rank - 1], style: const TextStyle(fontSize: 24))
                                      : Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.grey.shade200,
                                                Colors.grey.shade300,
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '$rank',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                // Avatar
                                CircleAvatar(
                                  radius: isSmallScreen ? 16 : 20,
                                  backgroundColor: _getRankColor(rank).withOpacity(0.15),
                                  backgroundImage: leader['avatar_url'] != null
                                      ? NetworkImage(leader['avatar_url'])
                                      : null,
                                  child: leader['avatar_url'] == null
                                      ? Text(
                                          (leader['name'] as String)[0].toUpperCase(),
                                          style: TextStyle(
                                            color: _getRankColor(rank),
                                            fontWeight: FontWeight.bold,
                                            fontSize: isSmallScreen ? 12 : 14,
                                          ),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                // Name
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
                                                fontSize: isSmallScreen ? 13 : 14,
                                                color: isCurrentUser ? const Color(0xFF1A237E) : Colors.black87,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isCurrentUser) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1A237E),
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
                                      // Stat chips - wrapped for mobile
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 2,
                                        children: [
                                          _StatChip(
                                            label: '${leader['completed_lessons']}L',
                                            isHighlighted: _selectedCategory == 'lessons',
                                            color: const Color(0xFF1A237E),
                                          ),
                                          _StatChip(
                                            label: '${(leader['avg_mcq'] as double).toStringAsFixed(0)}%M',
                                            isHighlighted: _selectedCategory == 'mcqs',
                                            color: const Color(0xFFFF9800),
                                          ),
                                          _StatChip(
                                            label: '${(leader['avg_paper'] as double).toStringAsFixed(0)}%P',
                                            isHighlighted: _selectedCategory == 'papers',
                                            color: const Color(0xFF00897B),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Points badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        highlightColor,
                                        highlightColor.withOpacity(0.7),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: highlightColor.withOpacity(0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        highlightedLabel,
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: isSmallScreen ? 6 : 7,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        highlightedValue,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: isSmallScreen ? 12 : 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
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

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return Colors.grey.shade400;
      case 3: return const Color(0xFFCD7F32);
      default: return const Color(0xFF1A237E);
    }
  }
}

class _TopTrophy extends StatelessWidget {
  final int rank;
  final double size;
  final Color color;
  const _TopTrophy({required this.rank, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(['🥇', '🥈', '🥉'][rank - 1], style: TextStyle(fontSize: size));
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final bool isHighlighted;
  final Color color;

  const _StatChip({
    required this.label,
    required this.isHighlighted,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isHighlighted 
            ? color.withOpacity(0.2)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(3),
        border: isHighlighted
            ? Border.all(color: color, width: 1)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w400,
          color: isHighlighted ? color : Colors.grey.shade600,
        ),
      ),
    );
  }
}