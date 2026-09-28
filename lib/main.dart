import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/notification_service.dart';
import 'core/supabase_config.dart';
import 'core/referral_tracker.dart';
import 'core/navigation.dart';
import 'features/notifications/notifications_screen.dart';
import 'app.dart';

// ── Background message handler (must be top-level) ──
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('Handling background message: ${message.messageId}');
}

// ── Notification tap handler ──
// Called when the user taps a push notification. If the user is signed
// in, we push the notifications screen. If not, we stash the tap and
// let the auth listener in `main()` consume it once a session exists.
// Keep track of whether we already consumed the launch notification
bool _hasConsumedTap = false;

void _handleNotificationTap(Map<String, dynamic> data) {
  final session = Supabase.instance.client.auth.currentSession;

  // Stash the payload if there is no session yet
  if (session?.accessToken == null) {
    debugPrint('[push] no session — stashing pending tap');
    pendingNotificationTap = data;
    return;
  }
  _openNotificationsScreen();
}

void _openNotificationsScreen() {
  // Ensure the navigator widget tree is completely ready
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      // Re-queue safely if the navigator hasn't initialized
      Future.delayed(const Duration(milliseconds: 200), _openNotificationsScreen);
      return;
    }
    
    // Clear out any existing notification overlays first, preventing duplicates
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      (route) => route.isFirst, // Retains your base underlying app home route
    );
  });
}

void _consumePendingNotificationTap() {
  if (pendingNotificationTap == null || _hasConsumedTap) return;
  _hasConsumedTap = true; // Mark as consumed so token refreshes don't re-trigger it
  pendingNotificationTap = null;

  _openNotificationsScreen();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ReferralTracker.initialize();
  await SupabaseConfig.initialize();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.instance.initialize();
  await NotificationService.instance.registerDeviceToken();

  // ── Auth state listener ──
  Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
    if (data.event == AuthChangeEvent.signedIn ||
        data.event == AuthChangeEvent.tokenRefreshed ||
        data.event == AuthChangeEvent.userUpdated) {
      await NotificationService.instance.registerDeviceToken();
    }

    // ONLY consume the stashed notification tap during an explicit SIGNED_IN event
    if (data.event == AuthChangeEvent.signedIn && data.session?.accessToken != null) {
      _consumePendingNotificationTap();
    }
  });

  // ── Foreground / background tap ──
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap(message.data);
  });

  // ── Cold-start tap ──
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    // Instead of risking a hardcoded timer race condition, 
    // let your main layout frame build loop drive the routing action safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(initialMessage.data);
    });
  }

  runApp(const AfriNovaApp());
}
