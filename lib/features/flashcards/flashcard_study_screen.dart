import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:flutter_highlighter/flutter_highlighter.dart';
import 'package:flutter_highlighter/themes/atom-one-dark.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;


 enum _SlideDirection { left, right }
 enum _CardState {
  mastered,
  struggling,
}
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

class _FlashcardStudyScreenState extends State<FlashcardStudyScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _showAnswer = false;
  int _correct = 0;
  int _reviewed = 0;

  // Animation controllers
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  bool _showResultsScreen = false;

  final Map<int, _CardState> _cardStates = {};
final Set<int> _masteredCards = {};
final Set<int> _strugglingCards = {};
 

  


// Update initState to use a more flexible animation setup
@override
void initState() {
    super.initState();
    
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    // Default: slide out to left (going forward)
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0.0),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));
  }

  // New method to handle animated transitions
  void _animateToCard(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= widget.cards.length) return;
    if (targetIndex == _currentIndex) return;
    
    final goingForward = targetIndex > _currentIndex;
    
    // Configure animation direction
    setState(() {
      _slideAnimation = Tween<Offset>(
        begin: Offset.zero,
        end: goingForward 
            ? const Offset(-1.5, 0.0)  // Slide out left
            : const Offset(1.5, 0.0),   // Slide out right
      ).animate(CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeInOut,
      ));
    });
    
    _slideController.forward().then((_) {
      if (mounted) {
        setState(() {
          _currentIndex = targetIndex;
          _showAnswer = false;
          _flipController.reset();
          _slideController.reset();
        });
      }
    });
  }

  void _markCorrect() {
    final currentCard = _currentIndex;
    
    // Only count if not already mastered
    if (!_masteredCards.contains(currentCard)) {
      setState(() {
        _correct++;
        _reviewed++;
        _masteredCards.add(currentCard);
        _strugglingCards.remove(currentCard);
        _cardStates[currentCard] = _CardState.mastered;
      });
    }

    
    
    // ✅ Check if ALL cards are mastered
    if (_masteredCards.length >= widget.cards.length) {
      _showResults();
      return;
    }

    bool allReviewed = true;
    for (int i = 0; i < widget.cards.length; i++) {
      if (!_masteredCards.contains(i) && !_strugglingCards.contains(i)) {
        allReviewed = false;
        break;
      }
    }
    
    if (allReviewed) {
      // Optional: Show a prompt asking if they want to see results
      _showCompletionPrompt();
      return;
    }
    
    // ✅ Find next unmastered card
    _goToNextUnmasteredCard();
  }

  void _markIncorrect() {
    final currentCard = _currentIndex;
    
    // If it was mastered, remove mastery
    if (_masteredCards.contains(currentCard)) {
      setState(() {
        _correct--;
        _masteredCards.remove(currentCard);
        _strugglingCards.add(currentCard);
        _cardStates[currentCard] = _CardState.struggling;
      });
    } else {
      setState(() {
        _reviewed++;
        _strugglingCards.add(currentCard);
        _cardStates[currentCard] = _CardState.struggling;
      });
    }
    bool allReviewed = true;
    for (int i = 0; i < widget.cards.length; i++) {
      if (!_masteredCards.contains(i) && !_strugglingCards.contains(i)) {
        allReviewed = false;
        break;
      }
    }
    
    if (allReviewed) {
      // Optional: Show a prompt asking if they want to see results
      _showCompletionPrompt();
      return;
    }
    
    // Stay on same card, just flip back
    setState(() {
      _showAnswer = false;
      _flipController.reverse();
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _masteredCards.contains(currentCard) 
              ? 'Mastery lost - keep studying! 💪' 
              : 'Card marked for review - study it again! 📚'
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showCompletionPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('All Cards Reviewed! 🎉'),
        content: Text(
          'Mastered: ${_masteredCards.length}/${widget.cards.length}\n'
          'Still struggling: ${_strugglingCards.length}/${widget.cards.length}\n\n'
          'Would you like to see your results or continue practicing?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Stay on current card
              setState(() {
                _showAnswer = false;
                _flipController.reverse();
              });
            },
            child: const Text('Continue'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showResults();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
            ),
            child: const Text('See Results'),
          ),
        ],
      ),
    );
  }

  // ✅ New method: Find and go to next unmastered card
  void _goToNextUnmasteredCard() {
    // Start searching from next card
    for (int i = _currentIndex + 1; i < widget.cards.length; i++) {
      if (!_masteredCards.contains(i)) {
        _animateOutToCard(i);
        return;
      }
    }
    
    // If no unmastered cards after current, wrap around to beginning
    for (int i = 0; i < _currentIndex; i++) {
      if (!_masteredCards.contains(i)) {
        _animateOutToCard(i);
        return;
      }
    }
    
    // Should never reach here if we checked mastery count, but just in case
    _showResults();
  }

  // ✅ New method: Animate to specific card
  void _animateOutToCard(int targetIndex) {
    _slideController.forward().then((_) {
      if (mounted) {
        setState(() {
          _currentIndex = targetIndex;
          _showAnswer = false;
          _flipController.reset();
          _slideController.reset();
        });
      }
    });
  }

  // ✅ Keep _animateOut for simple next card
  void _animateOut() {
    _slideController.forward().then((_) {
      if (mounted) {
        setState(() {
          _currentIndex++;
          _showAnswer = false;
          _flipController.reset();
          _slideController.reset();
        });
      }
    });
  }

  void _showResults() {
    setState(() {
      _showResultsScreen = true;
    });
  }

 

  // Keep your existing nextCard and prevCard as they are
  void _nextCard() {
    if (_currentIndex < widget.cards.length - 1) {
      setState(() {
        _currentIndex++;
        _showAnswer = false;
        _flipController.reset();
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showAnswer = false;
        _flipController.reset();
      });
    }
  }
 

  void _flipCard() {
    if (_showAnswer) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() {
      _showAnswer = !_showAnswer;
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
    if (_showResultsScreen) {
      return _buildResults();
    }

    final card = widget.cards[_currentIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(widget.topicName),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        // Add in your AppBar actions
actions: [
  // Show results manually
  TextButton.icon(
    onPressed: () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End Session?'),
          content: Text(
            'You\'ve mastered ${_masteredCards.length} of ${widget.cards.length} cards.\n\n'
            '${widget.cards.length - _masteredCards.length} cards still need review.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Continue Studying'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showResults();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
              ),
              child: const Text('See Results'),
            ),
          ],
        ),
      );
    },
    icon: const Icon(Icons.assessment, size: 16, color: Colors.white),
    label: const Text('Results', style: TextStyle(color: Colors.white, fontSize: 12)),
  ),
  IconButton(
    icon: const Icon(Icons.info_outline),
    onPressed: () => _showStudyTips(context),
  ),
],
      ),
      body: Column(
        children: [
          // Progress section
          _buildProgressSection(),
          
          // ✅ NEW: Navigation bar
          _buildNavigationBar(),
          
          
          // Card section
Expanded(
    child: SlideTransition(
        position: _slideAnimation,
        child: _buildSwipeableCard(card),  // ✅ Now supports swipe + tap
    ),
),

          // Action buttons
          if (_showAnswer)
            _buildActionButtons(),
        ],
      ),
    );
  }
  Widget _buildNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Previous button - always use animation
          TextButton.icon(
            onPressed: _currentIndex > 0 
                ? () => _animateToCard(_currentIndex - 1)  // ✅ Use animation
                : null,
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            label: const Text('Previous'),
            style: TextButton.styleFrom(
              foregroundColor: _currentIndex > 0 
                  ? const Color(0xFF1A237E) 
                  : Colors.grey.shade400,
            ),
          ),
          
          // Card counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.style, size: 16, color: Color(0xFF1A237E)),
                const SizedBox(width: 8),
                Text(
                  '${_currentIndex + 1} / ${widget.cards.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ],
            ),
          ),
          
          // Skip/Next button - always use animation
          TextButton.icon(
            onPressed: _currentIndex < widget.cards.length - 1 
                ? () => _animateToCard(_currentIndex + 1)  // ✅ Use animation
                : null,
            icon: const Icon(Icons.arrow_forward_ios, size: 16),
            label: Text(_currentIndex < widget.cards.length - 1 ? 'Skip' : 'Last'),
            style: TextButton.styleFrom(
              foregroundColor: _currentIndex < widget.cards.length - 1 
                  ? const Color(0xFF1A237E) 
                  : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  // Add this in initState or as a helper method
Widget _buildSwipeableCard(Map<String, String> card) {
    return GestureDetector(
      onTap: _flipCard,
      onHorizontalDragEnd: (details) {
        // Swipe left = next card
        if (details.primaryVelocity! < -300 && _currentIndex < widget.cards.length - 1) {
          _animateToCard(_currentIndex + 1);
        }
        // Swipe right = previous card
        else if (details.primaryVelocity! > 300 && _currentIndex > 0) {
          _animateToCard(_currentIndex - 1);
        }
      },
      child: _buildFlipCard(card),
    );
  }

 Widget _buildProgressSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Progress
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_masteredCards.length} of ${widget.cards.length} mastered',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 200,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: widget.cards.length > 0 
                          ? _masteredCards.length / widget.cards.length 
                          : 0,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Score chips
              Row(
                children: [
                  _buildScoreChip(
                    icon: Icons.check_circle,
                    count: _masteredCards.length,
                    color: const Color(0xFF4CAF50),
                  ),
                  const SizedBox(width: 12),
                  _buildScoreChip(
                    icon: Icons.warning_rounded,
                    count: _strugglingCards.length,
                    color: const Color(0xFFFF9800),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Mastery level
          LinearProgressIndicator(
            value: widget.cards.length > 0 ? _masteredCards.length / widget.cards.length : 0,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF7C4DFF)),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${widget.cards.length > 0 ? (_masteredCards.length / widget.cards.length * 100).round() : 0}% mastery',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
          
          // Show card state indicator if applicable
          if (_cardStates.containsKey(_currentIndex))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _buildCardStateIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildCardStateIndicator() {
    final state = _cardStates[_currentIndex];
    if (state == null) return const SizedBox.shrink();
    
    IconData icon;
    Color color;
    String label;
    
    switch (state) {
      case _CardState.mastered:
        icon = Icons.check_circle;
        color = const Color(0xFF4CAF50);
        label = 'Mastered';
        break;
      case _CardState.struggling:
        icon = Icons.warning_rounded;
        color = const Color(0xFFFF9800);
        label = 'Needs Review';
        break;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreChip({
    required IconData icon,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlipCard(Map<String, String> card) {
    return GestureDetector(
      onTap: _flipCard,
      child: AnimatedBuilder(
        animation: _flipAnimation,
        builder: (context, child) {
          final isFrontVisible = _flipAnimation.value < 0.5;
          final angle = _flipAnimation.value * math.pi;
          
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // Perspective
              ..rotateY(angle),
            child: isFrontVisible
                ? _buildCardFace(
                    content: card['question']!,
                    isQuestion: true,
                    card: card,
                  )
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: _buildCardFace(
                      content: card['answer']!,
                      isQuestion: false,
                      card: card,
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCardFace({
    required String content,
    required bool isQuestion,
    required Map<String, String> card,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            gradient: isQuestion
                ? const LinearGradient(
                    colors: [Color(0xFFFFFFFF), Color(0xFFF8F9FA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : const LinearGradient(
                    colors: [Color(0xFFF3E5F5), Color(0xFFE8EAF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: isQuestion
                    ? Colors.black.withOpacity(0.08)
                    : Colors.purple.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: isQuestion
                    ? Colors.black.withOpacity(0.04)
                    : Colors.blue.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative elements
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isQuestion
                        ? const Color(0xFF1A237E).withOpacity(0.03)
                        : Colors.purple.withOpacity(0.05),
                  ),
                ),
              ),
              Positioned(
                bottom: -30,
                left: -30,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isQuestion
                        ? Colors.blue.withOpacity(0.03)
                        : Colors.deepPurple.withOpacity(0.05),
                  ),
                ),
              ),

              // Card content
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Card type badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isQuestion
                                ? const Color(0xFF1A237E).withOpacity(0.08)
                                : Colors.purple.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isQuestion
                                    ? Icons.help_outline
                                    : Icons.lightbulb_outline,
                                size: 16,
                                color: isQuestion
                                    ? const Color(0xFF1A237E)
                                    : Colors.purple,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isQuestion ? 'Question' : 'Answer',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isQuestion
                                      ? const Color(0xFF1A237E)
                                      : Colors.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        // Difficulty indicator (optional)
                        if (card.containsKey('difficulty'))
                          Row(
                            children: List.generate(
                              int.tryParse(card['difficulty'] ?? '1') ?? 1,
                              (index) => const Icon(
                                Icons.star,
                                size: 14,
                                color: Color(0xFFFFD700),
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: GptMarkdown(
                          content,
                          useDollarSignsForLatex: true,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.6,
                            color: isQuestion
                                ? const Color(0xFF1A237E)
                                : const Color(0xFF4A148C),
                            fontWeight: isQuestion
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          codeBuilder: (context, name, code, closed) {
                            return _buildSyntaxHighlighter(name, code);
                          },
                          latexBuilder: (context, texString, textStyle, isInline) {
                            if (isInline) {
                              return GptMarkdown(
                                '\$$texString\$',
                                useDollarSignsForLatex: true,
                                style: textStyle ?? TextStyle(
                                  fontSize: 17,
                                  color: isQuestion
                                      ? const Color(0xFF1A237E)
                                      : const Color(0xFF4A148C),
                                ),
                              );
                            }

                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isQuestion
                                      ? Colors.blue.shade100
                                      : Colors.purple.shade100,
                                ),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: GptMarkdown(
                                  '\$\$${texString}\$\$',
                                  useDollarSignsForLatex: true,
                                  style: textStyle ?? TextStyle(
                                    fontSize: 17,
                                    color: isQuestion
                                        ? const Color(0xFF1A237E)
                                        : const Color(0xFF4A148C),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Tap hint
                    if (isQuestion)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app,
                              size: 16,
                              color: Colors.grey,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Tap to reveal answer',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _markIncorrect,
                icon: const Icon(Icons.refresh),
                label: const Text('Study Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFFF6B6B),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFFF6B6B), width: 2),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _markCorrect,
                icon: const Icon(Icons.check_circle),
                label: const Text('I Know This!'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  shadowColor: const Color(0xFF4CAF50).withOpacity(0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStudyTips(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // ✅ Allow full height
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6, // ✅ Limit height
        ),
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView( // ✅ Make scrollable
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📚 Study Tips',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 16),
              _buildTip(
                icon: Icons.touch_app,
                text: 'Tap cards to flip them and reveal answers',
              ),
              _buildTip(
                icon: Icons.swipe,
                text: 'Swipe or use buttons to navigate between cards',
              ),
              _buildTip(
                icon: Icons.repeat,
                text: 'Mark cards honestly to track your progress',
              ),
              _buildTip(
                icon: Icons.star,
                text: 'Review difficult cards more frequently',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Got it!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTip({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF1A237E)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, color: Color(0xFF666666)),
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
      margin: const EdgeInsets.symmetric(vertical: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF282C34),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            padding: const EdgeInsets.all(16),
            textStyle: const TextStyle(
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final percentage = _reviewed > 0 ? (_correct / widget.cards.length * 100).round() : 0;
    final isGreat = percentage >= 80;
    final isGood = percentage >= 60 && percentage < 80;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Session Complete! 🎉'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated celebration icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isGreat
                          ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                          : isGood
                              ? [Colors.orange.shade400, Colors.amber.shade400]
                              : [Colors.purple.shade400, Colors.blue.shade400],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isGreat
                                ? const Color(0xFF4CAF50)
                                : isGood
                                    ? Colors.orange
                                    : Colors.purple)
                            .withOpacity(0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    isGreat
                        ? Icons.emoji_events
                        : isGood
                            ? Icons.thumb_up
                            : Icons.school,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Results text
              Text(
                isGreat
                    ? 'Excellent Work!'
                    : isGood
                        ? 'Good Progress!'
                        : 'Keep Practicing!',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_correct of ${widget.cards.length} cards mastered',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Stats cards
              // Replace the stats cards section with this:
Row(
    children: [
      Expanded(
        child: _buildStatCard(
          icon: Icons.check_circle,
          value: '${_masteredCards.length}',
          label: 'Mastered',
          color: const Color(0xFF4CAF50),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildStatCard(
          icon: Icons.warning_rounded,
          value: '${_strugglingCards.length}',
          label: 'Need Review',
          color: const Color(0xFFFF9800),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildStatCard(
          icon: Icons.trending_up,
          value: '${widget.cards.length > 0 ? (_masteredCards.length / widget.cards.length * 100).round() : 0}%',
          label: 'Score',
          color: const Color(0xFF7C4DFF),
        ),
      ),
    ],
  ),

// Also update the text below the title
Text(
    '${_masteredCards.length} of ${widget.cards.length} cards mastered',
    style: TextStyle(
      fontSize: 16,
      color: Colors.grey.shade600,
    ),
  ),

              const SizedBox(height: 32),
              
              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Topics'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () {
        setState(() {
          _currentIndex = 0;  // ✅ Reset to first card
          _showAnswer = false;
          _correct = 0;
          _reviewed = 0;
          _showResultsScreen = false;  // ✅ Back to study mode
          _masteredCards.clear();
          _strugglingCards.clear();
          _cardStates.clear();
          _flipController.reset();
          _slideController.reset();
        });
      },
      icon: const Icon(Icons.replay),
      label: const Text('Study Again'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1A237E),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        side: const BorderSide(color: Color(0xFF1A237E), width: 2),
      ),
    ),
  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
        await Clipboard.setData(ClipboardData(text: widget.textToCopy));
        if (mounted) {
          setState(() => _isCopied = true);
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _isCopied = false);
          });
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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