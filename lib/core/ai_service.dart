import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';

class AIService {
  static String get _functionUrl => '${SupabaseConfig.url}/functions/v1/ai-tutor';
  static String get _anonKey => SupabaseConfig.anonKey;

  Future<String> askAI({
    required String message,
    String subject = 'Physics',
    List<Map<String, dynamic>>? history,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_anonKey',
        },
        body: jsonEncode({
          'message': message,
          'subject': subject,
          'history': history, // ← Send conversation history
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['reply'] as String? ?? 'No response from AI.';
      } else if (response.statusCode == 429) {
        return 'Too many requests. Please wait a moment.';
      } else {
        debugPrint('Edge Function error: ${response.statusCode}');
        return 'AI tutor is unavailable. Please try again later.';
      }
    } catch (e) {
      debugPrint('Connection error: $e');
      return 'Connection error. Please check your internet.';
    }
  }
}