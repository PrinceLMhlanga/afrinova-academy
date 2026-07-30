import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
class ChatService {
  final SupabaseClient _client = Supabase.instance.client;

  // Create a new chat session — starts untitled
  Future<String?> createSession({
  required String studentId,
  String? subject, // ✅ Nullable, no default
}) async {
  final response = await _client.from('chat_sessions').insert({
    'student_id': studentId,
    'subject': subject, // Will be null if not provided
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

  Future<void> autoNameSession(String sessionId, String firstMessage) async {
  final title = firstMessage.length > 40
      ? '${firstMessage.substring(0, 40)}...'
      : firstMessage;

  await _client.from('chat_sessions').update({
    'title': title,
    'updated_at': DateTime.now().toUtc().toIso8601String(), // ✅ UTC
  }).eq('id', sessionId);
}

Future<void> updateSessionTimestamp(String sessionId) async {
  await _client.from('chat_sessions').update({
    'updated_at': DateTime.now().toUtc().toIso8601String(), // ✅ UTC
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

  Future<List<Map<String, dynamic>>> getSessions(String studentId, {String? currentSessionId}) async {
  try {
    // ✅ Step 1: Find session IDs that have messages
    final activeSessionIds = await _client
        .from('chat_messages')
        .select('session_id');
    
    final activeIds = activeSessionIds
        .map((m) => m['session_id'] as String)
        .toSet()
        .toList();

    // ✅ Step 2: Add current session to protected list (never delete it)
    if (currentSessionId != null && !activeIds.contains(currentSessionId)) {
      activeIds.add(currentSessionId);
    }

    // ✅ Step 3: Delete sessions without messages (EXCEPT current session)
    if (activeIds.isNotEmpty) {
      await _client
          .from('chat_sessions')
          .delete()
          .eq('student_id', studentId)
          .not('id', 'in', activeIds);
    } else {
      await _client
          .from('chat_sessions')
          .delete()
          .eq('student_id', studentId);
      return [];
    }

    // ✅ Step 4: Load only sessions that have messages
    final response = await _client
        .from('chat_sessions')
        .select()
        .eq('student_id', studentId)
        .inFilter('id', activeIds)
        .order('updated_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  } catch (e) {
    debugPrint('Get sessions error: $e');
    return [];
  }
}
  

  // Delete a session
  Future<void> deleteSession(String sessionId) async {
    await _client.from('chat_sessions').delete().eq('id', sessionId);
  }

  
  

  // Delete empty session - call this when leaving chat
Future<void> deleteIfEmpty(String sessionId) async {
  final messages = await _client
      .from('chat_messages')
      .select('id')
      .eq('session_id', sessionId)
      .limit(1);

  if (messages.isEmpty) {
    await _client.from('chat_sessions').delete().eq('id', sessionId);
  }
}
}