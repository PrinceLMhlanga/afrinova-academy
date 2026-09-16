import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';

/// Syntax-highlighted code block with copy button.
class CodeBlockWidget extends StatelessWidget {
  final String? languageName;
  final String codeSnippet;

  const CodeBlockWidget({
    super.key,
    required this.languageName,
    required this.codeSnippet,
  });

  @override
  Widget build(BuildContext context) {
    final lang = (languageName ?? 'code').toLowerCase();
    final displayLang = lang.isNotEmpty
        ? lang[0].toUpperCase() + lang.substring(1)
        : 'Code';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF282C34),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            color: const Color(0xFF21252B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  displayLang,
                  style: const TextStyle(
                    color: Color(0xFFA6ACCD),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier, Courier New, monospace',
                  ),
                ),
                CodeCopyButton(textToCopy: codeSnippet),
              ],
            ),
          ),
          HighlightView(
            codeSnippet.trim(),
            language: lang,
            theme: atomOneDarkTheme,
            padding: const EdgeInsets.all(16.0),
            textStyle: const TextStyle(
              fontFamily: 'Courier, Courier New, monospace, RobotoMono',
              fontSize: 14.5,
              height: 1.5,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Copy button for code blocks.
class CodeCopyButton extends StatefulWidget {
  final String textToCopy;
  const CodeCopyButton({super.key, required this.textToCopy});

  @override
  State<CodeCopyButton> createState() => _CodeCopyButtonState();
}

class _CodeCopyButtonState extends State<CodeCopyButton> {
  bool _isCopied = false;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        if (_isCopied) return;
        await Clipboard.setData(ClipboardData(text: widget.textToCopy));
        if (mounted) {
          setState(() => _isCopied = true);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _isCopied = false);
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isCopied ? Icons.check_circle_rounded : Icons.copy_rounded,
              size: 15,
              color: _isCopied ? Colors.green : const Color(0xFFA6ACCD),
            ),
            const SizedBox(width: 6),
            Text(
              _isCopied ? 'Copied!' : 'Copy',
              style: TextStyle(
                color: _isCopied ? Colors.green : const Color(0xFFA6ACCD),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}