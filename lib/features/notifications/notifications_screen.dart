import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribe();
  }

  Future<void> _loadNotifications() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _isLoading = true);
    try {
      final response = await _client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      setState(() => _notifications = List<Map<String, dynamic>>.from(response));
    } catch (e) {
      debugPrint('Load notifications error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribe() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _subscription = _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .listen((event) {
      _loadNotifications();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _markRead(String id) async {
    try {
      await _client.from('notifications').update({'is_read': true}).eq('id', id);
      _loadNotifications();
    } catch (e) {
      debugPrint('Mark read error: $e');
    }
  }

 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('No notifications'))
              : ListView.separated(
                  itemCount: _notifications.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = _notifications[i];
                    final isRead = n['is_read'] == true;
                    return ListTile(
                      tileColor: isRead ? Colors.white : Colors.grey.shade100,
                      title: Text(n['title'] ?? ''),
                      subtitle: Text(n['body'] ?? ''),
                      trailing: isRead
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.mark_email_read),
                              onPressed: () => _markRead(n['id'] as String),
                            ),
                      onTap: () {
                        if (!isRead) _markRead(n['id'] as String);
                        // Optionally navigate based on n['data']
                      },
                    );
                  },
                ),
    );
  }
}
