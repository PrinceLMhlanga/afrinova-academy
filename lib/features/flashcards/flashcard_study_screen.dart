import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:flutter/services.dart';
import '../../widgets/math_renderer.dart';

class FlashcardStudyScreen extends StatefulWidget {
  final List<Map<String, String>> cards;
  final String topicName;

  const FlashcardStudyScreen({
    super.key,
    required this.cards,
    required this.topicName,
  });

  @override
  State<FlashcardStudyScreen> createState() => _FlashcardStudyScreenState();
}

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen> {
  int _currentIndex = 0;
  bool _showAnswer = false;
  int _correct = 0;
  int _reviewed = 0;

  void _markCorrect() {
    setState(() {
      _correct++;
      _reviewed++;
      _nextCard();
    });
  }

  void _markIncorrect() {
    setState(() {
      _reviewed++;
      _nextCard();
    });
  }

  void _nextCard() {
    if (_currentIndex < widget.cards.length - 1) {
      setState(() {
        _currentIndex++;
        _showAnswer = false;
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showAnswer = false;
      });
    }
  }

  
  @override
  Widget build(BuildContext context) {
    if (_currentIndex >= widget.cards.length) {
      return _buildResults();
    }

    final card = widget.cards[_currentIndex];

   

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(widget.topicName),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Progress
          LinearProgressIndicator(
            value: (_currentIndex + 1) / widget.cards.length,
            backgroundColor: Colors.grey.shade200,
            color: Colors.purple,
            minHeight: 3,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Card ${_currentIndex + 1} of ${widget.cards.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                Text('✅ $_correct  ❌ ${_reviewed - _correct}',
                    style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),

          // Flashcard
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showAnswer = !_showAnswer),
              child: Center(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _showAnswer ? Colors.blue.shade50 : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: SingleChildScrollView(
      child: MathRenderer(
  _showAnswer ? card['answer']! : card['question']!,
  fontSize: 18,
  textColor: _showAnswer ? Colors.blue.shade900 : const Color(0xFF1A237E),
  //fontWeight: _showAnswer ? FontWeight.normal : FontWeight.w600,
),

    ),
  

                ),
              ),
            ),
          ),

          // Hint
          if (!_showAnswer)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('👆 Tap to reveal answer', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),

          // Buttons
          if (_showAnswer)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _markIncorrect,
                      icon: const Icon(Icons.close),
                      label: const Text('Still Learning'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _markCorrect,
                      icon: const Icon(Icons.check),
                      label: const Text('Got It!'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Navigation
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                if (_currentIndex > 0)
                  TextButton.icon(
                    onPressed: _prevCard,
                    icon: const Icon(Icons.arrow_back, size: 16),
                    label: const Text('Previous'),
                  ),
                const Spacer(),
                if (_currentIndex < widget.cards.length - 1)
                  TextButton.icon(
                    onPressed: _nextCard,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Skip'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyntaxHighlighter(String? languageName, String codeSnippet) {
  final lang = (languageName ?? 'code').toLowerCase();
  final displayLang = lang.isNotEmpty ? lang[0].toUpperCase() + lang.substring(1) : 'Code';

  return Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(vertical: 12.0),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF282C34), // Matches Dark Atom code theme background
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
        // 🛠️ THE NEW UTILITY HEADER BAR
       // Inside your _buildSyntaxHighlighter Column header row child block:
Container(
  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
  color: const Color(0xFF21252B), 
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      // Language Label Indicator
      Text(
        displayLang,
        style: const TextStyle(
          color: Color(0xFFA6ACCD),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          fontFamily: 'Courier, Courier New, monospace',
        ),
      ),
      
      // ✅ CLEAN DEPLOYMENT: Swapped out the old StatefulBuilder for your new robust widget
      CodeCopyButton(textToCopy: codeSnippet),
    ],
  ),
),

        
        // 💻 NATIVE CODE WORKSPACE PANEL
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

  Widget _buildResults() {
    final percentage = _reviewed > 0 ? (_correct / widget.cards.length * 100).round() : 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Session Complete'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.purple.shade400, Colors.blue.shade400]),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              Text('$_correct / ${widget.cards.length} correct',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              const SizedBox(height: 8),
              Text('$percentage% mastery',
                  style: TextStyle(fontSize: 18, color: percentage >= 70 ? const Color(0xFF4CAF50) : Colors.orange)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
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

        // Write raw code string text directly into native OS clipboard memory buffers
        await Clipboard.setData(ClipboardData(text: widget.textToCopy));

        if (mounted) {
          setState(() => _isCopied = true);

          // Return back to standard copy text display layer layout safely after 2 seconds
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() => _isCopied = false);
            }
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
              _isCopied ? 'Copied!' : 'Copy code',
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
