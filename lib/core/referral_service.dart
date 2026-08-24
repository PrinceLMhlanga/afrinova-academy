import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'package:share_plus/share_plus.dart';
import 'referral_tracker.dart';

class ReferralService {
  final SupabaseClient _client = Supabase.instance.client;

  // Generate referral code for user
  Future<String> generateReferralCode(String userId, {String? campaignName}) async {
    try {
      final response = await _client.rpc('generate_referral_code', params: {
        'p_owner_id': userId,
        'p_campaign_name': campaignName,
      });
      
      return response as String;
    } catch (e) {
      print('Error generating referral code: $e');
      throw e;
    }
  }

  // Get user's referral codes
  Future<List<Map<String, dynamic>>> getUserReferralCodes(String userId) async {
    try {
      final response = await _client
          .from('referral_codes')
          .select()
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting referral codes: $e');
      return [];
    }
  }

  // Get referral stats
  Future<Map<String, dynamic>?> getReferralStats(String userId) async {
    try {
      final response = await _client
          .from('user_referral_stats')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      
      return response;
    } catch (e) {
      print('Error getting referral stats: $e');
      return null;
    }
  }

  // Track referral automatically after signup
  Future<bool> trackReferralAutomatically(String referredUserId) async {
    try {
      final referralCode = ReferralTracker.getReferralCode();
      
      if (referralCode == null || referralCode.isEmpty) {
        print('No referral code found');
        return false;
      }
      
      // Check if referral is still valid
      if (!ReferralTracker.isReferralValid()) {
        print('Referral code expired');
        await ReferralTracker.clearReferralCode();
        return false;
      }
      
      // Track the referral
      await _client.rpc('track_referral', params: {
        'p_referral_code': referralCode,
        'p_referred_user_id': referredUserId,
        'p_source': 'referral_link',
        'p_ip_address': _getIpAddress(),
        'p_user_agent': _getUserAgent(),
      });
      
      print('✅ Referral tracked successfully');
      
      // Clear the code after successful tracking
      await ReferralTracker.clearReferralCode();
      
      return true;
    } catch (e) {
      print('❌ Error tracking referral: $e');
      // Don't clear the code on error - might be temporary
      return false;
    }
  }

  // Track referral manually (if needed)
  Future<void> trackReferral({
    required String referralCode,
    required String referredUserId,
    String source = 'referral_link',
  }) async {
    try {
      await _client.rpc('track_referral', params: {
        'p_referral_code': referralCode,
        'p_referred_user_id': referredUserId,
        'p_source': source,
      });
    } catch (e) {
      print('Error tracking referral: $e');
    }
  }

  // Get referral link
  String getReferralLink(String code) {
    return ReferralTracker.getReferralLink(code);
  }

  // Share referral link
Future<void> shareReferralLink(String code, String referrerName) async {
    final link = getReferralLink(code);
    final message = '🎓 Join AfriNova Academy using my link!\n\n'
        'I\'ve been using AfriNova and it\'s been amazing for my exam prep.\n\n'
        'What you get:\n'
        '✅ Syllabus-based AI Tutor that knows ZIMSEC & Cambridge inside out\n'
        '✅ Easy-to-understand syllabus summaries\n'
        '✅ AI Flashcards for quick concept mastery\n'
        '✅ Custom exam generation with AI feedback on failed questions\n'
        '✅ Past papers & marking schemes\n\n'
        '👉 $link\n\n'
        'Trust me, your grades will thank you! 🚀';
    
    try {
      await Share.share(
        message,
        subject: 'Join me on AfriNova Academy',
      );
    } catch (e) {
      print('Error sharing: $e');
    }
  }

  // Copy to clipboard (web)
  Future<void> copyToClipboard(String text) async {
    if (kIsWeb) {
      try {
        html.window.navigator.clipboard?.writeText(text);
      } catch (e) {
        print('Error copying to clipboard: $e');
      }
    }
  }

  // Get IP address (web)
  String? _getIpAddress() {
    if (kIsWeb) {
      // Can't get IP directly from browser
      return null;
    }
    return null;
  }

  // Get user agent (web)
  String? _getUserAgent() {
    if (kIsWeb) {
      try {
        return html.window.navigator.userAgent;
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}