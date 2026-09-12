import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/ai_service.dart';
import '../../core/trial_usage_service.dart';
import '../../widgets/trial_limit_dialog.dart';
import 'flashcard_study_screen.dart';
import '../premium/ai_subscription_screen.dart';

class FlashcardGeneratorScreen extends StatefulWidget {
  const FlashcardGeneratorScreen({super.key});

  @override
  State<FlashcardGeneratorScreen> createState() => _FlashcardGeneratorScreenState();
}

class _FlashcardGeneratorScreenState extends State<FlashcardGeneratorScreen> {
  final AuthService _authService = AuthService();
  final AIService _aiService = AIService();
  
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedSubjectId;
  String? _selectedTopicId;
  String? _studentLevelId;
  String? _studentLevelName;
  int _cardCount = 10;
  bool _isGenerating = false;
  bool _isLoading = true;
  
  // ✅ Track trial usage
  // Change from hardcoded 10 to safe default (will be replaced on load)
int _trialRemaining = 0;
int _trialLimit = 0;
  bool _isUnlimited = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadTrialInfo();
  }

  Future<void> _loadTrialInfo() async {
  try {
    // ✅ Load limits from cache
    await TrialLimitsCache.load();
    final flashcardsLimit = TrialLimitsCache.flashcards();
    
    final check = await TrialUsageService().canUseFeature('flashcards_generated');
    
    debugPrint('🔍 Trial: used=${check.used}, remaining=${check.remaining}, limit=${check.limit}, unlimited=${check.unlimited}');
    
    if (!mounted) return;
    
    setState(() {
      _isUnlimited = check.unlimited;
      
      // ✅ Use DB-driven limit
      _trialLimit = flashcardsLimit;
      
      if (check.unlimited) {
        _trialRemaining = 999999;
      } else if (check.remaining != null) {
        _trialRemaining = check.remaining!;
      } else if (check.used != null) {
        final calc = flashcardsLimit - check.used!;
        _trialRemaining = calc < 0 ? 0 : (calc > flashcardsLimit ? flashcardsLimit : calc);
      } else {
        _trialRemaining = flashcardsLimit;
      }
      
      // Safe clamp
      if (!_isUnlimited) {
        if (_trialRemaining <= 0) {
          _cardCount = 0;
        } else if (_trialRemaining < 5) {
          _cardCount = _trialRemaining;
        } else {
          if (_cardCount < 5) _cardCount = 5;
          if (_cardCount > _trialRemaining) _cardCount = _trialRemaining;
          if (_cardCount > 20) _cardCount = 20;
        }
      }
    });
  } catch (e) {
    debugPrint('❌ Error loading trial info: $e');
  }
}

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
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

      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name');

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopics(String subjectId) async {
    final topics = await Supabase.instance.client
        .from('topics')
        .select()
        .eq('subject_id', subjectId)
        .eq('level_id', _studentLevelId ?? '')
        .order('display_order');

    if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(topics));
  }

  Future<void> _generateFlashcards() async {
    if (_selectedSubjectId == null || _selectedTopicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select subject and topic'), backgroundColor: Colors.red),
      );
      return;
    }

    // ✅ CHECK TRIAL LIMIT
    final trialCheck = await TrialUsageService().canUseFeature('flashcards_generated');
    if (!trialCheck.allowed) {
      if (mounted) {
        await TrialLimitDialog.show(
          context,
          featureName: 'AI Flashcards',
          customMessage: trialCheck.message ??
            'You have reached your free trial limit for AI Flashcards. Subscribe for unlimited access.',
        );
      }
      return;
    }

    // ✅ Check if enough remaining for the requested count
    if (!trialCheck.unlimited) {
      final remaining = trialCheck.remaining ?? 0;
      if (remaining < _cardCount) {
        if (remaining == 0) {
          if (mounted) {
            final subscribed = await TrialLimitDialog.show(
  context,
  featureName: 'AI Flashcards',
  customMessage: trialCheck.message,
);

if (subscribed == true && mounted) {
  await _loadTrialInfo();  // ✅ Refresh slider + banner
}
return;
          }
          return;
        }
        
        // Show dialog asking if they want to use remaining
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Limited Trial'),
            content: Text(
              'You only have $remaining flashcards left in your free trial. '
              'Would you like to generate $remaining flashcards now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                ),
                child: Text('Generate $remaining'),
              ),
            ],
          ),
        );
        
        if (confirmed != true) return;
        
        setState(() => _cardCount = remaining);
      }
    }

    setState(() => _isGenerating = true);

    final subjectName = _subjects.firstWhere((s) => s['id'] == _selectedSubjectId)['name'] ?? '';
    final topicName = _topics.firstWhere((t) => t['id'] == _selectedTopicId)['name'] ?? '';

    try {
      final cards = await _aiService.generateFlashcards(
        topic: topicName,
        subject: subjectName,
        level: _studentLevelName ?? 'Form 4',
        count: _cardCount,
      );

      if (cards.isNotEmpty && mounted) {
        // Save to database
        final userId = _authService.currentUserId;
        for (final card in cards) {
          await Supabase.instance.client.from('ai_flashcards').insert({
            'student_id': userId,
            'subject_id': _selectedSubjectId,
            'topic_id': _selectedTopicId,
            'question': card['question'],
            'answer': card['answer'],
          });
        }

        // ✅ INCREMENT TRIAL USAGE
        await TrialUsageService().incrementUsage(
          'flashcards_generated',
          amount: cards.length,
        );

        // Refresh trial info
        await _loadTrialInfo();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FlashcardStudyScreen(
                cards: cards,
                topicName: topicName,
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate flashcards. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Compute bounds safely ONCE at the top of build
    final int minCards;
    final int maxCards;
    
    if (_isUnlimited) {
      minCards = 5;
      maxCards = 20;
    } else if (_trialRemaining <= 0) {
      minCards = 1;
      maxCards = 1;
    } else if (_trialRemaining < 5) {
      minCards = 1;
      maxCards = _trialRemaining;
    } else {
      minCards = 5;
      maxCards = _trialRemaining > 20 ? 20 : _trialRemaining;
    }
    
    // Ensure maxCards >= minCards (safety)
    final safeMax = maxCards < minCards ? minCards : maxCards;
    
    // Compute effective card count safely
    final effectiveCardCount = _cardCount < minCards 
        ? minCards 
        : (_cardCount > safeMax ? safeMax : _cardCount);
    
    // Is the slider usable?
    final isSliderDisabled = _trialRemaining <= 0 && !_isUnlimited;
    
    // Can we generate?
    final canGenerate = _isUnlimited || _trialRemaining >= 1;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('AI Flashcard Generator'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade600, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
                        const SizedBox(height: 12),
                        const Text('AI Flashcard Generator',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(_studentLevelName ?? 'Select level',
                            style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ✅ TRIAL USAGE BANNER
                  if (!_isUnlimited)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _trialRemaining <= 3
                            ? Colors.orange.withOpacity(0.1)
                            : const Color(0xFF1A237E).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _trialRemaining <= 3
                              ? Colors.orange.withOpacity(0.3)
                              : const Color(0xFF1A237E).withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _trialRemaining <= 3 ? Icons.warning_amber_rounded : Icons.info_outline,
                            color: _trialRemaining <= 3 ? Colors.orange : const Color(0xFF1A237E),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Free Trial: $_trialRemaining of $_trialLimit flashcards remaining',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _trialRemaining <= 3 ? Colors.orange : const Color(0xFF1A237E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _trialRemaining <= 3
                                      ? 'Subscribe for unlimited flashcards!'
                                      : 'Trial flashcards never reset',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),

                  // Subject
                  const Text('Subject', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.book_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _subjects.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['name'] ?? ''))).toList(),
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
                    items: _topics.map((t) => DropdownMenuItem(value: t['id'] as String, child: Text(t['name'] ?? ''))).toList(),
                    onChanged: (v) => setState(() => _selectedTopicId = v),
                  ),
                  const SizedBox(height: 16),

                  // Number of Cards section
                  Row(
                    children: [
                      const Text('Number of Cards', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (!_isUnlimited) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Max $safeMax (trial)',
                            style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$minCards', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          isSliderDisabled ? 'No cards left' : '$effectiveCardCount cards',
                          style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            fontSize: 16, 
                            color: isSliderDisabled ? Colors.red : const Color(0xFF1A237E),
                          ),
                        ),
                        Text('$safeMax', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // ✅ Slider with strict bounds
                  if (isSliderDisabled)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          'Subscribe to generate more flashcards',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Slider(
                      value: effectiveCardCount.toDouble(),
                      min: minCards.toDouble(),
                      max: safeMax.toDouble(),
                      divisions: (safeMax - minCards) > 0 
                          ? ((safeMax - minCards) ~/ 1).clamp(1, 20) 
                          : null,
                      activeColor: const Color(0xFF1A237E),
                      onChanged: (v) => setState(() => _cardCount = v.round()),
                    ),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
                    width: double.infinity, 
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: (_isGenerating || !canGenerate) ? null : _generateFlashcards,
                      icon: _isGenerating
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(!canGenerate ? Icons.lock : Icons.auto_awesome),
                      label: Text(
                        _isGenerating
                            ? 'Generating...'
                            : !canGenerate
                                ? 'Trial Limit Reached'
                                : 'Generate $effectiveCardCount Flashcards',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canGenerate ? Colors.purple : Colors.grey,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  // ✅ Subscribe CTA when running low
                  if (!_isUnlimited && _trialRemaining <= 3) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Navigate to subscription
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const AISubscriptionScreen()));
                        },
                        icon: const Icon(Icons.diamond),
                        label: const Text('Subscribe for Unlimited Flashcards'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}