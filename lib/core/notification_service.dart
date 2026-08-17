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

    // Setup message handlers
    _foregroundSubscription = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    
    // Check if app was opened from terminated state
    final RemoteMessage? initialMessage = 
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
    
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
    print('Foreground message: ${message.data}');
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    print('Message opened app: ${message.data}');
    _navigateBasedOnNotification(message.data);
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

  void _navigateBasedOnNotification(Map<String, dynamic> data) {
    // Implement navigation based on notification type
    final type = data['type'];
    print('Navigate based on type: $type');
    
    // Example routing:
    // switch (type) {
    //   case 'live_lesson':
    //     // Navigate to lesson
    //     break;
    //   case 'chat_message':
    //     // Navigate to chat
    //     break;
    //   case 'payment':
    //     // Navigate to payment
    //     break;
    // }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _foregroundSubscription?.cancel();
    _openedAppSubscription?.cancel();
  }
}