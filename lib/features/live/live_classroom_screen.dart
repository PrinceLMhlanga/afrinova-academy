import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LiveClassroomScreen extends StatefulWidget {
  final String meetUrl;
  final String topic;
  final String teacherName;

  const LiveClassroomScreen({
    super.key,
    required this.meetUrl,
    required this.topic,
    required this.teacherName,
  });

  @override
  State<LiveClassroomScreen> createState() => _LiveClassroomScreenState();
}

class _LiveClassroomScreenState extends State<LiveClassroomScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.meetUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          Chip(
            avatar: const Icon(Icons.circle, color: Colors.red, size: 10),
            label: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 12)),
            backgroundColor: Colors.red,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text('Joining live classroom...',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}