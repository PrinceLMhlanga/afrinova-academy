import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://rwheufzhixqqifoleltu.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ3aGV1ZnpoaXhxcWlmb2xlbHR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MjUwMTksImV4cCI6MjA5NTIwMTAxOX0.27b2JWt5vXZZ4W9AAxJZMth4Fxw2lHSFbimuXEfTswA';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}