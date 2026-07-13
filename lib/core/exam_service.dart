import 'package:supabase_flutter/supabase_flutter.dart';

class ExamService {
  final SupabaseClient _client = Supabase.instance.client;

  // Create a new exam
  Future<String?> createExam({
    required String topicId,
    required String creatorId,
    required String title,
    required String description,
    int? durationMinutes,
    int totalMarks = 0,
    int passingPercentage = 50,
    String? subjectId,
  }) async {
    final response = await _client.from('exams').insert({
      'topic_id': topicId,
      'creator_id': creatorId,
      'title': title,
      'description': description,
      'duration_minutes': durationMinutes,
      'total_marks': totalMarks,
      'passing_percentage': passingPercentage,
      'subject_id': subjectId,
      'is_published': false,
    }).select('id').single();

    return response['id'] as String?;
  }

  // Add a question to an exam
  Future<void> addQuestion({
  required String examId,
  required String questionText,
  required String questionType,
  required List<String> options,
  required String correctAnswer,
  required int marks,
  String? explanation,
  String? diagramUrl,
  String? drawingData,     // ✅ Add
  String? graphData,       // ✅ Add
  int displayOrder = 0,
}) async {
  await _client.from('questions').insert({
    'exam_id': examId,
    'question_text': questionText,  // Just the text, no media
    'question_type': questionType,
    'options': options,
    'correct_answer': correctAnswer,
    'marks': marks,
    'explanation': explanation,
    'diagram_url': diagramUrl,
    'drawing_data': drawingData,    // ✅ Store separately
    'graph_data': graphData,        // ✅ Store separately
    'display_order': displayOrder,
  });
}

  // Get all exams created by a teacher
  Future<List<Map<String, dynamic>>> getTeacherExams(String teacherId) async {
  final response = await _client
      .from('exams')
      .select('*, teacher_topics(name, subjects(name))')
      .eq('creator_id', teacherId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
}

  // Get questions for an exam
  Future<List<Map<String, dynamic>>> getQuestions(String examId) async {
    final response = await _client
        .from('questions')
        .select()
        .eq('exam_id', examId)
        .order('display_order', ascending: true);  // ✅ Reverse the order

    return List<Map<String, dynamic>>.from(response);
  }

  // Publish an exam
  Future<void> publishExam(String examId) async {
    await _client
        .from('exams')
        .update({'is_published': true}).eq('id', examId);
  }

  // Delete a question
  Future<void> deleteQuestion(String questionId) async {
    await _client.from('questions').delete().eq('id', questionId);
  }

  // Update exam total marks
  Future<void> updateTotalMarks(String examId, int totalMarks) async {
    await _client
        .from('exams')
        .update({'total_marks': totalMarks}).eq('id', examId);
  }

  // Get all subjects and topics (for dropdowns)
  Future<List<Map<String, dynamic>>> getSubjectsWithTopics() async {
    final response = await _client
        .from('subject_offerings')
        .select('id, subjects(name), topics(id, name)')
        .eq('is_active', true);

    return List<Map<String, dynamic>>.from(response);
  }
  // Create a new exam linked to teacher_topic
Future<String?> createExamWithTeacherTopic({
  required String teacherTopicId,
  required String creatorId,
  required String title,
  required String description,
  int? durationMinutes,
  int totalMarks = 0,
  int passingPercentage = 50,
  String? subjectId,
  String? levelId,
}) async {
  final response = await _client.from('exams').insert({
    'teacher_topic_id': teacherTopicId,
    'creator_id': creatorId,
    'title': title,
    'description': description,
    'duration_minutes': durationMinutes,
    'total_marks': totalMarks,
    'passing_percentage': passingPercentage,
    'subject_id': subjectId,
    'level_id': levelId,
    'is_published': false,
  }).select('id').single();

  return response['id'] as String?;
}
}