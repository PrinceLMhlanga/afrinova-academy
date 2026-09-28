import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const FirebaseOptions _webOptions = FirebaseOptions(
    apiKey: "AIzaSyDAMiHqhaKQ33dAHaJLuldeNPXz3EMEOj4",
    authDomain: "afrinova-academy.firebaseapp.com",
    projectId: "afrinova-academy",
    storageBucket: "afrinova-academy.firebasestorage.app",
    messagingSenderId: "563580728976",
    appId: "1:563580728976:web:48c88535de756b9484ca15",
    measurementId: "G-CM4DF0G5XK"
  );

  static const String _webVapidKey = 'BPNsUK63GXsjZD1YWfmzsFDt3Cr4Vgq1nrnHDVilO1lfH9KaHQDg_j8XfjlxXq8PtRaOUqkLKV0sMyR06BQLK-A';
  
  String? _deviceId;
  String? _currentToken;

  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      await Firebase.initializeApp(options: _webOptions);
    } else {
      await Firebase.initializeApp();
    }

    // Initialize local notifications
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings = 
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _localNotifications.initialize(initSettings);

    await _getOrCreateDeviceId();

    // Setup foreground message handling only here.
    // Notification tap handling is centralized in main.dart to avoid duplicate
    // processing when the app opens from a notification or cold start.
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    _initialized = true;
  }

  Future<void> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('fcm_device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = DateTime.now().microsecondsSinceEpoch.toString();
      await prefs.setString('fcm_device_id', _deviceId!);
    }
  }

  Future<void> registerDeviceToken() async {
    await initialize();

    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('Notification permission not granted');
      return;
    }

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: _webVapidKey)
        : await messaging.getToken();
    
    if (token == null || token.isEmpty) return;
    
    _currentToken = token;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_device_token', token);

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await _registerTokenWithBackend(userId, token);
    } else {
      await _registerAnonymousToken(token);
    }

    _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      _currentToken = newToken;

      await prefs.setString('fcm_device_token', newToken);

      final refreshedUserId = Supabase.instance.client.auth.currentUser?.id;
      if (refreshedUserId != null) {
        await _registerTokenWithBackend(refreshedUserId, newToken);
      } else {
        await _registerAnonymousToken(newToken);
      }
    });
  }

  Future<void> _registerTokenWithBackend(String userId, String token) async {
    try {
      await Supabase.instance.client.from('user_devices').upsert({
        'device_id': _deviceId,
        'user_id': userId,
        'token': token,
        'platform': kIsWeb ? 'web' : 'mobile',
        'is_web': kIsWeb,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'device_id');
    } catch (e) {
      debugPrint('Error registering token with backend: $e');
    }
  }

  Future<void> _registerAnonymousToken(String token) async {
    try {
      await Supabase.instance.client.from('user_devices').upsert({
        'device_id': _deviceId,
        'token': token,
        'platform': kIsWeb ? 'web' : 'mobile',
        'is_web': kIsWeb,
        'user_id': null,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'device_id');
    } catch (e) {
      debugPrint('Error registering anonymous token: $e');
    }
  }

  Future<void> onUserLogin(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('fcm_device_token') ?? _currentToken;
    
    if (token != null && token.isNotEmpty) {
      await _registerTokenWithBackend(userId, token);
    } else {
      await registerDeviceToken();
    }
  }

  Future<void> onUserLogout() async {
    // Optionally clear user association
    
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('Foreground message: ${message.data}');

    // On web, the service worker already renders the browser notification.
    // Showing a second local notification here duplicates the same push.
    if (kIsWeb) return;

    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Notifications',
      channelDescription: 'General notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      details,
      payload: message.data.toString(),
    );
  }

/// Fetch the current user's notifications, newest first.
Future<List<Map<String, dynamic>>> fetchMyNotifications({
  int limit = 50,
}) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return const [];

  try {
    final res = await Supabase.instance.client
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (res as List)
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList(growable: false);
  } catch (e) {
    debugPrint('[NotificationService] fetchMyNotifications failed: $e');
    return const [];
  }
}

/// Live stream of the current user's notifications.
Stream<List<Map<String, dynamic>>> watchMyNotifications() {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return Stream.value(const []);

  return Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50)
      .map((rows) => rows.cast<Map<String, dynamic>>());
}

/// Count unread notifications for the current user.
Future<int> getUnreadCount() async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return 0;

  try {
    final res = await Supabase.instance.client
        .from('notifications')
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);
    return (res as List).length;
  } catch (e) {
    debugPrint('[NotificationService] getUnreadCount failed: $e');
    return 0;
  }
}

/// Mark a single notification as read.
Future<void> markRead(String notificationId) async {
  try {
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  } catch (e) {
    debugPrint('[NotificationService] markRead failed: $e');
  }
}

/// Mark every unread notification for the current user as read.
Future<void> markAllRead() async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  try {
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  } catch (e) {
    debugPrint('[NotificationService] markAllRead failed: $e');
  }
}

/// Approve or deny a parent link request.
/// Updates the link status and marks the notification as read.
Future<String?> respondToParentLink({
  required String notificationId,
  required String linkId,
  required bool approve,
}) async {
  try {
    // 1. Update the link
    await Supabase.instance.client
        .from('parent_student_links')
        .update({
          'status': approve ? 'active' : 'denied',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', linkId);

    // 2. Update the notification's data so we know the outcome
    //    next time the screen loads.
    final existing = await Supabase.instance.client
        .from('notifications')
        .select('data')
        .eq('id', notificationId)
        .maybeSingle();

    final existingData =
        (existing?['data'] as Map?)?.cast<String, dynamic>() ?? {};

    await Supabase.instance.client
        .from('notifications')
        .update({
          'is_read': true,
          'data': {
            ...existingData,
            'resolved': approve ? 'approved' : 'denied',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          },
        })
        .eq('id', notificationId);

    return null;
  } catch (e) {
    debugPrint('[NotificationService] respondToParentLink failed: $e');
    return 'Something went wrong. Please try again.';
  }
}

/// Revoke an active parent link. Called from the notifications screen
/// when the student changes their mind after approving.
Future<String?> revokeParentLink({
  required String notificationId,
  required String linkId,
}) async {
  try {
    await Supabase.instance.client
        .from('parent_student_links')
        .update({
          'status': 'revoked',
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', linkId);

    // Update the notification's data to reflect the revoked state.
    final existing = await Supabase.instance.client
        .from('notifications')
        .select('data')
        .eq('id', notificationId)
        .maybeSingle();

    final existingData =
        (existing?['data'] as Map?)?.cast<String, dynamic>() ?? {};

    await Supabase.instance.client
        .from('notifications')
        .update({
          'data': {
            ...existingData,
            'resolved': 'revoked',
            'resolved_at': DateTime.now().toUtc().toIso8601String(),
          },
        })
        .eq('id', notificationId);

    return null;
  } catch (e) {
    debugPrint('[NotificationService] revokeParentLink failed: $e');
    return 'Could not revoke access. Please try again.';
  }
}

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _openedAppSubscription?.cancel();
  }
}