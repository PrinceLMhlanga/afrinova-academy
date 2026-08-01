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
          latexBuilder: (context, texString, textStyle, isInline) {
  // ✅ FIX: Instead of returning null, return a simple inline GptMarkdown widget
  if (isInline) {
    return GptMarkdown(
      '\$$texString\$',
      useDollarSignsForLatex: true,
      style: textStyle ?? const TextStyle(fontSize: 17, color: Color(0xFF1E1E1E)),
    );
  }

  // If it's a big block equation ($$ ... $$), wrap it in a side-scrollable canvas box
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12.0),
    padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 12.0),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F9FA), 
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE0E0E0)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal, // Enables horizontal scrolling for mobile devices
      physics: const BouncingScrollPhysics(),
      child: GptMarkdown(
        '\$\$${texString}\$\$', 
        useDollarSignsForLatex: true,
        style: textStyle ?? const TextStyle(fontSize: 17, color: Color(0xFF1E1E1E)),
      ),
    ),
  );
},
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