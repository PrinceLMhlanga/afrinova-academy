import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'my_subjects_screen.dart';

class TeacherClassesScreen extends StatefulWidget {
  const TeacherClassesScreen({super.key});

  @override
  State<TeacherClassesScreen> createState() => _TeacherClassesScreenState();
}

class _TeacherClassesScreenState extends State<TeacherClassesScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _myLevels = [];
  Map<String, int> _subjectCounts = {};
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

      // Get teacher's assigned levels with their names
      final levelsResponse = await Supabase.instance.client
          .from('teacher_levels')
          .select('level_id, levels!inner(name, description, display_order)')
          .eq('teacher_id', userId)
          .order('display_order', referencedTable: 'levels');

      // Count subjects per level
      final subjectCounts = <String, int>{};
      for (final row in levelsResponse) {
        final levelId = row['level_id'] as String;
        final count = await Supabase.instance.client
            .from('teacher_subjects')
            .select('id')
            .eq('teacher_id', userId)
            .eq('level_id', levelId)
            .count(CountOption.exact);
        
        subjectCounts[levelId] = count.count ?? 0;
      }

      if (mounted) {
        setState(() {
          _myLevels = List<Map<String, dynamic>>.from(levelsResponse);
          _subjectCounts = subjectCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 140,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: const BackButton(color: Colors.white),
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: FlexibleSpaceBar(
                  title: const Text('My Classes',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  centerTitle: false,
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                  background: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_myLevels.length} class(es)',
                            style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('Manage your subjects and content',
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(60),
                      child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                    ))
                  else if (_myLevels.isEmpty)
                    _buildEmptyState()
                  else ...[
                    // Info card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Color(0xFF1A237E), size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Select a class to manage subjects, topics, and content',
                              style: TextStyle(fontSize: 12, color: Color(0xFF1A237E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Level cards
                    ..._myLevels.map((row) {
                      final level = row['levels'] as Map<String, dynamic>;
                      final levelId = row['level_id'] as String;
                      final levelName = level['name'] as String;
                      final levelDesc = level['description'] as String? ?? '';
                      final subjectCount = _subjectCounts[levelId] ?? 0;
                      final color = _getLevelColor(levelName);
                      final icon = _getLevelIcon(levelName);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 1,
                          shadowColor: color.withOpacity(0.2),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TeacherLevelSubjectsScreen(
                                    levelId: levelId,
                                    levelName: levelName,
                                  ),
                                ),
                              ).then((_) => _loadData()); // Refresh on return
                            },
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: color.withOpacity(0.15)),
                              ),
                              child: Row(
                                children: [
                                  // Icon
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(icon, color: color, size: 28),
                                  ),
                                  const SizedBox(width: 16),
                                  
                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          levelName,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: color,
                                          ),
                                        ),
                                        if (levelDesc.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            levelDesc,
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.book_rounded, size: 14, color: Colors.grey.shade400),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$subjectCount subject(s)',
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Arrow
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.chevron_right, color: color, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school_outlined, size: 48, color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 24),
            const Text('No classes assigned yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 8),
            const Text('Once admin approves your application,\nyour assigned classes will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'Form 1':
        return Colors.blue;
      case 'Form 2':
        return Colors.teal;
      case 'O-Level':
        return const Color(0xFFFF9800);
      case 'A-Level':
        return Colors.purple;
      default:
        return const Color(0xFF1A237E);
    }
  }

  IconData _getLevelIcon(String level) {
    switch (level) {
      case 'Form 1':
        return Icons.looks_one_rounded;
      case 'Form 2':
        return Icons.looks_two_rounded;
      case 'O-Level':
        return Icons.school_rounded;
      case 'A-Level':
        return Icons.workspace_premium_rounded;
      default:
        return Icons.class_rounded;
    }
  }
}