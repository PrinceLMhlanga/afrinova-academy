import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'summary_generator_screen.dart';
import 'summary_viewer_screen.dart';

class MySummariesScreen extends StatefulWidget {
  const MySummariesScreen({super.key});

  @override
  State<MySummariesScreen> createState() => _MySummariesScreenState();
}

class _MySummariesScreenState extends State<MySummariesScreen> {
  final AuthService _authService = AuthService();
  Map<String, List<Map<String, dynamic>>> _groupedBySubject = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  Future<void> _loadSummaries() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final summaries = await Supabase.instance.client
          .from('ai_summaries')
          .select('*, subject:subject_id(name)')
          .eq('student_id', userId)
          .order('created_at', ascending: false);

      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final s in summaries) {
        final subjectName = s['subject']?['name'] as String? ?? 'General';
        if (!grouped.containsKey(subjectName)) {
          grouped[subjectName] = [];
        }
        grouped[subjectName]!.add(s);
      }

      if (mounted) setState(() { _groupedBySubject = grouped; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Summaries'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SummaryGeneratorScreen()))
                  .then((_) => _loadSummaries());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groupedBySubject.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadSummaries,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _groupedBySubject.entries.map((entry) {
                      return _buildSubjectGroup(entry.key, entry.value);
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
          Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.teal.withOpacity(0.08), shape: BoxShape.circle),
              child: const Icon(Icons.summarize_rounded, size: 48, color: Colors.teal)),
          const SizedBox(height: 24),
          const Text('No Summaries Yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
          const SizedBox(height: 8),
          const Text('Generate AI-powered study summaries\nto ace your exams', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SummaryGeneratorScreen()))
                  .then((_) => _loadSummaries());
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Summary'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectGroup(String subjectName, List<Map<String, dynamic>> summaries) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12, top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.teal.shade600, Colors.green.shade600]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.summarize_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(subjectName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              Text('${summaries.length}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
        ...summaries.map((s) => GestureDetector(
          onTap: () {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => SummaryViewerScreen(title: s['title'] ?? '', content: s['content'] ?? ''),
            ));
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))]),
            child: Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: Colors.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.article_rounded, color: Colors.teal, size: 24)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['title'] ?? 'Summary', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF1A237E))),
                  const SizedBox(height: 4),
                  Text(_formatDate(s['created_at'] as String?), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ])),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        )),
        const SizedBox(height: 16),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) { return ''; }
  }
}