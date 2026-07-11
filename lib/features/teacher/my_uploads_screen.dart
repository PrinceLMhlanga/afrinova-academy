import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'upload_resource_screen.dart';
import '../pdf/pdf_viewer_screen.dart'; // ✅ Import your inline PDF viewer

class MyUploadsScreen extends StatefulWidget {
  const MyUploadsScreen({super.key});

  @override
  State<MyUploadsScreen> createState() => _MyUploadsScreenState();
}

class _MyUploadsScreenState extends State<MyUploadsScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _resources = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadUploads();
  }

  Future<void> _loadUploads() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // ✅ Load resources with level, subject, and topic info
      final response = await Supabase.instance.client
          .from('resources')
          .select('*, teacher_topics!inner(name, subject_id, level_id, subjects!inner(name), levels!inner(name))')
          .eq('teacher_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _resources = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading uploads: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredResources {
    if (_selectedFilter == 'all') return _resources;
    return _resources
        .where((r) => r['resource_type'] == _selectedFilter)
        .toList();
  }

  Future<void> _deleteResource(Map<String, dynamic> resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Resource?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete "${resource['title'] ?? 'this resource'}"?'),
            const SizedBox(height: 8),
            const Text(
              'This will permanently remove the file from storage and database.',
              style: TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ),
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

    if (confirmed == true) {
      try {
        // Delete from storage
        final fileUrl = resource['file_url'] as String?;
        if (fileUrl != null) {
          final path = Uri.parse(fileUrl).path;
          await Supabase.instance.client.storage.from('resources').remove([path]);
        }
        // Delete from database
        await Supabase.instance.client.from('resources').delete().eq('id', resource['id'] as String);
        _loadUploads();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Resource deleted successfully'), backgroundColor: Color(0xFF4CAF50)),
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
  }

  Future<void> _openFile(String url) async {
  // ✅ Open in your inline PDF viewer instead of external browser
  final fileName = url.split('/').last;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PdfViewerScreen(url: url, title: fileName),
    ),
  );
}

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  IconData _getFileIcon(String? type) {
    switch (type) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': return Icons.description;
      case 'ppt': return Icons.slideshow;
      case 'image': return Icons.image;
      default: return Icons.attach_file;
    }
  }

  Color _getFileColor(String? type) {
    switch (type) {
      case 'pdf': return Colors.red;
      case 'doc': return Colors.blue;
      case 'ppt': return Colors.orange;
      case 'image': return Colors.purple;
      default: return Colors.grey;
    }
  }

  Color _getLevelColor(String? level) {
    switch (level) {
      case 'Form 1': return Colors.blue;
      case 'Form 2': return Colors.teal;
      case 'O-Level': return const Color(0xFFFF9800);
      case 'A-Level': return Colors.purple;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredResources = _filteredResources;
    final totalSize = _resources.fold<int>(0, (sum, r) => sum + ((r['file_size_bytes'] as int?) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Uploads'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Upload New Resource',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UploadResourceScreen()),
              ).then((_) => _loadUploads());
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : Column(
              children: [
                // Stats bar
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      _StatItem(icon: Icons.folder, label: 'Files', value: '${_resources.length}', color: const Color(0xFF1A237E)),
                      const SizedBox(width: 24),
                      _StatItem(icon: Icons.storage, label: 'Total Size', value: _formatFileSize(totalSize), color: const Color(0xFFFF9800)),
                      const Spacer(),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _MiniFilterChip(label: 'All', isSelected: _selectedFilter == 'all', onTap: () => setState(() => _selectedFilter = 'all')),
                            const SizedBox(width: 6),
                            _MiniFilterChip(label: 'Notes', isSelected: _selectedFilter == 'notes', onTap: () => setState(() => _selectedFilter = 'notes')),
                            const SizedBox(width: 6),
                            _MiniFilterChip(label: 'Papers', isSelected: _selectedFilter == 'question_paper', onTap: () => setState(() => _selectedFilter = 'question_paper')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Resource list
                Expanded(
                  child: filteredResources.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(_resources.isEmpty ? 'No uploads yet' : 'No items found',
                                  style: const TextStyle(fontSize: 16, color: Colors.grey)),
                              if (_resources.isEmpty) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const UploadResourceScreen()),
                                    ).then((_) => _loadUploads());
                                  },
                                  icon: const Icon(Icons.upload),
                                  label: const Text('Upload Your First File'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1A237E),
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadUploads,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredResources.length,
                            itemBuilder: (context, index) {
                              final r = filteredResources[index];
                              final fileType = r['file_type'] as String?;
                              final resourceType = r['resource_type'] as String?;
                              
                              // ✅ Extract joined data
                              final topicData = r['teacher_topics'] as Map<String, dynamic>?;
                              final topicName = topicData?['name'] ?? 'Unknown Topic';
                              final levelData = topicData?['levels'] as Map<String, dynamic>?;
                              final levelName = levelData?['name'] ?? '';
                              final subjectData = topicData?['subjects'] as Map<String, dynamic>?;
                              final subjectName = subjectData?['name'] ?? '';

                              return Dismissible(
                                key: Key(r['id'] as String),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) async {
                                  await _deleteResource(r);
                                  return false;
                                },
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () => _openFile(r['file_url'] ?? ''),
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // File icon
                                          Container(
                                            width: 52, height: 52,
                                            decoration: BoxDecoration(
                                              color: _getFileColor(fileType).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Icon(_getFileIcon(fileType), color: _getFileColor(fileType), size: 26),
                                          ),
                                          const SizedBox(width: 14),
                                          // File info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  r['title'] ?? 'Untitled',
                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1A237E)),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                // ✅ Level → Subject → Topic
                                                Row(
                                                  children: [
                                                    if (levelName.isNotEmpty)
                                                      _LevelBadge(label: levelName, color: _getLevelColor(levelName)),
                                                    if (levelName.isNotEmpty) const SizedBox(width: 4),
                                                    if (subjectName.isNotEmpty)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1A237E).withOpacity(0.1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(subjectName, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF1A237E))),
                                                      ),
                                                    if (subjectName.isNotEmpty) const SizedBox(width: 4),
                                                    Text(topicName, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                // Size + Date + Downloads
                                                Row(
                                                  children: [
                                                    Text(_formatFileSize(r['file_size_bytes']),
                                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                    const SizedBox(width: 8),
                                                    Text('•', style: TextStyle(color: Colors.grey.shade400)),
                                                    const SizedBox(width: 8),
                                                    Text(_formatDate(r['created_at']),
                                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                    const SizedBox(width: 8),
                                                    Text('•', style: TextStyle(color: Colors.grey.shade400)),
                                                    const SizedBox(width: 8),
                                                    Icon(Icons.download_done, size: 12, color: Colors.grey.shade400),
                                                    Text('${r['download_count'] ?? 0}',
                                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          // Actions
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.download, size: 20, color: Color(0xFF1A237E)),
                                                onPressed: () => _openFile(r['file_url'] ?? ''),
                                                tooltip: 'Open',
                                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                padding: EdgeInsets.zero,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                                onPressed: () => _deleteResource(r),
                                                tooltip: 'Delete',
                                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                                padding: EdgeInsets.zero,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _LevelBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatItem({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ],
    );
  }
}

class _MiniFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _MiniFilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : Colors.grey.shade600),
        ),
      ),
    );
  }
}