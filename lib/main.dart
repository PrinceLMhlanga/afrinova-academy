import 'package:flutter/material.dart';
import 'core/notification_service.dart';
import 'core/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  await NotificationService.instance.initialize();

  if (Supabase.instance.client.auth.currentUser != null) {
    await NotificationService.instance.registerDeviceToken();
  }

  runApp(const AfriNovaApp());
}
