import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../core/auth_service.dart';
import '../../core/expert_tutor_service.dart';
import '../../core/supabase_config.dart';
import 'package:http/http.dart' as http;
import '../../core/trial_usage_service.dart';
import '../../widgets/trial_limit_dialog.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/ai_markdown.dart';

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

  // ✅ Pending image attachment
String? _pendingImageUrl;      // public URL after upload
bool _pendingImageUploading = false;
double _pendingImageProgress = 0.0;
String? _pendingImageLocalPath; // for preview
bool _isSubmitting = false;     // lock for the send button

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
    // ✅ isFirstBatch = true
    final stream = _streamTeachingContent(
      objectivesText,
      isFirstBatch: true,  // ✅ FIRST batch - GREET
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

  // ✅ NO system message — the AI already handled the transition
  // Just generate teaching content for next batch
  await _generateTeachingContentForNextBatch(isFirstBatch: false);
}

// ✅ Generate teaching for next batch
Future<void> _generateTeachingContentForNextBatch({required bool isFirstBatch}) async {
  if (_sessionId == null) return;
  
  final nextObjectives = _objectives
      .where((obj) => obj['is_mastered'] != true)
      .take(5)
      .toList();
  
  if (nextObjectives.isEmpty) return;
  
  final objectivesText = nextObjectives
      .map((obj) => '- ${obj['objective_text']}')
      .join('\n');
  
  // ✅ Get mastered objectives for continuity
  final masteredText = _objectives
      .where((obj) => obj['is_mastered'] == true)
      .map((obj) => '- ${obj['objective_text']}')
      .join('\n');
  
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
    // ✅ isFirstBatch = false - NO greeting, just continuation
    final stream = _streamTeachingContent(
      objectivesText,
      isFirstBatch: false,  // ✅ SUBSEQUENT batch - NO GREET
      masteredText: masteredText,  // ✅ Pass mastered for context
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

Future<void> _pickAttachment({required ImageSource source}) async {
  if (_isSending || _isTeachingMode || _isSubmitting) return;
  
  try {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    
    if (image == null) return;
    
    // Show pending state in the input bar
    setState(() {
      _pendingImageLocalPath = image.path;
      _pendingImageUploading = true;
      _pendingImageProgress = 0.0;
    });
    
    // Trial check
    final trialCheck = await TrialUsageService().canUseFeature('expert_tutor_messages');
    if (!trialCheck.allowed) {
      if (mounted) {
        setState(() {
          _pendingImageLocalPath = null;
          _pendingImageUploading = false;
        });
        final subscribed = await TrialLimitDialog.show(
          context,
          featureName: 'Expert Tutor',
          customMessage: trialCheck.message ?? 'Trial limit reached.',
        );
        if (subscribed == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Unlimited access activated!'),
              backgroundColor: Color(0xFF4CAF50),
            ),
          );
        }
      }
      return;
    }
    
    // Upload to Supabase Storage
    final bytes = await image.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = '$_studentId/$_sessionId/$fileName';
    
    // Simulate progress since Supabase doesn't expose it directly
    // For large files, we can fake progress with a timer
    _simulateUploadProgress();
    
    await Supabase.instance.client.storage
        .from('expert-tutor-answers')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ));
    
    final imageUrl = Supabase.instance.client.storage
        .from('expert-tutor-answers')
        .getPublicUrl(path);
    
    if (mounted) {
      setState(() {
        _pendingImageUrl = imageUrl;
        _pendingImageUploading = false;
        _pendingImageProgress = 1.0;
      });
    }
  } catch (e) {
    debugPrint('❌ Error picking image: $e');
    if (mounted) {
      setState(() {
        _pendingImageUrl = null;
        _pendingImageLocalPath = null;
        _pendingImageUploading = false;
        _pendingImageProgress = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// Simple fake progress simulation for UI feedback
void _simulateUploadProgress() {
  _pendingImageProgress = 0.0;
  Timer.periodic(const Duration(milliseconds: 100), (timer) {
    if (!mounted || !_pendingImageUploading) {
      timer.cancel();
      return;
    }
    setState(() {
      _pendingImageProgress = (_pendingImageProgress + 0.1).clamp(0.0, 0.95);
    });
  });
}

// Stream teaching content
Stream<String> _streamTeachingContent(String objectivesText, {bool isFirstBatch = false, String? masteredText}) async* {
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
      'isFirstBatch': isFirstBatch,  
      'masteredText': masteredText,  
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

 // ✅ Shared logic — called after ANY stream (text or image) completes
Future<void> _processAIResponse(int streamingIndex) async {
  final finalText = _streamingText;
  String cleanText = finalText;
  bool alreadySaved = false;

  // TOPIC COMPLETE
  if (finalText.contains('[TOPIC_COMPLETE]')) {
    cleanText = cleanText
        .replaceAll('[TOPIC_COMPLETE]', '')
        .replaceAll('[OBJECTIVE_MASTERED]', '')
        .replaceAll('[BATCH_COMPLETE]', '')
        .trim();
    _messages[streamingIndex]['content'] = cleanText;

    if (_currentObjective != null && _studentId.isNotEmpty) {
      await _expertService.markObjectiveMastered(
        studentId: _studentId,
        objectiveId: _currentObjective!['id'] as String,
      );
    }

    final currentIndex = _objectives.indexWhere((o) => o['id'] == _currentObjective?['id']);
    if (currentIndex != -1) {
      _objectives[currentIndex]['is_mastered'] = true;
    }

    if (_sessionId != null && cleanText.isNotEmpty) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: cleanText,
        objectiveId: _currentObjective?['id'] as String?,
      );
      alreadySaved = true;
    }

    await _loadTopicMCQs();
  }
  // BATCH COMPLETE
  else if (finalText.contains('[BATCH_COMPLETE]')) {
    cleanText = cleanText
        .replaceAll('[BATCH_COMPLETE]', '')
        .replaceAll('[OBJECTIVE_MASTERED]', '')
        .trim();
    _messages[streamingIndex]['content'] = cleanText;

    if (_currentObjective != null && _studentId.isNotEmpty) {
      await _expertService.markObjectiveMastered(
        studentId: _studentId,
        objectiveId: _currentObjective!['id'] as String,
      );
    }

    final currentIndex = _objectives.indexWhere((o) => o['id'] == _currentObjective?['id']);
    if (currentIndex != -1) {
      _objectives[currentIndex]['is_mastered'] = true;
    }

    // ✅ Save assessor message BEFORE teaching starts
    if (_sessionId != null && cleanText.isNotEmpty) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: cleanText,
        objectiveId: _currentObjective?['id'] as String?,
      );
      alreadySaved = true;
    }

    // Advance objective
    Map<String, dynamic>? nextObjective;
    for (int i = currentIndex + 1; i < _objectives.length; i++) {
      if (_objectives[i]['is_mastered'] != true) {
        nextObjective = _objectives[i];
        break;
      }
    }
    if (nextObjective != null) _currentObjective = nextObjective;

    await _startNewTeachingBatch();
  }
  // OBJECTIVE MASTERED
  else if (finalText.contains('[OBJECTIVE_MASTERED]')) {
    cleanText = cleanText.replaceAll('[OBJECTIVE_MASTERED]', '').trim();
    _messages[streamingIndex]['content'] = cleanText;

    if (_currentObjective != null && _studentId.isNotEmpty) {
      await _expertService.markObjectiveMastered(
        studentId: _studentId,
        objectiveId: _currentObjective!['id'] as String,
      );
    }

    if (_sessionId != null && cleanText.isNotEmpty) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: cleanText,
        objectiveId: _currentObjective?['id'] as String?,
      );
      alreadySaved = true;
    }

    _moveToNextObjective();
  }
  // NORMAL RESPONSE
  else {
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

    if (_sessionId != null && cleanText.isNotEmpty) {
      await _expertService.saveMessage(
        sessionId: _sessionId!,
        role: 'expert',
        content: cleanText,
        objectiveId: _currentObjective?['id'] as String?,
      );
      alreadySaved = true;
    }

    // Increment trial usage
    if (cleanText.isNotEmpty && !cleanText.contains('Sorry, an error occurred')) {
      await TrialUsageService().incrementUsage('expert_tutor_messages');
    }
  }

  // Fallback save
  if (!alreadySaved && _sessionId != null && cleanText.isNotEmpty) {
    await _expertService.saveMessage(
      sessionId: _sessionId!,
      role: 'expert',
      content: cleanText,
      objectiveId: _currentObjective?['id'] as String?,
    );
  }

  await _loadObjectives();
}
Future<void> _submitMessage() async {
  if (_isTeachingMode) return;
  if (_isSubmitting || _isSending) return;
  if (_pendingImageUploading) return; // Wait for upload

  final text = _inputController.text.trim();
  final hasImage = _pendingImageUrl != null;
  
  // Need at least text or image
  if (text.isEmpty && !hasImage) return;

  // ✅ Lock immediately to prevent double-send
  setState(() => _isSubmitting = true);

  // Trial check (only if sending content)
  final trialCheck = await TrialUsageService().canUseFeature('expert_tutor_messages');
  if (!trialCheck.allowed) {
    if (mounted) {
      setState(() => _isSubmitting = false);
      final subscribed = await TrialLimitDialog.show(
        context,
        featureName: 'Expert Tutor',
        customMessage: trialCheck.message ?? 'Trial limit reached.',
      );
      if (subscribed == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Unlimited access activated!'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    }
    return;
  }

  // Capture values before clearing
  final imageUrlToSend = _pendingImageUrl;
  final textToSend = text;

  // Clear input + pending attachment
  _inputController.clear();
  
  setState(() {
    _messages.add({
      'role': 'student',
      'content': textToSend.isNotEmpty ? textToSend : '[Handwritten answer]',
      'message_type': hasImage ? 'image' : 'text',
      'image_url': imageUrlToSend,
      'created_at': DateTime.now().toIso8601String(),
    });
    _pendingImageUrl = null;
    _pendingImageLocalPath = null;
    _pendingImageProgress = 0.0;
    _isSending = true;
    _isStreaming = true;
    _streamingText = '';
  });

  // Save student message to DB
  if (_sessionId != null) {
    await _expertService.saveMessage(
      sessionId: _sessionId!,
      role: 'student',
      content: textToSend.isNotEmpty ? textToSend : '[Handwritten answer]',
      messageType: hasImage ? 'image' : 'text',
      imageUrl: imageUrlToSend,
    );
  }

  // Add streaming placeholder for AI response
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
    // Stream response — image or text
    final stream = hasImage
        ? _streamExpertResponseWithImage(
            sessionId: _sessionId!,
            imageUrl: imageUrlToSend!,
            currentObjectiveId: _currentObjective?['id'] as String?,
          )
        : _streamExpertResponse(
            sessionId: _sessionId!,
            message: textToSend,
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

    await _processAIResponse(streamingIndex);
  } catch (e) {
    if (mounted) {
      setState(() {
        _messages[streamingIndex]['content'] = 'Sorry, an error occurred.';
      });
    }
    debugPrint('❌ Error: $e');
  } finally {
    if (mounted) {
      setState(() {
        _isSending = false;
        _isStreaming = false;
        _isSubmitting = false;
        _streamingText = '';
      });
    }
  }
}

  void _moveToNextObjective() {
  final currentIndex = _objectives.indexWhere(
    (obj) => obj['id'] == _currentObjective?['id']
  );

  if (currentIndex != -1) {
    _objectives[currentIndex]['is_mastered'] = true;
  }

  // ✅ Skip already-mastered objectives
  Map<String, dynamic>? nextObjective;
  for (int i = currentIndex + 1; i < _objectives.length; i++) {
    if (_objectives[i]['is_mastered'] != true) {
      nextObjective = _objectives[i];
      break;
    }
  }

  if (nextObjective != null) {
    _currentObjective = nextObjective;

    // Check batch boundary
    final masteredCount = _objectives
        .where((o) => o['is_mastered'] == true)
        .length;
    final isEndOfBatch = masteredCount % 5 == 0 && masteredCount > 0;

    if (isEndOfBatch) {
      _startNewTeachingBatch();
    }
    // For normal transition: do nothing
    // AI already introduced the next objective in its message
  } else {
    // No more non-mastered objectives
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

  Stream<String> _streamExpertResponseWithImage({
  required String sessionId,
  required String imageUrl,
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
    });

    final payload = jsonEncode({
      'action': 'expert_chat',
      'sessionId': sessionId,
      'message': '[Handwritten answer uploaded]',
      'image_url': imageUrl,
      'has_image': true,
      'currentObjectiveId': currentObjectiveId,
      'studentId': _studentId,
    });

    request.sink.add(utf8.encode(payload));
    request.sink.close();

    final response = await client.send(request);
    if (response.statusCode != 200) {
      yield 'Error: Failed to connect';
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
    debugPrint('Image stream error: $e');
    yield 'Connection error.';
  } finally {
    client.close();
  }
}

// ✅ Show attachment options (Camera / Gallery)
Future<void> _showAttachmentSheet() async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const Text(
              'Add a photo of your answer',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A237E),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Show your working — the tutor will grade your handwriting',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Camera option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: Color(0xFF1A237E),
                  size: 24,
                ),
              ),
              title: const Text(
                'Take a photo',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: const Text(
                'Opens your camera',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),

            // Gallery option
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.purple,
                  size: 24,
                ),
              ),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              subtitle: const Text(
                'Pick an existing photo',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),

            const SizedBox(height: 8),

            // Cancel button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // Handle the choice
  if (choice == 'camera') {
  await _pickAttachment(source: ImageSource.camera);
} else if (choice == 'gallery') {
  await _pickAttachment(source: ImageSource.gallery);
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
  final hasImage = _pendingImageUrl != null || _pendingImageLocalPath != null;
  final canSend = (hasText || hasImage) 
      && !_isSending 
      && !_isSubmitting 
      && !_pendingImageUploading;

  return Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Colors.grey.shade100)),
    ),
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ Image preview ABOVE the input bar
          if (hasImage) _buildImagePreview(),
          
          // The pill-shaped input bar
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Plus button
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: IconButton(
                    onPressed: (_isSending || _isSubmitting || _pendingImageUploading) 
                        ? null 
                        : _showAttachmentSheet,
                    icon: Icon(
                      Icons.add_rounded,
                      color: (_isSending || _isSubmitting || _pendingImageUploading) 
                          ? Colors.grey.shade400 
                          : Colors.black87,
                      size: 24,
                    ),
                    splashRadius: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    tooltip: 'Attach',
                  ),
                ),
                
                // Text input
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    maxLines: 5,
                    minLines: 1,
                    enabled: !_isSending && !_isSubmitting,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                    decoration: const InputDecoration(
                      hintText: 'Ask anything',
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                
                // Send button with loading state
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: canSend ? const Color(0xFF1A237E) : Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: _isSubmitting || _isSending
                      // ✅ Loading spinner during send
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : IconButton(
                          onPressed: canSend ? _submitMessage : null,
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: canSend ? Colors.white : Colors.grey.shade500,
                            size: 20,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildImagePreview() {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    alignment: Alignment.centerLeft,
    child: Stack(
      children: [
        // Thumbnail
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            image: _pendingImageUrl != null
                ? DecorationImage(
                    image: NetworkImage(_pendingImageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: _pendingImageUploading
              // ✅ Loading overlay while uploading
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        value: _pendingImageProgress > 0 ? _pendingImageProgress : null,
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        
        // Remove (X) button
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _pendingImageUrl = null;
                _pendingImageLocalPath = null;
                _pendingImageUploading = false;
                _pendingImageProgress = 0.0;
              });
            },
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.close,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
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
    final imageUrl = message['image_url'] as String?;
    
    // Don't show the placeholder text if there's an image
    final showText = content.isNotEmpty 
        && content != '[Handwritten answer]';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isExpert ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isExpert) ...[
            Container(
              width: 34, height: 34,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image preview
                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: 220,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 220, height: 150,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (c, e, s) => Container(
                          width: 220, height: 100,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                    if (showText) const SizedBox(height: 8),
                  ],
                  
                  // Text content (or loading)
                  if (content.isEmpty && isExpert)
                    const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (showText)
                    AiMarkdown(
                        text: content,
                        style: TextStyle(
                        fontSize: 15, height: 1.6,
                        color: isExpert ? const Color(0xFF1E1E1E) : Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}