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

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Replace these values with your Firebase web app config
  static const FirebaseOptions _webOptions = FirebaseOptions(
    apiKey: "AIzaSyDAMiHqhaKQ33dAHaJLuldeNPXz3EMEOj4",
    authDomain: "afrinova-academy.firebaseapp.com",
    projectId: "afrinova-academy",
    storageBucket: "afrinova-academy.firebasestorage.app",
    messagingSenderId: "563580728976",
    appId: "1:563580728976:web:48c88535de756b9484ca15",
    measurementId: "G-CM4DF0G5XK"
  );

  // Replace with your Firebase public VAPID key from the Firebase console
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

    // Initialize local notifications for displaying push notifications
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

    // Setup message handlers
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    
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
      print('Notification permission not granted');
      return;
    }

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: _webVapidKey)
        : await messaging.getToken();
    
    if (token == null || token.isEmpty) return;
    
    _currentToken = token;

    // Always save token locally regardless of auth state
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
      print('Error registering token with backend: $e');
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
      print('Error registering anonymous token: $e');
    }
  }

  // Call this when user logs in
  Future<void> onUserLogin(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('fcm_device_token') ?? _currentToken;
    
    if (token != null && token.isNotEmpty) {
      await _registerTokenWithBackend(userId, token);
    } else {
      // Re-register to get a new token
      await registerDeviceToken();
    }
  }

  // Handle foreground messages (when app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      print('Message also contained a notification: ${message.notification}');
      
      // Show local notification even in foreground
      _showLocalNotification(message);
    }
  }

  // Handle when user taps on notification to open app
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('Message opened app: ${message.data}');
    _navigateBasedOnNotification(message.data);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Default Channel',
      channelDescription: 'Default notification channel',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      message.messageId?.hashCode ?? 0,
      message.notification?.title ?? 'New Notification',
      message.notification?.body ?? '',
      details,
      payload: message.data.toString(),
    );
  }

  void _navigateBasedOnNotification(Map<String, dynamic> data) {
    // Implement your navigation logic here
    // This will depend on your app's routing setup
    print('Navigate based on: $data');
  }

  // Call this when user logs out
  Future<void> onUserLogout() async {
    // Keep token for potential next login
    // Or clear it if you prefer
    // final prefs = await SharedPreferences.getInstance();
    // await prefs.remove('fcm_device_token');
  }
}

// Simple UUID class to avoid adding dependency
class Uuid {
  String v4() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final str = random.toString() + random.toString();
    return '${str.substring(0, 8)}-${str.substring(8, 12)}-${str.substring(12, 16)}-${str.substring(16, 20)}-${str.substring(20, 32)}';
  }
}