import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../core/auth_service.dart';

class QuestionBankEntryScreen extends StatefulWidget {
  const QuestionBankEntryScreen({super.key});

  @override
  State<QuestionBankEntryScreen> createState() => _QuestionBankEntryScreenState();
}

class _QuestionBankEntryScreenState extends State<QuestionBankEntryScreen> {
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final _textController = TextEditingController();

  // Filters
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _levels = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedSubjectId;
  String? _selectedLevelId;
  String? _selectedTopicId;
  

  // Parsed questions
  List<_ParsedQuestion> _parsedQuestions = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isExpanded = false;
  String _parseError = '';

  @override
  void initState() {
    super.initState();
    _loadData();
    _textController.addListener(() => setState(() {}));
  }

  Future<void> _loadData() async {
    try {
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name', ascending: true);

      final levels = await Supabase.instance.client
          .from('levels')
          .select()
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _levels = List<Map<String, dynamic>>.from(levels);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopics(String subjectId) async {
    try {
      final response = await Supabase.instance.client
          .from('topics')
          .select()
          .eq('subject_id', subjectId)
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() => _topics = List<Map<String, dynamic>>.from(response));
      }
    } catch (e) {
      debugPrint('Error loading topics: $e');
    }
  }

  void _parseQuestions() {
    String text = _textController.text.trim();
    setState(() => _parseError = '');

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste questions first'), backgroundColor: Colors.red),
      );
      return;
    }

    // Remove code block markers if present
    text = _removeCodeBlockMarkers(text);

    final parsed = QuestionParser.parseOutput(text);

    if (parsed.isEmpty) {
      setState(() => _parseError = 'No questions found. Check format: Q: ...\nA: ...\nB: ...\nC: ...\nD: ...\nAnswer: X');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('No questions parsed! Check format.'), backgroundColor: Colors.orange),

      );
      return;
    }

    // Check for questions without answers
    final missingAnswers = parsed.where((q) => q.correctAnswer.isEmpty).toList();
    if (missingAnswers.isNotEmpty) {
      setState(() => _parseError = '${missingAnswers.length} question(s) missing "Answer:" line');
    }

    setState(() {
      _parsedQuestions = parsed.map((q) => _ParsedQuestion(
        question: q.question,
        optionA: q.optionA,
        optionB: q.optionB,
        optionC: q.optionC,
        optionD: q.optionD,
        correctAnswer: q.correctAnswer,
        difficulty: 'medium', // Default, will be overwritten per question
      )).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_parsedQuestions.length} questions parsed! ${missingAnswers.isNotEmpty ? "⚠️ ${missingAnswers.length} missing answers" : "✅"}'),
        backgroundColor: missingAnswers.isNotEmpty ? Colors.orange : const Color(0xFF4CAF50),
      ),
    );
  }

  String _removeCodeBlockMarkers(String text) {
    // Remove ``` at start and end
    text = text.replaceAll(RegExp(r'^```\s*\n?'), '');
    text = text.replaceAll(RegExp(r'\n?```\s*$'), '');
    // Remove language specifiers like ```latex or ```text
    text = text.replaceAll(RegExp(r'^```[a-zA-Z]*\s*\n'), '');
    return text.trim();
  }

  Future<void> _pickDiagram(int index) async {
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (image == null) return;

      final bytes = await image.readAsBytes();
      final userId = _authService.currentUserId ?? 'admin';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.png';
      final filePath = 'question-bank/$userId/$fileName';

      await Supabase.instance.client
          .storage
          .from('resources')
          .uploadBinary(filePath, Uint8List.fromList(bytes));

      final url = Supabase.instance.client
          .storage
          .from('resources')
          .getPublicUrl(filePath);

      setState(() {
        _parsedQuestions[index].diagramUrl = url;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading diagram: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveAll() async {
    if (_parsedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No questions to save'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_selectedSubjectId == null || _selectedLevelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select subject and level'), backgroundColor: Colors.red),
      );
      return;
    }

    // Check for missing answers before saving
    final missingAnswers = _parsedQuestions.where((q) => q.correctAnswer.isEmpty).toList();
    if (missingAnswers.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Missing Answers'),
          content: Text('${missingAnswers.length} question(s) have no correct answer selected. Save anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Anyway')),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId;
      int saved = 0;

      for (final q in _parsedQuestions) {
        if (q.question.isEmpty) continue;

        await Supabase.instance.client.from('question_bank').insert({
          'subject_id': _selectedSubjectId,
          'level_id': _selectedLevelId,
          'topic_id': _selectedTopicId,
          'question_text': q.question,
          'option_a': q.optionA,
          'option_b': q.optionB,
          'option_c': q.optionC,
          'option_d': q.optionD,
          'correct_answer': q.correctAnswer,
          'difficulty': q.difficulty,
          'diagram_url': q.diagramUrl,
          'created_by': userId,
          'created_at': DateTime.now().toIso8601String(),
        });
        saved++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$saved questions saved! ✅'), backgroundColor: const Color(0xFF4CAF50)),
        );
        _textController.clear();
        setState(() { _parsedQuestions.clear(); _isExpanded = false; _parseError = ''; });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Bank'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          if (_parsedQuestions.isNotEmpty)
            TextButton.icon(
              onPressed: _isSaving ? null : _saveAll,
              icon: const Icon(Icons.save, color: Colors.white, size: 18),
              label: Text('Save ${_parsedQuestions.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Column(
              children: [
                // Filters
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedSubjectId,
                          decoration: _dropdownDecoration('Subject'),
                          items: _subjects.map((s) => DropdownMenuItem<String>(
                            value: s['id'] as String, child: Text(s['name'] ?? '', style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) {
                            setState(() { _selectedSubjectId = v; _selectedTopicId = null; });
                            if (v != null) _loadTopics(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedLevelId,
                          decoration: _dropdownDecoration('Level'),
                          items: _levels.map((l) => DropdownMenuItem<String>(
                            value: l['id'] as String, child: Text(l['name'] ?? '', style: const TextStyle(fontSize: 13)),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedLevelId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedTopicId,
                          decoration: _dropdownDecoration('Topic'),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('None', style: TextStyle(fontSize: 13))),
                            ..._topics.map((t) => DropdownMenuItem<String>(
                              value: t['id'] as String, child: Text(t['name'] ?? '', style: const TextStyle(fontSize: 13)),
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedTopicId = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Text area + controls
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Difficulty + Parse
                      // Parse button only
Row(
  children: [
    const Spacer(),
    ElevatedButton.icon(
      onPressed: _parseQuestions,
      icon: const Icon(Icons.auto_fix_high, size: 18),
      label: const Text('Parse Questions'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF9800),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    ),
  ],
),
                      const SizedBox(height: 12),

                      // Error message if any
                      if (_parseError.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_parseError, style: const TextStyle(fontSize: 12, color: Colors.orange))),
                            ],
                          ),
                        ),

                      // Expandable text field
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            // Toolbar
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.paste, size: 14, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  const Text('Paste questions here', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                  const Spacer(),
                                  // Clear button
                                  if (_textController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => _textController.clear(),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        margin: const EdgeInsets.only(right: 8),
                                        child: const Icon(Icons.clear, size: 14, color: Colors.red),
                                      ),
                                    ),
                                  GestureDetector(
                                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Icon(
                                        _isExpanded ? Icons.zoom_in_map : Icons.zoom_out_map,
                                        size: 16, color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            // Text field
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: _isExpanded 
                                  ? MediaQuery.of(context).size.height * 0.6 
                                  : _textController.text.isNotEmpty ? 250 : 150,
                              child: TextFormField(
                                controller: _textController,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                decoration: const InputDecoration(
                                  hintText: 'Q: What is force?\nA: Push or pull\nB: Energy\nC: Power\nD: Work\nAnswer: A\n\nQ: Next question...',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(14),
                                ),
                                style: const TextStyle(fontSize: 13, fontFamily: 'monospace', height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Stats bar
                      if (_parsedQuestions.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A237E).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text('${_parsedQuestions.length} Questions',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                              const Spacer(),
                              // Count missing answers
                              if (_parsedQuestions.where((q) => q.correctAnswer.isEmpty).isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '⚠️ ${_parsedQuestions.where((q) => q.correctAnswer.isEmpty).length} missing',
                                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => setState(() => _parsedQuestions.clear()),
                                child: const Text('Clear All', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._parsedQuestions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final q = entry.value;
                          return _QuestionCard(
                            index: index + 1,
                            question: q,
                            onCorrectChanged: (v) => setState(() => _parsedQuestions[index].correctAnswer = v),
                            onDifficultyChanged: (v) => setState(() => _parsedQuestions[index].difficulty = v),
                            onAddDiagram: () => _pickDiagram(index),
                            onRemoveDiagram: () => setState(() => _parsedQuestions[index].diagramUrl = null),
                            onRemove: () => setState(() => _parsedQuestions.removeAt(index)),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

// ===== QUESTION CARD =====
class _QuestionCard extends StatelessWidget {
  final int index;
  final _ParsedQuestion question;
  final ValueChanged<String> onCorrectChanged;
  final ValueChanged<String> onDifficultyChanged; // NEW
  final VoidCallback onAddDiagram;
  final VoidCallback onRemoveDiagram;
  final VoidCallback onRemove;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.onCorrectChanged,
    required this.onDifficultyChanged, // NEW

    required this.onAddDiagram,
    required this.onRemoveDiagram,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasMissingAnswer = question.correctAnswer.isEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: hasMissingAnswer ? BorderSide(color: Colors.orange.shade300, width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasMissingAnswer ? Colors.orange.withOpacity(0.15) : const Color(0xFF1A237E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Q$index',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: hasMissingAnswer ? Colors.orange : const Color(0xFF1A237E),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (hasMissingAnswer)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('Select answer', style: TextStyle(fontSize: 10, color: Colors.orange)),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.close, size: 16, color: Colors.red),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Question
            Text(
              question.question,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 10),

            // Options
            _OptionLine(letter: 'A', text: question.optionA),
            _OptionLine(letter: 'B', text: question.optionB),
            _OptionLine(letter: 'C', text: question.optionC),
            _OptionLine(letter: 'D', text: question.optionD),
            const SizedBox(height: 12),

            // Diagram
            if (question.diagramUrl != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Diagram attached',
                        style: const TextStyle(fontSize: 12, color: Colors.green),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: onRemoveDiagram,
                      child: const Icon(Icons.close, size: 14, color: Colors.red),
                    ),
                  ],
                ),
              ),

            // Correct answer + Diagram button
            // Correct answer + Difficulty + Diagram button
Row(
  children: [
    Expanded(
      flex: 2,
      child: DropdownButtonFormField<String>(
        value: question.correctAnswer.isNotEmpty ? question.correctAnswer : null,
        decoration: InputDecoration(
          labelText: 'Correct Answer',
          labelStyle: TextStyle(
            color: hasMissingAnswer ? Colors.orange : Colors.grey.shade600,
            fontSize: 12,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: ['A', 'B', 'C', 'D'].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
        onChanged: (v) => onCorrectChanged(v ?? ''),
      ),
    ),
    const SizedBox(width: 8),
    Expanded(
      flex: 1,
      child: DropdownButtonFormField<String>(
        value: question.difficulty,
        decoration:  InputDecoration(
          labelText: 'Difficulty',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: const [
          DropdownMenuItem(value: 'easy', child: Text('Easy', style: TextStyle(fontSize: 12))),
          DropdownMenuItem(value: 'medium', child: Text('Medium', style: TextStyle(fontSize: 12))),
          DropdownMenuItem(value: 'hard', child: Text('Hard', style: TextStyle(fontSize: 12))),
        ],
        onChanged: (v) => onDifficultyChanged(v ?? 'medium'),
      ),
    ),
    const SizedBox(width: 8),
    GestureDetector(
      onTap: onAddDiagram,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: question.diagramUrl != null ? Colors.green.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: question.diagramUrl != null ? Colors.green : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate,
              size: 18,
              color: question.diagramUrl != null ? Colors.green : Colors.grey.shade600,
            ),
            const SizedBox(width: 4),
            Text(
              'Diagram',
              style: TextStyle(
                fontSize: 12,
                color: question.diagramUrl != null ? Colors.green : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    ),
  ],
),
          ],
        ),
      ),
    );
  }
}

class _OptionLine extends StatelessWidget {
  final String letter;
  final String text;
  const _OptionLine({required this.letter, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$letter.',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1A237E)),
            ),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

// ===== MODELS & PARSER =====
class _ParsedQuestion {
  String question;
  String optionA;
  String optionB;
  String optionC;
  String optionD;
  String correctAnswer;
  String difficulty;
  String? diagramUrl;

  _ParsedQuestion({
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctAnswer,
    required this.difficulty,
    this.diagramUrl,
  });
}

class QuestionParser {
  static List<QuestionBankEntry> parseOutput(String text) {
    final entries = <QuestionBankEntry>[];
    
    // Split by Q: at start of line or Question: at start of line
    final blocks = text.split(RegExp(r'(?=^Q:|^Question:)', multiLine: true));
    
    for (final block in blocks) {
      final trimmedBlock = block.trim();
      if (trimmedBlock.isEmpty) continue;
      
      // Skip if it's just whitespace or doesn't start with Q
      if (!trimmedBlock.startsWith(RegExp(r'^Q:|^Question:', caseSensitive: false))) continue;
      
      final lines = trimmedBlock.split('\n');
      String question = '';
      String optionA = '';
      String optionB = '';
      String optionC = '';
      String optionD = '';
      String correctAnswer = '';
      
      for (String line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        
        // Remove any leading bullet points or numbering
        String cleanLine = trimmed.replaceFirst(RegExp(r'^[\d\s]+\.?\s*'), '');
        
        if (cleanLine.startsWith(RegExp(r'^Q:|^Question:', caseSensitive: false))) {
          question = cleanLine.replaceFirst(RegExp(r'^(Q:|Question:)\s*', caseSensitive: false), '');
        } else if (cleanLine.startsWith(RegExp(r'^A(\.|:|\))\s*'))) {
          optionA = cleanLine.replaceFirst(RegExp(r'^A(\.|:|\))\s*'), '').trim();
        } else if (cleanLine.startsWith(RegExp(r'^B(\.|:|\))\s*'))) {
          optionB = cleanLine.replaceFirst(RegExp(r'^B(\.|:|\))\s*'), '').trim();
        } else if (cleanLine.startsWith(RegExp(r'^C(\.|:|\))\s*'))) {
          optionC = cleanLine.replaceFirst(RegExp(r'^C(\.|:|\))\s*'), '').trim();
        } else if (cleanLine.startsWith(RegExp(r'^D(\.|:|\))\s*'))) {
          optionD = cleanLine.replaceFirst(RegExp(r'^D(\.|:|\))\s*'), '').trim();
        } else if (cleanLine.startsWith(RegExp(r'^(Answer:|Correct:)\s*', caseSensitive: false))) {
          correctAnswer = cleanLine
              .replaceFirst(RegExp(r'^(Answer:|Correct:)\s*', caseSensitive: false), '')
              .trim()
              .toUpperCase()
              .replaceFirst(RegExp(r'[.].*$'), ''); // Remove trailing period
        } else if (question.isNotEmpty) {
          // Append to question if it's a continuation line
          question += ' $trimmed';
        }
      }
      
      // Clean up question (remove extra spaces)
      question = question.trim().replaceAll(RegExp(r'\s+'), ' ');
      
      // Validate and add
      if (question.isNotEmpty && optionA.isNotEmpty) {
        entries.add(QuestionBankEntry(
          question: question,
          optionA: optionA,
          optionB: optionB,
          optionC: optionC,
          optionD: optionD,
          correctAnswer: correctAnswer,
        ));
      }
    }
    
    return entries;
  }
}

class QuestionBankEntry {
  final String question;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String correctAnswer;
  
  QuestionBankEntry({
    required this.question,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctAnswer,
  });
}