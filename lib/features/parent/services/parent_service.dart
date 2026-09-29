import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../analytics/models/analytics_kpis.dart';
import '../../analytics/models/subject_progress.dart';
import '../../analytics/models/trend_point.dart';
import '../../analytics/services/analytics_service.dart';
import '../models/child_summary.dart';
import '../../analytics/models/subject_allocation.dart';

/// Service for parent-side operations.
///
/// Covers:
///   • saving parent profile details (address, phone, country)
///   • requesting a link to a student by email
///   • watching the parent's own links in realtime
///   • listing active links (for the dashboard)
///   • fetching a child's analytics (delegates to AnalyticsService)
class ParentService {
  ParentService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  final AnalyticsService _analytics = AnalyticsService();

  // ─────────────────────────────────────────────────────────────
  // Profile
  // ─────────────────────────────────────────────────────────────

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

  // ─────────────────────────────────────────────────────────────
  // Links
  // ─────────────────────────────────────────────────────────────

  Future<String?> requestLinkByEmail({
    required String email,
    required String relationship,
  }) async {
    final parentId = _client.auth.currentUser?.id;
    if (parentId == null) return 'Not signed in.';

    final trimmed = email.trim().toLowerCase();

    try {
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

      await _client.from('parent_student_links').insert({
        'parent_id': parentId,
        'student_id': studentId,
        'status': 'pending',
        'relationship': relationship,
        'initiated_by': 'parent',
      });

      return null;
    } catch (e) {
      debugPrint('[ParentService] requestLinkByEmail failed: $e');
      return 'Could not send request. Please try again.';
    }
  }

  /// Original shape. Returns raw maps so existing callers (the
  /// onboarding screen, etc.) keep working unchanged.
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
        is_subscribed,
        subscription_expires_at,
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

  /// Same as before — active only, raw maps.
  Future<List<Map<String, dynamic>>> getActiveLinks() async {
    final all = await getMyLinks();
    return all
        .where((l) => l['status'] == 'active')
        .toList(growable: false);
  }

  /// NEW convenience: active children as typed [ChildSummary] objects.
  /// Used by the dashboard for the child selector. Doesn't touch the
  /// original map-based methods above.
  Future<List<ChildSummary>> getActiveChildrenTyped() async {
    final all = await getMyLinks();
    return all
        .where((l) => l['status'] == 'active')
        .map((m) => ChildSummary.fromLinkJson(m))
        .toList(growable: false);
  }

  /// NEW convenience: all links as typed [ChildSummary] objects.
  /// Used by the Children tab.
  Future<List<ChildSummary>> getAllLinksTyped() async {
    final all = await getMyLinks();
    return all
        .map((m) => ChildSummary.fromLinkJson(m))
        .toList(growable: false);
  }

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

  /// Remove a link. Works for pending or active.
  Future<void> unlink(String linkId) async {
    try {
      await _client
          .from('parent_student_links')
          .delete()
          .eq('id', linkId);
    } catch (e) {
      debugPrint('[ParentService] unlink failed: $e');
    }
  }

  Future<List<SubjectAllocation>> getChildAllocation(
  String studentId, {
  int days = 30,
}) =>
    _analytics.getAllocation(studentId, days: days);

  // ─────────────────────────────────────────────────────────────
  // Analytics — delegate to AnalyticsService with the child's id
  // ─────────────────────────────────────────────────────────────

  Future<AnalyticsKpis> getChildKpis(String studentId) =>
      _analytics.getKpis(studentId);

  Future<List<TrendPoint>> getChildTrend(
    String studentId, {
    int days = 10,
  }) =>
      _analytics.getTrend(studentId, days: days);

  Future<List<SubjectProgress>> getChildSubjectProgress(
    String studentId,
  ) =>
      _analytics.getSubjectProgress(studentId);
}