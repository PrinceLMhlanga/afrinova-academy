import 'package:flutter/foundation.dart';
import 'package:universal_html/html.dart' as html;

class ReferralTracker {
  static String? _referralCode;
  
  static String? get referralCode => _referralCode;
  
  // Initialize - call this in main.dart
  static void initialize() {
    if (kIsWeb) {
      _captureReferralFromWeb();
    } else {
      // Mobile will be implemented later
      _referralCode = null;
    }
  }
  
  static void _captureReferralFromWeb() {
    try {
      // Get current URL
      final uri = Uri.parse(html.window.location.href);
      final pathSegments = uri.pathSegments;
      
      // Check if URL contains /ref/CODE
      if (pathSegments.length >= 2 && pathSegments[0].toLowerCase() == 'ref') {
        _referralCode = pathSegments[1].toUpperCase();
        // Store in localStorage
        html.window.localStorage['referral_code'] = _referralCode!;
        html.window.localStorage['referral_timestamp'] = DateTime.now().toIso8601String();
        print('✅ Referral code captured from URL: $_referralCode');
      } else {
        // Check localStorage as fallback
        final storedCode = html.window.localStorage['referral_code'];
        if (storedCode != null && storedCode.isNotEmpty) {
          _referralCode = storedCode;
          print('✅ Referral code loaded from localStorage: $_referralCode');
        }
      }
    } catch (e) {
      print('❌ Error capturing referral: $e');
    }
  }
  
  // ✅ NEW: Store referral code explicitly (for route handling)
  static void storeReferralCode(String code) {
    _referralCode = code.toUpperCase();
    if (kIsWeb) {
      try {
        html.window.localStorage['referral_code'] = _referralCode!;
        html.window.localStorage['referral_timestamp'] = DateTime.now().toIso8601String();
        print('✅ Referral code stored: $_referralCode');
      } catch (e) {
        print('❌ Error storing referral: $e');
      }
    }
  }
  
  static Future<void> clearReferralCode() async {
    _referralCode = null;
    if (kIsWeb) {
      try {
        html.window.localStorage.remove('referral_code');
        html.window.localStorage.remove('referral_timestamp');
        print('✅ Referral code cleared');
      } catch (e) {
        print('❌ Error clearing referral: $e');
      }
    }
  }
  
  // Get referral code for tracking
  static String? getReferralCode() {
    if (_referralCode != null && _referralCode!.isNotEmpty) {
      return _referralCode;
    }
    
    // Try localStorage again
    if (kIsWeb) {
      try {
        final storedCode = html.window.localStorage['referral_code'];
        if (storedCode != null && storedCode.isNotEmpty) {
          _referralCode = storedCode;
          return _referralCode;
        }
      } catch (e) {
        print('Error reading localStorage: $e');
      }
    }
    
    return null;
  }
  
  // Check if referral is still valid (not expired)
  static bool isReferralValid() {
    if (kIsWeb) {
      try {
        final timestamp = html.window.localStorage['referral_timestamp'];
        if (timestamp != null) {
          final storedTime = DateTime.parse(timestamp);
          final difference = DateTime.now().difference(storedTime);
          
          // Referral valid for 7 days
          if (difference.inDays <= 7) {
            return true;
          }
        }
      } catch (e) {
        print('Error checking referral validity: $e');
      }
    }
    return false;
  }
  
  // Get referral link for sharing
  static String getReferralLink(String code) {
    return 'https://www.afrinova-academy.com/ref/$code';
  }
}