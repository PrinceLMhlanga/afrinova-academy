import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class AddSubjectScreen extends StatefulWidget {
  const AddSubjectScreen({super.key});

  @override
  State<AddSubjectScreen> createState() => _AddSubjectScreenState();
}

class _AddSubjectScreenState extends State<AddSubjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final AuthService _authService = AuthService();
  bool _isSaving = false;

  final List<Map<String, String>> _iconOptions = [
    {'icon': 'school', 'label': 'School'},
    {'icon': 'science', 'label': 'Science'},
    {'icon': 'calculate', 'label': 'Math'},
    {'icon': 'menu_book', 'label': 'Books'},
    {'icon': 'computer', 'label': 'Computer'},
    {'icon': 'language', 'label': 'Language'},
    {'icon': 'translate', 'label': 'Translate'},
    {'icon': 'history_edu', 'label': 'History'},
    {'icon': 'public', 'label': 'Geography'},
    {'icon': 'business', 'label': 'Business'},
    {'icon': 'account_balance', 'label': 'Finance'},
    {'icon': 'agriculture', 'label': 'Agriculture'},
    {'icon': 'palette', 'label': 'Arts'},
    {'icon': 'music_note', 'label': 'Music'},
    {'icon': 'sports', 'label': 'Sports'},
    {'icon': 'psychology', 'label': 'Psychology'},
    {'icon': 'engineering', 'label': 'Engineering'},
    {'icon': 'biotech', 'label': 'Biology'},
    {'icon': 'design_services', 'label': 'Design'},
    {'icon': 'nature', 'label': 'Nature'},
  ];

  final List<Color> _colorOptions = [
    const Color(0xFF1A237E),
    const Color(0xFFB71C1C),
    const Color(0xFF004D40),
    const Color(0xFF1B5E20),
    const Color(0xFFE65100),
    const Color(0xFF4A148C),
    const Color(0xFF0D47A1),
    const Color(0xFFBF360C),
    const Color(0xFF37474F),
    const Color(0xFF880E4F),
    const Color(0xFF33691E),
    const Color(0xFF827717),
  ];

  String _selectedIcon = 'school';
  Color _selectedColor = const Color(0xFF1A237E);

  Future<void> _saveSubject() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // 1. Insert the custom subject into subjects table
      final subjectResponse = await Supabase.instance.client
          .from('subjects')
          .insert({
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'icon_name': _selectedIcon,
        'color_hex': '#${_selectedColor.value.toRadixString(16).substring(2)}',
        'display_order': 99,
        'is_active': true,
      }).select('id').single();

      

      

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subject added successfully! ✅'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context, true);
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
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Custom Subject'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Subject Name',
                hintText: 'e.g., Religious Studies, Woodwork, etc.',
                prefixIcon: const Icon(Icons.book),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => v!.isEmpty ? 'Enter subject name' : null,
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'Brief description of the subject',
                prefixIcon: const Icon(Icons.description),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            // Icon picker
            const Text('Choose Icon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _iconOptions.map((icon) {
                final isSelected = _selectedIcon == icon['icon'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = icon['icon']!),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? _selectedColor.withOpacity(0.1) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: _selectedColor, width: 2)
                          : Border.all(color: Colors.transparent),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_getIconData(icon['icon']!), color: isSelected ? _selectedColor : Colors.grey, size: 24),
                        const SizedBox(height: 4),
                        Text(icon['label']!, style: TextStyle(fontSize: 10, color: isSelected ? _selectedColor : Colors.grey)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Color picker
            const Text('Choose Color', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colorOptions.map((color) {
                final isSelected = _selectedColor == color;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Preview
            const Text('Preview', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _selectedColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _selectedColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_getIconData(_selectedIcon), color: _selectedColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text.isEmpty ? 'Subject Name' : _nameController.text,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _selectedColor),
                        ),
                        Text(
                          _descriptionController.text.isEmpty ? 'Description preview' : _descriptionController.text,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveSubject,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add Subject', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'school': return Icons.school;
      case 'science': return Icons.science;
      case 'calculate': return Icons.calculate;
      case 'menu_book': return Icons.menu_book;
      case 'computer': return Icons.computer;
      case 'language': return Icons.language;
      case 'translate': return Icons.translate;
      case 'history_edu': return Icons.history_edu;
      case 'public': return Icons.public;
      case 'business': return Icons.business;
      case 'account_balance': return Icons.account_balance;
      case 'agriculture': return Icons.agriculture;
      case 'palette': return Icons.palette;
      case 'music_note': return Icons.music_note;
      case 'sports': return Icons.sports;
      case 'psychology': return Icons.psychology;
      case 'engineering': return Icons.engineering;
      case 'biotech': return Icons.biotech;
      case 'design_services': return Icons.design_services;
      case 'nature': return Icons.nature;
      default: return Icons.school;
    }
  }
}