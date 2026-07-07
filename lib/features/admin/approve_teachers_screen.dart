import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pdf/pdf_viewer_screen.dart';

class ApproveTeachersScreen extends StatefulWidget {
  const ApproveTeachersScreen({super.key});

  @override
  State<ApproveTeachersScreen> createState() => _ApproveTeachersScreenState();
}

class _ApproveTeachersScreenState extends State<ApproveTeachersScreen> {
  List<Map<String, dynamic>> _applications = [];
  Map<String, Map<String, dynamic>> _profiles = {};
  bool _isLoading = true;
  String _filterStatus = 'pending'; // pending, under_review, approved, rejected

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    setState(() => _isLoading = true);
    try {
      // Get applications
      final response = await Supabase.instance.client
          .from('teacher_applications')
          .select('*')
          .eq('status', _filterStatus)
          .order('created_at', ascending: false);

      // Get associated profiles
      final userIds = response.map((a) => a['user_id'] as String).toSet().toList();
      Map<String, Map<String, dynamic>> profiles = {};
      if (userIds.isNotEmpty) {
        final profilesResponse = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, email')
            .inFilter('id', userIds);
        for (final p in profilesResponse) {
          profiles[p['id'] as String] = p;
        }
      }

      if (mounted) {
        setState(() {
          _applications = List<Map<String, dynamic>>.from(response);
          _profiles = profiles;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading applications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _approveApplication(Map<String, dynamic> application) async {
    final profile = _profiles[application['user_id']] ?? {};
    final teacherName = profile['full_name'] ?? 'Teacher';
    
    // ✅ Build preferred mapping from application data
    Map<String, List<String>> preferredMapping = {};
    
    if (application['subject_levels'] != null) {
      final subjectLevels = application['subject_levels'] as Map<String, dynamic>;
      preferredMapping = subjectLevels.map(
        (key, value) => MapEntry(key, List<String>.from(value as List)),
      );
    } else {
      // Fallback for old applications
      final subjects = (application['preferred_subjects'] as List<dynamic>?)?.cast<String>() ?? [];
      final levels = (application['preferred_levels'] as List<dynamic>?)?.cast<String>() ?? [];
      for (final subject in subjects) {
        preferredMapping[subject] = levels;
      }
    }

    final result = await showDialog<Map<String, dynamic>>(
  context: context,
  builder: (ctx) => _AssignSubjectsDialog(
    teacherName: teacherName,
    preferredMapping: preferredMapping, // Map<subject, List<level>>
  ),
);

    if (result == null) return;

    final assignments = result['assignments'] as Map<String, List<String>>;
    final notes = result['notes'] as String? ?? '';

    try {
      // Update application status
      await Supabase.instance.client
          .from('teacher_applications')
          .update({
        'status': 'approved',
        'reviewer_id': Supabase.instance.client.auth.currentUser?.id,
        'review_notes': notes,
        'reviewed_at': DateTime.now().toIso8601String(),
      })
          .eq('id', application['id']);

      // Update profile
      await Supabase.instance.client
          .from('profiles')
          .update({
        'is_approved': true,
        'approval_status': 'approved',
      })
          .eq('id', application['user_id']);

      // ✅ Assign levels and subjects per level
      // ✅ Assign levels and subjects per level
for (final entry in assignments.entries) {
  final subjectName = entry.key;
  final levels = entry.value;

  debugPrint('🔵 Processing: $subjectName -> $levels');

  if (levels.isEmpty) {
    debugPrint('⚠️ No levels for $subjectName, skipping');
    continue;
  }

  // Get subject ID
  final subjectData = await Supabase.instance.client
      .from('subjects')
      .select('id, name')
      .eq('name', subjectName)
      .maybeSingle();

  if (subjectData == null) {
    debugPrint('❌ Subject not found in database: $subjectName');
    continue;
  }
  
  final subjectId = subjectData['id'] as String;
  debugPrint('   Subject ID: $subjectId');

  for (final levelName in levels) {
    // Get level ID
    final levelData = await Supabase.instance.client
        .from('levels')
        .select('id, name')
        .eq('name', levelName)
        .maybeSingle();

    if (levelData == null) {
      debugPrint('❌ Level not found in database: $levelName');
      continue;
    }
    
    final levelId = levelData['id'] as String;
    debugPrint('   Level ID: $levelId ($levelName)');

    // ✅ Add teacher_levels
    final existingLevel = await Supabase.instance.client
        .from('teacher_levels')
        .select('id')
        .eq('teacher_id', application['user_id'])
        .eq('level_id', levelId)
        .maybeSingle();

    if (existingLevel == null) {
      debugPrint('   ➕ Adding teacher_level: ${application['user_id']} -> $levelId');
      try {
        await Supabase.instance.client.from('teacher_levels').insert({
          'teacher_id': application['user_id'],
          'level_id': levelId,
        });
        debugPrint('   ✅ teacher_level added');
      } catch (e) {
        debugPrint('   ❌ Error adding teacher_level: $e');
      }
    } else {
      debugPrint('   ⏭️ teacher_level already exists');
    }

    // ✅ Add teacher_subjects
    final existingSubject = await Supabase.instance.client
        .from('teacher_subjects')
        .select('id')
        .eq('teacher_id', application['user_id'])
        .eq('subject_id', subjectId)
        .eq('level_id', levelId)
        .maybeSingle();

    if (existingSubject == null) {
      debugPrint('   ➕ Adding teacher_subject: ${application['user_id']} -> $subjectId ($subjectName) at $levelId ($levelName)');
      try {
        final insertResult = await Supabase.instance.client.from('teacher_subjects').insert({
          'teacher_id': application['user_id'],
          'subject_id': subjectId,
          'level_id': levelId,
        }).select('id');
        debugPrint('   ✅ teacher_subject added: ${insertResult}');
      } catch (e) {
        debugPrint('   ❌ Error adding teacher_subject: $e');
      }
    } else {
      debugPrint('   ⏭️ teacher_subject already exists');
    }
  }
}

      _loadApplications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$teacherName approved and assigned! ✅'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
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

  Future<void> _rejectApplication(Map<String, dynamic> application) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReviewDialog(
        title: 'Reject Teacher',
        hintText: 'Reason for rejection (required)',
        isRequired: true,
      ),
    );

    if (reason == null || reason.isEmpty) return;

    try {
      await Supabase.instance.client
          .from('teacher_applications')
          .update({
        'status': 'rejected',
        'reviewer_id': Supabase.instance.client.auth.currentUser?.id,
        'review_notes': reason,
        'reviewed_at': DateTime.now().toIso8601String(),
      })
          .eq('id', application['id']);

      await Supabase.instance.client
          .from('profiles')
          .update({
        'approval_status': 'rejected',
      })
          .eq('id', application['user_id']);

      _loadApplications();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_profiles[application['user_id']]?['full_name'] ?? 'Teacher'} rejected'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _markUnderReview(Map<String, dynamic> application) async {
    try {
      await Supabase.instance.client
          .from('teacher_applications')
          .update({'status': 'under_review'})
          .eq('id', application['id']);

      _loadApplications();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF4CAF50);
      case 'rejected':
        return Colors.red;
      case 'under_review':
        return Colors.orange;
      default:
        return Colors.amber;
    }
  }

  Color _getLevelColor(String level) {
  switch (level) {
    case 'Form 1':
      return Colors.blue;
    case 'Form 2':
      return Colors.teal;
    case 'O-Level':
      return const Color(0xFFFF9800);
    case 'A-Level':
      return Colors.purple;
    default:
      return Colors.grey;
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approve Teachers'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'Pending (${_getCount('pending')})',
                    isSelected: _filterStatus == 'pending',
                    onTap: () {
    setState(() => _filterStatus = 'pending');
    _loadApplications(); // ✅ Reload data
  },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Under Review',
                    isSelected: _filterStatus == 'under_review',
                    onTap: () {
    setState(() => _filterStatus = 'under_review');
    _loadApplications(); // ✅ Reload data
  },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Approved',
                    isSelected: _filterStatus == 'approved',
                    onTap: () {
    setState(() => _filterStatus = 'approved');
    _loadApplications(); // ✅ Reload data
  },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Rejected',
                    isSelected: _filterStatus == 'rejected',
                    onTap: () {
    setState(() => _filterStatus = 'rejected');
    _loadApplications(); // ✅ Reload data
  },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Applications list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
                : _applications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'No ${_filterStatus.replaceAll('_', ' ')} applications',
                              style: const TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _applications.length,
                        itemBuilder: (context, index) {
                          final app = _applications[index];
                          final profile = _profiles[app['user_id']] ?? {};
                          final status = app['status'] as String;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: _getStatusColor(status).withOpacity(0.1),
                                      child: Text(
                                        (profile['full_name'] as String? ?? 'T')[0].toUpperCase(),
                                        style: TextStyle(
                                          color: _getStatusColor(status),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            profile['full_name'] ?? 'Unknown',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          Text(
                                            profile['email'] ?? '',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        status.replaceAll('_', ' ').toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _getStatusColor(status),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 12),

                                // Details
                                _DetailRow(label: 'Phone', value: app['phone_number'] ?? 'N/A'),
                                _DetailRow(label: 'Location', value: '${app['city'] ?? ''}, ${app['province'] ?? ''}'),
                                _DetailRow(label: 'Qualification', value: app['highest_qualification'] ?? 'N/A'),
                                _DetailRow(label: 'Experience', value: '${app['teaching_experience_years'] ?? 0} years'),
                                
                                const SizedBox(height: 8),
                                
                                // Subjects
                                // In the card, replace the separate subjects and levels Wraps with this:

// Subject-Level Mapping
if (app['subject_levels'] != null && (app['subject_levels'] as Map<String, dynamic>).isNotEmpty)
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      const Text('Teaches:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      const SizedBox(height: 6),
      ...(app['subject_levels'] as Map<String, dynamic>).entries.map((entry) {
        final subject = entry.key;
        final levels = List<String>.from(entry.value as List);
        final wasPreferred = (app['preferred_subjects'] as List<dynamic>?)?.contains(subject) ?? false;
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subject name
              SizedBox(
                width: 100,
                child: Row(
                  children: [
                    if (wasPreferred)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.star, size: 12, color: Colors.amber),
                      ),
                    Expanded(
                      child: Text(
                        subject,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              // Levels
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: levels.map((level) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getLevelColor(level).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        level,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getLevelColor(level),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }),
    ],
  )
else
  // Fallback for old applications without subject_levels
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if ((app['preferred_subjects'] as List<dynamic>?)?.isNotEmpty == true) ...[
        const SizedBox(height: 8),
        const Text('Subjects:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: (app['preferred_subjects'] as List<dynamic>).map((s) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1A237E).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(s.toString(), style: const TextStyle(fontSize: 11)),
            );
          }).toList(),
        ),
      ],
      if ((app['preferred_levels'] as List<dynamic>?)?.isNotEmpty == true) ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: (app['preferred_levels'] as List<dynamic>).map((l) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _getLevelColor(l.toString()).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(l.toString(), 
                  style: TextStyle(fontSize: 11, color: _getLevelColor(l.toString()))),
            );
          }).toList(),
        ),
      ],
    ],
  ),
                                 const SizedBox(height: 8),
                                 // Documents section
if (app['qualifications_url'] != null || app['cv_url'] != null || 
    (app['certificates_urls'] != null && (app['certificates_urls'] as List).isNotEmpty))
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10),
      const Divider(height: 1),
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.attach_file, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          const Text('Documents:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
        ],
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          // Qualifications PDF
          if (app['qualifications_url'] != null)
            _DocumentChip(
              label: 'Qualifications',
              url: app['qualifications_url'] as String,
              icon: Icons.school,
              color: Colors.blue,
            ),
          
          // CV PDF
          if (app['cv_url'] != null)
            _DocumentChip(
              label: 'CV / Resume',
              url: app['cv_url'] as String,
              icon: Icons.description,
              color: Colors.green,
            ),
          
          // Additional certificates
          if (app['certificates_urls'] != null)
            ...(app['certificates_urls'] as List).asMap().entries.map((entry) {
              return _DocumentChip(
                label: 'Certificate ${entry.key + 1}',
                url: entry.value as String,
                icon: Icons.verified,
                color: Colors.orange,
              );
            }),
        ],
      ),
    ],
  ),

                                if (app['bio'] != null && app['bio'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(app['bio'], style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],

                                if (app['review_notes'] != null && app['review_notes'].toString().isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '📝 ${app['review_notes']}',
                                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                ],

                                // Action buttons
                                if (status == 'pending' || status == 'under_review') ...[
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      if (status == 'pending')
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _markUnderReview(app),
                                            icon: const Icon(Icons.visibility, size: 16),
                                            label: const Text('Review', style: TextStyle(fontSize: 12)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.orange,
                                              side: const BorderSide(color: Colors.orange),
                                            ),
                                          ),
                                        ),
                                      if (status == 'pending') const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _rejectApplication(app),
                                          icon: const Icon(Icons.close, size: 16),
                                          label: const Text('Reject', style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () => _approveApplication(app),
                                          icon: const Icon(Icons.check, size: 16),
                                          label: const Text('Approve', style: TextStyle(fontSize: 12)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF4CAF50),
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  int _getCount(String status) {
    // This is approximate - loads on next refresh
    return _filterStatus == status ? _applications.length : 0;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ReviewDialog extends StatelessWidget {
  final String title;
  final String hintText;
  final bool isRequired;

  const _ReviewDialog({required this.title, required this.hintText, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController();
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title),
      content: TextField(
        controller: controller,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: hintText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (isRequired && controller.text.trim().isEmpty) return;
            Navigator.pop(context, controller.text.trim());
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _AssignSubjectsDialog extends StatefulWidget {
  final String teacherName;
  final Map<String, List<String>> preferredMapping; // subject -> [levels]

  const _AssignSubjectsDialog({
    required this.teacherName,
    required this.preferredMapping,
  });

  @override
  State<_AssignSubjectsDialog> createState() => _AssignSubjectsDialogState();
}

class _AssignSubjectsDialogState extends State<_AssignSubjectsDialog> {
  final _notesController = TextEditingController();
  Map<String, List<String>> _assignments = {}; // subject -> [levels]
  List<Map<String, dynamic>> _allSubjects = [];
  bool _isLoading = true;

  final List<String> _allLevels = ['Form 1', 'Form 2', 'O-Level', 'A-Level'];

  @override
  void initState() {
    super.initState();
    // ✅ Start with teacher's actual preferred mapping
    _assignments = Map.from(widget.preferredMapping);
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final response = await Supabase.instance.client
          .from('subjects')
          .select('name')
          .order('name');
      
      if (mounted) {
        setState(() {
          _allSubjects = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addSubject(String subject) {
    setState(() {
      if (!_assignments.containsKey(subject)) {
        _assignments[subject] = [];
      }
    });
  }

  void _removeSubject(String subject) {
    setState(() {
      _assignments.remove(subject);
    });
  }

  void _toggleLevel(String subject, String level) {
    setState(() {
      if (!_assignments.containsKey(subject)) return;
      if (_assignments[subject]!.contains(level)) {
        _assignments[subject]!.remove(level);
        if (_assignments[subject]!.isEmpty) {
          _assignments.remove(subject);
        }
      } else {
        _assignments[subject]!.add(level);
      }
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subjects NOT yet assigned
    final unassignedSubjects = _allSubjects
        .map((s) => s['name'] as String)
        .where((s) => !_assignments.containsKey(s))
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: 550,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.assignment_ind, color: Color(0xFF1A237E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Assign ${widget.teacherName}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select classes for each subject',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            // ✅ Subject cards with their levels
            Expanded(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_assignments.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Text('No subjects assigned yet.\nAdd subjects below or use "Reset to Preferred".',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ..._assignments.entries.map((entry) {
                      final subjectName = entry.key;
                      final selectedLevels = entry.value;
                      final wasPreferred = widget.preferredMapping.containsKey(subjectName);
                      final preferredLevels = widget.preferredMapping[subjectName] ?? [];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selectedLevels.isNotEmpty
                                ? const Color(0xFF4CAF50).withOpacity(0.3)
                                : Colors.red.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Subject header
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A237E).withOpacity(0.03),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                              ),
                              child: Row(
                                children: [
                                  if (wasPreferred)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.star, size: 14, color: Colors.amber),
                                    ),
                                  Container(
                                    width: 8, height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1A237E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      subjectName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                  ),
                                  if (selectedLevels.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${selectedLevels.length}',
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50)),
                                      ),
                                    ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _removeSubject(subjectName),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.close, size: 14, color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // ✅ Levels for this subject
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _allLevels.map((level) {
                                  final isSelected = selectedLevels.contains(level);
                                  final wasPreferredLevel = preferredLevels.contains(level);
                                  
                                  return FilterChip(
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (wasPreferredLevel)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Icon(Icons.star, size: 10, color: Colors.amber),
                                          ),
                                        Text(level, style: const TextStyle(fontSize: 11)),
                                      ],
                                    ),
                                    selected: isSelected,
                                    onSelected: (_) => _toggleLevel(subjectName, level),
                                    selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
                                    checkmarkColor: const Color(0xFF4CAF50),
                                    backgroundColor: wasPreferredLevel ? Colors.amber.withOpacity(0.05) : null,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  );
                                }).toList(),
                              ),
                            ),
                            if (selectedLevels.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(left: 12, bottom: 8),
                                child: Text('Select at least one class',
                                    style: TextStyle(color: Colors.red, fontSize: 11)),
                              ),
                          ],
                        ),
                      );
                    }),

                  // Add more subjects
                  if (unassignedSubjects.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Add more subjects:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: unassignedSubjects.map((subject) {
                        final wasPreferred = widget.preferredMapping.containsKey(subject);
                        return ActionChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (wasPreferred)
                                const Padding(
                                  padding: EdgeInsets.only(right: 3),
                                  child: Icon(Icons.star, size: 12, color: Colors.amber),
                                ),
                              Text(subject, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                          avatar: const Icon(Icons.add, size: 14),
                          onPressed: () => _addSubject(subject),
                          backgroundColor: wasPreferred ? Colors.amber.withOpacity(0.1) : Colors.grey.shade100,
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Quick actions
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      // ✅ Reset to exact teacher preferences
                      _assignments = Map.from(widget.preferredMapping);
                    });
                  },
                  icon: const Icon(Icons.star, size: 14, color: Colors.amber),
                  label: const Text('Reset to Preferred', style: TextStyle(fontSize: 11)),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _assignments.clear()),
                  icon: const Icon(Icons.clear_all, size: 14),
                  label: const Text('Clear All', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Notes
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final hasEmpty = _assignments.entries.any((e) => e.value.isEmpty);
                      if (_assignments.isEmpty || hasEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Each subject needs at least one class'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context, {
                        'assignments': _assignments, // Map<subject, List<level>>
                        'notes': _notesController.text.trim(),
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Approve & Assign'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentChip extends StatelessWidget {
  final String label;
  final String url;
  final IconData icon;
  final Color color;

  const _DocumentChip({
    required this.label,
    required this.url,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openDocument(context, url, label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new, size: 12, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _openDocument(BuildContext context, String url, String title) async {
  // ✅ Open in-app PDF viewer
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PdfViewerScreen(url: url, title: title),
    ),
  );
}
}