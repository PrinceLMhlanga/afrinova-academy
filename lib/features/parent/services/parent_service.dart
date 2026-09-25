import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for parent-side operations.
///
/// Covers:
///   • saving parent profile details (address, phone, country)
///   • requesting a link to a student by email
///   • watching the parent's own links in realtime
///   • listing active links (for the dashboard, later)
class ParentService {
  ParentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Save parent onboarding details and mark onboarding complete.
  ///
  /// Pass null for any field to leave it unchanged. `onboardingCompleted`
  /// defaults to true because this is called at the end of Phase 1.
  Future<void> saveParentDetails({
    required String parentId,
    String? phoneNumber,
    String? country,
    String? address,
    bool onboardingCompleted = true,
  }) async {
    final updates = <String, dynamic>{
      'onboarding_completed': onboardingCompleted,
    };
    if (phoneNumber != null) updates['phone_number'] = phoneNumber;
    if (country != null) updates['country'] = country;
    if (address != null) updates['address'] = address;

    await _client
        .from('profiles')
        .update(updates)
        .eq('id', parentId);
  }

  /// Request a link to a student by email.
  ///
  /// Returns null on success, or a user-facing error string.
  ///
  /// The student is looked up by email. If found and role is student,
  /// a pending link row is created. If not found, we return an error
  /// string — the caller can choose to show it or ignore it.
  Future<String?> requestLinkByEmail({
    required String email,
    required String relationship,
  }) async {
    final parentId = _client.auth.currentUser?.id;
    if (parentId == null) return 'Not signed in.';

    final trimmed = email.trim().toLowerCase();

    try {
      // 1. Find the student by email
      final student = await _client
          .from('profiles')
          .select('id, role, full_name')
          .eq('email', trimmed)
          .maybeSingle();

      if (student == null) {
        return 'No student found with that email.';
      }
      if (student['role'] != 'student') {
        return 'That account is not a student account.';
      }

      final studentId = student['id'] as String;

      // 2. Check for an existing link (any status)
      final existing = await _client
          .from('parent_student_links')
          .select('id, status')
          .eq('parent_id', parentId)
          .eq('student_id', studentId)
          .maybeSingle();

      if (existing != null) {
        final status = existing['status'] as String?;
        switch (status) {
          case 'active':
            return 'You are already linked to that student.';
          case 'pending':
            return 'A request to that student is already pending.';
          case 'denied':
            return 'That student previously declined. Contact support to retry.';
          default:
            return 'A link already exists.';
        }
      }

      // 3. Create a pending request
      await _client.from('parent_student_links').insert({
        'parent_id': parentId,
        'student_id': studentId,
        'status': 'pending',
        'relationship': relationship,
        'initiated_by': 'parent',
      });

      return null; // success
    } catch (e) {
      debugPrint('[ParentService] requestLinkByEmail failed: $e');
      return 'Could not send request. Please try again.';
    }
  }

  /// Fetch the parent's own links with student info attached.
  ///
  /// Returns rows shaped like:
  ///   {
  ///     id, status, relationship, linked_at, requested_at, responded_at,
  ///     student: { id, full_name, display_name, avatar_url,
  ///                levels: { name } }
  ///   }
  Future<List<Map<String, dynamic>>> getMyLinks() async {
    final parentId = _client.auth.currentUser?.id;
    if (parentId == null) return const [];

    try {
      final res = await _client
          .from('parent_student_links')
          .select('''
            id,
            status,
            relationship,
            linked_at,
            requested_at,
            responded_at,
            student:student_id (
              id,
              full_name,
              display_name,
              avatar_url,
              levels ( name )
            )
          ''')
          .eq('parent_id', parentId)
          .order('requested_at', ascending: false);

      return (res as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[ParentService] getMyLinks failed: $e');
      return const [];
    }
  }

  /// Live stream of the parent's own links. Emits the full list any
  /// time a row is inserted, updated, or deleted.
  Stream<List<Map<String, dynamic>>> watchMyLinks() {
    final parentId = _client.auth.currentUser?.id;
    if (parentId == null) return Stream.value(const []);

    return _client
        .from('parent_student_links')
        .stream(primaryKey: ['id'])
        .eq('parent_id', parentId)
        .order('requested_at', ascending: false)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Active-linked students only. Used by the parent dashboard.
  Future<List<Map<String, dynamic>>> getActiveLinks() async {
    final all = await getMyLinks();
    return all.where((l) => l['status'] == 'active').toList(growable: false);
  }
}