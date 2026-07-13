import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeacherSubjectManagerScreen extends StatefulWidget {
  const TeacherSubjectManagerScreen({super.key});

  @override
  State<TeacherSubjectManagerScreen> createState() => _TeacherSubjectManagerScreenState();
}

class _TeacherSubjectManagerScreenState extends State<TeacherSubjectManagerScreen> {
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _allSubjects = [];
  List<Map<String, dynamic>> _allLevels = [];
  
  // Replace _teachersPerSubject and _teachersPerLevel with:
Map<String, Map<String, int>> _subjectLevelCounts = {}; // subject -> {level -> count}
Map<String, int> _levelCounts = {};
  int _totalTeachers = 0;
  
  bool _isLoading = true;
  bool _showStats = true;
  
  // Editing state
  String? _editingTeacherId;
  Map<String, List<String>> _editingAssignments = {}; // subjectId -> [levelIds]
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load all approved teachers
      final teachers = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email')
          .eq('role', 'teacher')
          .eq('approval_status', 'approved')
          .order('full_name', ascending: true);

      // Load teacher subjects with levels
      final teacherSubjects = await Supabase.instance.client
          .from('teacher_subjects')
          .select('teacher_id, subject_id, level_id, subjects!inner(name, color_hex), levels!inner(name)');

      // Load all subjects
      final allSubjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .eq('is_active', true)
          .order('name', ascending: true);

      // Load all levels
      final allLevels = await Supabase.instance.client
          .from('levels')
          .select()
          .order('display_order', ascending: true);

      // Group assignments by teacher
      final teacherAssignments = <String, Map<String, List<String>>>{};
      final subjectCounts = <String, Set<String>>{};
      final levelCounts = <String, Set<String>>{};
      final allTeacherIds = <String>{};

      for (final ts in teacherSubjects) {
        final teacherId = ts['teacher_id'] as String;
        final subjectId = ts['subject_id'] as String;
        final levelId = ts['level_id'] as String;
        final subjectName = ts['subjects']?['name'] as String? ?? 'Unknown';
        final levelName = ts['levels']?['name'] as String? ?? 'Unknown';

        allTeacherIds.add(teacherId);
        
        teacherAssignments.putIfAbsent(teacherId, () => {});
        teacherAssignments[teacherId]!.putIfAbsent(subjectId, () => []);
        teacherAssignments[teacherId]![subjectId]!.add(levelId);

        subjectCounts.putIfAbsent(subjectName, () => {});
        subjectCounts[subjectName]!.add(teacherId);

        levelCounts.putIfAbsent(levelName, () => {});
        levelCounts[levelName]!.add(teacherId);
      }

      if (mounted) {
  setState(() {
    _teachers = List<Map<String, dynamic>>.from(teachers);
    _allSubjects = List<Map<String, dynamic>>.from(allSubjects);
    _allLevels = List<Map<String, dynamic>>.from(allLevels);
    
    // ✅ Convert Set counts to int counts
    final subjectLevelCounts = <String, Map<String, int>>{};
    
    for (final ts in teacherSubjects) {
      final subjectName = ts['subjects']?['name'] as String? ?? 'Unknown';
      final levelName = ts['levels']?['name'] as String? ?? 'Unknown';
      final teacherId = ts['teacher_id'] as String;

      allTeacherIds.add(teacherId);

      subjectLevelCounts.putIfAbsent(subjectName, () => {});
      subjectLevelCounts[subjectName]!.putIfAbsent(levelName, () => 0);
      subjectLevelCounts[subjectName]![levelName] = (subjectLevelCounts[subjectName]![levelName] ?? 0) + 1;
    }
    
    _subjectLevelCounts = subjectLevelCounts;
    _totalTeachers = allTeacherIds.length;
    _isLoading = false;
  });
}
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, List<String>>> _getTeacherAssignments(String teacherId) async {
    final response = await Supabase.instance.client
        .from('teacher_subjects')
        .select('subject_id, level_id')
        .eq('teacher_id', teacherId);

    final assignments = <String, List<String>>{};
    for (final row in response) {
      final subjectId = row['subject_id'] as String;
      final levelId = row['level_id'] as String;
      assignments.putIfAbsent(subjectId, () => []);
      assignments[subjectId]!.add(levelId);
    }
    return assignments;
  }

  Future<void> _startEditing(String teacherId) async {
    final assignments = await _getTeacherAssignments(teacherId);
    setState(() {
      _editingTeacherId = teacherId;
      _editingAssignments = assignments;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingTeacherId = null;
      _editingAssignments = {};
    });
  }

  void _toggleSubjectLevel(String subjectId, String levelId) {
    setState(() {
      _editingAssignments.putIfAbsent(subjectId, () => []);
      if (_editingAssignments[subjectId]!.contains(levelId)) {
        _editingAssignments[subjectId]!.remove(levelId);
        if (_editingAssignments[subjectId]!.isEmpty) {
          _editingAssignments.remove(subjectId);
        }
      } else {
        _editingAssignments[subjectId]!.add(levelId);
      }
    });
  }

  void _addSubjectToEdit(String subjectId) {
    setState(() {
      _editingAssignments.putIfAbsent(subjectId, () => []);
    });
  }

  Future<void> _saveEditing() async {
    if (_editingTeacherId == null) return;
    
    setState(() => _isSaving = true);
    try {
      // Remove all existing assignments
      await Supabase.instance.client
          .from('teacher_subjects')
          .delete()
          .eq('teacher_id', _editingTeacherId!);

      await Supabase.instance.client
          .from('teacher_levels')
          .delete()
          .eq('teacher_id', _editingTeacherId!);

      // Insert new assignments
      final allLevelIds = <String>{};
      for (final entry in _editingAssignments.entries) {
        final subjectId = entry.key;
        for (final levelId in entry.value) {
          await Supabase.instance.client.from('teacher_subjects').insert({
            'teacher_id': _editingTeacherId,
            'subject_id': subjectId,
            'level_id': levelId,
          });
          allLevelIds.add(levelId);
        }
      }

      // Update teacher_levels
      for (final levelId in allLevelIds) {
        await Supabase.instance.client.from('teacher_levels').insert({
          'teacher_id': _editingTeacherId,
          'level_id': levelId,
        });
      }

      _cancelEditing();
      _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignments updated! ✅'), backgroundColor: Color(0xFF4CAF50)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Subjects'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showStats ? Icons.list : Icons.bar_chart),
            tooltip: _showStats ? 'Show Teachers' : 'Show Stats',
            onPressed: () => setState(() => _showStats = !_showStats),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _showStats
              ? _buildStatsView()
              : _buildTeachersView(),
    );
  }

 Widget _buildStatsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Overall stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.people, color: Color(0xFF1A237E), size: 24),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$_totalTeachers', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                  const Text('Total Teachers', style: TextStyle(color: Colors.grey)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Subject cards with levels
          const Text('Teachers by Subject & Level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          ..._subjectLevelCounts.entries.map((entry) {
            final subjectName = entry.key;
            final levelCounts = entry.value;
            final subject = _allSubjects.firstWhere(
              (s) => s['name'] == subjectName,
              orElse: () => {'color_hex': '#1A237E', 'description': ''},
            );
            final color = Color(int.parse('FF${(subject['color_hex'] as String? ?? '1A237E').replaceAll('#', '')}', radix: 16));
            final totalForSubject = levelCounts.values.fold<int>(0, (sum, count) => sum + count);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subject header
                  Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(subjectName,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text('$totalForSubject teacher(s)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                      ),
                    ],
                  ),
                  if (subject['description'] != null && (subject['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subject['description'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                  const SizedBox(height: 12),

                  // Level breakdown
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: levelCounts.entries
                        .where((e) => e.value > 0) // ✅ Only show levels with teachers
                        .map((levelEntry) {
                      final levelName = levelEntry.key;
                      final count = levelEntry.value;
                      final levelColor = _getLevelColor(levelName);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: levelColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: levelColor.withOpacity(0.2)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: levelColor)),
                            const SizedBox(height: 2),
                            Text(levelName, style: TextStyle(fontSize: 11, color: levelColor, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTeachersView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _teachers.length,
      itemBuilder: (context, index) {
        final teacher = _teachers[index];
        final teacherId = teacher['id'] as String;
        final isEditing = _editingTeacherId == teacherId;

        // ✅ Load this teacher's assignments for display
        return FutureBuilder<Map<String, List<String>>>(
          future: _getTeacherAssignments(teacherId),
          builder: (context, snapshot) {
            final assignments = snapshot.data ?? {};
            final subjectIds = assignments.keys.toList();

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isEditing ? const Color(0xFF4CAF50).withOpacity(0.5) : Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Teacher header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFFF9800).withOpacity(0.1),
                        child: Text((teacher['full_name'] as String? ?? 'T')[0].toUpperCase(),
                            style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(teacher['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(teacher['email'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ]),
                      ),
                      if (!isEditing)
                        ElevatedButton.icon(
                          onPressed: () => _startEditing(teacherId),
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Edit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                        ),
                    ],
                  ),

                  // ✅ Show assigned subjects with levels
                  if (!isEditing && subjectIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    ...subjectIds.map((subjectId) {
                      final subject = _allSubjects.firstWhere(
                        (s) => s['id'] == subjectId,
                        orElse: () => {'name': 'Unknown', 'color_hex': '#1A237E'},
                      );
                      final subjectName = subject['name'] as String? ?? 'Unknown';
                      final color = Color(int.parse('FF${(subject['color_hex'] as String? ?? '1A237E').replaceAll('#', '')}', radix: 16));
                      final levels = assignments[subjectId] ?? [];
                      final levelNames = levels.map((lid) {
                        final level = _allLevels.firstWhere((l) => l['id'] == lid, orElse: () => {'name': '?'});
                        return level['name'] as String? ?? '?';
                      }).toList();

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 8, height: 8,
                              margin: const EdgeInsets.only(top: 5),
                              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(subjectName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                                  const SizedBox(height: 2),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: levelNames.map((levelName) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: _getLevelColor(levelName).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(levelName, style: TextStyle(fontSize: 10, color: _getLevelColor(levelName))),
                                    )).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  if (isEditing) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 12),
                    
                    // Edit mode - Show all subjects with level checkboxes
                    ..._allSubjects.map((subject) {
                      final subjectId = subject['id'] as String;
                      final subjectName = subject['name'] as String;
                      final color = Color(int.parse('FF${(subject['color_hex'] as String? ?? '1A237E').replaceAll('#', '')}', radix: 16));
                      final selectedLevels = _editingAssignments[subjectId] ?? [];
                      final isSubjectSelected = selectedLevels.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSubjectSelected ? color.withOpacity(0.03) : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isSubjectSelected ? color.withOpacity(0.3) : Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Text(subjectName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _allLevels.map((level) {
                                final levelId = level['id'] as String;
                                final levelName = level['name'] as String;
                                final isLevelSelected = selectedLevels.contains(levelId);
                                return FilterChip(
                                  label: Text(levelName, style: const TextStyle(fontSize: 11)),
                                  selected: isLevelSelected,
                                  onSelected: (_) => _toggleSubjectLevel(subjectId, levelId),
                                  selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
                                  checkmarkColor: const Color(0xFF4CAF50),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(onPressed: _cancelEditing, child: const Text('Cancel')),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveEditing,
                          icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                          label: const Text('Save Changes'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'Form 1': return Colors.blue;
      case 'Form 2': return Colors.teal;
      case 'O-Level': return const Color(0xFFFF9800);
      case 'A-Level': return Colors.purple;
      default: return Colors.grey;
    }
  }
}