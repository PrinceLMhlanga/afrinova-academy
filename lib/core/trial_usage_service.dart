import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class TrialUsageService {
  final SupabaseClient _client = Supabase.instance.client;

  // Check if user can use a feature
  Future<TrialCheckResult> canUseFeature(String featureKey) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return TrialCheckResult(allowed: false, reason: 'not_logged_in');
    }

    try {
      final response = await _client.rpc('can_use_ai_feature', params: {
        'p_user_id': userId,
        'p_feature_key': featureKey,
      });

      return TrialCheckResult.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error checking feature: $e');
      // Fail open on error so students aren't blocked by bugs
      return TrialCheckResult(allowed: true, reason: 'error_fallback');
    }
  }

  // Increment usage
  Future<void> incrementUsage(String featureKey, {int amount = 1}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.rpc('increment_trial_usage', params: {
        'p_user_id': userId,
        'p_feature_key': featureKey,
        'p_amount': amount,
      });
    } catch (e) {
      debugPrint('Error incrementing usage: $e');
    }
  }

  // Get all trial limits from DB
Future<Map<String, int>> getTrialLimits() async {
  try {
    final response = await _client
        .from('trial_limits')
        .select('feature_key, trial_limit')
        .eq('is_active', true);

    final limits = <String, int>{};
    for (final row in response) {
      limits[row['feature_key'] as String] = row['trial_limit'] as int;
    }
    return limits;
  } catch (e) {
    debugPrint('Error loading trial limits: $e');
    // Fallback to defaults if DB fails
    return {
      'exams_generated': 2,
      'flashcards_generated': 10,
      'summaries_generated': 2,
      'general_tutor_messages': 20,
      'expert_tutor_topics_started': 1,
      'expert_tutor_messages': 10,
    };
  }
}

  // Check if user can start a specific Expert Tutor topic
  Future<TrialCheckResult> canStartExpertTopic(String topicId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return TrialCheckResult(allowed: false, reason: 'not_logged_in');
    }

    try {
      final response = await _client.rpc('register_expert_topic', params: {
        'p_user_id': userId,
        'p_topic_id': topicId,
      });

      return TrialCheckResult.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error checking expert topic: $e');
      return TrialCheckResult(allowed: true, reason: 'error_fallback');
    }
  }

  // Get current usage summary
  Future<Map<String, dynamic>?> getUsageSummary() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    try {
      final response = await _client
          .from('trial_usage')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return response;
    } catch (e) {
      debugPrint('Error getting usage: $e');
      return null;
    }
  }
}

// Result class
class TrialCheckResult {
  final bool allowed;
  final String reason;
  final String? message;
  final String? featureName;
  final int? used;
  final int? limit;
  final int? remaining;
  final bool unlimited;

  TrialCheckResult({
    required this.allowed,
    required this.reason,
    this.message,
    this.featureName,
    this.used,
    this.limit,
    this.remaining,
    this.unlimited = false,
  });

  factory TrialCheckResult.fromJson(Map<String, dynamic> json) {
  final used = json['used'] as int?;
  final limit = json['limit'] as int?;
  final unlimited = json['unlimited'] as bool? ?? false;
  
  // ✅ Calculate remaining from used and limit if not provided
  int? remaining = json['remaining'] as int?;
  if (remaining == null && used != null && limit != null && !unlimited) {
    remaining = (limit - used).clamp(0, limit);
  }
  
  return TrialCheckResult(
    allowed: json['allowed'] as bool? ?? false,
    reason: json['reason'] as String? ?? 'unknown',
    message: json['message'] as String?,
    featureName: json['feature_name'] as String?,
    used: used,
    limit: limit,
    remaining: remaining,
    unlimited: unlimited,
  );
}
}

class TrialLimitsCache {
  static Map<String, int>? _cached;
  static DateTime? _cachedAt;
  
  static Future<Map<String, int>> load() async {
    // Cache for 5 minutes
    if (_cached != null && _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < const Duration(minutes: 5)) {
      return _cached!;
    }
    
    _cached = await TrialUsageService().getTrialLimits();
    _cachedAt = DateTime.now();
    return _cached!;
  }
  
  static void invalidate() {
    _cached = null;
    _cachedAt = null;
  }
  
  // Convenience getters (fall back to safe defaults)
  static int flashcards() => _cached?['flashcards_generated'] ?? 10;
  static int exams() => _cached?['exams_generated'] ?? 2;
  static int summaries() => _cached?['summaries_generated'] ?? 2;
  static int tutorMessages() => _cached?['general_tutor_messages'] ?? 20;
  static int expertTopics() => _cached?['expert_tutor_topics_started'] ?? 1;
  static int expertMessages() => _cached?['expert_tutor_messages'] ?? 10;
}