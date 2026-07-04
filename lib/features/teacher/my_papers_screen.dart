import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'paper_submissions_screen.dart';

class MyPapersScreen extends StatefulWidget {
  const MyPapersScreen({super.key});

  @override
  State<MyPapersScreen> createState() => _MyPapersScreenState();
}

class _MyPapersScreenState extends State<MyPapersScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _papers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPapers();
  }

  Future<void> _loadPapers() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('exam_papers')
          .select('*, subjects(name)')
          .eq('creator_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _papers = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Exam Papers'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : _papers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No papers created yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _papers.length,
                  itemBuilder: (context, index) {
                    final paper = _papers[index];
                    final isPublished = paper['is_published'] ?? false;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: Container(
                          width: 50, height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00897B).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.assignment, color: Color(0xFF00897B), size: 26),
                        ),
                        title: Text(paper['title'] ?? 'Untitled',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('${paper['subjects']?['name'] ?? ''} • ${paper['curriculum'] ?? ''} ${paper['paper_type'] ?? ''}'),
                            Text('${paper['total_marks'] ?? 0} marks • ${paper['duration_minutes'] ?? 0} min',
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isPublished
                                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                                    : Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isPublished ? 'Published' : 'Draft',
                                style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: isPublished ? const Color(0xFF4CAF50) : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaperSubmissionsScreen(paper: paper),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}