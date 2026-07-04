import 'package:flutter/material.dart';
import '../../core/teacher_service.dart';
import '../../core/auth_service.dart';

class TopicManagerScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final Color subjectColor;

  const TopicManagerScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.subjectColor,
  });

  @override
  State<TopicManagerScreen> createState() => _TopicManagerScreenState();
}

class _TopicManagerScreenState extends State<TopicManagerScreen> {
  final TeacherService _teacherService = TeacherService();
  final AuthService _authService = AuthService();
  final _topicController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _topics = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      final userId = _authService.currentUserId;
      if (userId != null) {
        final topics = await _teacherService.getMyTopics(userId, widget.subjectId);
        if (mounted) setState(() { _topics = topics; _isLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addTopic() async {
    final name = _topicController.text.trim();
    if (name.isEmpty) return;

    final userId = _authService.currentUserId;
    if (userId == null) return;

    await _teacherService.addTopic(
      teacherId: userId,
      subjectId: widget.subjectId,
      name: name,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      displayOrder: _topics.length,
    );

    _topicController.clear();
    _descriptionController.clear();
    _loadTopics();
  }

  Future<void> _deleteTopic(String topicId) async {
    await _teacherService.deleteTopic(topicId);
    _loadTopics();
  }

  Future<void> _editTopic(Map<String, dynamic> topic) async {
    _topicController.text = topic['name'] ?? '';
    _descriptionController.text = topic['description'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Topic'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(labelText: 'Topic Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _teacherService.updateTopic(
                topicId: topic['id'] as String,
                name: _topicController.text.trim(),
                description: _descriptionController.text.trim(),
              );
              Navigator.pop(ctx);
              _topicController.clear();
              _descriptionController.clear();
              _loadTopics();
            },
            style: ElevatedButton.styleFrom(backgroundColor: widget.subjectColor),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _topicController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} Topics'),
        backgroundColor: widget.subjectColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: widget.subjectColor))
          : Column(
              children: [
                // Add topic form
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _topicController,
                          decoration: InputDecoration(
                            hintText: 'Topic name...',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addTopic,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.subjectColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ),

                // Topics list
                Expanded(
                  child: _topics.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.topic_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text('No topics yet', style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 4),
                              Text('Add topics for ${widget.subjectName}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _topics.length,
                          onReorder: (oldIndex, newIndex) async {
                            if (newIndex > oldIndex) newIndex--;
                            final topic = _topics.removeAt(oldIndex);
                            _topics.insert(newIndex, topic);
                            setState(() {});
                          },
                          itemBuilder: (context, index) {
                            final topic = _topics[index];
                            return Card(
                              key: Key(topic['id'] as String),
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                leading: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: widget.subjectColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text('${index + 1}',
                                        style: TextStyle(color: widget.subjectColor, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                                title: Text(topic['name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.edit, size: 18, color: Colors.grey.shade600),
                                      onPressed: () => _editTopic(topic),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                      onPressed: () => _deleteTopic(topic['id'] as String),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}