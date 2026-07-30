import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/chat_service.dart';
import '../../core/auth_service.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';

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
      final sessions = await _chatService.getSessions(
        userId,
        currentSessionId: widget.currentSessionId,
      );
      
      // ✅ Put current session at the top
      sessions.sort((a, b) {
        final aId = a['id'] as String;
        final bId = b['id'] as String;
        
        // Current session always first
        if (aId == widget.currentSessionId) return -1;
        if (bId == widget.currentSessionId) return 1;
        
        // Then sort by updated_at descending
        final aTime = DateTime.parse(a['updated_at'] as String? ?? '');
        final bTime = DateTime.parse(b['updated_at'] as String? ?? '');
        return bTime.compareTo(aTime);
      });
      
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
    // 1. Parse the string directly (Dart natively tracks its explicit Z/UTC offsets if provided)
    final date = DateTime.parse(dateStr); 
    
    // 2. Fetch the current time in UTC to match the server baseline
    final nowUtc = DateTime.now().toUtc();
    
    // 3. Take the absolute difference to eliminate future/past negative numbers
    final diff = nowUtc.difference(date);
    final minutes = diff.inMinutes.abs();
    final hours = diff.inHours.abs();
    final days = diff.inDays.abs();

    if (minutes < 1) return 'Just now';
    if (hours < 1) return '${minutes}m ago';
    if (days < 1) return '${hours}h ago';
    if (days < 7) return '${days}d ago';
    
    // Convert to local only when printing the fallback calendar digits
    final localDate = date.toLocal();
    return '${localDate.day}/${localDate.month}';
  } catch (_) { 
    return ''; 
  }
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
                ? Shimmer.fromColors(
  baseColor: Colors.grey.shade300,
  highlightColor: Colors.grey.shade100,
  child: _buildSkeletonLoader(),
)
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
                              subtitle: Text(
  subject.isNotEmpty ? '$subject • $date' : date, // ✅ No bullet if no subject
  style: const TextStyle(fontSize: 11, color: Colors.grey),
),
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

  Widget _buildSkeletonLoader() {
  return ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    itemCount: 8, // Show 8 skeleton items
    itemBuilder: (context, index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Avatar skeleton
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title skeleton
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Subtitle skeleton
                    Container(
                      height: 10,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
}

class ChatSidebarContent extends StatefulWidget {
  final String? currentSessionId;
  final String? currentSubject;
  final Function(String? sessionId, String? subject) onSessionSelected;
  final VoidCallback onNewChat;
  final VoidCallback? onClose;
  final Widget? sidebarToggle;

  const ChatSidebarContent({
    super.key,
    this.currentSessionId,
    this.currentSubject,
    required this.onSessionSelected,
    required this.onNewChat,
    this.onClose,
    this.sidebarToggle
  });

  @override
  State<ChatSidebarContent> createState() => _ChatSidebarContentState();
}

class _ChatSidebarContentState extends State<ChatSidebarContent> {
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  StreamSubscription? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _subscribeToSessionUpdates();
  }

  Future<void> _loadSessions() async {
  try {
    final userId = _authService.currentUserId;
    if (userId != null) {
      final sessions = await _chatService.getSessions(
        userId,
        currentSessionId: widget.currentSessionId,
      );
      // ✅ No sorting needed - database already returns ordered by updated_at DESC
      if (mounted) setState(() { _sessions = sessions; _isLoading = false; });
    }
  } catch (e) {
    if (mounted) setState(() => _isLoading = false);
  }
}

void _subscribeToSessionUpdates() {
  final userId = _authService.currentUserId;
  if (userId == null) return;

  _sessionSubscription = Supabase.instance.client
      .from('chat_sessions')
      .stream(primaryKey: ['id'])
      .eq('student_id', userId)
      .listen((data) {
    if (mounted) {
      setState(() {
        for (final updated in data) {
          final index = _sessions.indexWhere((s) => s['id'] == updated['id']);
          if (index != -1) {
            _sessions[index] = Map<String, dynamic>.from(updated);
          }
        }
        // ✅ Sort by updated_at descending (just like the database query)
        _sessions.sort((a, b) {
          final aTime = DateTime.parse(a['updated_at'] as String? ?? '');
          final bTime = DateTime.parse(b['updated_at'] as String? ?? '');
          return bTime.compareTo(aTime);
        });
      });
    }
  });
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
    final date = DateTime.parse(dateStr).toLocal(); // ✅ Convert to local
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
  void dispose() {
    _sessionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF9F9F9),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
            decoration: const BoxDecoration(color: Color(0xFFEEEEEE)),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFFFF9800)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text('AfriNova AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                if (widget.sidebarToggle != null)
        widget.sidebarToggle!,  

              ],
            ),
          ),
          
          // New Chat button
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onNewChat,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Chat'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1A237E),
                  side: const BorderSide(color: Color(0xFF1A237E), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
          
          const Divider(),
          
          // Chat list
          Expanded(
            child: _isLoading
                ? Shimmer.fromColors(
  baseColor: Colors.grey.shade300,
  highlightColor: Colors.grey.shade100,
  child: _buildSkeletonLoader(),
)
                : _sessions.isEmpty
                    ? const Center(child: Text('No chats yet', style: TextStyle(color: Colors.grey, fontSize: 13)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
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
                              leading: Icon(Icons.chat_bubble_outline, size: 16, color: isActive ? const Color(0xFF1A237E) : Colors.grey),
                              title: Text(title, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
  subject.isNotEmpty ? '$subject • $date' : date, // ✅ No bullet if no subject
  style: const TextStyle(fontSize: 11, color: Colors.grey),
),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                onPressed: () => _deleteSession(sessionId),
                              ),
                              onTap: () => widget.onSessionSelected(sessionId, session['subject'] as String?),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
  return ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    itemCount: 8, // Show 8 skeleton items
    itemBuilder: (context, index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Avatar skeleton
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title skeleton
                    Container(
                      height: 12,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Subtitle skeleton
                    Container(
                      height: 10,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
}