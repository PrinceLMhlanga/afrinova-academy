import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AIAccessChecker {
  /// Check if user has access to ANY AI feature
  static Future<bool> canAccessAIFeatures() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('is_subscribed, subscription_expires_at, trial_started_at, trial_ends_at')
          .eq('id', userId)
          .single();

      final now = DateTime.now();

      // ✅ Check active subscription
      if (profile['is_subscribed'] == true) {
        final expiresAt = profile['subscription_expires_at'] as String?;
        if (expiresAt != null) {
          final expiry = DateTime.parse(expiresAt);
          if (expiry.isAfter(now)) return true; // Still subscribed
        }
      }

      // ✅ Check active trial
      final trialEndsAt = profile['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        if (trialEnd.isAfter(now)) return true; // Trial still active
      }

      // ❌ No access - subscription expired AND trial expired
      return false;
    } catch (e) {
      debugPrint('AI Access check error: $e');
      return false;
    }
  }

  /// Start trial if not already started
  static Future<void> startTrial() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Check if trial already exists
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('trial_started_at, trial_ends_at')
          .eq('id', userId)
          .single();

      // Don't restart if trial already started
      if (profile['trial_started_at'] != null) return;

      final now = DateTime.now();
      await Supabase.instance.client
          .from('profiles')
          .update({
            'trial_started_at': now.toIso8601String(),
            'trial_ends_at': now.add(const Duration(days: 3)).toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      debugPrint('Start trial error: $e');
    }
  }

  /// Get detailed status for UI display
  static Future<Map<String, dynamic>> getStatus() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return {'active': false, 'daysLeft': 0, 'type': 'none', 'message': 'Please log in'};
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('is_subscribed, subscription_expires_at, trial_started_at, trial_ends_at')
          .eq('id', userId)
          .single();

      final now = DateTime.now();

      // Subscription active
      if (profile['is_subscribed'] == true) {
        final expiresAt = profile['subscription_expires_at'] as String?;
        if (expiresAt != null) {
          final expiry = DateTime.parse(expiresAt);
          final daysLeft = expiry.difference(now).inDays;
          if (daysLeft > 0) {
            return {
              'active': true,
              'daysLeft': daysLeft,
              'type': 'subscribed',
              'message': 'Subscribed · $daysLeft days left',
            };
          } else {
            return {
              'active': false,
              'daysLeft': 0,
              'type': 'expired',
              'message': 'Subscription expired',
            };
          }
        }
      }

      // Trial active
      final trialEndsAt = profile['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        final daysLeft = trialEnd.difference(now).inDays;
        if (daysLeft > 0) {
          return {
            'active': true,
            'daysLeft': daysLeft,
            'type': 'trial',
            'message': 'Free trial · $daysLeft day${daysLeft == 1 ? '' : 's'} left',
          };
        } else {
          return {
            'active': false,
            'daysLeft': 0,
            'type': 'trial_expired',
            'message': 'Free trial ended',
          };
        }
      }

      // No trial started yet
      return {
        'active': false,
        'daysLeft': 0,
        'type': 'no_trial',
        'message': 'Start your free 3-day trial',
      };
    } catch (e) {
      return {'active': false, 'daysLeft': 0, 'type': 'error', 'message': 'Error checking status'};
    }
  }
}