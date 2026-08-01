import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SyllabusManagementScreen extends StatefulWidget {
  const SyllabusManagementScreen({super.key});

  @override
  State<SyllabusManagementScreen> createState() => _SyllabusManagementScreenState();
}

class _SyllabusManagementScreenState extends State<SyllabusManagementScreen> {
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedSubjectId;
  String? _selectedLevelId;
  List<Map<String, dynamic>> _levels = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('name');

      final levels = await Supabase.instance.client
          .from('levels')
          .select()
          .order('display_order');

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

  Future<void> _loadTopics() async {
    if (_selectedSubjectId == null || _selectedLevelId == null) return;

    try {
      final topics = await Supabase.instance.client
          .from('topics')
          .select('*')
          .eq('subject_id', _selectedSubjectId!)
          .eq('level_id', _selectedLevelId!)
          .order('display_order', ascending : true);

      if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(topics));
    } catch (e) {
      debugPrint('Load topics error: $e');
    }
  }

  Future<void> _saveSyllabus(String topicId, String syllabusOutline) async {
    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client
          .from('topics')
          .update({'syllabus_outline': syllabusOutline})
          .eq('id', topicId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Syllabus saved! ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
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

  void _editSyllabus(Map<String, dynamic> topic) {
    final controller = TextEditingController(text: topic['syllabus_outline'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A237E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.menu_book, color: Color(0xFF1A237E), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(topic['name'] ?? 'Topic', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Syllabus Outline', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ]),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
              const SizedBox(height: 16),
              
              // Instructions
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.lightbulb, color: Colors.amber, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Enter the syllabus outline for this topic. Use numbers or bullet points to list subtopics. This helps AI create accurate study plans.',
                      style: TextStyle(fontSize: 12, color: Colors.amber),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              
              // Text editor
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: InputDecoration(
                    hintText: '''1. Introduction to...
2. Key concepts:
   - Concept A
   - Concept B
3. Formulas and calculations
4. Practical applications
5. Exam tips''',
                    hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ),
              const SizedBox(height: 16),
              
              // Save button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : () {
                    _saveSyllabus(topic['id'] as String, controller.text.trim());
                    Navigator.pop(ctx);
                  },
                  icon: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Syllabus'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Syllabus Management'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Subject selector
                  DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    decoration: InputDecoration(
                      labelText: 'Select Subject',
                      prefixIcon: const Icon(Icons.book_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: _subjects.map((s) => DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text(s['name'] ?? ''),
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _selectedSubjectId = v; _topics = []; });
                      if (v != null && _selectedLevelId != null) _loadTopics();
                    },
                  ),
                  const SizedBox(height: 12),
                  
                  // Level selector
                  DropdownButtonFormField<String>(
                    value: _selectedLevelId,
                    decoration: InputDecoration(
                      labelText: 'Select Level',
                      prefixIcon: const Icon(Icons.school_rounded),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    items: _levels.map((l) => DropdownMenuItem(
                      value: l['id'] as String,
                      child: Text(l['name'] ?? ''),
                    )).toList(),
                    onChanged: (v) {
                      setState(() { _selectedLevelId = v; _topics = []; });
                      if (v != null && _selectedSubjectId != null) _loadTopics();
                    },
                  ),
                  const SizedBox(height: 20),
                  
                  // Topics list
                  Expanded(
                    child: _topics.isEmpty
                        ? Center(
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.topic, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              const Text('Select subject and level to view topics',
                                  style: TextStyle(color: Colors.grey)),
                            ]),
                          )
                        : ListView.builder(
                            itemCount: _topics.length,
                            itemBuilder: (context, index) {
                              final topic = _topics[index];
                              final hasSyllabus = topic['syllabus_outline'] != null && 
                                  (topic['syllabus_outline'] as String).isNotEmpty;
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: hasSyllabus
                                          ? const Color(0xFF4CAF50).withOpacity(0.1)
                                          : Colors.grey.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      hasSyllabus ? Icons.check_circle : Icons.edit_note,
                                      color: hasSyllabus ? const Color(0xFF4CAF50) : Colors.grey,
                                    ),
                                  ),
                                  title: Text(topic['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  subtitle: Text(
                                    hasSyllabus ? 'Syllabus added ✅' : 'No syllabus yet - tap to add',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hasSyllabus ? const Color(0xFF4CAF50) : Colors.orange,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                                  onTap: () => _editSyllabus(topic),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}