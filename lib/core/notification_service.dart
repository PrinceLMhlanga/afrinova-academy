import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;

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

  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      await Firebase.initializeApp(options: _webOptions);
    } else {
      await Firebase.initializeApp();
    }

    _initialized = true;
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
      return;
    }

    final token = kIsWeb
        ? await messaging.getToken(vapidKey: _webVapidKey)
        : await messaging.getToken();
    if (token == null || token.isEmpty) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    await Supabase.instance.client.from('user_devices').upsert({
      'user_id': userId,
      'token': token,
      'platform': kIsWeb ? 'web' : 'mobile',
      'is_web': kIsWeb,
    }, onConflict: 'token');

    messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) return;
      final refreshedUserId = Supabase.instance.client.auth.currentUser?.id;
      if (refreshedUserId == null) return;

      await Supabase.instance.client.from('user_devices').upsert({
        'user_id': refreshedUserId,
        'token': newToken,
        'platform': kIsWeb ? 'web' : 'mobile',
        'is_web': kIsWeb,
      }, onConflict: 'token');
    });
  }
}
