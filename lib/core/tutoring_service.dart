import 'package:supabase_flutter/supabase_flutter.dart';

class TutoringService {
  final SupabaseClient _client = Supabase.instance.client;

  // Create or get existing session
  Future<String> getOrCreateSession({
    required String studentId,
    required String teacherId,
    String? subjectId,
  }) async {
    // Check for existing active session
    final existing = await _client
        .from('tutoring_sessions')
        .select('id')
        .eq('student_id', studentId)
        .eq('teacher_id', teacherId)
        .eq('status', 'active')
        .maybeSingle();

    if (existing != null) {
      return existing['id'] as String;
    }

    // Create new session
    final response = await _client
        .from('tutoring_sessions')
        .insert({
          'student_id': studentId,
          'teacher_id': teacherId,
          'subject_id': subjectId,
          'status': 'active',
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  // Send message
  Future<void> sendMessage({
    required String sessionId,
    required String senderId,
    required String content,
    String messageType = 'text',
    String? fileUrl,
    String? fileName,
    int? fileSize,
  }) async {
    await _client.from('tutoring_messages').insert({
      'session_id': sessionId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType,
      'file_url': fileUrl,
      'file_name': fileName,
      'file_size': fileSize,
    });
  }

  // Load messages
  Future<List<Map<String, dynamic>>> loadMessages(String sessionId) async {
    final response = await _client
        .from('tutoring_messages')
        .select('*, sender:profiles!sender_id(display_name, full_name)')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Save whiteboard stroke
  Future<void> saveStroke({
    required String sessionId,
    required String createdBy,
    required Map<String, dynamic> strokeData,
  }) async {
    await _client.from('tutoring_whiteboard').insert({
      'session_id': sessionId,
      'created_by': createdBy,
      'stroke_data': strokeData,
    });
  }

  // Load whiteboard strokes
  Future<List<Map<String, dynamic>>> loadStrokes(String sessionId) async {
    final response = await _client
        .from('tutoring_whiteboard')
        .select('*')
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Clear whiteboard
  Future<void> clearWhiteboard(String sessionId) async {
    await _client
        .from('tutoring_whiteboard')
        .delete()
        .eq('session_id', sessionId);
  }

  // End session
  Future<void> endSession(String sessionId, int totalMinutes) async {
    await _client
        .from('tutoring_sessions')
        .update({
          'status': 'completed',
          'ended_at': DateTime.now().toIso8601String(),
          'total_minutes': totalMinutes,
        })
        .eq('id', sessionId);
  }

  // Subscribe to new messages (real-time)
  Stream<List<Map<String, dynamic>>> subscribeToMessages(String sessionId) {
    return _client
        .from('tutoring_messages')
        .stream(primaryKey: ['id'])
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
  }

  // Share resource
  Future<void> shareResource({
    required String sessionId,
    required String title,
    required String fileUrl,
    required String fileType,
    required String uploadedBy,
  }) async {
    await _client.from('tutoring_resources').insert({
      'session_id': sessionId,
      'title': title,
      'file_url': fileUrl,
      'file_type': fileType,
      'uploaded_by': uploadedBy,
    });
  }

  // Load resources
  Future<List<Map<String, dynamic>>> loadResources(String sessionId) async {
    final response = await _client
        .from('tutoring_resources')
        .select('*')
        .eq('session_id', sessionId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}