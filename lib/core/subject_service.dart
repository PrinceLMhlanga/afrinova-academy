import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class SubjectService {
  final SupabaseClient _client = Supabase.instance.client;

  // Fetch all active subjects
  Future<List<Map<String, dynamic>>> getSubjects() async {
    final response = await _client
        .from('subjects')
        .select()
        .eq('is_active', true)
        .order('display_order', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch curriculums
  Future<List<Map<String, dynamic>>> getCurriculums() async {
    final response = await _client.from('curriculums').select();
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch levels
  Future<List<Map<String, dynamic>>> getLevels() async {
    final response = await _client.from('levels').select().order('display_order', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch subject offerings (subject + curriculum + level combinations)
  Future<List<Map<String, dynamic>>> getSubjectOfferings() async {
    final response = await _client
        .from('subject_offerings')
        .select('id, is_active, subjects(name, description, icon_name, color_hex), curriculums(name), levels(name)')
        .eq('is_active', true);

    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch topics for a specific subject offering
  Future<List<Map<String, dynamic>>> getTopics(String subjectOfferingId) async {
    final response = await _client
        .from('topics')
        .select()
        .eq('subject_offering_id', subjectOfferingId)
        .order('display_order', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

    // Fetch lessons for a specific topic
  Future<List<Map<String, dynamic>>> getLessons(String topicId) async {
    final response = await _client
        .from('lessons')
        .select('*, profiles(full_name)')
        .eq('topic_id', topicId)
        .eq('is_published', true)
        .order('created_at');

    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch resources for a lesson
  Future<List<Map<String, dynamic>>> getResources(String lessonId) async {
    final response = await _client
        .from('resources')
        .select()
        .eq('lesson_id', lessonId);

    return List<Map<String, dynamic>>.from(response);
  }

  // Update lesson progress
  Future<void> updateProgress({
    required String lessonId,
    required String studentId,
    required int watchedPercentage,
    required int lastPositionSeconds,
    bool completed = false,
  }) async {
    await _client.from('lesson_progress').upsert({
      'student_id': studentId,
      'lesson_id': lessonId,
      'watched_percentage': watchedPercentage,
      'last_position_seconds': lastPositionSeconds,
      'completed': completed,
      'completed_at': completed ? DateTime.now().toIso8601String() : null,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // Get lesson progress for a student
  Future<Map<String, dynamic>?> getLessonProgress({
    required String lessonId,
    required String studentId,
  }) async {
    final response = await _client
        .from('lesson_progress')
        .select()
        .eq('lesson_id', lessonId)
        .eq('student_id', studentId)
        .maybeSingle();

    return response;
  }

    // Upload a new lesson (teacher)
  Future<Map<String, dynamic>?> createLesson({
    required String topicId,
    required String teacherId,
    required String title,
    required String description,
    required String videoUrl,
    int? durationMinutes,
    bool isPremium = false,
  }) async {
    final response = await _client.from('lessons').insert({
      'topic_id': topicId,
      'teacher_id': teacherId,
      'title': title,
      'description': description,
      'video_url': videoUrl,
      'duration_minutes': durationMinutes,
      'is_premium': isPremium,
      'is_published': true,
    }).select().single();

    return response;
  }

  // Get lessons uploaded by a specific teacher
  Future<List<Map<String, dynamic>>> getTeacherLessons(String teacherId) async {
  final response = await _client
      .from('lessons')
      .select('*, teacher_topics(name, subjects(name))')
      .eq('teacher_id', teacherId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
}

  // Update a lesson
  Future<void> updateLesson({
    required String lessonId,
    String? title,
    String? description,
    String? videoUrl,
    int? durationMinutes,
    bool? isPublished,
  }) async {
    final updates = <String, dynamic>{};
    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (videoUrl != null) updates['video_url'] = videoUrl;
    if (durationMinutes != null) updates['duration_minutes'] = durationMinutes;
    if (isPublished != null) updates['is_published'] = isPublished;
    updates['updated_at'] = DateTime.now().toIso8601String();

    await _client.from('lessons').update(updates).eq('id', lessonId);
  }

  // Delete a lesson
  Future<void> deleteLesson(String lessonId) async {
    await _client.from('lessons').delete().eq('id', lessonId);
  }

    // Upload video file to Supabase Storage and create lesson
  Future<Map<String, dynamic>?> createLessonWithVideoFile({
    required String topicId,
    required String teacherId,
    required String title,
    required String description,
    required List<int> videoBytes,
    required String fileName,
    int? durationMinutes,
    bool isPremium = false,
  }) async {
    try {
      // 1. Upload video to storage
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Sanitize file name — remove special characters Supabase doesn't allow
final sanitizedFileName = fileName
    .replaceAll(RegExp(r'[\[\]\(\)\{\}\#\?\&\%\~\|\^\<\>\:\;]'), '_')
    .replaceAll(RegExp(r'\s+'), '_');
final filePath = 'lessons/$teacherId/$timestamp-$sanitizedFileName';
      
      final bytes = Uint8List.fromList(videoBytes);
      await _client.storage.from('videos').uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'video/mp4',
              upsert: false,
            ),
          );

      // 2. Get public URL
      final videoUrl = _client.storage.from('videos').getPublicUrl(filePath);

      // 3. Create lesson record with the video URL
      final response = await _client.from('lessons').insert({
        'topic_id': topicId,
        'teacher_id': teacherId,
        'title': title,
        'description': description,
        'video_url': videoUrl,
        'duration_minutes': durationMinutes,
        'is_premium': isPremium,
        'is_published': true,
      }).select().single();

      return response;
    } catch (e) {
      debugPrint('Video upload error: $e');
      rethrow;
    }
  }

  // Upload a new lesson linked to teacher_topic
Future<Map<String, dynamic>?> createLessonWithTeacherTopic({
  required String teacherTopicId,
  required String teacherId,
  required String title,
  required String description,
  required String videoUrl,
  int? durationMinutes,
  bool isPremium = false,
}) async {
  final response = await _client.from('lessons').insert({
    'teacher_topic_id': teacherTopicId,
    'teacher_id': teacherId,
    'title': title,
    'description': description,
    'video_url': videoUrl,
    'duration_minutes': durationMinutes,
    'is_premium': isPremium,
    'is_published': true,
  }).select().single();

  return response;
}

// Upload video file lesson linked to teacher_topic
Future<Map<String, dynamic>?> createLessonWithVideoFileTeacherTopic({
  required String teacherTopicId,
  required String teacherId,
  required String title,
  required String description,
  required List<int> videoBytes,
  required String fileName,
  int? durationMinutes,
  bool isPremium = false,
}) async {
  try {
    final sanitizedFileName = fileName
        .replaceAll(RegExp(r'[\[\]\(\)\{\}\#\?\&\%\~\|\^\<\>\:\;]'), '_')
        .replaceAll(RegExp(r'\s+'), '_');
    
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = 'lessons/$teacherId/$timestamp-$sanitizedFileName';
    
    final bytes = Uint8List.fromList(videoBytes);
    await _client.storage.from('videos').uploadBinary(
          filePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'video/mp4',
            upsert: false,
          ),
        );

    final videoUrl = _client.storage.from('videos').getPublicUrl(filePath);

    final response = await _client.from('lessons').insert({
      'teacher_topic_id': teacherTopicId,
      'teacher_id': teacherId,
      'title': title,
      'description': description,
      'video_url': videoUrl,
      'duration_minutes': durationMinutes,
      'is_premium': isPremium,
      'is_published': true,
    }).select().single();

    return response;
  } catch (e) {
    debugPrint('Video upload error: $e');
    rethrow;
  }
}

// Get lessons for a teacher topic
Future<List<Map<String, dynamic>>> getLessonsByTeacherTopic(String teacherTopicId) async {
  final response = await _client
      .from('lessons')
      .select('*, profiles(full_name)')
      .eq('teacher_topic_id', teacherTopicId)
      .eq('is_published', true)
      .order('created_at');

  return List<Map<String, dynamic>>.from(response);
}

// Get all lessons by a teacher (using new teacher_topic_id)
Future<List<Map<String, dynamic>>> getTeacherLessonsV2(String teacherId) async {
  final response = await _client
      .from('lessons')
      .select('*, teacher_topics(name, subjects(name))')
      .eq('teacher_id', teacherId)
      .order('created_at', ascending: false);

  return List<Map<String, dynamic>>.from(response);
}
}