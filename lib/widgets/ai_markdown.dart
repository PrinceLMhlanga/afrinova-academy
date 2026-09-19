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

    

      // ── Code / SVG / diagram handling ────────────────────────
      codeBuilder: (context, name, code, closed) {
        final lang = (name ?? '').toLowerCase().trim();

        if (lang == 'svg' ||
            lang == 'xml' ||
            (code.contains('<svg') && code.contains('</svg>'))) {
          return TextbookDiagramWidget(rawSvgString: code);
        }

        return CodeBlockWidget(
          languageName: name,
          codeSnippet: code,
        );
      },

      // ── LaTeX handler ────────────────────────────────────────
      // Long equations get a horizontally scrollable container.
      // Colors are derived from the ambient context so this works
      // in both a white card (dark text) and a blue chat bubble
      // (white text).
      latexBuilder: (context, texString, textStyle, isInline) {
        // Resolve the effective text color from the widest possible
        // source: the textStyle GptMarkdown passed in, then our
        // widget's style, then the ambient DefaultTextStyle.
        final ambient = DefaultTextStyle.of(context).style;
        final effectiveColor = textStyle?.color ??
            style?.color ??
            ambient.color ??
            const Color(0xFF1E1E1E);
        final isLightText = effectiveColor.computeLuminance() > 0.5;

        // Build the LaTeX renderer's style so it always carries
        // the right color, regardless of inheritance quirks.
        final latexStyle = (textStyle ?? style ?? ambient).copyWith(
          color: effectiveColor,
        );

        if (isInline) {
          return GptMarkdown(
            '\$$texString\$',
            useDollarSignsForLatex: true,
            style: latexStyle,
          );
        }

        // Block equation — horizontally scrollable to handle wide
        // equations. Background adapts to the text color so it's
        // readable on both light and dark contexts.
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12.0),
          padding: const EdgeInsets.symmetric(
            vertical: 14.0,
            horizontal: 12.0,
          ),
          decoration: BoxDecoration(
            color: isLightText
                ? Colors.white.withOpacity(0.12)   // subtle overlay on blue bubble
                : const Color(0xFFF8F9FA),         // light grey on white card
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isLightText
                  ? Colors.white.withOpacity(0.22)
                  : const Color(0xFFE0E0E0),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: GptMarkdown(
              '\$\$$texString\$\$',
              useDollarSignsForLatex: true,
              style: latexStyle,
            ),
          ),
        );
      },
    );
  }
}