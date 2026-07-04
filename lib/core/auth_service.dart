import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  // Get current user
  User? get currentUser => _client.auth.currentUser;

  // Get current user ID
  String? get currentUserId => _client.auth.currentUser?.id;

  // Check if logged in
  bool get isLoggedIn => _client.auth.currentUser != null;

  // Stream of auth state changes
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'role': role,
      },
    );

    // Create profile in profiles table
    if (response.user != null) {
      await _client.from('profiles').insert({
        'id': response.user!.id,
        'full_name': fullName,
        'email': email,
        'role': role,
      });
    }

    return response;
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // Get user profile
  Future<Map<String, dynamic>?> getProfile() async {
    if (currentUserId == null) return null;

    final response = await _client
        .from('profiles')
        .select()
        .eq('id', currentUserId!)
        .single();

    return response;
  }
}