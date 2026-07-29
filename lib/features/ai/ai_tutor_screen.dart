import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/ai_service.dart';
import '../../core/chat_service.dart';
import '../../core/auth_service.dart';
import 'chat_history_screen.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../core/chat_stream_controller.dart';
import 'chat_sidebar.dart';

class AITutorScreen extends StatefulWidget {
  final String? subjectName;
  final String? sessionId;

  const AITutorScreen({super.key, this.subjectName, this.sessionId});

  @override
  State<AITutorScreen> createState() => _AITutorScreenState();
}

class _AITutorScreenState extends State<AITutorScreen>
    with SingleTickerProviderStateMixin {
  final AIService _aiService = AIService();
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isInitializing = true;
  String? _sessionId;
  String _streamingText = '';
  Timer? _streamTimer;
  bool _isDarkMode = false;
  bool _showScrollToBottom = false;

  // Animation controllers for welcome screen
  late AnimationController _welcomeAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initChat();
    
    _welcomeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _welcomeAnimationController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(
      parent: _welcomeAnimationController,
      curve: Curves.easeOut,
    ));
    
    _welcomeAnimationController.forward();
    
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    if (_sessionId != null && _messages.isEmpty) {
      _chatService.deleteIfEmpty(_sessionId!);
    }
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _streamTimer?.cancel();
    _welcomeAnimationController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final show = currentScroll < maxScroll - 100;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
    }
  }

  Future<void> _initChat() async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    if (widget.sessionId != null) {
      _sessionId = widget.sessionId;
      final history = await _chatService.getMessages(_sessionId!);
      if (history.isNotEmpty) {
        for (final msg in history) {
          _messages.add(_ChatMessage(
            text: msg['message'] as String,
            isUser: msg['sender'] == 'student',
          ));
        }
      } else {
        _addWelcomeMessage();
      }
    } else {
      _sessionId = await _chatService.createSession(
        studentId: userId,
        subject: widget.subjectName ?? 'General',
      );
      _addWelcomeMessage();
    }

    if (mounted) setState(() => _isInitializing = false);
  }

  void _addWelcomeMessage() {
    _messages.add(_ChatMessage(
      text: widget.subjectName != null
          ? "👋 Hello! I'm your AI tutor for **${widget.subjectName}**. How can I help you today?"
          : "👋 Hello! I'm your AfriNova AI tutor. I'm here to help you learn. What would you like to explore?",
      isUser: false,
    ));
  }

  Future<void> _sendMessage() async {
  final text = _inputController.text.trim();
  if (text.isEmpty || _isLoading) return;

  _inputController.clear();
  
  final streamController = ChatStreamController();
  
  // 1. Create mutable reference index safely
  int? streamingIndex;

  setState(() {
    _messages.add(_ChatMessage(text: text, isUser: true));
    
    // Create the loading placeholder bubble
    final placeholder = _ChatMessage(
      text: 'Thinking...', // Non-empty initial text prevents layout collapse
      isUser: false,
      isStreaming: true,
      streamController: streamController,
    );
    _messages.add(placeholder);
    streamingIndex = _messages.length - 1;
    _isLoading = true;
  });
  _scrollToBottom();

  // Save user message to database
  if (_sessionId != null) {
    final studentMessages = _messages.where((m) => m.isUser).length;
    if (studentMessages == 1) {
      await _chatService.autoNameSession(_sessionId!, text);
    }
    await _chatService.saveMessage(sessionId: _sessionId!, sender: 'student', message: text);
    await _chatService.updateSessionTimestamp(_sessionId!);
  }

  // Build clean non-streaming conversational history context
  final history = _messages
      .where((m) => !m.isStreaming)
      .map((m) => {'sender': m.isUser ? 'student' : 'ai', 'message': m.text})
      .toList();

  // Limit history slice smoothly to avoid bloated payloads
  final trimmedHistory = history.length > 10 
      ? history.sublist(history.length - 10) 
      : history;

  try {
    final stream = _aiService.chatStream(
      message: text,
      subject: widget.subjectName ?? 'General',
      history: trimmedHistory,
    );

    await for (final chunk in stream) {
      streamController.addChunk(chunk);
      
      // 2. Force the list view to accommodate changing text height
      if (mounted) {
        _scrollToBottom(); 
      }
    }
  } catch (e) {
    streamController.addChunk('\n\n*Error generating response. Please try again.*');
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
    
    final finalAiText = streamController.fullText.isNotEmpty 
        ? streamController.fullText 
        : 'No response received from tutor.';

    // Save complete response string to database
    if (_sessionId != null && streamController.fullText.isNotEmpty) {
      await _chatService.saveMessage(
        sessionId: _sessionId!,
        sender: 'ai',
        message: finalAiText,
      );
    }
    
    streamController.closeStream();
    
    // 3. Re-locate index safely and replace entirely to dodge immutability issues
    if (mounted) {
      final targetIndex = _messages.indexWhere((m) => m.streamController == streamController);
      if (targetIndex != -1) {
        setState(() {
          _messages[targetIndex] = _ChatMessage(
            text: finalAiText,
            isUser: false,
            isStreaming: false,
            streamController: null,
          );
        });
      }
      _scrollToBottom();
    }
  }
}


  

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _startNewChat() {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => AITutorScreen(subjectName: widget.subjectName),
    ),
  );
}

  @override
Widget build(BuildContext context) {
  if (_isInitializing) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('AI Tutor', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF1A237E)),
            SizedBox(height: 16),
            Text('Loading your AI tutor...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  return Scaffold(
    backgroundColor: const Color(0xFFFAFAFA),
    appBar: AppBar(
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu, color: Colors.black87),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      title: Text(
        widget.subjectName != null ? '${widget.subjectName} Tutor' : 'AI Tutor',
        style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      centerTitle: true,
      backgroundColor: Colors.white,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, color: Colors.black54),
          onPressed: _startNewChat,
          tooltip: 'New Chat',
        ),
      ],
    ),
    drawer: Builder(
  builder: (drawerContext) => ChatSidebar(
    currentSessionId: _sessionId,
    currentSubject: widget.subjectName,
    onSessionSelected: (sessionId, subject) {
      // Closes only the drawer using the unique drawerContext
      Navigator.pop(drawerContext); 
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AITutorScreen(
            sessionId: sessionId,
            subjectName: subject,
          ),
        ),
      );
    },
    onNewChat: () {
      // Closes only the drawer using the unique drawerContext
      Navigator.pop(drawerContext); 
      _startNewChat();
    },
  ),
),


    body: Column(
      children: [
        // Messages
        Expanded(
          child: _messages.isEmpty
              ? _buildWelcomeScreen()
              : Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _MessageBubble(message: msg);
                      },
                    ),
                    if (_showScrollToBottom)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: GestureDetector(
                          onTap: _scrollToBottom,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A237E),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: const Color(0xFF1A237E).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                            ),
                            child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        _buildInputBar(),
      ],
    ),
  );
}

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFFFF9800)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.subjectName != null ? '${widget.subjectName} Tutor' : 'AI Tutor',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (widget.subjectName != null)
                Text(
                  'Powered by AfriNova AI',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1A237E),
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
     
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.history, size: 20),
          ),
          tooltip: 'Chat History',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatHistoryScreen()),
            ).then((result) {
              if (result is String) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AITutorScreen(
                      subjectName: widget.subjectName,
                      sessionId: result,
                    ),
                  ),
                );
              }
            });
          },
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.add, size: 20),
          ),
          tooltip: 'New Chat',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => AITutorScreen(subjectName: widget.subjectName),
              ),
            );
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildWelcomeScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                children: [
                  // Logo/Icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A237E), Color(0xFFFF9800)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1A237E).withOpacity(0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    widget.subjectName != null
                        ? '${widget.subjectName} Tutor'
                        : 'AfriNova AI Tutor',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.subjectName != null
                        ? 'Ask me anything about ${widget.subjectName}'
                        : 'Your personal learning assistant',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Quick actions
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _QuickActionChip(
                        icon: Icons.lightbulb_outline_rounded,
                        label: 'Explain Concept',
                        color: const Color(0xFF1A237E),
                        onTap: () {
                          _inputController.text = 'Explain ';
                          _focusNode.requestFocus();
                        },
                      ),
                      _QuickActionChip(
                        icon: Icons.calculate_outlined,
                        label: 'Solve Problem',
                        color: const Color(0xFFFF9800),
                        onTap: () {
                          _inputController.text = 'Help me solve ';
                          _focusNode.requestFocus();
                        },
                      ),
                      _QuickActionChip(
                        icon: Icons.quiz_outlined,
                        label: 'Exam Tips',
                        color: const Color(0xFF00897B),
                        onTap: () {
                          _inputController.text = 'Give me exam tips for ';
                          _focusNode.requestFocus();
                        },
                      ),
                      _QuickActionChip(
                        icon: Icons.summarize_rounded,
                        label: 'Summarize Topic',
                        color: const Color(0xFF9C27B0),
                        onTap: () {
                          _inputController.text = 'Summarize ';
                          _focusNode.requestFocus();
                        },
                      ),
                      _QuickActionChip(
                        icon: Icons.assignment_rounded,
                        label: 'Practice Quiz',
                        color: const Color(0xFFE91E63),
                        onTap: () {
                          _inputController.text = 'Create a practice quiz on ';
                          _focusNode.requestFocus();
                        },
                      ),
                      _QuickActionChip(
                        icon: Icons.live_help_rounded,
                        label: 'Ask Question',
                        color: const Color(0xFF4CAF50),
                        onTap: () {
                          _focusNode.requestFocus();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Features
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: const [
                        _FeatureItem(icon: Icons.speed, label: 'Fast', color: Color(0xFF1A237E)),
                        _FeatureItem(icon: Icons.menu_book, label: 'Knowledge', color: Color(0xFFFF9800)),
                        _FeatureItem(icon: Icons.support_agent, label: '24/7', color: Color(0xFF00897B)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final hasText = _inputController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Attachment button (like ChatGPT)
            IconButton(
              icon: Icon(
                Icons.attach_file_rounded,
                color: Colors.grey[500],
                size: 22,
              ),
              onPressed: () {},
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? const Color(0xFF1A237E).withOpacity(0.4)
                        : Colors.grey.shade200,
                  ),
                  boxShadow: _focusNode.hasFocus
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1A237E).withOpacity(0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1E1E1E),
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask AfriNova AI...',
                    hintStyle: TextStyle(
                      color: Colors.grey,
                      fontSize: 15,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Send button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: hasText
                    ? const LinearGradient(
                        colors: [Color(0xFF1A237E), Color(0xFF283593)],
                      )
                    : null,
                color: hasText ? null : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: hasText
                    ? [
                        BoxShadow(
                          color: const Color(0xFF1A237E).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: IconButton(
                onPressed: hasText ? _sendMessage : null,
                icon: Icon(
                  hasText ? Icons.arrow_upward_rounded : Icons.arrow_upward_rounded,
                  color: hasText ? Colors.white : Colors.grey,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== CHAT MESSAGE MODEL =====
class _ChatMessage {
  String text;
  final bool isUser;
  bool isStreaming;
  ChatStreamController? streamController;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
    this.streamController,
  });
}

// ===== MESSAGE BUBBLE =====
class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ Three dots while waiting for first chunk
    if (message.text.isEmpty && message.isStreaming) {
      return const _TypingIndicator();
    }

    // ✅ Max width for large screens, full width for phones
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth > 800 ? 700.0 : screenWidth * 0.9;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: message.isUser
              // User message - right aligned within the max-width
              ? Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth * 0.75,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: GptMarkdown(
                      message.text,
                      useDollarSignsForLatex: true,
                      style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.white),
                    ),
                  ),
                )
              // AI message - left aligned within max-width, large font
              : message.isStreaming && message.streamController != null
    ? StreamBuilder<String>(
        stream: message.streamController!.textStream,
        initialData: message.text, // Starts with 'Thinking...' baseline placeholder
        builder: (context, snapshot) {
          final text = snapshot.data ?? '';
          
          if (text == 'Thinking...' || text.isEmpty) {
            return const PremiumTypingIndicator();
          }

          return GptMarkdown(
            text,
            useDollarSignsForLatex: true,
            style: const TextStyle(fontSize: 17, height: 1.7, color: Color(0xFF1E1E1E)),
          );
        },
      )
    : GptMarkdown(
        message.text,
        useDollarSignsForLatex: true,
        style: const TextStyle(fontSize: 17, height: 1.7, color: Color(0xFF1E1E1E)),
      ),

        ),
      ),
    );
  }
}

// ===== QUICK ACTION CHIP =====
class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== FEATURE ITEM =====
class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _FeatureItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ===== TYPING INDICATOR =====
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFFFF9800)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BouncingDot(delay: 0),
                  const SizedBox(width: 5),
                  _BouncingDot(delay: 150),
                  const SizedBox(width: 5),
                  _BouncingDot(delay: 300),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== BOUNCING DOT =====
class _BouncingDot extends StatefulWidget {
  final int delay;

  const _BouncingDot({required this.delay});

  @override
  State<_BouncingDot> createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -4 * _animation.value),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF1A237E),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
} 

class PremiumTypingIndicator extends StatelessWidget {
  const PremiumTypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          _BouncingDot(delay: 0),
          SizedBox(width: 4),
          _BouncingDot(delay: 200),
          SizedBox(width: 4),
          _BouncingDot(delay: 400),
        ],
      ),
    );
  }
}
