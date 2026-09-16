import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'textbook_diagram.dart';
import 'code_block_widgets.dart';

class AiMarkdown extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const AiMarkdown({
    super.key,
    required this.text,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return GptMarkdown(
      text,
      useDollarSignsForLatex: true,
      style: style ??
          const TextStyle(
            fontSize: 17,
            height: 1.7,
            color: Color(0xFF1E1E1E),
          ),

      // ✅ Code block handler — now also detects SVG
      codeBuilder: (context, name, code, closed) {
        final lang = (name ?? '').toLowerCase().trim();

        // SVG → render as diagram
        if (lang == 'svg' ||
            lang == 'xml' ||
            (code.contains('<svg') && code.contains('</svg>'))) {
          return TextbookDiagramWidget(rawSvgString: code);
        }

        // Otherwise → syntax-highlighted code block
        return CodeBlockWidget(
          languageName: name,
          codeSnippet: code,
        );
      },

      // ✅ LaTeX handler — inline + block with horizontal scroll
      latexBuilder: (context, texString, textStyle, isInline) {
        if (isInline) {
          return GptMarkdown(
            '\$$texString\$',
            useDollarSignsForLatex: true,
            style: textStyle ??
                const TextStyle(fontSize: 17, color: Color(0xFF1E1E1E)),
          );
        }

        // Block equation — horizontally scrollable
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
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: GptMarkdown(
              '\$\$$texString\$\$',
              useDollarSignsForLatex: true,
              style: textStyle ??
                  const TextStyle(fontSize: 17, color: Color(0xFF1E1E1E)),
            ),
          ),
        );
      },
    );
  }
}