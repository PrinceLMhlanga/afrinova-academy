import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/resource_service.dart';

class ResourceLibraryScreen extends StatefulWidget {
  const ResourceLibraryScreen({super.key});

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen> {
  final ResourceService _resourceService = ResourceService();
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _resources = [];
  Map<String, Map<String, dynamic>> _enrollments = {};
  List<String> _enrolledSubjectIds = [];
  List<Map<String, dynamic>> _subjects = [];
  String? _selectedSubjectId;
  String _selectedType = 'all';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get enrollments
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('id, teacher_id, subject_id, status, trial_ends_at, is_subscribed, subscription_expires_at')
          .eq('student_id', userId)
          .inFilter('status', ['approved', 'paid']);

      final enrollmentMap = <String, Map<String, dynamic>>{};
      final teacherIds = <String>{};
      final subjectIds = <String>{};
      final subjectMap = <String, Map<String, dynamic>>{};

      for (final e in enrollments) {
        final teacherId = e['teacher_id'] as String;
        final subjectId = e['subject_id'] as String;
        teacherIds.add(teacherId);
        subjectIds.add(subjectId);
        enrollmentMap[teacherId] = e;
      }

      // Get subject names
      List<Map<String, dynamic>> subjects = [];
      if (subjectIds.isNotEmpty) {
        subjects = await Supabase.instance.client
            .from('subjects')
            .select('id, name')
            .inFilter('id', subjectIds.toList())
            .eq('is_active', true)
            .order('display_order');

        for (final s in subjects) {
          subjectMap[s['id'] as String] = s;
        }
      }

      // Get student's level
      String? studentLevelId;
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('level_id')
          .eq('id', userId)
          .maybeSingle();
      studentLevelId = profile?['level_id'] as String?;

      // Get resources
      List<Map<String, dynamic>> resources = [];
      if (teacherIds.isNotEmpty) {
        var query = Supabase.instance.client
            .from('resources')
            .select('*, subjects(name), profiles!teacher_id(full_name), levels(name)')
            .inFilter('teacher_id', teacherIds.toList());

        // ✅ Only add level filter if student has a level
        if (studentLevelId != null && studentLevelId.isNotEmpty) {
          query = query.eq('level_id', studentLevelId);
        }

        // ✅ Apply subject filter
        if (_selectedSubjectId != null && _selectedSubjectId!.isNotEmpty) {
          query = query.eq('subject_id', _selectedSubjectId!);
        }

        // ✅ Apply type filter
        if (_selectedType != 'all') {
          query = query.eq('resource_type', _selectedType);
        }

        final response = await query.order('created_at', ascending: false);
        resources = List<Map<String, dynamic>>.from(response);
      }

      if (mounted) {
        setState(() {
          _enrollments = enrollmentMap;
          _enrolledSubjectIds = subjectIds.toList();
          _subjects = subjects;
          _resources = resources;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Resource load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Access check
  bool _canAccessResource(Map<String, dynamic> resource) {
    final teacherId = resource['teacher_id'] as String?;  // ✅ Changed from uploaded_by
    if (teacherId == null) return false;

    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return false;

    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (expiry.isAfter(DateTime.now())) return true;
      }
    }

    // ✅ Check trial
    if (enrollment['is_subscribed'] != true) {
      final trialEndsAt = enrollment['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        return DateTime.now().isBefore(trialEnd);
      }
    }

    return false;
  }

  // ✅ Status text
  String _getAccessStatus(Map<String, dynamic> resource) {
    final teacherId = resource['teacher_id'] as String?;  // ✅ Changed
    if (teacherId == null) return '';

    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return '';

    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        if (daysLeft <= 0) return 'Subscription Ended';
        return 'Subscribed ✅';
      }
    }

    final trialEndsAt = enrollment['trial_ends_at'] as String?;
    if (trialEndsAt != null) {
      final trialEnd = DateTime.parse(trialEndsAt);
      final daysLeft = trialEnd.difference(DateTime.now()).inDays;
      if (daysLeft <= 0) return 'Trial Ended';
      return '$daysLeft days free';
    }

    return '';
  }

  Future<void> _openFile(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
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
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resource Library'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(label: 'All', isSelected: _selectedType == 'all',
                          onTap: () { setState(() => _selectedType = 'all'); _loadData(); }),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Notes', icon: Icons.menu_book, isSelected: _selectedType == 'notes',
                          onTap: () { setState(() => _selectedType = 'notes'); _loadData(); }),
                      const SizedBox(width: 8),
                      _FilterChip(label: 'Question Papers', icon: Icons.quiz, isSelected: _selectedType == 'question_paper',
                          onTap: () { setState(() => _selectedType = 'question_paper'); _loadData(); }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(label: 'All Subjects', isSelected: _selectedSubjectId == null,
                          onTap: () { setState(() => _selectedSubjectId = null); _loadData(); }),
                      const SizedBox(width: 8),
                      ..._subjects.map((s) {
                        final id = s['id'] as String;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _FilterChip(
                            label: s['name'] ?? '',
                            isSelected: _selectedSubjectId == id,
                            onTap: () { setState(() => _selectedSubjectId = id); _loadData(); },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
                : _resources.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_off, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('No resources found', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _resources.length,
                        itemBuilder: (context, index) {
                          final r = _resources[index];
                          final canAccess = _canAccessResource(r);
                          final statusText = _getAccessStatus(r);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: canAccess
                                      ? _getFileColor(r['file_type']).withOpacity(0.1)
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  canAccess ? _getFileIcon(r['file_type']) : Icons.lock_outline,
                                  color: canAccess ? _getFileColor(r['file_type']) : Colors.grey,
                                ),
                              ),
                              title: Text(
                                r['title'] ?? 'Untitled',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: canAccess ? Colors.black87 : Colors.grey,
                                ),
                              ),
                              subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (r['subjects'] != null)
      Text(r['subjects']['name'] ?? '',
          style: TextStyle(fontSize: 11, color: canAccess ? const Color(0xFF1A237E) : Colors.grey)),
    // ✅ Teacher name
    if (r['profiles'] != null)
      Text('By: ${r['profiles']['full_name'] ?? 'Teacher'}',
          style: TextStyle(fontSize: 10, color: canAccess ? Colors.grey.shade600 : Colors.grey.shade400)),
    Text(
      '${_formatFileSize(r['file_size_bytes'])} • ${r['resource_type'] == 'question_paper' ? 'Question Paper' : 'Notes'}',
      style: TextStyle(fontSize: 11, color: canAccess ? Colors.grey : Colors.grey.shade400),
    ),
    if (statusText.isNotEmpty)
      Text(statusText,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: statusText.contains('Ended') ? Colors.red : const Color(0xFF4CAF50))),
  ],
),
                              trailing: canAccess
                                  ? const Icon(Icons.download, color: Color(0xFFFF9800))
                                  : const Icon(Icons.lock, color: Colors.grey, size: 20),
                              onTap: canAccess ? () => _openFile(r['file_url'] ?? '') : null,
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

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            )),
          ],
        ),
      ),
    );
  }
}