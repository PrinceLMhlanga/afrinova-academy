import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
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
// Keep a small dedupe set so the same notification payload is not processed
// multiple times when both the app launch hook and the tap listener fire.
final Set<String> _handledNotificationIds = <String>{};

void _handleNotificationTap(RemoteMessage message) {
  final data = message.data;
  final notificationKey =
      message.messageId ??
      data['message_id'] ??
      data['id'] ??
      data.toString();

  if (_handledNotificationIds.contains(notificationKey)) {
    debugPrint('[push] duplicate notification tap ignored: $notificationKey');
    return;
  }
  _handledNotificationIds.add(notificationKey);

  final session = Supabase.instance.client.auth.currentSession;

  // Stash the payload if there is no session yet.
  if (session?.accessToken == null) {
    debugPrint('[push] no session — stashing pending tap');
    pendingNotificationTap = data;
    return;
  }

  _openNotificationsScreen();
}

void _openNotificationsScreen() {
  // Ensure the navigator widget tree is completely ready.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) {
      // Re-queue safely if the navigator hasn't initialized yet.
      Future.delayed(const Duration(milliseconds: 200), _openNotificationsScreen);
      return;
    }

    // Push the notifications screen without removing the app shell/home route.
    // This keeps the user on the main app flow while opening the notification center.
    nav.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  });
}

void _consumePendingNotificationTap() {
  if (pendingNotificationTap == null) return;
  pendingNotificationTap = null;

  _openNotificationsScreen();
}

void _handleWebNotificationRouteFromUrl() {
  if (!kIsWeb) return;

  final screen = Uri.base.queryParameters['screen'];
  if (screen == 'notifications') {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openNotificationsScreen();
    });
  }
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
    _handleNotificationTap(message);
  });

  // ── Cold-start tap ──
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    // Instead of risking a hardcoded timer race condition,
    // let the main layout frame build loop drive the routing action safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(initialMessage);
    });
  }

  if (kIsWeb) {
    _handleWebNotificationRouteFromUrl();
  }

  runApp(const AfriNovaApp());
}
