import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageTopicsScreen extends StatefulWidget {
  final String subjectId;
  final String subjectName;
  final Color subjectColor;

  const ManageTopicsScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.subjectColor,
  });

  @override
  State<ManageTopicsScreen> createState() => _ManageTopicsScreenState();
}

class _ManageTopicsScreenState extends State<ManageTopicsScreen> {
  List<Map<String, dynamic>> _topics = [];
  bool _isLoading = true;

  final _topicController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      final response = await Supabase.instance.client
          .from('topics')
          .select()
          .eq('subject_id', widget.subjectId)
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading topics: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addTopic() async {
    final name = _topicController.text.trim();
    if (name.isEmpty) return;

    try {
      await Supabase.instance.client.from('topics').insert({
        'name': name,
        'subject_id': widget.subjectId,
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'display_order': _topics.length,
      });

      _topicController.clear();
      _descriptionController.clear();
      _loadTopics();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Topic added! ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
        title: Text('Edit Topic - ${widget.subjectName}'),
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
              await Supabase.instance.client
                  .from('topics')
                  .update({
                    'name': _topicController.text.trim(),
                    'description': _descriptionController.text.trim().isNotEmpty
                        ? _descriptionController.text.trim()
                        : null,
                  })
                  .eq('id', topic['id']);
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

  Future<void> _deleteTopic(String topicId, String topicName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Topic?'),
        content: Text('Delete "$topicName"? This may affect question bank entries.'),
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
      await Supabase.instance.client.from('topics').delete().eq('id', topicId);
      _loadTopics();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$topicName deleted'), backgroundColor: Colors.orange),
        );
      }
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
      body: Column(
        children: [
          // Add topic bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey.shade50,
            child: Row(
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
          ),
          const Divider(height: 1),

          // Topics list
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: widget.subjectColor))
                : _topics.isEmpty
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
                        onReorder: (oldIndex, newIndex) async {
                          if (newIndex > oldIndex) newIndex--;
                          final topic = _topics.removeAt(oldIndex);
                          _topics.insert(newIndex, topic);
                          setState(() {});
                          for (int i = 0; i < _topics.length; i++) {
                            await Supabase.instance.client
                                .from('topics')
                                .update({'display_order': i})
                                .eq('id', _topics[i]['id']);
                          }
                        },
                        itemBuilder: (context, index) {
                          final topic = _topics[index];
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
                                  child: Text('${index + 1}', style: TextStyle(
                                    color: widget.subjectColor, fontWeight: FontWeight.bold, fontSize: 16,
                                  )),
                                ),
                              ),
                              title: Text(topic['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: topic['description'] != null && (topic['description'] as String).isNotEmpty
                                  ? Text(topic['description'], style: const TextStyle(fontSize: 12, color: Colors.grey))
                                  : null,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit_outlined, size: 20, color: Colors.grey.shade600),
                                    onPressed: () => _editTopic(topic),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                    onPressed: () => _deleteTopic(topic['id'] as String, topic['name'] ?? ''),
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