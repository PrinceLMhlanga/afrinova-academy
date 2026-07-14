import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QuestionBankOverviewScreen extends StatefulWidget {
  const QuestionBankOverviewScreen({super.key});

  @override
  State<QuestionBankOverviewScreen> createState() => _QuestionBankOverviewScreenState();
}

class _QuestionBankOverviewScreenState extends State<QuestionBankOverviewScreen> {
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _topics = [];
  
  String? _selectedSubjectId;
  String? _selectedLevelId;
  String? _selectedTopicId;
  
  // Stats
  int _totalQuestions = 0;
  Map<String, int> _subjectCounts = {};
  Map<String, int> _levelCounts = {};
  Map<String, int> _topicCounts = {};
  Map<String, Map<String, int>> _difficultyCounts = {};
  
  bool _isLoading = true;
  bool _isLoadingStats = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // Load subjects and levels in parallel
      final results = await Future.wait([
        Supabase.instance.client
            .from('subjects')
            .select()
            .eq('is_active', true)
            .order('name', ascending: true),
        Supabase.instance.client
            .from('levels')
            .select()
            .order('display_order', ascending: true),
      ]);

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(results[0]);
          _levels = List<Map<String, dynamic>>.from(results[1]);
        });
      }

      // Load stats using the PostgreSQL function
      await _loadStats();
    } catch (e) {
      debugPrint('Error loading initial data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoadingStats = true);
    try {
      // Call the PostgreSQL function
      final data = await Supabase.instance.client
          .rpc('get_question_bank_stats', params: {
            'subject_filter': _selectedSubjectId,
            'level_filter': _selectedLevelId,
          });

      if (data != null && mounted) {
        final stats = data as Map<String, dynamic>;
        
        setState(() {
          // Total count
          _totalQuestions = stats['total_count'] ?? 0;
          
          // Subject counts - only show subjects with questions
          _subjectCounts = {};
          final subjectData = stats['subject_counts'] as Map<String, dynamic>? ?? {};
          subjectData.forEach((key, value) {
            if (value is int && value > 0) {
              _subjectCounts[key] = value;
            }
          });
          
          // Level counts - only show levels with questions
          _levelCounts = {};
          final levelData = stats['level_counts'] as Map<String, dynamic>? ?? {};
          levelData.forEach((key, value) {
            if (value is int && value > 0) {
              _levelCounts[key] = value;
            }
          });
          
          // Topic counts - only show topics with questions
          _topicCounts = {};
          final topicData = stats['topic_counts'] as Map<String, dynamic>? ?? {};
          topicData.forEach((key, value) {
            if (value is int && value > 0) {
              _topicCounts[key] = value;
            }
          });
          
          // Difficulty counts per subject
          _difficultyCounts = {};
          final diffData = stats['difficulty_counts'] as Map<String, dynamic>? ?? {};
          diffData.forEach((subject, difficulties) {
            if (difficulties is Map<String, dynamic>) {
              _difficultyCounts[subject] = {
                'easy': difficulties['easy'] ?? 0,
                'medium': difficulties['medium'] ?? 0,
                'hard': difficulties['hard'] ?? 0,
              };
            }
          });
        });
      }
    } catch (e) {
      debugPrint('Error loading stats via RPC: $e');
      // If RPC fails, show error state
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading statistics: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  Future<void> _loadTopics() async {
    if (_selectedSubjectId == null) {
      setState(() => _topics = []);
      return;
    }
    
    try {
      var query = Supabase.instance.client
          .from('topics')
          .select()
          .eq('subject_id', _selectedSubjectId!);
      
      if (_selectedLevelId != null && _selectedLevelId!.isNotEmpty) {
        query = query.eq('level_id', _selectedLevelId!);
      }

      final response = await query.order('display_order', ascending: true);
      
      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(response);
          if (_selectedTopicId != null && !_topics.any((t) => t['id'] == _selectedTopicId)) {
            _selectedTopicId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading topics: $e');
    }
  }

  void _onSubjectChanged(String? value) {
    setState(() { 
      _selectedSubjectId = value; 
      _selectedLevelId = null;
      _selectedTopicId = null;
    });
    if (value != null) {
      _loadTopics();
    } else {
      setState(() => _topics = []);
    }
    _loadStats();
  }

  void _onLevelChanged(String? value) {
    setState(() { 
      _selectedLevelId = value;
      _selectedTopicId = null;
    });
    if (_selectedSubjectId != null) {
      _loadTopics();
    }
    _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Bank Overview'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Total count card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A237E), Color(0xFF283593)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1A237E).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.quiz_rounded, color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '$_totalQuestions',
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (_isLoadingStats) ...[
                                      const SizedBox(width: 12),
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _selectedSubjectId != null && _selectedLevelId != null
                                      ? 'Filtered Questions'
                                      : _selectedSubjectId != null
                                          ? 'Questions in Subject'
                                          : 'Total Approved Questions',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Filters
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedSubjectId,
                              decoration: _dropdownDeco('Subject'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null, 
                                  child: Text('All Subjects', style: TextStyle(fontSize: 13))
                                ),
                                ..._subjects.map((s) => DropdownMenuItem<String>(
                                  value: s['id'] as String, 
                                  child: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
                                )),
                              ],
                              onChanged: _onSubjectChanged,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedLevelId,
                              decoration: _dropdownDeco('Level'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null, 
                                  child: Text('All Levels', style: TextStyle(fontSize: 13))
                                ),
                                ..._levels.map((l) => DropdownMenuItem<String>(
                                  value: l['id'] as String, 
                                  child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 13)),
                                )),
                              ],
                              onChanged: _onLevelChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stats loading indicator
                    if (_isLoadingStats && _totalQuestions == 0)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                        ),
                      ),

                    // Empty state
                    if (!_isLoadingStats && _totalQuestions == 0)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(Icons.inbox_rounded, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'No questions found',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedSubjectId != null || _selectedLevelId != null
                                    ? 'Try adjusting your filters'
                                    : 'Questions will appear here once approved',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Subject stats (when no subject selected)
                    if (!_isLoadingStats && _selectedSubjectId == null && _subjectCounts.isNotEmpty) ...[
                      const Text(
                        'Questions by Subject',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                      ),
                      const SizedBox(height: 12),
                      ..._subjectCounts.entries.map((entry) {
                        final subject = _subjects.firstWhere(
                          (s) => s['name'] == entry.key,
                          orElse: () => {'color_hex': '#1A237E'},
                        );
                        final colorHex = (subject['color_hex'] as String? ?? '#1A237E').replaceAll('#', '');
                        final color = Color(int.parse('FF$colorHex', radix: 16));
                        final difficulties = _difficultyCounts[entry.key] ?? {};

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: color.withOpacity(0.2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: color,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${entry.value} questions',
                                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              // Difficulty breakdown
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _DiffBadge(
                                    label: 'Easy',
                                    count: difficulties['easy'] ?? 0,
                                    color: const Color(0xFF4CAF50),
                                  ),
                                  const SizedBox(width: 6),
                                  _DiffBadge(
                                    label: 'Med',
                                    count: difficulties['medium'] ?? 0,
                                    color: const Color(0xFFFF9800),
                                  ),
                                  const SizedBox(width: 6),
                                  _DiffBadge(
                                    label: 'Hard',
                                    count: difficulties['hard'] ?? 0,
                                    color: Colors.red,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Level stats (when subject is selected)
                    if (!_isLoadingStats && _selectedSubjectId != null && _levelCounts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Questions by Level',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                      ),
                      const SizedBox(height: 12),
                      ..._levelCounts.entries.map((entry) {
                        final color = _getLevelColor(entry.key);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withOpacity(0.2)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: color,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Topic stats (when level is selected)
                    if (!_isLoadingStats && _selectedLevelId != null && _topicCounts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Questions by Topic',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                      ),
                      const SizedBox(height: 12),
                      ..._topicCounts.entries.map((entry) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A237E).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.topic_rounded,
                                  size: 18,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9800).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${entry.value}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFFFF9800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  InputDecoration _dropdownDeco(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }

  Color _getLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'form 1':
        return Colors.blue;
      case 'form 2':
        return Colors.teal;
      case 'form 3':
        return Colors.green;
      case 'form 4':
        return Colors.orange;
      case 'o-level':
        return const Color(0xFFFF9800);
      case 'a-level':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

class _DiffBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DiffBadge({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}