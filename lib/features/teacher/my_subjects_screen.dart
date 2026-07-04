import 'package:flutter/material.dart';
import '../../core/teacher_service.dart';
import '../../core/auth_service.dart';
import 'topic_manager_screen.dart';
import 'add_subject_screen.dart';

class MySubjectsScreen extends StatefulWidget {
  const MySubjectsScreen({super.key});

  @override
  State<MySubjectsScreen> createState() => _MySubjectsScreenState();
}

class _MySubjectsScreenState extends State<MySubjectsScreen> {
  final TeacherService _teacherService = TeacherService();
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _allSubjects = [];
  List<Map<String, dynamic>> _mySubjects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final allSubjects = await _teacherService.getAllSubjects();
      final mySubjects = await _teacherService.getMySubjects(userId);

      if (mounted) {
        setState(() {
          _allSubjects = allSubjects;
          _mySubjects = mySubjects;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isMySubject(String subjectId) {
    return _mySubjects.any((s) => s['subject_id'] == subjectId);
  }

  Future<void> _toggleSubject(Map<String, dynamic> subject) async {
    final userId = _authService.currentUserId;
    if (userId == null) return;

    final subjectId = subject['id'] as String;

    if (_isMySubject(subjectId)) {
      await _teacherService.removeSubject(userId, subjectId);
    } else {
      await _teacherService.addSubject(userId, subjectId);
    }
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: const Text('My Subjects'),
  backgroundColor: const Color(0xFF1A237E),
  foregroundColor: Colors.white,
  actions: [
    IconButton(
      icon: const Icon(Icons.add),
      tooltip: 'Add Custom Subject',
      onPressed: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddSubjectScreen()),
        );
        if (result == true) _loadData();
      },
    ),
  ],
),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Select the subjects you teach',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_mySubjects.length} subject(s) selected',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                ..._allSubjects.map((subject) {
                  final isSelected = _isMySubject(subject['id'] as String);
                  final color = Color(
                    int.parse(
                      'FF${(subject['color_hex'] as String? ?? '1A237E').replaceAll('#', '')}',
                      radix: 16,
                    ),
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getSubjectIcon(subject['icon_name'] as String?),
                          color: isSelected ? color : Colors.grey,
                        ),
                      ),
                      title: Text(
                        subject['name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? color : Colors.black87,
                        ),
                      ),
                      subtitle: Text(
                        subject['description'] ?? '',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Switch(
                        value: isSelected,
                        onChanged: (_) => _toggleSubject(subject),
                        activeColor: color,
                      ),
                      onTap: isSelected
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TopicManagerScreen(
                                    subjectId: subject['id'] as String,
                                    subjectName: subject['name'] as String,
                                    subjectColor: color,
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                  );
                }),
              ],
            ),
    );
  }

  IconData _getSubjectIcon(String? iconName) {
    switch (iconName) {
      case 'calculate': return Icons.calculate;
      case 'science': return Icons.science;
      case 'nature': return Icons.eco;
      case 'computer': return Icons.computer;
      default: return Icons.school;
    }
  }
}