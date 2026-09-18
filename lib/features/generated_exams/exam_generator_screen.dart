import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'student_exam_taker_screen.dart';
import '../../core/trial_usage_service.dart';
import '../../widgets/trial_limit_dialog.dart';
import '../premium/ai_subscription_screen.dart';
import '../../core/shell/panel_scaffold.dart';

class ExamGeneratorScreen extends StatefulWidget {
  /// When true, this screen is hosted inside [AppShell] as a panel.
  /// Renders without its own AppBar — the shell provides the chrome.
  final bool embedded;

  const ExamGeneratorScreen({super.key, this.embedded = false});

  @override
  State<ExamGeneratorScreen> createState() => _ExamGeneratorScreenState();
}

class _ExamGeneratorScreenState extends State<ExamGeneratorScreen> {
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  
  String? _selectedSubjectId;
  String? _studentLevelId;
  String? _studentLevelName;
  String? _selectedTopicId;
  int _questionCount = 20;
  bool _isLoading = true;
  bool _isGenerating = false;

  // ✅ Trial usage tracking
int _trialRemaining = 0;
int _trialLimit = 0;
bool _isUnlimited = false;

  @override
void initState() {
  super.initState();
  _loadData();
  _loadTrialInfo();  // ✅ Add this
}

// ✅ Add this method
Future<void> _loadTrialInfo() async {
  try {
    await TrialLimitsCache.load();
    final examsLimit = TrialLimitsCache.exams();
    
    final check = await TrialUsageService().canUseFeature('exams_generated');
    
    if (!mounted) return;
    
    setState(() {
      _isUnlimited = check.unlimited;
      _trialLimit = examsLimit;
      
      if (check.unlimited) {
        _trialRemaining = 999999;
      } else if (check.remaining != null) {
        _trialRemaining = check.remaining!;
      } else if (check.used != null) {
        _trialRemaining = (examsLimit - check.used!).clamp(0, examsLimit);
      } else {
        _trialRemaining = examsLimit;
      }
    });
  } catch (e) {
    debugPrint('Error loading trial info: $e');
  }
}

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      
      // Load student's level from profile
      if (userId != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('level_id, levels(name)')
            .eq('id', userId)
            .maybeSingle();
        
        if (profile != null) {
          _studentLevelId = profile['level_id'] as String?;
          _studentLevelName = profile['levels']?['name'] as String?;
        }
      }

      // Load subjects
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name', ascending: true);

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopics(String subjectId) async {
    try {
      final response = await Supabase.instance.client
          .from('topics')
          .select()
          .eq('subject_id', subjectId)
          .eq('level_id', _studentLevelId ?? '')  // ✅ Filter by student's level
          .order('display_order', ascending: true);

      if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Error loading topics: $e');
    }
  }

  Future<void> _generateExam() async {
  if (_selectedSubjectId == null || _studentLevelId == null) return;

  // ✅ CHECK TRIAL LIMIT
  final trialCheck = await TrialUsageService().canUseFeature('exams_generated');
  if (!trialCheck.allowed) {
    if (mounted) {
      final subscribed = await TrialLimitDialog.show(
  context,
  featureName: 'Exam Generator',
  customMessage: trialCheck.message,
);

if (subscribed == true && mounted) {
  await _loadTrialInfo();  // ✅ Refresh banner
}
return;
    }
    return;
  }

  setState(() => _isGenerating = true);

  try {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    // 1. Get recently attempted questions (last 30 days)
    final recentAttempts = await Supabase.instance.client
        .from('practice_exam_history')
        .select('question_id')
        .eq('student_id', userId)
        .gte('attempted_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());

    final Set<String> recentQuestionIds = recentAttempts.map((a) => a['question_id'] as String).toSet();

    // 2. Resolve Topic IDs
    List<String> topicIds = [];
    if (_selectedTopicId != null && _selectedTopicId!.isNotEmpty) {
      topicIds = [_selectedTopicId!];
    } else {
      final topics = await Supabase.instance.client
          .from('topics')
          .select('id')
          .eq('subject_id', _selectedSubjectId!)
          .eq('level_id', _studentLevelId!);
      topicIds = topics.map((t) => t['id'] as String).toList();
    }

    if (topicIds.isEmpty) return;

    // 3. Fetch all approved questions across target topics
    final allQuestions = await Supabase.instance.client
        .from('question_bank')
        .select('*')
        .eq('subject_id', _selectedSubjectId!)
        .eq('level_id', _studentLevelId!)
        .inFilter('topic_id', topicIds)
        .eq('is_approved', true);

    if (allQuestions.isEmpty) return;

    // 4. Calculate GLOBAL exact difficulty limits to prevent rounding degradation
    int targetEasy = (_questionCount * 0.3).round();
    int targetMedium = (_questionCount * 0.5).round();
    int targetHard = _questionCount - targetEasy - targetMedium;

    final List<Map<String, dynamic>> selectedQuestions = [];
    final Set<String> usedIds = {};

    // Helper closure to draw matching questions while observing global limits
    void drawFromPool(List<dynamic> pool, String difficulty, int perTopicTarget) {
      int addedForThisTopic = 0;
      
      // Check which global count limit we need to respect
      int getGlobalNeeded() {
        if (difficulty == 'easy') return targetEasy;
        if (difficulty == 'medium') return targetMedium;
        return targetHard;
      }

      void decrementGlobal() {
        if (difficulty == 'easy') targetEasy--;
        else if (difficulty == 'medium') targetMedium--;
        else targetHard--;
      }

      // Pass 1: Try unattempted questions
      for (final q in pool) {
        if (addedForThisTopic >= perTopicTarget || getGlobalNeeded() <= 0) break;
        final id = q['id'] as String;
        if (!usedIds.contains(id) && !recentQuestionIds.contains(id)) {
          selectedQuestions.add(q);
          usedIds.add(id);
          addedForThisTopic++;
          decrementGlobal();
        }
      }

      // Pass 2: Fallback to recently attempted questions
      for (final q in pool) {
        if (addedForThisTopic >= perTopicTarget || getGlobalNeeded() <= 0) break;
        final id = q['id'] as String;
        if (!usedIds.contains(id)) {
          selectedQuestions.add(q);
          usedIds.add(id);
          addedForThisTopic++;
          decrementGlobal();
        }
      }
    }

    // 5. Distribute evenly across topics using the pre-shuffled global database pool
    final questionsPerTopic = (_questionCount / topicIds.length).floor();
    final remainder = _questionCount - (questionsPerTopic * topicIds.length);

    for (int i = 0; i < topicIds.length; i++) {
      final topicId = topicIds[i];
      final topicQuestionCount = questionsPerTopic + (i < remainder ? 1 : 0);

      final topicQuestions = allQuestions.where((q) => q['topic_id'] == topicId).toList();
      if (topicQuestions.isEmpty) continue;

      final tEasy = topicQuestions.where((q) => q['difficulty'] == 'easy').toList()..shuffle();
      final tMedium = topicQuestions.where((q) => q['difficulty'] == 'medium').toList()..shuffle();
      final tHard = topicQuestions.where((q) => q['difficulty'] == 'hard').toList()..shuffle();

      // Calculate how many to ideally pull per difficulty slot for this topic
      int idealEasy = (topicQuestionCount * 0.3).round();
      int idealMedium = (topicQuestionCount * 0.5).round();
      int idealHard = topicQuestionCount - idealEasy - idealMedium;

      // Draw up to the target amount while adjusting global capacity parameters
      drawFromPool(tEasy, 'easy', idealEasy > 0 ? idealEasy : 1);
      drawFromPool(tMedium, 'medium', idealMedium > 0 ? idealMedium : 1);
      drawFromPool(tHard, 'hard', idealHard > 0 ? idealHard : 1);
    }

    // 6. Global fallback: If pools are unevenly distributed across topics, fill remaining targets directly from the global pool
    for (final diff in ['easy', 'medium', 'hard']) {
      final globalPool = allQuestions.where((q) => q['difficulty'] == diff && !usedIds.contains(q['id'] as String)).toList()..shuffle();
      int needed = diff == 'easy' ? targetEasy : diff == 'medium' ? targetMedium : targetHard;
      
      for (final q in globalPool) {
        if (needed <= 0) break;
        selectedQuestions.add(q);
        usedIds.add(q['id'] as String);
        needed--;
        if (diff == 'easy') targetEasy--;
        else if (diff == 'medium') targetMedium--;
        else targetHard--;
      }
    }

    // 7. Absolute Safety Net Fallback
    if (selectedQuestions.length < _questionCount) {
      final leftovers = allQuestions.where((q) => !usedIds.contains(q['id'] as String)).toList()..shuffle();
      for (final q in leftovers) {
        if (selectedQuestions.length >= _questionCount) break;
        selectedQuestions.add(q);
      }
    }

    // Trim excess items safely if necessary
    if (selectedQuestions.length > _questionCount) {
      selectedQuestions.shuffle();
      selectedQuestions.removeRange(_questionCount, selectedQuestions.length);
    }

    selectedQuestions.shuffle(Random());

// ✅ INCREMENT TRIAL USAGE (only if we actually have questions to show)
if (selectedQuestions.isNotEmpty) {
  await TrialUsageService().incrementUsage('exams_generated');
  await _loadTrialInfo();  // Refresh trial display
}

if (mounted) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => StudentExamTakerScreen(
        questions: selectedQuestions,
        subjectName: _subjects.firstWhere((s) => s['id'] == _selectedSubjectId)['name'] ?? 'Exam',
        totalQuestions: selectedQuestions.length,
        timeMinutes: (selectedQuestions.length * 1.5).ceil(),
      ),
    ),
  );
}
  } catch (e) {
    debugPrint('Generation Error: $e');
  } finally {
    if (mounted) setState(() => _isGenerating = false);
  }
}


// ✅ Helper to pick questions avoiding duplicates
void _pickQuestions(
  List<Map<String, dynamic>> source,
  int count,
  List<Map<String, dynamic>> target,
  Set<String> usedIds,
  Set<String> recentIds,
) {
  int picked = 0;
  // First pass: skip recent questions
  for (final q in source) {
    if (picked >= count) break;
    final qId = q['id'] as String;
    if (!usedIds.contains(qId) && !recentIds.contains(qId)) {
      target.add(q);
      usedIds.add(qId);
      picked++;
    }
  }
  // Second pass: allow recent if not enough
  if (picked < count) {
    for (final q in source) {
      if (picked >= count) break;
      final qId = q['id'] as String;
      if (!usedIds.contains(qId)) {
        target.add(q);
        usedIds.add(qId);
        picked++;
      }
    }
  }
}
    @override
  Widget build(BuildContext context) {
    // Body is identical in both modes — only the outer chrome differs.
    final Widget body = _isLoading
        ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF1A237E)),
          )
        : SingleChildScrollView(
            padding: EdgeInsets.all(widget.embedded ? 0 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [const Color(0xFF1A237E), const Color(0xFF1A237E).withOpacity(0.8)],
    ),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    children: [
      const Icon(Icons.auto_awesome, color: Colors.white, size: 40),
      const SizedBox(height: 12),
      const Text('Practice Exam Generator',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(
        _studentLevelName != null 
            ? 'Generating questions for $_studentLevelName'
            : 'Set your class level in My Account',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ],
  ),
),
const SizedBox(height: 16),

// ✅ TRIAL USAGE BANNER
if (!_isUnlimited)
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _trialRemaining <= 1
          ? Colors.orange.withOpacity(0.1)
          : const Color(0xFF1A237E).withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: _trialRemaining <= 1
            ? Colors.orange.withOpacity(0.3)
            : const Color(0xFF1A237E).withOpacity(0.1),
      ),
    ),
    child: Row(
      children: [
        Icon(
          _trialRemaining <= 1 ? Icons.warning_amber_rounded : Icons.info_outline,
          color: _trialRemaining <= 1 ? Colors.orange : const Color(0xFF1A237E),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Free Trial: $_trialRemaining of $_trialLimit exams remaining',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _trialRemaining <= 1 ? Colors.orange : const Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _trialRemaining <= 1
                    ? 'Subscribe for unlimited practice exams!'
                    : 'Trial exam credits never reset',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    ),
  ),

                  const SizedBox(height: 24),

                  // Level (read-only)
                  if (_studentLevelName != null) ...[
                    const Text('Your Level', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.school_rounded, color: Color(0xFF1A237E)),
                          const SizedBox(width: 10),
                          Text(_studentLevelName!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              // Navigate to My Account to change level
                            },
                            child: const Text('Change', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Subject
                  const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.book_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _subjects.map((s) => DropdownMenuItem<String>(
                      value: s['id'] as String, child: Text(s['name'] ?? ''),
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _selectedSubjectId = v; _selectedTopicId = null; });
                      if (v != null) _loadTopics(v);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Topic
                  const Text('Topic', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedTopicId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.topic_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('All Topics')),
                      ..._topics.map((t) => DropdownMenuItem<String>(
                        value: t['id'] as String, child: Text(t['name'] ?? ''),
                      )),
                    ],
                    onChanged: (v) => setState(() => _selectedTopicId = v),
                  ),
                  const SizedBox(height: 16),

                  // Question count
                  const Text('Number of Questions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('10', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Text('$_questionCount questions',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E))),
                            const Text('40', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        Slider(
                          value: _questionCount.toDouble(),
                          min: 10,
                          max: 40,
                          divisions: 6,
                          activeColor: const Color(0xFF1A237E),
                          onChanged: (v) => setState(() => _questionCount = v.round()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
  width: double.infinity,
  height: 56,
  child: ElevatedButton.icon(
    onPressed: (_isGenerating || _studentLevelId == null) ? null : _generateExam,
    icon: _isGenerating
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.auto_awesome),
    label: Text(
      _isGenerating 
          ? 'Generating...' 
          : 'Generate $_questionCount Questions',
    ),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1A237E),
      foregroundColor: Colors.white,
      disabledBackgroundColor: Colors.grey.shade300,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  ),
),

// ✅ Subscribe CTA when trial is exhausted
if (!_isUnlimited && _trialRemaining <= 0) ...[
  const SizedBox(height: 12),
  SizedBox(
    width: double.infinity,
    height: 48,
    child: OutlinedButton.icon(
      onPressed: () async {
  final subscribed = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => const AISubscriptionScreen()),
  );
  
  if (subscribed == true && mounted) {
    await _loadTrialInfo();  // Refresh
  }
},
      icon: const Icon(Icons.diamond),
      label: const Text('Subscribe for Unlimited Exams'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.orange,
        side: const BorderSide(color: Colors.orange),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  ),
],

                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Approx. ${_questionCount * 1.5 } minutes',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          );

        if (widget.embedded) {
      return PanelScaffold(child: body);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice Exam'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}