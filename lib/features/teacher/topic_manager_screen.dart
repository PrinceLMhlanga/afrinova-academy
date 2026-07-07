import 'package:flutter/material.dart';
import '../../core/teacher_service.dart';
import '../../core/auth_service.dart';
import 'upload_lesson_screen.dart';
import 'upload_resource_screen.dart';

class TopicManagerScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final Color subjectColor;
  final String levelId;  // ✅ Added
  final String levelName;

  const TopicManagerScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.subjectColor,
    required this.levelId,
    required this.levelName,
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
        final topics = await _teacherService.getMyTopics(
          userId, 
          widget.subjectId,
          levelId: widget.levelId,  // ✅ Filter by level
        );
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
      levelId: widget.levelId,  // ✅ Pass level
    );

    _topicController.clear();
    _descriptionController.clear();
    _loadTopics();
  }

  Future<void> _deleteTopic(String topicId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Topic?'),
        content: const Text('This will also delete all lessons and resources under this topic.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await _teacherService.deleteTopic(topicId);
      _loadTopics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Topic deleted'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _editTopic(Map<String, dynamic> topic) async {
    _topicController.text = topic['name'] ?? '';
    _descriptionController.text = topic['description'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Topic'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _topicController,
              decoration: InputDecoration(
                labelText: 'Topic Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (_topicController.text.trim().isEmpty) return;
              await _teacherService.updateTopic(
                topicId: topic['id'] as String,
                name: _topicController.text.trim(),
                description: _descriptionController.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _topicController.clear();
              _descriptionController.clear();
              _loadTopics();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.subjectColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _reorderTopics(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final topic = _topics.removeAt(oldIndex);
    _topics.insert(newIndex, topic);
    setState(() {});

    // Update display order in database
    for (int i = 0; i < _topics.length; i++) {
      await _teacherService.updateTopicOrder(
        topicId: _topics[i]['id'] as String,
        displayOrder: i,
      );
    }
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
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _topicController,
                              decoration: InputDecoration(
                                hintText: 'Enter topic name...',
                                prefixIcon: Icon(Icons.topic_rounded, color: widget.subjectColor),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                isDense: true,
                              ),
                              onFieldSubmitted: (_) => _addTopic(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: _addTopic,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.subjectColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Topics list
                Expanded(
                  child: _topics.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.topic_outlined, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              const Text('No topics yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('Add topics for ${widget.subjectName}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _topics.length,
                          onReorder: _reorderTopics,
                          buildDefaultDragHandles: true,
                          itemBuilder: (context, index) {
                            final topic = _topics[index];
                            final topicName = topic['name'] ?? '';
                            final topicDesc = topic['description'] ?? '';

                            return Card(
                              key: Key(topic['id'] as String),
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                leading: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: widget.subjectColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: widget.subjectColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  topicName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                                subtitle: topicDesc.isNotEmpty
                                    ? Text(topicDesc, style: const TextStyle(fontSize: 12, color: Colors.grey))
                                    : null,
                                trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    // ✅ Upload Lesson button
    IconButton(
      icon: Icon(Icons.upload_file, size: 18, color: widget.subjectColor),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UploadLessonScreen(
              preSelectedLevelId: widget.levelId,
              preSelectedLevelName: widget.levelName,  // ✅ Actual level name
              preSelectedSubjectId: widget.subjectId,
              preSelectedSubjectName: widget.subjectName,
              preSelectedTopicId: topic['id'] as String,
              preSelectedTopicName: topicName,
            ),
          ),
        ).then((_) => _loadTopics());
      },
      tooltip: 'Upload Lesson',
    ),
    // Add this next to the lesson upload button
IconButton(
  icon: Icon(Icons.attach_file, size: 20, color: widget.subjectColor),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UploadResourceScreen(
          preSelectedLevelId: widget.levelId,
          preSelectedLevelName: widget.levelName,
          preSelectedSubjectId: widget.subjectId,
          preSelectedSubjectName: widget.subjectName,
          preSelectedTopicId: topic['id'] as String,
          preSelectedTopicName: topic['name'] ?? '',
        ),
      ),
    ).then((_) => _loadTopics());
  },
  tooltip: 'Upload Resource',
),
    // Edit button
    IconButton(
      icon: Icon(Icons.edit_outlined, size: 20, color: Colors.grey.shade600),
      onPressed: () => _editTopic(topic),
      tooltip: 'Edit',
    ),
    // Delete button
    IconButton(
      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
      onPressed: () => _deleteTopic(topic['id'] as String),
      tooltip: 'Delete',
    ),
    ReorderableDragStartListener(
      index: index,
      child: const Icon(Icons.drag_handle, color: Colors.grey, size: 20),
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