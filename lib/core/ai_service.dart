import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';
import 'dart:async';
import 'dart:convert';

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

  Future<Map<String, dynamic>> analyzeExam(List<Map<String, dynamic>> failedQuestions) async {
  try {
    final response = await http.post(
      Uri.parse(_functionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_anonKey',
      },
      body: jsonEncode({
        'action': 'analyze_exam',
        'failedQuestions': failedQuestions,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'feedback': data['feedback'] as String? ?? '',
        'perQuestion': List<String>.from(data['perQuestion'] ?? []),
      };
    }
    return {'feedback': '', 'perQuestion': <String>[]};
  } catch (e) {
    debugPrint('Analysis error: $e');
    return {'feedback': '', 'perQuestion': <String>[]};
  }
}

Future<List<Map<String, String>>> generateFlashcards({
  required String topic,
  required String subject,
  required String level,
  int count = 10,
}) async {
  try {
    final response = await http.post(
      Uri.parse(_functionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_anonKey',
      },
      body: jsonEncode({
        'action': 'generate_flashcards',
        'topic': topic,
        'subject': subject,
        'level': level,
        'count': count,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final cards = data['cards'] as List;
      return cards.map((c) => {
        'question': c['question'] as String,
        'answer': c['answer'] as String,
      }).toList();
    }
    return [];
  } catch (e) {
    debugPrint('Flashcard error: $e');
    return [];
  }
}

Future<String> generateSummary({
  required String topic,
  required String subject,
  required String level,
  String? syllabusOutline,
}) async {
  try {
    final response = await http.post(
      Uri.parse(_functionUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_anonKey',
      },
      body: jsonEncode({
        'action': 'generate_summary',
        'topic': topic,
        'subject': subject,
        'level': level,
        'syllabusOutline': syllabusOutline ?? '',
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['summary'] as String? ?? '';
    }
    return '';
  } catch (e) {
    debugPrint('Summary error: $e');
    return '';
  }
}



Stream<String> chatStream({  // ✅ Remove Future<>
  required String message,
  String subject = 'Physics',
  List<Map<String, dynamic>>? history,
}) async* {
  try {
    final request = http.Request('POST', Uri.parse(_functionUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_anonKey',
    });
    request.body = jsonEncode({
      'action': 'chat_stream',
      'message': message,
      'subject': subject,
      'history': history,
    });

    final response = await http.Client().send(request);
    
    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6);
        if (data == '[DONE]') break;
        try {
          final parsed = jsonDecode(data);
          yield parsed['text'] as String;
        } catch (_) {}
      }
    }
  } catch (e) {
    debugPrint('Stream error: $e');
  }
}
}