import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResourceService {
  final SupabaseClient _client = Supabase.instance.client;

  // Upload file bytes and save metadata in one go
  Future<Map<String, dynamic>?> uploadResource({
    required String filePath,
    required List<int> fileBytes,
    required String fileName,
    required int fileSizeBytes,
    required String fileType,
    required String title,
    required String resourceType,
    required String uploadedById,
    String? subjectId,
    String? topicId,
    String? description,
  }) async {
    try {
      // 1. Upload file to Supabase Storage
      final bytes = Uint8List.fromList(fileBytes);
      await _client.storage.from('resources').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: fileType == 'pdf'
                  ? 'application/pdf'
                  : 'application/octet-stream',
            ),
          );

      // 2. Get public URL
      final fileUrl =
          _client.storage.from('resources').getPublicUrl(filePath);

      // 3. Save metadata to database
      final response = await _client.from('resources').insert({
        'title': title,
        'file_url': fileUrl,
        'file_type': fileType,
        'file_size_bytes': fileSizeBytes,
        'resource_type': resourceType,
        'subject_id': subjectId,
        'topic_id': topicId,
        'uploaded_by': uploadedById,
        'lesson_id': null,
      }).select().single();

      return response;
    } catch (e) {
      debugPrint('Upload error: $e');
      rethrow;
    }
  }

  // Get all resources with filters
  Future<List<Map<String, dynamic>>> getResources({
    String? subjectId,
    String? topicId,
    String? resourceType,
    String? uploadedBy,
  }) async {
    try {
      // Build query step by step
      dynamic query = _client.from('resources').select(
          '*, subjects(name), topics(name), profiles!uploaded_by(full_name)');

      if (subjectId != null) {
        query = query.eq('subject_id', subjectId);
      }
      if (topicId != null) {
        query = query.eq('topic_id', topicId);
      }
      if (resourceType != null) {
        query = query.eq('resource_type', resourceType);
      }
      if (uploadedBy != null) {
        query = query.eq('uploaded_by', uploadedBy);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Get resources error: $e');
      return [];
    }
  }

  // Get resources uploaded by a specific teacher
  Future<List<Map<String, dynamic>>> getMyUploads(String teacherId) async {
    return getResources(uploadedBy: teacherId);
  }

  // Delete a resource
  Future<void> deleteResource(String resourceId, String fileUrl) async {
    try {
      // Extract file path from URL
      final uri = Uri.parse(fileUrl);
      final pathSegments = uri.pathSegments;
      final filePath = pathSegments
          .sublist(pathSegments.indexOf('resources') + 1)
          .join('/');

      // Delete from storage
      await _client.storage.from('resources').remove([filePath]);

      // Delete from database
      await _client.from('resources').delete().eq('id', resourceId);
    } catch (e) {
      debugPrint('Delete error: $e');
      rethrow;
    }
  }
}