import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class TrialService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get trial status for a specific enrollment
  Future<Map<String, dynamic>> getEnrollmentTrialStatus({
    required String studentId,
    required String teacherId,
    required String subjectId,
  }) async {
    try {
      final enrollment = await _client
          .from('enrollments')
          .select('id, status, trial_started_at, trial_ends_at, is_subscribed, subscription_expires_at')
          .eq('student_id', studentId)
          .eq('teacher_id', teacherId)
          .eq('subject_id', subjectId)
          .maybeSingle();

      if (enrollment == null) {
        return {'status': 'not_enrolled'};
      }

      // Check if paid
      if (enrollment['is_subscribed'] == true) {
        final expiresAt = enrollment['subscription_expires_at'] as String?;
        if (expiresAt != null) {
          final expiry = DateTime.parse(expiresAt);
          if (expiry.isAfter(DateTime.now())) {
            final daysLeft = expiry.difference(DateTime.now()).inDays;
            return {
              'status': 'subscribed',
              'days_left': daysLeft,
              'expires_at': expiresAt,
            };
          }
        }
        return {'status': 'subscription_expired'};
      }

      // Check trial
      final trialEndsAt = enrollment['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        if (DateTime.now().isBefore(trialEnd)) {
          final daysLeft = trialEnd.difference(DateTime.now()).inDays;
          return {
            'status': 'trial_active',
            'days_left': daysLeft,
            'trial_ends_at': trialEndsAt,
          };
        }
      }

      return {'status': 'trial_expired'};
    } catch (e) {
      debugPrint('Trial status error: $e');
      return {'status': 'error'};
    }
  }

  // Start trial for a new enrollment
  Future<void> startTrial(String enrollmentId) async {
    await _client.from('enrollments').update({
      'trial_started_at': DateTime.now().toIso8601String(),
      'trial_ends_at': DateTime.now().add(const Duration(days: 14)).toIso8601String(),
    }).eq('id', enrollmentId);
  }

  // Activate subscription after payment
  Future<void> activateSubscription(String enrollmentId, {int months = 1}) async {
    final expiry = DateTime.now().add(Duration(days: 30 * months));
    await _client.from('enrollments').update({
      'is_subscribed': true,
      'subscription_expires_at': expiry.toIso8601String(),
      'status': 'paid',
    }).eq('id', enrollmentId);
  }

  // Get all trial warnings for a student (banners to show)
  Future<List<Map<String, dynamic>>> getTrialWarnings(String studentId) async {
    try {
      final enrollments = await _client
          .from('enrollments')
          .select('id, subject_id, teacher_id, trial_ends_at, is_subscribed, subjects(name), profiles!teacher_id(full_name)')
          .eq('student_id', studentId)
          .inFilter('status', ['approved', 'paid'])
          .eq('is_subscribed', false);

      final warnings = <Map<String, dynamic>>[];

      for (final e in enrollments) {
        final trialEndsAt = e['trial_ends_at'] as String?;
        if (trialEndsAt != null) {
          final trialEnd = DateTime.parse(trialEndsAt);
          final daysLeft = trialEnd.difference(DateTime.now()).inDays;

          if (daysLeft <= 3 || daysLeft < 0) {
            warnings.add({
              'enrollment_id': e['id'],
              'teacher_id': e['teacher_id'],
              'teacher_name': e['profiles']?['full_name'] ?? 'Teacher',
              'subject_name': e['subjects']?['name'] ?? 'Subject',
              'days_left': daysLeft > 0 ? daysLeft : 0,
              'is_expired': daysLeft <= 0,
            });
          }
        }
      }

      return warnings;
    } catch (e) {
      return [];
    }
  }

  // Get subscription warnings (expiring soon or expired)
Future<List<Map<String, dynamic>>> getSubscriptionWarnings(String studentId) async {
    try {
      final enrollments = await _client
          .from('enrollments')
          .select('id, subject_id, teacher_id, subscription_expires_at, is_subscribed, subjects(name), profiles!teacher_id(full_name)')
          .eq('student_id', studentId)
          .eq('is_subscribed', true);

      final warnings = <Map<String, dynamic>>[];

      for (final e in enrollments) {
        final expiresAt = e['subscription_expires_at'] as String?;
        if (expiresAt != null) {
          final expiry = DateTime.parse(expiresAt);
          final daysLeft = expiry.difference(DateTime.now()).inDays;

          // Warn if expired or expiring within 5 days
          if (daysLeft <= 5) {
            warnings.add({
              'enrollment_id': e['id'],
              'teacher_id': e['teacher_id'],
              'teacher_name': e['profiles']?['full_name'] ?? 'Teacher',
              'subject_name': e['subjects']?['name'] ?? 'Subject',
              'days_left': daysLeft > 0 ? daysLeft : 0,
              'is_expired': daysLeft <= 0,
              'type': 'subscription', // ✅ Mark as subscription warning
            });
          }
        }
      }

      return warnings;
    } catch (e) {
      return [];
    }
  }
}