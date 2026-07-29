import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'supabase_config.dart';
import 'dart:async';

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
          'action': 'chat', // Added action identifier to stay uniform
          'message': message,
          'subject': subject,
          'history': history, 
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

  // ✅ Stream implementation optimized for chunk processing
  Stream<String> chatStream({ 
  required String message,
  String subject = 'Physics',
  List<Map<String, dynamic>>? history,
}) async* {
  final client = http.Client();
  try {
    // 1. Explicitly use a StreamedRequest for event-streams
    final request = http.StreamedRequest('POST', Uri.parse(_functionUrl));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_anonKey',
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
    });

    final payload = jsonEncode({
      'action': 'chat_stream',
      'message': message,
      'subject': subject,
      'history': history,
    });
    
    request.sink.add(utf8.encode(payload));
    request.sink.close();

    final response = await client.send(request);
    
    if (response.statusCode != 200) {
      yield 'Error: Failed to connect to AI server (${response.statusCode})';
      return;
    }

    // 2. Read the raw text strings without crashing on jsonDecode
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
      
      // ✅ CRITICAL FILTER: Skip lines containing metadata blocks
      if (parsed is Map && parsed.containsKey('meta')) {
        debugPrint('Connected to fallback model target node: ${parsed['meta']['model']}');
        continue; // Do not yield this line to the chat UI!
      }

      if (parsed is Map && parsed.containsKey('text')) {
        final text = parsed['text'] as String;
        if (text.isNotEmpty) {
          yield text; // Only stream actual conversation words to the UI
        }
      }
    } catch (_) {
      // If it's a raw string fragment that isn't JSON, verify it's safe and yield it
      if (rawData.isNotEmpty && !rawData.startsWith('{')) {
        yield rawData;
      }
    }
  }
}

  } catch (e) {
    debugPrint('Stream runtime error: $e');
    yield 'Connection error. Lost connection to tutor stream.';
  } finally {
    client.close();
  }
}

}

// ✅ Stream wrapper optimized to push incremental updates to UI
