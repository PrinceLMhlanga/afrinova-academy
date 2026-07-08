import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A widget that renders text with embedded LaTeX math expressions.
/// Supports both inline ($...$) and display ($$...$$) math.
class MathRenderer extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color? textColor;
  final TextAlign textAlign;
  final bool selectable;
  final double mathFontSize;
  final Color? mathColor;

  const MathRenderer(
    this.text, {
    super.key,
    this.fontSize = 16,
    this.textColor,
    this.textAlign = TextAlign.start,
    this.selectable = true,
    this.mathFontSize = 16,
    this.mathColor,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final segments = _parseText(text);
    final defaultColor = textColor ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    if (segments.isEmpty) {
      return Text(
        text,
        style: TextStyle(fontSize: fontSize, color: defaultColor),
        textAlign: textAlign,
      );
    }

    if (selectable) {
      return SelectableText.rich(
        _buildTextSpan(segments, defaultColor),
        textAlign: textAlign,
      );
    }

    return Text.rich(
      _buildTextSpan(segments, defaultColor),
      textAlign: textAlign,
    );
  }

  TextSpan _buildTextSpan(List<TextSegment> segments, Color defaultColor) {
    final children = <InlineSpan>[];

    for (final segment in segments) {
      if (segment.isMath) {
        final mathWidget = _buildMathWidget(
          segment.text,
          segment.isDisplayMath,
          defaultColor,
        );

        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: mathWidget,
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: segment.text,
            style: TextStyle(fontSize: fontSize, color: defaultColor),
          ),
        );
      }
    }

    return TextSpan(children: children);
  }

  Widget _buildMathWidget(String latex, bool isDisplay, Color defaultColor) {
    final mathStyle = isDisplay ? MathStyle.display : MathStyle.text;

    return Math.tex(
      latex,
      mathStyle: mathStyle,
      textStyle: TextStyle(
        fontSize: isDisplay ? mathFontSize * 1.2 : mathFontSize,
        color: mathColor ?? defaultColor,
        fontFamily: 'Times New Roman',
      ),
      onErrorFallback: (error) {
        // If math fails to render, show the raw text
        return Text(
          latex,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.red,
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );
  }

  List<TextSegment> _parseText(String text) {
    final segments = <TextSegment>[];
    final buffer = StringBuffer();
    int i = 0;
    bool inMath = false;
    bool inDisplayMath = false;

    while (i < text.length) {
      // Check for display math $$...$$
      if (i + 1 < text.length && text[i] == '\$' && text[i + 1] == '\$') {
        if (buffer.isNotEmpty) {
          segments.add(TextSegment(buffer.toString(), false, false));
          buffer.clear();
        }

        // Find closing $$
        int end = i + 2;
        while (end + 1 < text.length && !(text[end] == '\$' && text[end + 1] == '\$')) {
          end++;
        }

        if (end + 1 < text.length) {
          final mathContent = text.substring(i + 2, end);
          segments.add(TextSegment(mathContent, true, true));
          i = end + 2;
        } else {
          // No closing $$ found, treat as normal text
          buffer.write(text.substring(i));
          break;
        }
        continue;
      }

      // Check for inline math $...$
      if (text[i] == '\$') {
        if (buffer.isNotEmpty) {
          segments.add(TextSegment(buffer.toString(), false, false));
          buffer.clear();
        }

        // Find closing $
        int end = i + 1;
        while (end < text.length && text[end] != '\$') {
          end++;
        }

        if (end < text.length) {
          final mathContent = text.substring(i + 1, end);
          segments.add(TextSegment(mathContent, true, false));
          i = end + 1;
        } else {
          // No closing $ found, treat as normal text
          buffer.write(text.substring(i));
          break;
        }
        continue;
      }

      buffer.write(text[i]);
      i++;
    }

    if (buffer.isNotEmpty) {
      segments.add(TextSegment(buffer.toString(), false, false));
    }

    return segments;
  }
}

/// A widget that renders a list of content items (text + optional diagrams)
class ContentRenderer extends StatelessWidget {
  final String content;
  final double fontSize;
  final Color? textColor;
  final bool selectable;
  final double imageHeight;
  final double imageWidth;

  const ContentRenderer(
    this.content, {
    super.key,
    this.fontSize = 16,
    this.textColor,
    this.selectable = true,
    this.imageHeight = 200,
    this.imageWidth = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    if (content.isEmpty) return const SizedBox.shrink();

    // Check for diagram placeholder
    if (content.contains('[See diagram - description]')) {
      return _buildContentWithDiagram(content);
    }

    return MathRenderer(
      content,
      fontSize: fontSize,
      textColor: textColor,
      selectable: selectable,
    );
  }

  Widget _buildContentWithDiagram(String content) {
    // Split content into text parts and diagram markers
    final parts = <Widget>[];
    final regex = RegExp(r'\[See diagram[^\]]*\]');
    int lastIndex = 0;

    for (final match in regex.allMatches(content)) {
      // Add text before diagram
      if (match.start > lastIndex) {
        final textPart = content.substring(lastIndex, match.start);
        parts.add(
          MathRenderer(
            textPart,
            fontSize: fontSize,
            textColor: textColor,
            selectable: selectable,
          ),
        );
      }

      // Add diagram placeholder
      parts.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Container(
            height: imageHeight,
            width: imageWidth,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Diagram',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  Text(
                    'Coming soon',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      lastIndex = match.end;
    }

    // Add remaining text after last diagram
    if (lastIndex < content.length) {
      final textPart = content.substring(lastIndex);
      parts.add(
        MathRenderer(
          textPart,
          fontSize: fontSize,
          textColor: textColor,
          selectable: selectable,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts,
    );
  }
}

/// A widget that renders a complete question with options
class QuestionRenderer extends StatelessWidget {
  final String question;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String? correctAnswer;
  final String? diagramUrl;
  final bool showAnswer;
  final double fontSize;
  final Color? textColor;

  const QuestionRenderer({
    super.key,
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    this.correctAnswer,
    this.diagramUrl,
    this.showAnswer = false,
    this.fontSize = 16,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final defaultColor = textColor ?? Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question
        ContentRenderer(
          question,
          fontSize: fontSize,
          textColor: defaultColor,
          selectable: true,
        ),
        const SizedBox(height: 12),

        // Diagram if URL provided
        if (diagramUrl != null && diagramUrl!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CachedNetworkImage(
              imageUrl: diagramUrl!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.contain,
              placeholder: (context, url) => Container(
                height: 200,
                color: Colors.grey.shade100,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                height: 200,
                color: Colors.grey.shade100,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Failed to load diagram'),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Options
        _OptionRenderer(letter: 'A', text: optionA, fontSize: fontSize, textColor: defaultColor),
        _OptionRenderer(letter: 'B', text: optionB, fontSize: fontSize, textColor: defaultColor),
        _OptionRenderer(letter: 'C', text: optionC, fontSize: fontSize, textColor: defaultColor),
        _OptionRenderer(letter: 'D', text: optionD, fontSize: fontSize, textColor: defaultColor),

        // Answer (if showing)
        if (showAnswer && correctAnswer != null && correctAnswer!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Answer: ${_getOptionText(correctAnswer!)}',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _getOptionText(String letter) {
    switch (letter.toUpperCase()) {
      case 'A':
        return optionA;
      case 'B':
        return optionB;
      case 'C':
        return optionC;
      case 'D':
        return optionD;
      default:
        return letter;
    }
  }
}

class _OptionRenderer extends StatelessWidget {
  final String letter;
  final String text;
  final double fontSize;
  final Color textColor;

  const _OptionRenderer({
    required this.letter,
    required this.text,
    required this.fontSize,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$letter.',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: fontSize,
                color: textColor,
              ),
            ),
          ),
          Expanded(
            child: MathRenderer(
              text,
              fontSize: fontSize,
              textColor: textColor,
              selectable: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper class for text parsing
class TextSegment {
  final String text;
  final bool isMath;
  final bool isDisplayMath;

  TextSegment(this.text, this.isMath, this.isDisplayMath);
}