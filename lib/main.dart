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
void _handleNotificationTap(Map<String, dynamic> data) {
  final session = Supabase.instance.client.auth.currentSession;

  Future.microtask(() {
    if (session?.accessToken == null) {
      debugPrint('[push] no session — stashing pending tap');
      pendingNotificationTap = data;
      return;
    }
    _openNotificationsScreen();
  });
}

void _openNotificationsScreen() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      // Navigator isn't ready yet — try again on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const NotificationsScreen(),
          ),
        );
      });
      return;
    }
    nav.push(
      MaterialPageRoute(
        builder: (_) => const NotificationsScreen(),
      ),
    );
  });
}

void _consumePendingNotificationTap() {
  final pending = pendingNotificationTap;
  if (pending == null) return;
  pendingNotificationTap = null;

  // Small delay so the app shell finishes mounting after login.
  Future.delayed(const Duration(milliseconds: 300), () {
    _openNotificationsScreen();
  });
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

    // Consume a pending notification tap once a session is live.
    if (data.session?.accessToken != null) {
      _consumePendingNotificationTap();
    }
  });

  // ── Foreground / background tap ──
  // Fires when the app is running (foreground or backgrounded) and the
  // user taps a push.
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap(message.data);
  });

  // ── Cold-start tap ──
  // Fires when the app was terminated and the user tapped a push to
  // launch it. Deferred so the app has time to build.
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    Future.delayed(const Duration(milliseconds: 500), () {
      _handleNotificationTap(initialMessage.data);
    });
  }

  runApp(const AfriNovaApp());
}