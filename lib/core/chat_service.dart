import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _client = Supabase.instance.client;

  // Create a new chat session — starts untitled
  Future<String?> createSession({
    required String studentId,
    String subject = 'General',
  }) async {
    final response = await _client.from('chat_sessions').insert({
      'student_id': studentId,
      'subject': subject,
      'title': 'New Chat',
    }).select('id').single();

    return response['id'] as String?;
  }

  // Save a message
  Future<void> saveMessage({
    required String sessionId,
    required String sender,
    required String message,
  }) async {
    await _client.from('chat_messages').insert({
      'session_id': sessionId,
      'sender': sender,
      'message': message,
    });
  }

  // Auto-name the chat based on first student message (like ChatGPT)
  Future<void> autoNameSession(String sessionId, String firstMessage) async {
    // Take first 40 characters of the first message as the title
    final title = firstMessage.length > 40
        ? '${firstMessage.substring(0, 40)}...'
        : firstMessage;

    await _client.from('chat_sessions').update({
      'title': title,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  // Get chat history for a session
  Future<List<Map<String, dynamic>>> getMessages(String sessionId) async {
    final response = await _client
        .from('chat_messages')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true); // newest first for loading

    return List<Map<String, dynamic>>.from(response);
  }

  // Get all sessions for a student (only ones with messages)
  Future<List<Map<String, dynamic>>> getSessions(String studentId) async {
    final response = await _client
        .from('chat_sessions')
        .select()
        .eq('student_id', studentId)
        .order('updated_at', ascending: false);

    // Filter out empty sessions
    final sessions = List<Map<String, dynamic>>.from(response);
    final nonEmpty = <Map<String, dynamic>>[];

    for (final session in sessions) {
      final count = await _client
          .from('chat_messages')
          .select('id')
          .eq('session_id', session['id'])
          .limit(1);

      if (count.isNotEmpty) {
        nonEmpty.add(session);
      }
    }

    return nonEmpty;
  }

  // Update session timestamp
  Future<void> updateSessionTimestamp(String sessionId) async {
    await _client.from('chat_sessions').update({
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', sessionId);
  }

  // Delete a session
  Future<void> deleteSession(String sessionId) async {
    await _client.from('chat_sessions').delete().eq('id', sessionId);
  }

  // Delete empty session
  Future<void> deleteIfEmpty(String sessionId) async {
    final messages = await getMessages(sessionId);
    if (messages.isEmpty) {
      await deleteSession(sessionId);
    }
  }
}