import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'manage_topics_screen.dart';
import 'add_subject_screen.dart';

class ManagePlatformSubjectsScreen extends StatefulWidget {
  const ManagePlatformSubjectsScreen({super.key});

  @override
  State<ManagePlatformSubjectsScreen> createState() => _ManagePlatformSubjectsScreenState();
}

class _ManagePlatformSubjectsScreenState extends State<ManagePlatformSubjectsScreen> {
  List<Map<String, dynamic>> _subjects = [];
  Map<String, int> _topicCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await Supabase.instance.client
          .from('subjects')
          .select()
          .order('display_order', ascending: true);  // ✅ Order by display_order

      // Count topics per subject
      final topicCounts = <String, int>{};
      for (final s in subjects) {
        final count = await Supabase.instance.client
            .from('topics')
            .select('id')
            .eq('subject_id', s['id'] as String)
            .count(CountOption.exact);
        topicCounts[s['id'] as String] = count.count ?? 0;
      }

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(subjects);
          _topicCounts = topicCounts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return const Color(0xFF1A237E);
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  IconData _getSubjectIcon(String? iconName) {
    switch (iconName) {
      case 'calculate': return Icons.calculate;
      case 'science': return Icons.science;
      case 'nature': return Icons.eco;
      case 'menu_book': return Icons.menu_book;
      case 'history_edu': return Icons.history_edu;
      case 'public': return Icons.public;
      case 'business': return Icons.business;
      case 'account_balance': return Icons.account_balance;
      case 'computer': return Icons.computer;
      case 'agriculture': return Icons.agriculture;
      case 'translate': return Icons.translate;
      case 'language': return Icons.language;
      case 'palette': return Icons.palette;
      case 'design_services': return Icons.design_services;
      case 'engineering': return Icons.engineering;
      case 'work': return Icons.work;
      default: return Icons.school;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Subjects & Topics'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Subject',
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddSubjectScreen()),
              );
              if (result == true) _loadSubjects();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _subjects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.book_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No subjects available', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AddSubjectScreen()),
                          );
                          if (result == true) _loadSubjects();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Subject'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subjects.length,
                  itemBuilder: (context, index) {
                    final subject = _subjects[index];
                    final subjectId = subject['id'] as String;
                    final subjectName = subject['name'] as String;
                    final subjectDesc = subject['description'] as String? ?? '';
                    final color = _parseColor(subject['color_hex'] as String?);
                    final icon = _getSubjectIcon(subject['icon_name'] as String?);
                    final topicCount = _topicCounts[subjectId] ?? 0;

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
                                builder: (_) => ManageTopicsScreen(
                                  subjectId: subjectId,
                                  subjectName: subjectName,
                                  subjectColor: color,
                                ),
                              ),
                            ).then((_) => _loadSubjects());
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: color.withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                // Subject icon
                                Container(
                                  width: 56, height: 56,
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(icon, color: color, size: 28),
                                ),
                                const SizedBox(width: 16),
                                // Subject info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(subjectName, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
                                      if (subjectDesc.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(subjectDesc, style: TextStyle(fontSize: 12, color: Colors.grey.shade500), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.topic_rounded, size: 14, color: Colors.grey.shade400),
                                          const SizedBox(width: 4),
                                          Text('$topicCount topics', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                // Arrow
                                Container(
                                  width: 34, height: 34,
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
                  },
                ),
    );
  }
}