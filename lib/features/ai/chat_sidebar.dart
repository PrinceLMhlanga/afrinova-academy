import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/chat_service.dart';
import '../../core/auth_service.dart';

class ChatSidebar extends StatefulWidget {
  final String? currentSessionId;
  final String? currentSubject;
  final Function(String? sessionId, String? subject) onSessionSelected;
  final VoidCallback onNewChat;

  const ChatSidebar({
    super.key,
    this.currentSessionId,
    this.currentSubject,
    required this.onSessionSelected,
    required this.onNewChat,
  });

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final userId = _authService.currentUserId;
      if (userId != null) {
        final sessions = await _chatService.getSessions(userId);
        if (mounted) setState(() { _sessions = sessions; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Chat?'),
        content: const Text('This will permanently delete this conversation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _chatService.deleteSession(sessionId);
      _loadSessions();
      if (sessionId == widget.currentSessionId) {
        widget.onNewChat();
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}';
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF9F9F9),
      width: 300,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFEEEEEE),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFFFF9800)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('AfriNova AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
          ),
          
          // New Chat button
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.onNewChat();
                  
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A237E),
                  side: const BorderSide(color: Color(0xFF1A237E), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          
          const Divider(),
          
          // Chat history
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? const Center(child: Text('No conversations yet', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          final session = _sessions[index];
                          final sessionId = session['id'] as String;
                          final title = session['title'] as String? ?? 'Untitled';
                          final subject = session['subject'] as String? ?? '';
                          final date = _formatDate(session['updated_at'] as String?);
                          final isActive = sessionId == widget.currentSessionId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            decoration: BoxDecoration(
                              color: isActive ? const Color(0xFF1A237E).withOpacity(0.08) : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              leading: Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                                color: isActive ? const Color(0xFF1A237E) : Colors.grey,
                              ),
                              title: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                  color: isActive ? const Color(0xFF1A237E) : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text('$subject • $date', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                onPressed: () => _deleteSession(sessionId),
                              ),
                              onTap: () {
                                widget.onSessionSelected(sessionId, session['subject'] as String?);
                                
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}