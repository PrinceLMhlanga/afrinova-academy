import 'package:supabase_flutter/supabase_flutter.dart';

class ExamPaperService {
  final SupabaseClient _client = Supabase.instance.client;

  // Create a structured exam paper
  Future<String?> createPaper({
    required String creatorId,
    required String subjectId,
    required String title,
    required String instructions,
    required int totalMarks,
    required int durationMinutes,
    required String curriculum,
    required String paperType,
    required List<Map<String, dynamic>> questions,
  }) async {
    // Insert the paper
    final paperResponse = await _client.from('exam_papers').insert({
      'creator_id': creatorId,
      'subject_id': subjectId,
      'title': title,
      'instructions': instructions,
      'total_marks': totalMarks,
      'duration_minutes': durationMinutes,
      'curriculum': curriculum,
      'paper_type': paperType,
      'is_published': false,
    }).select('id').single();

    final paperId = paperResponse['id'] as String;

    // Insert all questions
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      await _client.from('exam_questions').insert({
        'paper_id': paperId,
        'question_number': i + 1,
        'question_text': q['text'],
        'question_parts': q['parts'] ?? [],
        'marks': q['marks'] ?? 0,
        'answer_format': q['format'] ?? 'structured',
        'sample_answer': q['answer'],
        'display_order': i + 1,
      });
    }

    return paperId;
  }

  // Get all papers by teacher
  Future<List<Map<String, dynamic>>> getTeacherPapers(String teacherId) async {
    final response = await _client
        .from('exam_papers')
        .select('*, subjects(name)')
        .eq('creator_id', teacherId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Get questions for a paper
  Future<List<Map<String, dynamic>>> getPaperQuestions(String paperId) async {
    final response = await _client
        .from('exam_questions')
        .select()
        .eq('paper_id', paperId)
        .order('display_order', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Publish a paper
  Future<void> publishPaper(String paperId) async {
    await _client.from('exam_papers').update({
      'is_published': true,
    }).eq('id', paperId);
  }

  // Unpublish a paper
  Future<void> unpublishPaper(String paperId) async {
    await _client.from('exam_papers').update({
      'is_published': false,
    }).eq('id', paperId);
  }

  // Delete a paper
  Future<void> deletePaper(String paperId) async {
    await _client.from('exam_papers').delete().eq('id', paperId);
  }

  // Get all published papers (for students)
  Future<List<Map<String, dynamic>>> getPublishedPapers() async {
    final response = await _client
        .from('exam_papers')
        .select('*, subjects(name), profiles!creator_id(full_name)')
        .eq('is_published', true)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }
}