import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';

class ExpertTutorService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==========================================
  // SESSION MANAGEMENT (existing)
  // ==========================================
  
  Future<String> createSession({
    required String studentId,
    required String topicId,
    String? subjectId,
    String? levelId,
  }) async {
    final response = await _client
        .from('expert_tutor_sessions')
        .insert({
          'student_id': studentId,
          'topic_id': topicId,
          'subject_id': subjectId,
          'level_id': levelId,
          'session_status': 'active',
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  Future<Map<String, dynamic>?> getSession(String sessionId) async {
  final response = await _client
      .from('expert_tutor_sessions')
      .select('*, topics(name, syllabus_outline), subjects(name), levels(name)')
      .eq('id', sessionId)
      .maybeSingle();

  return response;
}

  Future<void> updateSessionStatus(String sessionId, String status) async {
    await _client
        .from('expert_tutor_sessions')
        .update({
          'session_status': status,
          'ended_at': status == 'completed' ? DateTime.now().toIso8601String() : null,
          'last_activity_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }

  

  Future<List<Map<String, dynamic>>> getStudentSessions(String studentId) async {
    final response = await _client
        .from('expert_tutor_sessions')
        .select('*, topics(name), subjects(name), levels(name)')
        .eq('student_id', studentId)
        .order('last_activity_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // ==========================================
  // SYLLABUS OBJECTIVES (existing)
  // ==========================================

  Future<List<Map<String, dynamic>>> getObjectives(String topicId) async {
    final response = await _client
        .from('expert_tutor_objectives')
        .select('*')
        .eq('topic_id', topicId)
        .eq('is_active', true)
        .order('display_order', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getObjectivesWithProgress({
    required String topicId,
    required String studentId,
  }) async {
    final objectives = await getObjectives(topicId);
    
    final progress = await _client
        .from('expert_tutor_progress')
        .select('*')
        .eq('student_id', studentId)
        .eq('topic_id', topicId);

    final progressMap = <String, Map<String, dynamic>>{};
    for (final p in progress) {
      progressMap[p['objective_id'] as String] = p;
    }

    return objectives.map((obj) {
      final objProgress = progressMap[obj['id']];
      return {
        ...obj,
        'is_mastered': objProgress?['is_mastered'] ?? false,
        'mastery_level': objProgress?['mastery_level'] ?? 0,
        'difficulty_reached': objProgress?['difficulty_reached'] ?? 'easy',
      };
    }).toList();
  }

  // ==========================================
  // STUDENT PROGRESS (existing + new)
  // ==========================================

  Future<List<Map<String, dynamic>>> getProgress(String sessionId) async {
    final session = await getSession(sessionId);
    if (session == null) return [];

    final response = await _client
        .from('expert_tutor_progress')
        .select('*')
        .eq('student_id', session['student_id'])
        .eq('topic_id', session['topic_id']);

    return List<Map<String, dynamic>>.from(response);
  }

  // ✅ NEW: Get progress for specific objective
  Future<Map<String, dynamic>?> getObjectiveProgress({
    required String studentId,
    required String objectiveId,
  }) async {
    final response = await _client
        .from('expert_tutor_progress')
        .select('*')
        .eq('student_id', studentId)
        .eq('objective_id', objectiveId)
        .maybeSingle();

    return response;
  }

  // ✅ NEW: Get all progress for a topic
  Future<List<Map<String, dynamic>>> getTopicProgress({
    required String studentId,
    required String topicId,
  }) async {
    final response = await _client
        .from('expert_tutor_progress')
        .select('*')
        .eq('student_id', studentId)
        .eq('topic_id', topicId);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> getNextObjective({
    required String studentId,
    required String topicId,
  }) async {
    final response = await _client.rpc('get_next_objective', params: {
      'p_student_id': studentId,
      'p_topic_id': topicId,
    });

    if (response == null) return null;
    
    String objectiveId;
    if (response is List) {
      if (response.isEmpty) return null;
      objectiveId = response.first.toString();
    } else {
      objectiveId = response.toString();
    }

    final objective = await _client
        .from('expert_tutor_objectives')
        .select('*')
        .eq('id', objectiveId)
        .maybeSingle();

    return objective;
  }

 Future<void> updateProgress({
  required String studentId,
  required String objectiveId,
  required String difficulty,
  required bool isCorrect,
}) async {
  try {
    await _client.rpc('update_expert_progress', params: {
      'p_student_id': studentId,
      'p_objective_id': objectiveId,
      'p_difficulty': difficulty,
      'p_is_correct': isCorrect,
    });
    
    debugPrint('✅ Progress saved via RPC');
  } catch (e) {
    debugPrint('❌ Error updating progress: $e');
  }
}

Future<void> markObjectiveMastered({
  required String studentId,
  required String objectiveId,
}) async {
  try {
    // Use RPC to mark as mastered properly
    await _client.rpc('mark_objective_mastered', params: {
      'p_student_id': studentId,
      'p_objective_id': objectiveId,
    });
    
    debugPrint('✅ Mastery saved via RPC');
  } catch (e) {
    debugPrint('❌ Error marking mastered: $e');
  }
}

  Future<bool> checkObjectiveMastered({
    required String studentId,
    required String objectiveId,
  }) async {
    final response = await _client.rpc('check_objective_mastery', params: {
      'p_student_id': studentId,
      'p_objective_id': objectiveId,
    });

    return response as bool? ?? false;
  }

  // ==========================================
  // MESSAGES (existing)
  // ==========================================

  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final response = await _client
        .from('expert_tutor_messages')
        .select('*')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> saveMessage({
    required String sessionId,
    required String role,
    required String content,
    String? messageType,
    String? objectiveId,
    String? questionId,
  }) async {
    await _client.from('expert_tutor_messages').insert({
      'session_id': sessionId,
      'role': role,
      'content': content,
      'message_type': messageType ?? 'text',
      'objective_id': objectiveId,
      'question_id': questionId,
    });
  }

  // ==========================================
  // EXERCISES (existing)
  // ==========================================

  Future<List<Map<String, dynamic>>> loadQuestions({
    required String topicId,
    required String difficulty,
    int count = 1,
  }) async {
    final response = await _client
        .from('question_bank')
        .select('*')
        .eq('topic_id', topicId)
        .eq('difficulty', difficulty)
        .eq('is_approved', true)
        .limit(count);

    if (response.isEmpty) {
      final fallback = await _client
          .from('question_bank')
          .select('*')
          .eq('topic_id', topicId)
          .eq('is_approved', true)
          .limit(count);
      
      return List<Map<String, dynamic>>.from(fallback);
    }

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> assignExercise({
    required String sessionId,
    required String studentId,
    required String objectiveId,
    required Map<String, dynamic> question,
    required String difficulty,
    int timeLimitSeconds = 300,
  }) async {
    final response = await _client
        .from('expert_tutor_exercises')
        .insert({
          'session_id': sessionId,
          'student_id': studentId,
          'objective_id': objectiveId,
          'question_id': question['id'],
          'difficulty': difficulty,
          'question_text': question['question_text'],
          'question_type': question['question_type'] ?? 'text',
          'correct_answer': question['correct_answer'],
          'time_limit_seconds': timeLimitSeconds,
          'due_at': DateTime.now().add(Duration(seconds: timeLimitSeconds)).toIso8601String(),
          'status': 'assigned',
        })
        .select()
        .single();

    return response;
  }

  Future<void> submitTextAnswer({
    required String exerciseId,
    required String studentId,
    required String answer,
  }) async {
    await _client.from('expert_tutor_answers').insert({
      'exercise_id': exerciseId,
      'student_id': studentId,
      'answer_type': 'text',
      'text_answer': answer,
      'submitted_at': DateTime.now().toIso8601String(),
    });

    await _client
        .from('expert_tutor_exercises')
        .update({
          'status': 'answered',
          'student_answer': answer,
          'submitted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', exerciseId);
  }

  Future<void> submitImageAnswer({
    required String exerciseId,
    required String studentId,
    required String imageUrl,
    required String imagePath,
  }) async {
    await _client.from('expert_tutor_answers').insert({
      'exercise_id': exerciseId,
      'student_id': studentId,
      'answer_type': 'image',
      'image_url': imageUrl,
      'image_path': imagePath,
      'submitted_at': DateTime.now().toIso8601String(),
    });

    await _client
        .from('expert_tutor_exercises')
        .update({
          'status': 'answered',
          'answer_image_url': imageUrl,
          'submitted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', exerciseId);
  }

  Future<void> gradeExercise({
    required String exerciseId,
    required bool isCorrect,
    required String aiFeedback,
    int? marksAwarded,
    int? marksTotal,
  }) async {
    await _client
        .from('expert_tutor_exercises')
        .update({
          'status': 'graded',
          'is_correct': isCorrect,
          'ai_feedback': aiFeedback,
          'marks_awarded': marksAwarded,
          'marks_total': marksTotal,
          'graded_at': DateTime.now().toIso8601String(),
        })
        .eq('id', exerciseId);
  }

  // ==========================================
  // AI INTERACTION (existing)
  // ==========================================

  Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    required String message,
    String? currentObjectiveId,
    String? studentId,
  }) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) throw Exception('Session not found');

      final response = await _client.functions.invoke('expert-tutor', body: {
        'action': 'expert_chat',
        'sessionId': sessionId,
        'message': message,
        'currentObjectiveId': currentObjectiveId,
        'studentId': studentId ?? session['student_id'],
      });

      if (response.data == null) {
        throw Exception('No response from AI');
      }

      Map<String, dynamic> data;
      if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else if (response.data is String) {
        try {
          data = jsonDecode(response.data as String) as Map<String, dynamic>;
        } catch (_) {
          data = {'content': response.data as String, 'type': 'text'};
        }
      } else {
        throw Exception('Unexpected response type');
      }

      await saveMessage(
        sessionId: sessionId,
        role: 'expert',
        content: data['content'] ?? '',
        messageType: data['type'] ?? 'text',
        objectiveId: currentObjectiveId,
      );

      return data;
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }

  // Update session phase
Future<void> updateSessionPhase({
  required String sessionId,
  required String phase,
}) async {
  await _client
      .from('expert_tutor_sessions')
      .update({
        'session_phase': phase,
        if (phase == 'assessment') 'assessment_started_at': DateTime.now().toIso8601String(),
        if (phase == 'teaching') 'teaching_started_at': DateTime.now().toIso8601String(),
        'last_activity_at': DateTime.now().toIso8601String(),
      })
      .eq('id', sessionId);
}

  Future<Map<String, dynamic>> gradeHandwrittenAnswer({
    required String imageUrl,
    required String questionText,
    required String correctAnswer,
    String? markingScheme,
  }) async {
    try {
      final response = await _client.functions.invoke('expert-tutor', body: {
        'action': 'grade_handwritten',
        'imageUrl': imageUrl,
        'questionText': questionText,
        'correctAnswer': correctAnswer,
        'markingScheme': markingScheme,
      });

      if (response.data == null) {
        throw Exception('No response from grading');
      }

      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error grading answer: $e');
      rethrow;
    }
  }

  Future<Map<String, String>> uploadAnswerImage({
    required String studentId,
    required String exerciseId,
    required Uint8List imageBytes,
    required String fileName,
  }) async {
    final path = 'expert_tutor_answers/$studentId/$exerciseId/$fileName';
    
    await _client.storage
        .from('expert-tutor-answers')
        .uploadBinary(path, imageBytes);

    final imageUrl = _client.storage
        .from('expert-tutor-answers')
        .getPublicUrl(path);

    return {
      'image_url': imageUrl,
      'image_path': path,
    };
  }

  // ==========================================
  // STATS (existing)
  // ==========================================

  Future<Map<String, dynamic>> getStudentStats(String studentId) async {
    final response = await _client
        .from('expert_tutor_progress')
        .select('*')
        .eq('student_id', studentId);

    final totalObjectives = response.length;
    final masteredObjectives = response.where((p) => p['is_mastered'] == true).length;
    final totalAttempts = response.fold<int>(0, (sum, p) => 
      sum + (p['attempts_easy'] as int? ?? 0) + 
      (p['attempts_medium'] as int? ?? 0) + 
      (p['attempts_hard'] as int? ?? 0) + 
      (p['attempts_exam'] as int? ?? 0)
    );

    return {
      'total_objectives': totalObjectives,
      'mastered_objectives': masteredObjectives,
      'mastery_percentage': totalObjectives > 0 ? (masteredObjectives / totalObjectives * 100) : 0,
      'total_attempts': totalAttempts,
    };
  }

  // Streaming
  Stream<String> sendMessageStream({
    required String sessionId,
    required String message,
    String? currentObjectiveId,
    String? studentId,
  }) async* {
    final client = http.Client();
    
    try {
      final session = await getSession(sessionId);
      if (session == null) throw Exception('Session not found');

      final request = http.StreamedRequest('POST', Uri.parse('${SupabaseConfig.url}/functions/v1/expert-tutor'));
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
        'studentId': studentId ?? session['student_id'],
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

  // Marker helpers
  bool hasObjectiveMastered(String text) => text.contains('[OBJECTIVE_MASTERED]');
  bool hasExerciseMarker(String text) {
    return RegExp(r'\[EXERCISE:(easy|medium|hard|exam)\]').hasMatch(text);
  }
  String? getExerciseDifficulty(String text) {
    final match = RegExp(r'\[EXERCISE:(easy|medium|hard|exam)\]').firstMatch(text);
    return match?.group(1);
  }
}