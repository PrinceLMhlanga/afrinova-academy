import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'exam_review_screen.dart';

class ExamHistoryScreen extends StatefulWidget {
  const ExamHistoryScreen({super.key});

  @override
  State<ExamHistoryScreen> createState() => _ExamHistoryScreenState();
}

class _ExamHistoryScreenState extends State<ExamHistoryScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _examSessions = [];
  Map<String, List<Map<String, dynamic>>> _sessionsGrouped = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get all unique exam sessions with details
      final history = await Supabase.instance.client
          .from('practice_exam_history')
          .select('''
            exam_session_id,
            subject_id,
            level_id,
            attempted_at,
            is_correct,
            subject:subject_id(name),
            level:level_id(name)
          ''')
          .eq('student_id', userId)
          .order('attempted_at', ascending: false);

      // Group by exam_session_id
      final Map<String, Map<String, dynamic>> sessions = {};
      
      for (final record in history) {
        final sessionId = record['exam_session_id'] as String;
        
        if (!sessions.containsKey(sessionId)) {
          sessions[sessionId] = {
            'session_id': sessionId,
            'subject_name': record['subject']?['name'] ?? 'Unknown Subject',
            'level_name': record['level']?['name'] ?? 'Unknown Level',
            'attempted_at': record['attempted_at'],
            'total': 0,
            'correct': 0,
          };
        }
        
        sessions[sessionId]!['total'] = (sessions[sessionId]!['total'] as int) + 1;
        if (record['is_correct'] == true) {
          sessions[sessionId]!['correct'] = (sessions[sessionId]!['correct'] as int) + 1;
        }
      }

      // Group by month for display
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final session in sessions.values) {
        final date = DateTime.parse(session['attempted_at'] as String);
        final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final monthName = _getMonthName(date.month) + ' ${date.year}';
        
        if (!grouped.containsKey(monthName)) {
          grouped[monthName] = [];
        }
        grouped[monthName]!.add(session);
      }

      if (mounted) {
        setState(() {
          _sessionsGrouped = grouped;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day} ${_getMonthName(date.month).substring(0, 3)} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Exam History'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _sessionsGrouped.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _sessionsGrouped.entries.map((entry) {
                      return _buildMonthGroup(entry.key, entry.value);
                    }).toList(),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history, size: 48, color: Color(0xFF1A237E)),
          ),
          const SizedBox(height: 24),
          const Text('No Exam History', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 8),
          const Text('Complete practice exams to see\nyour history here', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildMonthGroup(String monthName, List<Map<String, dynamic>> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 8),
          child: Text(
            monthName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
          ),
        ),
        ...sessions.map((session) => _buildSessionCard(session)),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final total = session['total'] as int;
    final correct = session['correct'] as int;
    final percentage = total > 0 ? (correct / total * 100) : 0;
    final passed = percentage >= 50;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExamReviewScreen(
              sessionId: session['session_id'] as String,
              subjectName: session['subject_name'] as String,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            // Score circle
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: passed
                      ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                      : [Colors.red.shade400, Colors.red.shade300],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('${percentage.round()}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 14),
            
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session['subject_name'] ?? 'Exam',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Color(0xFF1A237E))),
                  const SizedBox(height: 4),
                  Text(session['level_name'] ?? '',
                      style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text('$correct / $total correct • ${_formatDate(session['attempted_at'] as String)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            
            // Arrow
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}