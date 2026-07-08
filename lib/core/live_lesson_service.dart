//import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'jitsi_meeting_wrapper.dart';
import 'package:flutter/material.dart';

class LiveLessonService {
  final SupabaseClient _client = Supabase.instance.client;
  final _uuid = const Uuid();
  

  // Join a lesson directly in-app
  // Inside LiveLessonService class
Future<void> joinLesson({
  required BuildContext context,
  required String roomName,
  required String userName,
  required String lessonId,
  bool isTeacher = false,
}) async {
  await updateStatus(lessonId, 'live');  // ✅ Use this.updateStatus()

  await JitsiMeetingWrapper.join(
    context: context,
    roomName: roomName,
    userName: userName,
    lessonId: lessonId,
    isTeacher: isTeacher,
  );
}


  // Modified createLiveLesson to ensure unique but readable room names
 Future<Map<String, dynamic>> createLiveLesson({
  required String teacherId,
  required String subjectId,
  required String topic,
  required String description,
  String? meetUrl,
  DateTime? scheduledAt,  // ← Add this
  String? levelId,
  String? teacherTopicId,
}) async {
  final roomId = "AfriNova-${_uuid.v4().substring(0, 8)}";
  final finalUrl = meetUrl ?? 'https://meet.ffmuc.net/$roomId';

  final response = await _client.from('live_lessons').insert({
    'teacher_id': teacherId,
    'subject_id': subjectId,
    'level_id': levelId,
    'teacher_topic_id': teacherTopicId,
    'topic': topic,
    'description': description,
    'room_id': roomId,
    'meet_url': finalUrl,
    'status': 'scheduled',
    'scheduled_at': scheduledAt?.toIso8601String(),
    'scheduled_time': scheduledAt?.toIso8601String(),
  }).select().single();

  return response;
}

  // Get upcoming/active live lessons for a teacher
  Future<List<Map<String, dynamic>>> getTeacherLiveLessons(String teacherId) async {
    final response = await _client
        .from('live_lessons')
        .select('*, subjects(name)')
        .eq('teacher_id', teacherId)
        .inFilter('status', ['scheduled', 'live'])
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  // Get live lessons for a student (from enrolled teachers)
  Future<List<Map<String, dynamic>>> getStudentLiveLessons(String studentId) async {
    // Get teachers the student is enrolled with
    final enrollments = await _client
        .from('enrollments')
        .select('teacher_id')
        .eq('student_id', studentId)
        .inFilter('status', ['paid', 'approved']);

    final teacherIds = enrollments.map((e) => e['teacher_id'] as String).toList();

    if (teacherIds.isEmpty) return [];

    final response = await _client
        .from('live_lessons')
        .select('*, subjects(name), profiles!teacher_id(full_name)')
        .inFilter('teacher_id', teacherIds)
        .inFilter('status', ['scheduled', 'live'])
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updateStatus(String lessonId, String status) async {
    await _client.from('live_lessons').update({
      'status': status,
      if (status == 'live') 'started_at': DateTime.now().toIso8601String(),
      if (status == 'ended') 'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', lessonId);
  }

  // (Your existing getTeacherLiveLessons and getStudentLiveLessons remain same)
}
