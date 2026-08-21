import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class TeacherActivityScreen extends StatefulWidget {
  const TeacherActivityScreen({super.key});

  @override
  State<TeacherActivityScreen> createState() => _TeacherActivityScreenState();
}

class _TeacherActivityScreenState extends State<TeacherActivityScreen> {
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _filteredTeachers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _timeFilter = 'all'; // 'today', 'week', 'month', 'term', 'all'
  String _sortBy = 'recent_activity'; // 'recent_activity', 'most_students', 'most_content', 'alphabetical'
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadTeacherActivity();
  }

 Future<void> _loadTeacherActivity() async {
  try {
    setState(() => _isLoading = true);

    // Get all teachers
    final teachersResponse = await Supabase.instance.client
        .from('profiles')
        .select('id, full_name, email, avatar_url, created_at')
        .eq('role', 'teacher')
        .order('full_name');

    final teachers = List<Map<String, dynamic>>.from(teachersResponse);

    // For each teacher, get their activity metrics
    for (final teacher in teachers) {
      final teacherId = teacher['id'] as String;

      // Get counts in parallel
      final results = await Future.wait([
        // Lessons count
        Supabase.instance.client
            .from('lessons')
            .select('id, created_at, view_count')
            .eq('teacher_id', teacherId),
        
        // Resources count
        Supabase.instance.client
            .from('resources')
            .select('id, created_at, resource_type, download_count')
            .eq('teacher_id', teacherId),
        
        // Live lessons count
        Supabase.instance.client
            .from('live_lessons')
            .select('id, created_at, status')
            .eq('teacher_id', teacherId),
        
        // Exams count
        Supabase.instance.client
            .from('exams')
            .select('id, created_at, is_published')
            .eq('creator_id', teacherId),
        
        // Exam papers count
        Supabase.instance.client
            .from('exam_papers')
            .select('id, created_at, is_published')
            .eq('creator_id', teacherId),
        
        // Enrollments count - use requested_at
        Supabase.instance.client
            .from('enrollments')
            .select('id, student_id, status, requested_at, is_subscribed')
            .eq('teacher_id', teacherId),
        
        // Subjects taught - FIXED: Include level information
        Supabase.instance.client
            .from('teacher_subjects')
            .select('id, subject_id, level_id, subjects(name, color_hex), levels(name)')
            .eq('teacher_id', teacherId),
      ]);

      final lessons = results[0] as List;
      final resources = results[1] as List;
      final liveLessons = results[2] as List;
      final exams = results[3] as List;
      final examPapers = results[4] as List;
      final enrollments = results[5] as List;
      final subjects = results[6] as List;

      // Calculate metrics
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final monthAgo = now.subtract(const Duration(days: 30));
      final termAgo = now.subtract(const Duration(days: 90));

      int countInTimeRange(List items, String dateField) {
        if (_timeFilter == 'all') return items.length;
        
        return items.where((item) {
          final dateStr = item[dateField] as String?;
          if (dateStr == null) return false;
          final date = DateTime.parse(dateStr);
          
          switch (_timeFilter) {
            case 'today':
              return date.day == now.day && date.month == now.month && date.year == now.year;
            case 'week':
              return date.isAfter(weekAgo);
            case 'month':
              return date.isAfter(monthAgo);
            case 'term':
              return date.isAfter(termAgo);
            default:
              return true;
          }
        }).length;
      }

      final totalLessons = countInTimeRange(lessons, 'created_at');
      final totalResources = countInTimeRange(resources, 'created_at');
      final totalLiveLessons = countInTimeRange(liveLessons, 'created_at');
      final totalExams = countInTimeRange(exams, 'created_at');
      final totalExamPapers = countInTimeRange(examPapers, 'created_at');
      
      // Active students (paid or approved)
      final activeStudents = enrollments
          .where((e) => e['status'] == 'paid' || e['status'] == 'approved')
          .map((e) => e['student_id'])
          .toSet()
          .length;
      
      // Total content created
      final totalContent = totalLessons + totalResources + totalLiveLessons + totalExams + totalExamPapers;
      
      // Last activity date
      DateTime? lastActivity;
      final allActivityItems = [
        ...lessons.map((item) => {'date': item['created_at']}),
        ...resources.map((item) => {'date': item['created_at']}),
        ...liveLessons.map((item) => {'date': item['created_at']}),
        ...exams.map((item) => {'date': item['created_at']}),
        ...examPapers.map((item) => {'date': item['created_at']}),
        ...enrollments.map((item) => {'date': item['requested_at']}),
      ];
      
      for (final item in allActivityItems) {
        final dateStr = item['date'] as String?;
        if (dateStr != null) {
          final date = DateTime.parse(dateStr);
          if (lastActivity == null || date.isAfter(lastActivity)) {
            lastActivity = date;
          }
        }
      }

      teacher['metrics'] = {
        'lessons': totalLessons,
        'resources': totalResources,
        'live_lessons': totalLiveLessons,
        'exams': totalExams,
        'exam_papers': totalExamPapers,
        'active_students': activeStudents,
        'total_content': totalContent,
        'last_activity': lastActivity,
        'subjects': subjects.map((s) {
          final subjectName = (s['subjects'] as Map?)?['name'] as String? ?? 'Unknown';
          final levelName = (s['levels'] as Map?)?['name'] as String? ?? 'All Levels';
          final subjectColor = (s['subjects'] as Map?)?['color_hex'] as String? ?? '#1A237E';
          return {
            'subject_name': subjectName,
            'level_name': levelName,
            'display': '$subjectName ($levelName)',
            'subject_color': subjectColor,
          };
        }).toList(),
        'total_subjects': subjects.length,
      };
    }

    if (mounted) {
      setState(() {
        _teachers = teachers;
        _filteredTeachers = List.from(teachers);
        _isLoading = false;
      });
      _applyFilters();
    }
  } catch (e) {
    debugPrint('Error loading teacher activity: $e');
    if (mounted) setState(() => _isLoading = false);
  }
}

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_teachers);

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((teacher) {
        final name = (teacher['full_name'] as String? ?? '').toLowerCase();
        final email = (teacher['email'] as String? ?? '').toLowerCase();
        return name.contains(_searchQuery.toLowerCase()) || 
               email.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Apply sorting
    filtered.sort((a, b) {
      final aMetrics = a['metrics'] as Map<String, dynamic>;
      final bMetrics = b['metrics'] as Map<String, dynamic>;
      
      int comparison;
      switch (_sortBy) {
        case 'most_students':
          comparison = (aMetrics['active_students'] as int).compareTo(bMetrics['active_students'] as int);
          break;
        case 'most_content':
          comparison = (aMetrics['total_content'] as int).compareTo(bMetrics['total_content'] as int);
          break;
        case 'alphabetical':
          comparison = (a['full_name'] as String).compareTo(b['full_name'] as String);
          break;
        case 'recent_activity':
        default:
          final aDate = aMetrics['last_activity'] as DateTime?;
          final bDate = bMetrics['last_activity'] as DateTime?;
          if (aDate == null && bDate == null) {
            comparison = 0;
          } else if (aDate == null) {
            comparison = 1;
          } else if (bDate == null) {
            comparison = -1;
          } else {
            comparison = aDate.compareTo(bDate);
          }
          break;
      }
      
      return _sortAscending ? comparison : -comparison;
    });

    setState(() {
      _filteredTeachers = filtered;
    });
  }

  Color _getTimeFilterColor(String filter) {
    return _timeFilter == filter ? const Color(0xFF1A237E) : Colors.grey.shade600;
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
        child: Column(
          children: [
            // Header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D1B4C), Color(0xFF1A237E), Color(0xFF283593)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const BackButton(color: Colors.white),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Teacher Activity',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            onPressed: _loadTeacherActivity,
                          ),
                        ],
                      ),
                    ),
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        onChanged: (value) {
                          _searchQuery = value;
                          _applyFilters();
                        },
                        decoration: InputDecoration(
                          hintText: 'Search teachers...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          prefixIcon: const Icon(Icons.search, color: Colors.white54),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    // Time filters
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildFilterChip('Today', 'today'),
                          const SizedBox(width: 8),
                          _buildFilterChip('This Week', 'week'),
                          const SizedBox(width: 8),
                          _buildFilterChip('This Month', 'month'),
                          const SizedBox(width: 8),
                          _buildFilterChip('This Term', 'term'),
                          const SizedBox(width: 8),
                          _buildFilterChip('All Time', 'all'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            // Sort options
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('Sort by:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _sortBy,
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'recent_activity', child: Text('Recent Activity')),
                          DropdownMenuItem(value: 'most_students', child: Text('Most Students')),
                          DropdownMenuItem(value: 'most_content', child: Text('Most Content')),
                          DropdownMenuItem(value: 'alphabetical', child: Text('Alphabetical')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _sortBy = value!;
                            _applyFilters();
                          });
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
                    onPressed: () {
                      setState(() {
                        _sortAscending = !_sortAscending;
                        _applyFilters();
                      });
                    },
                  ),
                ],
              ),
            ),
            // Teacher list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
                  : _filteredTeachers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text('No teachers found', style: TextStyle(fontSize: 16, color: Colors.grey)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadTeacherActivity,
                          color: const Color(0xFFFF9800),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredTeachers.length,
                            itemBuilder: (context, index) {
                              final teacher = _filteredTeachers[index];
                              return _buildTeacherCard(teacher);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _timeFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _timeFilter = value;
        });
        _loadTeacherActivity();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? const Color(0xFF1A237E) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherCard(Map<String, dynamic> teacher) {
  final metrics = teacher['metrics'] as Map<String, dynamic>;
  final lastActivity = metrics['last_activity'] as DateTime?;
  final subjects = metrics['subjects'] as List;
  
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: Colors.grey.withOpacity(0.06), blurRadius: 8),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Teacher header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                child: Text(
                  (teacher['full_name'] as String? ?? 'T')[0].toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF1A237E),
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacher['full_name'] ?? 'Unknown Teacher',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      teacher['email'] ?? '',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    if (lastActivity != null)
                      Text(
                        'Last active: ${DateFormat('MMM d, yyyy').format(lastActivity)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${metrics['active_students']} Students',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Activity metrics grid
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Content Created',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMetricCard('Lessons', metrics['lessons'] as int, Icons.play_circle_outline, Colors.blue),
                  const SizedBox(width: 8),
                  _buildMetricCard('Resources', metrics['resources'] as int, Icons.folder_outlined, Colors.teal),
                  const SizedBox(width: 8),
                  _buildMetricCard('Live Lessons', metrics['live_lessons'] as int, Icons.live_tv, Colors.red),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildMetricCard('Exams', metrics['exams'] as int, Icons.assignment_outlined, Colors.purple),
                  const SizedBox(width: 8),
                  _buildMetricCard('Exam Papers', metrics['exam_papers'] as int, Icons.description_outlined, Colors.orange),
                  const SizedBox(width: 8),
                  _buildMetricCard('Total Content', metrics['total_content'] as int, Icons.library_books, const Color(0xFF1A237E)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Student Engagement',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildMetricCard('Active Students', metrics['active_students'] as int, Icons.people_rounded, const Color(0xFF4CAF50)),
                  const SizedBox(width: 8),
                  _buildMetricCard('Total Subjects', metrics['total_subjects'] as int, Icons.book_rounded, const Color(0xFF00897B)),
                ],
              ),
              if (subjects.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Subjects Taught',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: subjects.map((subject) {
                    final subjectData = subject as Map<String, dynamic>;
                    final subjectName = subjectData['subject_name'] as String;
                    final levelName = subjectData['level_name'] as String;
                    final colorHex = subjectData['subject_color'] as String;
                    final color = Color(int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16));
                    
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: color.withOpacity(0.1)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subjectName,
                            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            levelName,
                            style: TextStyle(fontSize: 9, color: color.withOpacity(0.7)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildMetricCard(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}