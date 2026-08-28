import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../core/auth_service.dart';
import '../../core/expert_tutor_service.dart';
import '../../core/supabase_config.dart';
import 'package:http/http.dart' as http;

class ExpertTutorScreen extends StatefulWidget {
  final String? topicId;
  final String? topicName;
  final String? subjectId;
  final String? subjectName;
  final String? levelId;
  final String? levelName;
  final String? sessionId;

  const ExpertTutorScreen({
    super.key,
    this.topicId,
    this.topicName,
    this.subjectId,
    this.subjectName,
    this.levelId,
    this.levelName,
    this.sessionId,
  });

  @override
  State<ExpertTutorScreen> createState() => _ExpertTutorScreenState();
}

class _ExpertTutorScreenState extends State<ExpertTutorScreen> {
  final AuthService _authService = AuthService();
  final ExpertTutorService _expertService = ExpertTutorService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Session data
  String? _sessionId;
  List<Map<String, dynamic>> _objectives = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _currentObjective;
  String _studentId = '';

  // UI state
  bool _isLoading = true;
  bool _isSending = false;
  bool _showSyllabus = true;
  bool _isStreaming = false;
  String _streamingText = '';

  // Timer
  Timer? _exerciseTimer;
  int _remainingSeconds = 0;
  bool _isTimerRunning = false;

  // Add these to _ExpertTutorScreenState:
String _sessionPhase = 'teaching'; // 'teaching' or 'assessment'
bool _isTeachingMode = true;
bool _teachingContentReady = false;

// Timer for teaching mode
Timer? _teachingTimer;
int _teachingSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _exerciseTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

 Future<void> _initSession() async {
  final userId = _authService.currentUserId;
  if (userId == null) return;
  _studentId = userId;

  try {
    if (widget.sessionId != null) {
      // Resume existing session
      _sessionId = widget.sessionId;
      await _loadSessionData();
    } else {
      // Create new session
      _sessionId = await _expertService.createSession(
        studentId: userId,
        topicId: widget.topicId!,
        subjectId: widget.subjectId,
        levelId: widget.levelId,
      );

      // Load objectives
      await _loadObjectives();

      // Get first objective
      if (_objectives.isNotEmpty) {
        _currentObjective = _objectives.first;
      }

      // ✅ Start with TEACHING MODE
      _sessionPhase = 'teaching';
      _isTeachingMode = true;
      
      // Start teaching timer
      _startTeachingTimer();
      
      // Generate teaching content
      await _generateTeachingContent();
    }

    if (mounted) setState(() => _isLoading = false);
  } catch (e) {
    debugPrint('Error initializing session: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}

  // Load session data for resume
  Future<void> _loadSessionData() async {
  await _loadObjectives();

  // ✅ Get session details including phase
  final session = await _expertService.getSession(_sessionId!);
  _sessionPhase = session?['session_phase'] as String? ?? 'teaching';
  _isTeachingMode = _sessionPhase == 'teaching';

  final messages = await _expertService.getMessages(_sessionId!);
  _messages = List<Map<String, dynamic>>.from(messages);

  final progress = await _expertService.getProgress(_sessionId!);

  // Update objectives with mastery status
  for (final p in progress) {
    final index = _objectives.indexWhere((obj) => obj['id'] == p['objective_id']);
    if (index != -1) {
      _objectives[index]['is_mastered'] = p['is_mastered'] ?? false;
      _objectives[index]['difficulty_reached'] = p['difficulty_reached'] ?? 'easy';
    }
  }

  // Find current objective (first non-mastered)
  for (final obj in _objectives) {
    final isMastered = obj['is_mastered'] == true;
    if (!isMastered) {
      _currentObjective = obj;
      break;
    }
  }

  if (_currentObjective == null && _objectives.isNotEmpty) {
    _currentObjective = _objectives.first;
  }

  // ✅ If teaching mode, check if teaching content already exists
  if (_isTeachingMode) {
    _teachingContentReady = _messages.any((m) => m['message_type'] == 'teaching');
    _startTeachingTimer();
  }
}

// Start teaching timer (counts up)
void _startTeachingTimer() {
  _teachingTimer?.cancel();
  _teachingSeconds = 0;
  _teachingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (mounted && _isTeachingMode) {
      setState(() => _teachingSeconds++);
    }
  });
}

// Format teaching time
String _formatTeachingTime() {
  final mins = _teachingSeconds ~/ 60;
  final secs = _teachingSeconds % 60;
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

// Generate teaching content
Future<void> _generateTeachingContent() async {
  if (_objectives.isEmpty || _sessionId == null) return;

  final teachingObjectives = _objectives.take(5).toList();
  final objectivesText = teachingObjectives
      .map((obj) => '- ${obj['objective_text']}')
      .join('\n');

  setState(() {
    _messages.add({
      'role': 'system',
      'content': '📚 **Teaching Mode**\n\nRead and understand the concepts. Click "START SESSION" when ready.',
      'message_type': 'system',
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  final streamingIndex = _messages.length;
  setState(() {
    _messages.add({
      'role': 'expert',
      'content': '',
      'message_type': 'streaming',
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  try {
    final stream = _streamTeachingContent(objectivesText);
    
    await for (final chunk in stream) {
      if (mounted) {
        setState(() {
          _messages[streamingIndex]['content'] += chunk;
        });
        _scrollToBottom();
      }
    }

    if (_sessionId != null) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: _messages[streamingIndex]['content'],
        messageType: 'teaching',
      );
    }

    setState(() => _teachingContentReady = true);
  } catch (e) {
    debugPrint('Error generating teaching content: $e');
    if (mounted) setState(() => _teachingContentReady = true);
  }
}

Future<void> _startNewTeachingBatch() async {
  setState(() {
    _isTeachingMode = true;
    _sessionPhase = 'teaching';
    _teachingContentReady = false;
  });
  
  // Update session phase in DB
  if (_sessionId != null) {
    await _expertService.updateSessionPhase(
      sessionId: _sessionId!,
      phase: 'teaching',
    );
  }
  
  // Start timer
  _startTeachingTimer();
  
  // Add system message
  setState(() {
    _messages.add({
      'role': 'system',
      'content': '📚 **Teaching Mode - Next Batch**\n\nRead and understand the next concepts. Click "START SESSION" when ready.',
      'message_type': 'system',
      'created_at': DateTime.now().toIso8601String(),
    });
  });
  
  // Generate teaching content for next 5 objectives
  await _generateTeachingContentForNextBatch();
}

// ✅ Generate teaching for next batch
Future<void> _generateTeachingContentForNextBatch() async {
  if (_sessionId == null) return;
  
  // Find next 5 non-mastered objectives
  final nextObjectives = _objectives
      .where((obj) => obj['is_mastered'] != true)
      .take(5)
      .toList();
  
  if (nextObjectives.isEmpty) return;
  
  final objectivesText = nextObjectives
      .map((obj) => '- ${obj['objective_text']}')
      .join('\n');
  
  // Stream teaching content
  final streamingIndex = _messages.length;
  setState(() {
    _messages.add({
      'role': 'expert',
      'content': '',
      'message_type': 'streaming',
      'created_at': DateTime.now().toIso8601String(),
    });
  });
  
  try {
    final stream = _streamTeachingContent(objectivesText);
    
    await for (final chunk in stream) {
      if (mounted) {
        setState(() {
          _messages[streamingIndex]['content'] += chunk;
        });
        _scrollToBottom();
      }
    }
    
    if (_sessionId != null) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: _messages[streamingIndex]['content'],
        messageType: 'teaching',
      );
    }
    
    setState(() => _teachingContentReady = true);
  } catch (e) {
    debugPrint('Error generating teaching content: $e');
    if (mounted) setState(() => _teachingContentReady = true);
  }
}

// ✅ Trigger topic complete
Future<void> _triggerTopicComplete() async {
  if (_sessionId == null) return;
  
  final streamingIndex = _messages.length;
  setState(() {
    _messages.add({
      'role': 'expert',
      'content': '',
      'message_type': 'streaming',
      'created_at': DateTime.now().toIso8601String(),
    });
  });
  
  try {
    final stream = _streamExpertResponse(
      sessionId: _sessionId!,
      message: 'All objectives mastered. Congratulate the student and end with [TOPIC_COMPLETE]',
      currentObjectiveId: null,
    );
    
    await for (final chunk in stream) {
      if (mounted) {
        setState(() {
          _messages[streamingIndex]['content'] += chunk;
        });
        _scrollToBottom();
      }
    }
    
    // Check for [TOPIC_COMPLETE]
    final finalText = _messages[streamingIndex]['content'] as String;
    if (finalText.contains('[TOPIC_COMPLETE]')) {
      final cleanText = finalText.replaceAll('[TOPIC_COMPLETE]', '').trim();
      _messages[streamingIndex]['content'] = cleanText;
      
      // Load MCQs
      await _loadTopicMCQs();
    }
  } catch (e) {
    debugPrint('Error triggering topic complete: $e');
  }
}

// Stream teaching content
Stream<String> _streamTeachingContent(String objectivesText) async* {
  final client = http.Client();

  try {
    final request = http.StreamedRequest(
      'POST',
      Uri.parse('${SupabaseConfig.url}/functions/v1/expert-tutor'),
    );

    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      'Accept': 'text/event-stream',
    });

    final payload = jsonEncode({
      'action': 'expert_teach',
      'sessionId': _sessionId,
      'objectivesText': objectivesText,
      'topicName': widget.topicName,
      'subjectName': widget.subjectName,
      'levelName': widget.levelName,
    });

    request.sink.add(utf8.encode(payload));
    request.sink.close();

    final response = await client.send(request);

    if (response.statusCode != 200) {
      yield 'Error: Failed to generate teaching content';
      return;
    }

    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) continue;

      if (trimmedLine.startsWith('data: ')) {
        final rawData = trimmedLine.substring(6).trim();
        if (rawData == '[DONE]') break;

        try {
          final parsed = jsonDecode(rawData);
          if (parsed is Map && parsed.containsKey('meta')) continue;
          if (parsed is Map && parsed.containsKey('text')) {
            final text = parsed['text'] as String;
            if (text.isNotEmpty) yield text;
          }
        } catch (_) {}
      }
    }
  } catch (e) {
    yield 'Connection error. Please try again.';
  } finally {
    client.close();
  }
}

// Start assessment mode
Future<void> _startAssessment() async {
  setState(() {
    _isTeachingMode = false;
    _sessionPhase = 'assessment';
    _teachingTimer?.cancel();
  });

  if (_sessionId != null) {
    await _expertService.updateSessionPhase(
      sessionId: _sessionId!,
      phase: 'assessment',
    );
  }

  setState(() {
    _messages.add({
      'role': 'system',
      'content': '📝 **Assessment Mode**\n\nLet\'s check your understanding!',
      'message_type': 'system',
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  await _triggerAssessment();
}

// Trigger assessment start
Future<void> _triggerAssessment() async {
  if (_currentObjective == null || _sessionId == null) return;

  final streamingIndex = _messages.length;
  setState(() {
    _messages.add({
      'role': 'expert',
      'content': '',
      'message_type': 'streaming',
      'created_at': DateTime.now().toIso8601String(),
    });
  });

  try {
    final stream = _streamExpertResponse(
      sessionId: _sessionId!,
      message: 'Start assessment. Ask me about: ${_currentObjective!['objective_text']}',
      currentObjectiveId: _currentObjective!['id'] as String?,
    );

    await for (final chunk in stream) {
      if (mounted) {
        setState(() {
          _messages[streamingIndex]['content'] += chunk;
        });
        _scrollToBottom();
      }
    }

    if (_sessionId != null) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: _messages[streamingIndex]['content'],
        objectiveId: _currentObjective!['id'] as String?,
      );
    }
  } catch (e) {
    debugPrint('Error starting assessment: $e');
  }
}

  // Load syllabus objectives
  Future<void> _loadObjectives() async {
  final objectives = await _expertService.getObjectives(widget.topicId!);
  
  if (_studentId.isNotEmpty) {
    // Get progress for this TOPIC directly
    final progress = await _expertService.getTopicProgress(
      studentId: _studentId,
      topicId: widget.topicId!,
    );
    
    final progressMap = <String, Map<String, dynamic>>{};
    for (final p in progress) {
      progressMap[p['objective_id'] as String] = p;
    }
    
    _objectives = objectives.map((obj) {
      final objProgress = progressMap[obj['id']];
      return {
        ...obj,
        'is_mastered': objProgress?['is_mastered'] ?? false,
        'mastery_level': objProgress?['mastery_level'] ?? 0,
        'difficulty_reached': objProgress?['difficulty_reached'] ?? 'easy',
      };
    }).toList();
  } else {
    _objectives = objectives;
  }
}

  // Build welcome message
  String _buildWelcomeMessage() {
    final objectiveText = _currentObjective?['objective_text'] ?? '';
    final subtopicName = _currentObjective?['subtopic_name'] ?? '';
    final commandWord = _currentObjective?['command_word'] ?? 'understand';

    return '''
👋 Welcome to **${widget.topicName ?? 'Expert Tutoring'}**!

I'm your Expert Tutor. I'll guide you through the syllabus step by step.

📋 **Current Objective:**
${subtopicName != 'General' ? '*$subtopicName*: ' : ''}$objectiveText

*Command word: $commandWord*

Let's start! I'll explain the concept, then we'll practice together.
''';
  }

  // Send student message with streaming
  Future<void> _sendMessage() async {
    // Don't allow sending in teaching mode
    if (_isTeachingMode) return;
    
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    
    // Add student message to chat
    setState(() {
      _messages.add({
        'role': 'student',
        'content': text,
        'message_type': 'text',
        'created_at': DateTime.now().toIso8601String(),
      });
      _isSending = true;
      _isStreaming = true;
      _streamingText = '';
    });

    // Save student message to database
    if (_sessionId != null) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'student',
        content: text,
      );
    }

    // Add a placeholder for AI response (will stream into this)
    final streamingIndex = _messages.length;
    setState(() {
      _messages.add({
        'role': 'expert',
        'content': '',
        'message_type': 'streaming',
        'created_at': DateTime.now().toIso8601String(),
      });
    });

    _scrollToBottom();

    try {
      // Stream AI response
      final stream = _streamExpertResponse(
        sessionId: _sessionId!,
        message: text,
        currentObjectiveId: _currentObjective?['id'] as String?,
      );

      await for (final chunk in stream) {
        if (mounted) {
          setState(() {
            _streamingText += chunk;
            _messages[streamingIndex]['content'] = _streamingText;
          });
          _scrollToBottom();
        }
      }

      // Get the full AI response
      final finalText = _streamingText;
      String cleanText = finalText;

      // ✅ Check if the entire TOPIC is complete
      if (finalText.contains('[TOPIC_COMPLETE]')) {
        cleanText = cleanText.replaceAll('[TOPIC_COMPLETE]', '').trim();
        _messages[streamingIndex]['content'] = cleanText;
        
        // Load 10 MCQs from question bank
        await _loadTopicMCQs();
      }
      
      // ✅ Check if current OBJECTIVE is mastered
      else if (finalText.contains('[OBJECTIVE_MASTERED]')) {
        cleanText = cleanText.replaceAll('[OBJECTIVE_MASTERED]', '').trim();
        _messages[streamingIndex]['content'] = cleanText;
        
        // Save mastery to database
        if (_currentObjective != null && _studentId.isNotEmpty) {
          await _expertService.markObjectiveMastered(
            studentId: _studentId,
            objectiveId: _currentObjective!['id'] as String,
          );
        }
        
        // Move to next objective
        _moveToNextObjective();
      }
      // ✅ Normal response (question, feedback, hint, etc.)
      else {
        // Save progress (correct/incorrect)
        final isCorrect = _isAnswerCorrect(finalText);
        final currentDifficulty = _getCurrentDifficulty();
        
        if (_currentObjective != null && _studentId.isNotEmpty) {
          await _expertService.updateProgress(
            studentId: _studentId,
            objectiveId: _currentObjective!['id'] as String,
            difficulty: currentDifficulty,
            isCorrect: isCorrect,
          );
        }
      }

      // Save AI response to database
      if (_sessionId != null && cleanText.isNotEmpty) {
        await _expertService.saveMessage(
          sessionId: _sessionId!,
          role: 'expert',
          content: cleanText,
          objectiveId: _currentObjective?['id'] as String?,
        );
      }

      // Reload objectives to show updated mastery
      await _loadObjectives();

    } catch (e) {
      if (mounted) {
        setState(() {
          _messages[streamingIndex]['content'] = 'Sorry, an error occurred. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isStreaming = false;
          _streamingText = '';
        });
      }
    }
  }

  void _moveToNextObjective() {
  final currentIndex = _objectives.indexWhere((obj) => obj['id'] == _currentObjective?['id']);
  
  if (currentIndex != -1) {
    _objectives[currentIndex]['is_mastered'] = true;
  }

  final masteredCount = _objectives.where((o) => o['is_mastered'] == true).length;
  final isEndOfBatch = masteredCount % 5 == 0 && masteredCount > 0;

  if (currentIndex != -1 && currentIndex + 1 < _objectives.length) {
    _currentObjective = _objectives[currentIndex + 1];
    
    if (isEndOfBatch) {
      // ✅ Only for batch transition, add teaching mode message
      _startNewTeachingBatch();
    }
    // ✅ For normal objective transition, do NOTHING
    // The AI already introduced the next objective in its response
  } else {
    _messages.add({
      'role': 'expert',
      'content': '🎉 **Congratulations!** You have mastered all objectives for this topic!',
      'message_type': 'text',
      'created_at': DateTime.now().toIso8601String(),
    });
    
    _triggerTopicComplete();
  }
}
  // ✅ Helper: Check if answer was correct based on AI response
  bool _isAnswerCorrect(String aiResponse) {
    final lowerResponse = aiResponse.toLowerCase();
    
    // If objective mastered, definitely correct
    if (lowerResponse.contains('[objective_mastered]')) {
      return true;
    }
    
    // Positive indicators
    final positiveIndicators = [
      'very good',
      'correct',
      'well done',
      'good job',
      'exactly',
      'you got it',
      'nailed it',
      'perfect',
      'excellent',
      'great',
      'right',
      'yes,',
      'that\'s right',
    ];
    
    // Negative indicators
    final negativeIndicators = [
      'not quite',
      'incorrect',
      'wrong',
      'not exactly',
      'try again',
      'here\'s a hint',
      'not really',
      'almost',
      'close',
      'not correct',
      'that\'s not',
    ];
    
    // Check positive first
    for (final indicator in positiveIndicators) {
      if (lowerResponse.contains(indicator)) {
        return true;
      }
    }
    
    // Check negative
    for (final indicator in negativeIndicators) {
      if (lowerResponse.contains(indicator)) {
        return false;
      }
    }
    
    // Default to true if no negative found
    return true;
  }

  // ✅ Helper: Get current difficulty from progress
  String _getCurrentDifficulty() {
    final objectiveProgress = _objectives.firstWhere(
      (obj) => obj['id'] == _currentObjective?['id'],
      orElse: () => {'difficulty_reached': 'easy'},
    );
    
    return objectiveProgress['difficulty_reached'] as String? ?? 'easy';
  }

  // ✅ Helper: Load exercise from question bank
  Future<void> _loadTopicMCQs() async {
  if (widget.topicId == null) return;
  
  try {
    // Load 10 questions from question bank
    final questions = await _expertService.loadQuestions(
      topicId: widget.topicId!,
      difficulty: 'medium', // Can be any difficulty or all
      count: 10,
    );
    
    if (questions.isNotEmpty) {
      // Add system message
      setState(() {
        _messages.add({
          'role': 'system',
          'content': '📝 **Final Assessment**\n\nHere are ${questions.length} MCQs to test your understanding.',
          'message_type': 'system',
          'created_at': DateTime.now().toIso8601String(),
        });
      });
      
      // Display each MCQ
      for (final question in questions) {
        final options = [
          'A: ${question['option_a'] ?? ''}',
          'B: ${question['option_b'] ?? ''}',
          'C: ${question['option_c'] ?? ''}',
          'D: ${question['option_d'] ?? ''}',
        ].where((o) => o.trim().isNotEmpty && !o.endsWith(': ')).join('\n');
        
        setState(() {
          _messages.add({
            'role': 'expert',
            'content': '${question['question_text']}\n\n$options',
            'message_type': 'mcq',
            'created_at': DateTime.now().toIso8601String(),
          });
        });
        
        // Save MCQ to database
        if (_sessionId != null) {
          await _expertService.saveMessage(
            sessionId: _sessionId!,
            role: 'expert',
            content: '${question['question_text']}\n\n$options',
            messageType: 'mcq',
            questionId: question['id'] as String?,
          );
        }
      }
      
      _scrollToBottom();
    }
  } catch (e) {
    debugPrint('Error loading topic MCQs: $e');
  }
}

  // Stream expert response using HTTP
  Stream<String> _streamExpertResponse({
    required String sessionId,
    required String message,
    String? currentObjectiveId,
  }) async* {
    final client = http.Client();

    try {
      final request = http.StreamedRequest(
        'POST',
        Uri.parse('${SupabaseConfig.url}/functions/v1/expert-tutor'),
      );
      
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
      });

      final payload = jsonEncode({
        'action': 'expert_chat',
        'sessionId': sessionId,
        'message': message,
        'currentObjectiveId': currentObjectiveId,
        'studentId': _studentId,
      });

      request.sink.add(utf8.encode(payload));
      request.sink.close();

      final response = await client.send(request);

      if (response.statusCode != 200) {
        yield 'Error: Failed to connect to Expert Tutor';
        return;
      }

      final stream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in stream) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;

        if (trimmedLine.startsWith('data: ')) {
          final rawData = trimmedLine.substring(6).trim();
          if (rawData == '[DONE]') break;

          try {
            final parsed = jsonDecode(rawData);

            if (parsed is Map && parsed.containsKey('meta')) {
              debugPrint('Connected to: ${parsed['meta']['model']}');
              continue;
            }

            if (parsed is Map && parsed.containsKey('text')) {
              final text = parsed['text'] as String;
              if (text.isNotEmpty) {
                yield text;
              }
            }
          } catch (_) {
            if (rawData.isNotEmpty && !rawData.startsWith('{')) {
              yield rawData;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Expert stream error: $e');
      yield 'Connection error. Please try again.';
    } finally {
      client.close();
    }
  }

  // When objective is mastered
 void _onObjectiveMastered() {
  final currentIndex = _objectives.indexWhere((obj) => obj['id'] == _currentObjective?['id']);
  
  if (currentIndex != -1) {
    _objectives[currentIndex]['is_mastered'] = true;
  }

  if (currentIndex != -1 && currentIndex + 1 < _objectives.length) {
    _currentObjective = _objectives[currentIndex + 1];
    
    // ✅ Simple system message - AI will introduce next objective
    _messages.add({
      'role': 'system',
      'content': '✅ Objective mastered! Moving to next objective...',
      'message_type': 'system',
      'created_at': DateTime.now().toIso8601String(),
    });
    
    // ✅ Trigger AI to introduce next objective
    _triggerAssessment();
  } else {
    _messages.add({
      'role': 'expert',
      'content': '🎉 **Congratulations!** You have mastered all objectives for this topic!',
      'message_type': 'text',
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

 @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color(0xFFFAFAFA),
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.topicName ?? 'Expert Tutor', style: const TextStyle(fontSize: 16)),
          Text(
            _isTeachingMode
                ? 'Teaching Mode • ${_formatTeachingTime()}'
                : '${_objectives.where((o) => o['is_mastered'] == true).length}/${_objectives.length} mastered',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
      elevation: 0,
      actions: [
        IconButton(
          icon: Icon(
            _showSyllabus ? Icons.checklist : Icons.checklist_outlined,
            color: _showSyllabus ? const Color(0xFF1A237E) : Colors.grey,
          ),
          onPressed: () => setState(() => _showSyllabus = !_showSyllabus),
        ),
      ],
    ),
    body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              // ✅ START SESSION button (only in teaching mode)
              if (_isTeachingMode && _teachingContentReady)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: ElevatedButton.icon(
                    onPressed: _startAssessment,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('START SESSION'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              
              Expanded(
                child: Row(
                  children: [
                    if (_showSyllabus)
                      Container(
                        width: 280,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border(right: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: _buildSyllabusSidebar(),
                      ),
                    Expanded(child: _buildChatContent()),
                  ],
                ),
              ),
            ],
          ),
  );
}

  Widget _buildSyllabusSidebar() {
    final masteredCount = _objectives.where((o) => o['is_mastered'] == true).length;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1A237E).withOpacity(0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Syllabus Outline',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '$masteredCount / ${_objectives.length} mastered',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _objectives.length,
            itemBuilder: (context, index) {
              final objective = _objectives[index];
              final isMastered = objective['is_mastered'] == true;
              final isCurrent = objective['id'] == _currentObjective?['id'];

              return ListTile(
                dense: true,
                leading: Icon(
                  isMastered ? Icons.check_circle : Icons.circle_outlined,
                  color: isMastered ? Colors.green : Colors.grey,
                  size: 18,
                ),
                title: Text(
                  objective['objective_text'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrent ? const Color(0xFF1A237E) : Colors.black87,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: objective['subtopic_name'] != 'General'
                    ? Text(
                        objective['subtopic_name'] as String,
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                      )
                    : null,
                tileColor: isCurrent ? const Color(0xFF1A237E).withOpacity(0.05) : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChatContent() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return _ExpertMessageBubble(message: msg);
            },
          ),
        ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildInputBar() {
    if (_isTeachingMode) {
    return const SizedBox.shrink();
  }
    final hasText = _inputController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _inputController,
                  maxLines: 5,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: 'Type your answer...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: hasText ? const Color(0xFF1A237E) : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: hasText && !_isSending ? _sendMessage : null,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: hasText ? Colors.white : Colors.grey,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Expert message bubble
class _ExpertMessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;

  const _ExpertMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isExpert = message['role'] == 'expert';
    final content = message['content'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isExpert ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isExpert) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFFFF9800)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.school, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isExpert ? Colors.grey.shade50 : const Color(0xFF1A237E),
                borderRadius: BorderRadius.circular(16),
              ),
              child: content.isEmpty && isExpert
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : GptMarkdown(
                      content,
                      useDollarSignsForLatex: true,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: isExpert ? const Color(0xFF1E1E1E) : Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}