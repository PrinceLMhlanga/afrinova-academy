import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class SummaryViewerScreen extends StatelessWidget {
  final String title;
  final String content;

  const SummaryViewerScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: GptMarkdown(
          content,
          useDollarSignsForLatex: true,
          style: const TextStyle(
            fontSize: 15,
            height: 1.7,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}