import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

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
                    child: GptMarkdown(
                      _showAnswer ? card['answer']! : card['question']!,
                      useDollarSignsForLatex: true,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.6,
                        color: _showAnswer ? Colors.blue.shade900 : const Color(0xFF1A237E),
                        fontWeight: _showAnswer ? FontWeight.normal : FontWeight.w600,
                      ),
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