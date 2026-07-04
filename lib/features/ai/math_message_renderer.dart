import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class MathMessageRenderer extends StatelessWidget {
  final String text;
  final Color textColor;

  const MathMessageRenderer({
    super.key,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final parts = _parseContent(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: parts.map((part) {
        if (part.isCodeBlock) {
          return _buildCodeBlock(part.content);
        } else if (part.isBlockquote) {
          return _buildBlockquote(part.content, context);
        } else if (part.isLatex) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Math.tex(
                part.content,
                textStyle: TextStyle(fontSize: 16, color: textColor),
                mathStyle: MathStyle.display,
              ),
            ),
          );
        } else if (part.isTable) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _buildTable(context, part.content),
          );
        } else if (part.isHeading) {
          return Padding(
            padding: EdgeInsets.only(
              top: part.headingLevel == 1 ? 20 : part.headingLevel == 2 ? 16 : 12, 
              bottom: 6,
            ),
            child: Text(
              part.content,
              style: TextStyle(
                fontSize: part.headingLevel == 1 ? 20 : part.headingLevel == 2 ? 17 : 15,
                fontWeight: part.headingLevel == 1 ? FontWeight.w800 : part.headingLevel == 2 ? FontWeight.w700 : FontWeight.w600,
                color: part.headingLevel == 1 
                    ? const Color(0xFF1A237E) 
                    : part.headingLevel == 2 
                        ? const Color(0xFF283593) 
                        : textColor,
                height: 1.3,
                letterSpacing: -0.3,
              ),
              softWrap: true,
            ),
          );
        } else if (part.isListItem) {
          return Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 3, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: part.isSubItem ? 32 : 24,
                  child: Text(
                    part.listMarker ?? '•',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: part.isSubItem ? Colors.grey.shade600 : textColor,
                      fontSize: part.isSubItem ? 12 : 13,
                    ),
                    textAlign: part.isSubItem ? TextAlign.center : TextAlign.left,
                  ),
                ),
                Expanded(
                  child: _buildRichText(part.content, textColor),
                ),
              ],
            ),
          );
        } else if (part.isHorizontalRule) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.grey.shade300, thickness: 1),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: _buildRichText(part.content, textColor),
          );
        }
      }).toList(),
    );
  }

  // ===== CODE BLOCK =====
  Widget _buildCodeBlock(String code) {
    // Extract language if specified
    String language = '';
    String codeContent = code;
    if (code.startsWith('```')) {
      final firstNewline = code.indexOf('\n');
      if (firstNewline > 3) {
        language = code.substring(3, firstNewline).trim();
        codeContent = code.substring(firstNewline + 1);
      } else {
        codeContent = code.substring(firstNewline + 1);
      }
      // Remove trailing ```
      if (codeContent.endsWith('```')) {
        codeContent = codeContent.substring(0, codeContent.length - 3);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code header bar with dots
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 10, height: 10, decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle)),
                const Spacer(),
                if (language.isNotEmpty)
                  Text(
                    language,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
          // Code content
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              codeContent.trim(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFFD4D4D4),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== BLOCKQUOTE =====
  Widget _buildBlockquote(String text, BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: const Color(0xFF1A237E).withOpacity(0.5), 
            width: 3,
          ),
        ),
        color: const Color(0xFF1A237E).withOpacity(0.03),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: _buildRichText(text, textColor.withOpacity(0.85)),
    );
  }

  // ===== BUILD TABLE =====
  Widget _buildTable(BuildContext context, String tableText) {
    final lines = tableText.trim().split('\n');

    final headers = <String>[];
    final rows = <List<String>>[];
    final alignments = <TextAlign>[];

    for (final line in lines) {
      if (!line.trim().startsWith('|')) continue;

      final cells = _parseTableRow(line);

      final isSeparator = cells.every(
        (c) => RegExp(r'^:?-{3,}:?$').hasMatch(c.trim()),
      );

      if (isSeparator) {
        // Parse alignments from separator
        alignments.clear();
        for (final cell in cells) {
          final trimmed = cell.trim();
          if (trimmed.startsWith(':') && trimmed.endsWith(':')) {
            alignments.add(TextAlign.center);
          } else if (trimmed.endsWith(':')) {
            alignments.add(TextAlign.right);
          } else {
            alignments.add(TextAlign.left);
          }
        }
        continue;
      }

      if (headers.isEmpty) {
        headers.addAll(cells);
      } else {
        rows.add(cells);
      }
    }

    if (headers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
            verticalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
          ),
          columnWidths: {
            for (int i = 0; i < headers.length; i++)
              i: const IntrinsicColumnWidth(),
          },
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.06),
              ),
              children: List.generate(headers.length, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A237E),
                    ),
                    child: _buildRichText(headers[i], const Color(0xFF1A237E)),
                  ),
                );
              }),
            ),
            // Data rows
            ...rows.asMap().entries.map((entry) {
              final rowIndex = entry.key;
              final row = entry.value;
              return TableRow(
                decoration: BoxDecoration(
                  color: rowIndex.isEven ? Colors.white : Colors.grey.shade50,
                ),
                children: List.generate(headers.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Align(
                      alignment: i < alignments.length 
                          ? _alignmentFromTextAlign(alignments[i]) 
                          : Alignment.centerLeft,
                      child: _buildRichText(
                        i < row.length ? row[i] : '',
                        textColor,
                      ),
                    ),
                  );
                }),
              );
            }),
          ],
        ),
      ),
    );
  }

  Alignment _alignmentFromTextAlign(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }

  List<String> _parseTableRow(String line) {
    String trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  // ===== RICH TEXT WITH BOLD + ITALIC + INLINE LATEX + INLINE CODE =====
  Widget _buildRichText(String text, Color color) {
    if (text.isEmpty) return const SizedBox.shrink();
    return _parseInline(text, color, isLineStart: true);
  }

  Widget _parseInline(String text, Color color, {bool inheritedBold = false, bool inheritedItalic = false, bool isLineStart = false}) {
    final spans = <InlineSpan>[];
    int i = 0;

    while (i < text.length) {
      // Check for inline code `code`
      if (text[i] == '`') {
        final end = text.indexOf('`', i + 1);
        if (end != -1) {
          final codeContent = text.substring(i + 1, end);
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                codeContent,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: const Color(0xFFE91E63),
                  fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ));
          i = end + 1;
          continue;
        }
      }

      // Check for **bold** at current position
      if (text.startsWith('**', i)) {
        final end = text.indexOf('**', i + 2);
        if (end != -1) {
          final boldContent = text.substring(i + 2, end);
          spans.add(WidgetSpan(
            child: _parseInline(boldContent, color, inheritedBold: true, inheritedItalic: inheritedItalic),
          ));
          i = end + 2;
          continue;
        }
      }

      // Check for *italic* — but NOT at line start (preserve bullet points)
      if (text[i] == '*' && !isLineStart && (i == 0 || text[i - 1] != '*')) {
        final end = text.indexOf('*', i + 1);
        if (end != -1 && (end == text.length - 1 || text[end + 1] != '*')) {
          final italicContent = text.substring(i + 1, end);
          if (italicContent.isNotEmpty && !italicContent.contains('\n')) {
            spans.add(WidgetSpan(
              child: _parseInline(italicContent, color, inheritedBold: inheritedBold, inheritedItalic: true),
            ));
            i = end + 1;
            continue;
          }
        }
      }

      // Check for $latex$ at current position
      if (text[i] == '\$') {
        final end = text.indexOf('\$', i + 1);
        if (end != -1) {
          final latexContent = text.substring(i + 1, end);
          try {
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Math.tex(
                latexContent.trim(),
                textStyle: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: inheritedItalic ? FontStyle.italic : FontStyle.normal,
                ),
                mathStyle: MathStyle.text,
              ),
            ));
          } catch (_) {
            spans.add(TextSpan(
              text: '\$$latexContent\$',
              style: TextStyle(
                fontSize: 13,
                color: const Color(0xFFE91E63),
                fontStyle: FontStyle.italic,
                fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
              ),
            ));
          }
          i = end + 1;
          continue;
        }
      }

      // Collect normal text until next special character
      int next = text.length;
      for (final char in ['\$', '*', '`']) {
        final idx = text.indexOf(char, i + 1);
        if (idx != -1 && idx < next) next = idx;
      }
      
      if (text.startsWith('**', i)) next = i;
      if (text[i] == '*' && isLineStart) next = i + 1;

      if (next > i) {
        spans.add(TextSpan(
          text: text.substring(i, next),
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: inheritedItalic ? FontStyle.italic : FontStyle.normal,
            color: color,
          ),
        ));
        i = next;
      } else {
        spans.add(TextSpan(
          text: text[i],
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
            fontStyle: inheritedItalic ? FontStyle.italic : FontStyle.normal,
            color: color,
          ),
        ));
        i++;
      }
      
      isLineStart = false;
    }

    if (spans.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: color,
          fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: inheritedItalic ? FontStyle.italic : FontStyle.normal,
        ),
        softWrap: true,
      );
    }

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: color,
          fontWeight: inheritedBold ? FontWeight.bold : FontWeight.normal,
          fontStyle: inheritedItalic ? FontStyle.italic : FontStyle.normal,
        ),
        children: spans,
      ),
      softWrap: true,
    );
  }

  // ===== PARSE CONTENT INTO SEGMENTS =====
  List<_TextPart> _parseContent(String text) {
    final parts = <_TextPart>[];

    // Extract code blocks first
    final codeRegex = RegExp(r'```[a-zA-Z]*\n[\s\S]*?\n```');
    final tableRegex = RegExp(r'(?:^|\n)(\|.+\|\n(?:\|[- :|]+\|\n)?(?:\|.+\|\n?)+)');
    
    // Combine all patterns
    int lastEnd = 0;
    final allMatches = <_MatchInfo>[];
    
    for (final match in codeRegex.allMatches(text)) {
      allMatches.add(_MatchInfo(start: match.start, end: match.end, content: match.group(0)!, type: 'code'));
    }
    for (final match in tableRegex.allMatches(text)) {
      allMatches.add(_MatchInfo(start: match.start, end: match.end, content: match.group(1)!.trim(), type: 'table'));
    }
    
    // Sort by start position
    allMatches.sort((a, b) => a.start.compareTo(b.start));
    
    for (final match in allMatches) {
      if (match.start > lastEnd) {
        _addTextParts(parts, text.substring(lastEnd, match.start));
      }
      if (match.type == 'code') {
        parts.add(_TextPart(content: match.content, isCodeBlock: true));
      } else if (match.type == 'table') {
        parts.add(_TextPart(content: match.content, isTable: true));
      }
      lastEnd = match.end;
    }
    
    if (lastEnd < text.length) {
      _addTextParts(parts, text.substring(lastEnd));
    }

    return parts;
  }

  void _addTextParts(List<_TextPart> parts, String text) {
    final lines = text.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Horizontal rule
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        parts.add(_TextPart(content: '', isHorizontalRule: true));
        continue;
      }

      // Blockquote
      if (trimmed.startsWith('> ')) {
        final quoteText = trimmed.substring(2);
        parts.add(_TextPart(content: quoteText, isBlockquote: true));
        continue;
      }

      // Check for headings (###, ##, #)
      if (trimmed.startsWith('### ')) {
        parts.add(_TextPart(content: trimmed.substring(4).trim(), isHeading: true, headingLevel: 3));
        continue;
      } else if (trimmed.startsWith('## ')) {
        parts.add(_TextPart(content: trimmed.substring(3).trim(), isHeading: true, headingLevel: 2));
        continue;
      } else if (trimmed.startsWith('# ')) {
        parts.add(_TextPart(content: trimmed.substring(2).trim(), isHeading: true, headingLevel: 1));
        continue;
      }

      // Check for sub-items (indented with spaces then - or *)
      final subItemMatch = RegExp(r'^\s{2,}([-*])\s+(.+)$').firstMatch(trimmed);
      if (subItemMatch != null) {
        parts.add(_TextPart(
          content: subItemMatch.group(2)!.trim(),
          isListItem: true,
          isSubItem: true,
          listMarker: subItemMatch.group(1),
        ));
        continue;
      }

      // Check for list items
      final listMatch = RegExp(r'^((?:\d+[.)]|[a-zA-Z][.)]|[-*•])\s+)(.+)$').firstMatch(trimmed);
      if (listMatch != null) {
        final marker = listMatch.group(1)!.trim();
        final content = listMatch.group(2)!.trim();
        parts.add(_TextPart(
          content: content,
          isListItem: true,
          listMarker: marker,
        ));
        continue;
      }

      // Parse for block LaTeX
      final latexParts = _parseBlockLatex(trimmed);
      parts.addAll(latexParts);
    }
  }

  List<_TextPart> _parseBlockLatex(String text) {
    final parts = <_TextPart>[];
    final regex = RegExp(r'\$\$(.*?)\$\$');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        parts.add(_TextPart(content: text.substring(lastEnd, match.start)));
      }
      parts.add(_TextPart(content: match.group(1)!.trim(), isLatex: true));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      parts.add(_TextPart(content: text.substring(lastEnd)));
    }

    return parts.isEmpty
        ? [_TextPart(content: text)]
        : parts;
  }
}

class _MatchInfo {
  final int start;
  final int end;
  final String content;
  final String type;

  _MatchInfo({required this.start, required this.end, required this.content, required this.type});
}

class _TextPart {
  final String content;
  final bool isLatex;
  final bool isTable;
  final bool isHeading;
  final bool isListItem;
  final bool isSubItem;
  final bool isCodeBlock;
  final bool isBlockquote;
  final bool isHorizontalRule;
  final String? listMarker;
  final int headingLevel;

  _TextPart({
    required this.content,
    this.isLatex = false,
    this.isTable = false,
    this.isHeading = false,
    this.isListItem = false,
    this.isSubItem = false,
    this.isCodeBlock = false,
    this.isBlockquote = false,
    this.isHorizontalRule = false,
    this.listMarker,
    this.headingLevel = 1,
  });
}