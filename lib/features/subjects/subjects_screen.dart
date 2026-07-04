import 'package:flutter/material.dart';
import '../../core/teacher_service.dart';
import 'teachers_by_subject_screen.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final TeacherService _teacherService = TeacherService();
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await _teacherService.getAllSubjects();
      if (mounted) {
        setState(() {
          _subjects = subjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getSubjectIcon(String? iconName) {
    switch (iconName) {
      case 'calculate': return Icons.calculate;
      case 'science': return Icons.science;
      case 'nature': return Icons.eco;
      case 'computer': return Icons.computer;
      case 'menu_book': return Icons.menu_book;
      case 'history_edu': return Icons.history_edu;
      case 'public': return Icons.public;
      case 'business': return Icons.business;
      case 'language': return Icons.language;
      default: return Icons.school;
    }
  }

  Color _getSubjectColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return const Color(0xFF1A237E);
    final hex = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Subjects'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _subjects.isEmpty
              ? const Center(child: Text('No subjects available'))
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _subjects.length,
                  itemBuilder: (context, index) {
                    final subject = _subjects[index];
                    final color = _getSubjectColor(subject['color_hex']);
                    final icon = _getSubjectIcon(subject['icon_name']);

                    return _SubjectCard(
                      name: subject['name'] ?? '',
                      description: 'Tap to find teachers',
                      icon: icon,
                      color: color,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeachersBySubjectScreen(
                              subjectId: subject['id'] as String,
                              subjectName: subject['name'] ?? '',
                              subjectColor: color,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SubjectCard({required this.name, required this.description, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 64, height: 64, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Icon(icon, size: 32, color: color)),
              const SizedBox(height: 16),
              Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text(description, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}