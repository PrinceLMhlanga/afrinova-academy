import 'package:flutter/material.dart';
import '../../core/subject_service.dart';
import 'lessons_screen.dart';

class TopicsScreen extends StatefulWidget {
  final String subjectName;
  final Color subjectColor;

  const TopicsScreen({
    super.key,
    required this.subjectName,
    required this.subjectColor,
  });

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  final SubjectService _subjectService = SubjectService();
  List<Map<String, dynamic>> _topics = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      // First get the subject offering ID
      final offerings = await _subjectService.getSubjectOfferings();
      final offering = offerings.firstWhere(
        (o) => o['subjects']?['name'] == widget.subjectName,
        orElse: () => {},
      );

      if (offering.isNotEmpty && offering['id'] != null) {
        final topics = await _subjectService.getTopics(offering['id']);
        if (mounted) {
          setState(() {
            _topics = topics;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load topics: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} Topics'),
        backgroundColor: widget.subjectColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: widget.subjectColor),
            )
          : _topics.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.topic_outlined,
                              size: 80, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No topics available yet',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _topics.length,
                  itemBuilder: (context, index) {
                    final topic = _topics[index];
                    return _TopicCard(
                      title: topic['name'] ?? '',
                      description: topic['description'] ?? 'Explore this topic',
                      displayOrder: topic['display_order'] ?? index + 1,
                      color: widget.subjectColor,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LessonsScreen(
                              topicId: topic['id'],
                              topicName: topic['name'] ?? '',
                              subjectColor: widget.subjectColor,
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

class _TopicCard extends StatelessWidget {
  final String title;
  final String description;
  final int displayOrder;
  final Color color;
  final VoidCallback onTap;

  const _TopicCard({
    required this.title,
    required this.description,
    required this.displayOrder,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Topic number
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '$displayOrder',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Topic info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Arrow
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}