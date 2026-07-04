import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lessons_screen.dart';

class TeacherContentScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String subjectName;
  final Color subjectColor;
  
  const TeacherContentScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.subjectName,
    required this.subjectColor,
    
  });

  @override
  State<TeacherContentScreen> createState() => _TeacherContentScreenState();
}

class _TeacherContentScreenState extends State<TeacherContentScreen> {
  List<Map<String, dynamic>> _topics = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      // Find the subject ID
      final subject = await Supabase.instance.client
          .from('subjects')
          .select('id')
          .eq('name', widget.subjectName)
          .single();

      // Get this teacher's topics for this subject
      final topics = await Supabase.instance.client
          .from('teacher_topics')
          .select()
          .eq('teacher_id', widget.teacherId)
          .eq('subject_id', subject['id'] as String)
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(topics);
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
        title: Text(widget.teacherName),
        backgroundColor: widget.subjectColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: widget.subjectColor))
          : _topics.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.topic_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No topics yet', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _topics.length,
                  itemBuilder: (context, index) {
                    final topic = _topics[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            color: widget.subjectColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text('${index + 1}',
                                style: TextStyle(color: widget.subjectColor, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        title: Text(topic['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: Icon(Icons.chevron_right, color: widget.subjectColor),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LessonsScreen(
                                topicId: topic['id'] as String,
                                topicName: topic['name'] ?? '',
                                subjectColor: widget.subjectColor,
                                
                              ),
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