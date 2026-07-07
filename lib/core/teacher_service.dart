import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get all available subjects in the system
  // Get all available subjects in the system
Future<List<Map<String, dynamic>>> getAllSubjects() async {
  final response = await _client
      .from('subjects')
      .select()
      .eq('is_active', true)
      .order('display_order', ascending: true); // ✅ Already correct

  return List<Map<String, dynamic>>.from(response);
}

  // Get subjects a teacher is assigned to
  Future<List<Map<String, dynamic>>> getMySubjects(String teacherId) async {
    final response = await _client
        .from('teacher_subjects')
        .select('*, subjects(*)')
        .eq('teacher_id', teacherId);

    return List<Map<String, dynamic>>.from(response);
  }

  // Add a subject to teacher's profile
  Future<void> addSubject(String teacherId, String subjectId) async {
    await _client.from('teacher_subjects').upsert({
      'teacher_id': teacherId,
      'subject_id': subjectId,
      'is_active': true,
    });
  }

  // Remove a subject from teacher's profile
  Future<void> removeSubject(String teacherId, String subjectId) async {
    await _client
        .from('teacher_subjects')
        .delete()
        .eq('teacher_id', teacherId)
        .eq('subject_id', subjectId);
  }

  Future<List<Map<String, dynamic>>> getMyTopics(
  String teacherId, 
  String subjectId, {
  String? levelId,
}) async {
  // ✅ Build query with all filters before select
  final filters = {
    'teacher_id': teacherId,
    'subject_id': subjectId,
  };
  
  if (levelId != null) {
    filters['level_id'] = levelId;
  }
  
  final response = await _client
      .from('teacher_topics')
      .select()
      .match(filters)
      .order('display_order', ascending: true);
  
  return List<Map<String, dynamic>>.from(response);
}

Future<void> addTopic({
  required String teacherId,
  required String subjectId,
  required String name,
  String? description,
  int? displayOrder,
  String? levelId,
}) async {
  final data = {
    'teacher_id': teacherId,
    'subject_id': subjectId,
    'name': name,
    'description': description,
    'display_order': displayOrder ?? 0,
  };
  
  if (levelId != null) {
    data['level_id'] = levelId;
  }
  
  await _client.from('teacher_topics').insert(data);
}
  // Update a topic
  Future<void> updateTopic({
    required String topicId,
    String? name,
    String? description,
    int? displayOrder,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;
    if (displayOrder != null) updates['display_order'] = displayOrder;

    await _client.from('teacher_topics').update(updates).eq('id', topicId);
  }
  Future<void> updateTopicOrder({
  required String topicId,
  required int displayOrder,
}) async {
  await _client
      .from('teacher_topics')
      .update({'display_order': displayOrder})
      .eq('id', topicId);
}

  // Delete a topic
  Future<void> deleteTopic(String topicId) async {
    await _client.from('teacher_topics').delete().eq('id', topicId);
  }
}