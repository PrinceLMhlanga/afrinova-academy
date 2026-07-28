import 'package:flutter/material.dart';



class ChatGPTCloneApp extends StatelessWidget {
  const ChatGPTCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatGPT Clone',
      debugShowCheckedModeBanner: false,
      // Enforce clean Light Mode styling
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF4D4D4D)),
          titleTextStyle: TextStyle(
            color: Color(0xFF000000),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, String>> _messages = [
    {"role": "assistant", "content": "Hello! How can I help you today?"},
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    setState(() {
      _messages.add({"role": "user", "content": _controller.text});
      _controller.clear();
    });

    // Auto-scroll to the bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChatGPT'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add({"role": "assistant", "content": "Started a new chat. How can I help?"});
              });
            },
          ),
        ],
      ),
      // ChatGPT Sidebar Drawer
      drawer: Drawer(
        backgroundColor: const Color(0xFFF9F9F9),
        child: Column(
          children: [
            const UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: Color(0xFFEEEEEE)),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Color(0xFF10A37F),
                child: Text('U', style: TextStyle(color: Colors.white, fontSize: 24)),
              ),
              accountName: Text('User Profile', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              accountEmail: Text('user@example.com', style: TextStyle(color: Colors.black54)),
            ),
            ListTile(
              leading:  Icon(Icons.chat_bubble_outline, color: Colors.black.withOpacity(0.85)),
              title: const Text('New Chat', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            const Spacer(),
            ListTile(
              leading:  Icon(Icons.settings_outlined, color: Colors.black.withOpacity(0.85)),
              title: const Text('Settings'),
              onTap: () {},
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat Message List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isUser = message["role"] == "user";

                  return Container(
                    width: double.infinity,
                    // ChatGPT uses alternating background tints instead of bubbles
                    color: isUser ? const Color(0xFFFFFFFF) : const Color(0xFFF7F7F8),
                    padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar Icon
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: isUser ? const Color(0xFF543A3A) : const Color(0xFF10A37F),
                          child: Icon(
                            isUser ? Icons.person : Icons.bolt,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Message Text
                        Expanded(
                          child: Text(
                            message["content"] ?? '',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF2D2D2D),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Bottom Input Section
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE5E5E5), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              maxLines: null,
                              decoration: const InputDecoration(
                                hintText: 'Message ChatGPT...',
                                hintStyle: const TextStyle(color: Colors.black54, fontSize: 15),

                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(vertical: 12),
                              ),
                              style: const TextStyle(color: Colors.black, fontSize: 16),
                            ),
                          ),
                          // Send Arrow Button inside container
                          IconButton(
                            icon: const Icon(Icons.arrow_upward_rounded),
                            color: const Color(0xFF000000),
                            onPressed: _sendMessage,
                          ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
