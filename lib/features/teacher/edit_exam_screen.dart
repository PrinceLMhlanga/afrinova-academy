import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/subject_service.dart';

class EditExamScreen extends StatefulWidget {
  final String examId;
  final Map<String, dynamic> examData;

  const EditExamScreen({
    super.key,
    required this.examId,
    required this.examData,
  });

  @override
  State<EditExamScreen> createState() => _EditExamScreenState();
}

class _EditExamScreenState extends State<EditExamScreen> {
  final _formKey = GlobalKey<FormState>();
  final SubjectService _subjectService = SubjectService();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _durationController;
  late TextEditingController _passingController;

  List<Map<String, dynamic>> _subjects = [];
  String? _selectedSubject;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.examData;
    _titleController =
        TextEditingController(text: data['title'] ?? '');
    _descriptionController =
        TextEditingController(text: data['description'] ?? '');
    _durationController = TextEditingController(
        text: data['duration_minutes']?.toString() ?? '');
    _passingController = TextEditingController(
        text: data['passing_percentage']?.toString() ?? '50');
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await _subjectService.getSubjects();
      if (mounted) setState(() => _subjects = subjects);
    } catch (_) {}
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      await Supabase.instance.client
          .from('exams')
          .update({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'duration_minutes': int.tryParse(_durationController.text),
        'passing_percentage':
            int.tryParse(_passingController.text) ?? 50,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.examId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exam updated successfully! ✅'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _passingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Exam'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Exam Title',
                prefixIcon: const Icon(Icons.quiz),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
                  v!.isEmpty ? 'Enter exam title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description',
                prefixIcon: const Icon(Icons.description),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Duration (min)',
                      prefixIcon: const Icon(Icons.timer_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _passingController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Passing %',
                      prefixIcon:
                          const Icon(Icons.check_circle_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Save Changes',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}