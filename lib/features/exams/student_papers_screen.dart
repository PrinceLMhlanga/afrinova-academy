import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../payment/payment_screen.dart';
import 'paper_view_screen.dart';
import 'student_paper_results_screen.dart';
import '../../core/access_checker.dart';  // ✅ Add

class StudentPapersScreen extends StatefulWidget {
  const StudentPapersScreen({super.key});

  @override
  State<StudentPapersScreen> createState() => _StudentPapersScreenState();
}

class _StudentPapersScreenState extends State<StudentPapersScreen>
    with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();

  late TabController _tabController;
  List<Map<String, dynamic>> _allPapers = [];
  Map<String, Map<String, dynamic>> _submissions = {};
  Map<String, Map<String, dynamic>> _enrollments = {};
  bool _isLoading = true;

  Map<String, bool> _paperAccessCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  Future<bool> _canAccessExamPrep(String teacherId) async {
  if (_paperAccessCache.containsKey(teacherId)) {
    return _paperAccessCache[teacherId]!;
  }

  try {
    final userId = _authService.currentUserId;
    if (userId == null) return false;

    final enrollment = await Supabase.instance.client
        .from('enrollments')
        .select('plan_features, is_subscribed, subscription_expires_at, trial_ends_at')
        .eq('student_id', userId)
        .eq('teacher_id', teacherId)
        .maybeSingle();

    final hasAccess = AccessChecker.canAccessExamPrep(enrollment);
    _paperAccessCache[teacherId] = hasAccess;
    return hasAccess;
  } catch (e) {
    return true;
  }
}

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // Get enrollments with full trial + subscription info
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('id, teacher_id, subject_id, status, trial_ends_at, is_subscribed, subscription_expires_at')
          .eq('student_id', userId)
          .inFilter('status', ['approved', 'paid']);

      final enrollmentMap = <String, Map<String, dynamic>>{};
      final teacherIds = <String>{};
      for (final e in enrollments) {
        final teacherId = e['teacher_id'] as String;
        teacherIds.add(teacherId);
        enrollmentMap[teacherId] = e;
      }

      // Load published papers ONLY from enrolled teachers
      List<Map<String, dynamic>> papers = [];
if (teacherIds.isNotEmpty) {
  String? studentLevelId;
  if (userId != null) {
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('level_id')
        .eq('id', userId)
        .maybeSingle();
    studentLevelId = profile?['level_id'] as String?;
  }

  final response = await Supabase.instance.client
      .from('exam_papers')
      .select('*, subjects(name), profiles!creator_id(display_name, full_name), levels(name)')
      .eq('is_published', true)
      .eq('level_id', studentLevelId ?? '')
      .inFilter('creator_id', teacherIds.toList())
      .order('created_at', ascending: false);

  papers = List<Map<String, dynamic>>.from(response);
}

      // Load ALL student's answers
      final allAnswers = await Supabase.instance.client
          .from('exam_answers')
          .select('paper_id, status, marks_awarded, teacher_comment, marked_at')
          .eq('student_id', userId);

      if (mounted) {
        setState(() {
          _allPapers = List<Map<String, dynamic>>.from(papers);
          _enrollments = enrollmentMap;

          final Map<String, Map<String, dynamic>> submissionsMap = {};
          for (final a in allAnswers) {
  final paperId = a['paper_id'] as String;
  final answerStatus = a['status'] as String? ?? 'draft';

  if (!submissionsMap.containsKey(paperId)) {
    submissionsMap[paperId] = {
      'paper_id': paperId,
      'status': answerStatus,
      'total_marks_awarded': 0,
      'marked_at': a['marked_at'],
      'teacher_comment': a['teacher_comment'],
    };
  }

  // ✅ Add marks
  submissionsMap[paperId]!['total_marks_awarded'] =
      (submissionsMap[paperId]!['total_marks_awarded'] as int) +
          ((a['marks_awarded'] as int?) ?? 0);

  // ✅ Upgrade status — highest priority wins
  final currentStatus = submissionsMap[paperId]!['status'] as String;
  if (answerStatus == 'marked' || currentStatus == 'marked') {
    submissionsMap[paperId]!['status'] = 'marked';
  } else if (answerStatus == 'submitted' || currentStatus == 'submitted') {
    submissionsMap[paperId]!['status'] = 'submitted';
  } else if (answerStatus == 'draft' || currentStatus == 'draft') {
    submissionsMap[paperId]!['status'] = 'draft';
  }
}
          _submissions = submissionsMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ Priority-based access check
  bool _canAccess(String teacherId) {
    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return false;

    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        if (expiry.isAfter(DateTime.now())) return true;
      }
    }

    if (enrollment['is_subscribed'] != true) {
      final trialEndsAt = enrollment['trial_ends_at'] as String?;
      if (trialEndsAt != null) {
        final trialEnd = DateTime.parse(trialEndsAt);
        return DateTime.now().isBefore(trialEnd);
      }
    }

    return false;
  }

  // ✅ Priority-based status text
  String _getStatusText(String teacherId) {
    final enrollment = _enrollments[teacherId];
    if (enrollment == null) return '';

    if (enrollment['is_subscribed'] == true) {
      final expiresAt = enrollment['subscription_expires_at'] as String?;
      if (expiresAt != null) {
        final expiry = DateTime.parse(expiresAt);
        final daysLeft = expiry.difference(DateTime.now()).inDays;
        if (daysLeft <= 0) return 'Subscription Ended';
        if (daysLeft <= 3) return 'Subscribed — $daysLeft days left ⚠️';
        return 'Subscribed ✅';
      }
    }

    final trialEndsAt = enrollment['trial_ends_at'] as String?;
    if (trialEndsAt != null) {
      final trialEnd = DateTime.parse(trialEndsAt);
      final daysLeft = trialEnd.difference(DateTime.now()).inDays;
      if (daysLeft <= 0) return 'Trial Ended';
      if (daysLeft <= 3) return '$daysLeft days left ⚠️';
      return '$daysLeft days free';
    }

    return '';
  }

  Color _getStatusColor(String status) {
    if (status.contains('Ended')) return Colors.red;
    if (status.contains('⚠️')) return Colors.orange;
    if (status.contains('Subscribed')) return const Color(0xFF4CAF50);
    return Colors.green;
  }

  List<Map<String, dynamic>> get _availablePapers {
    return _allPapers.where((p) => !_submissions.containsKey(p['id'])).toList();
  }

  List<Map<String, dynamic>> get _pendingPapers {
    return _allPapers.where((p) {
      final sub = _submissions[p['id']];
      return sub != null && (sub['status'] == 'submitted' || sub['status'] == 'draft');
    }).toList();
  }

  List<Map<String, dynamic>> get _markedPapers {
    return _allPapers.where((p) {
      final sub = _submissions[p['id']];
      return sub != null && sub['status'] == 'marked';
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Papers'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Available (${_availablePapers.length})'),
            Tab(text: 'Pending (${_pendingPapers.length})'),
            Tab(text: 'Marked (${_markedPapers.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
          : TabBarView(controller: _tabController, children: [
              _buildAvailableTab(),
              _buildPendingTab(),
              _buildMarkedTab(),
            ]),
    );
  }

  Widget _buildAvailableTab() {
    if (_availablePapers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No exam papers available', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _availablePapers.length,
        itemBuilder: (context, index) {
          final paper = _availablePapers[index];
          final creatorId = paper['creator_id'] as String? ?? '';
          final canAccess = _canAccess(creatorId);
          final statusText = _getStatusText(creatorId);
          final statusColor = _getStatusColor(statusText);
          final isExpired = statusText.contains('Ended');
          final isSubscriptionExpired = statusText == 'Subscription Ended';

          return _PaperCard(
            paper: paper,
            canAccess: canAccess,
            statusText: statusText,
            statusColor: statusColor,
            onTap: canAccess
    ? () async {
        final hasFeatureAccess = await _canAccessExamPrep(creatorId);
        if (hasFeatureAccess) {
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PaperViewScreen(paper: paper)),
            ).then((_) => _loadData());
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Exam papers require a premium plan. Upgrade to access.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    : null,
            trailing: isExpired
    ? GestureDetector(
        onTap: () {
          final enrollment = _enrollments[creatorId];
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => PaymentScreen(
              teacherId: creatorId,
              teacherName: paper['profiles']?['display_name'] ?? paper['profiles']?['full_name'] ?? 'Teacher',
              subjectName: paper['subjects']?['name'] ?? '',
              enrollmentId: enrollment?['id'] as String? ?? '',
              subjectId: enrollment?['subject_id'] as String?,
              levelId: enrollment?['level_id'] as String?,
            ),
          )).then((_) => _loadData());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF283593)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isSubscriptionExpired ? 'Renew' : 'Subscribe',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      )
    : canAccess
        ? FutureBuilder<bool>(
            future: _canAccessExamPrep(creatorId),
            builder: (context, snapshot) {
              final hasFeatureAccess = snapshot.data ?? true;
              if (!hasFeatureAccess) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 12, color: Colors.orange),
                      SizedBox(width: 3),
                      Text('Upgrade', style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }
              return ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PaperViewScreen(paper: paper)),
                  ).then((_) => _loadData());
                },
                icon: const Icon(Icons.edit_note, size: 18),
                label: const Text('Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
          )
        : const Icon(Icons.lock, color: Colors.grey, size: 20),
          );
        },
      ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingPapers.isEmpty) return _emptyTab('No pending papers', 'Submitted papers awaiting marking appear here');
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _pendingPapers.length,
        itemBuilder: (context, index) {
          final paper = _pendingPapers[index];
          final sub = _submissions[paper['id']];
          final status = sub?['status'] as String? ?? 'submitted';
          final creatorId = paper['creator_id'] as String? ?? '';
          final canAccess = _canAccess(creatorId);
          final statusText = _getStatusText(creatorId);
          final statusColor = _getStatusColor(statusText);

          return _PaperCard(
            paper: paper, canAccess: canAccess, statusText: statusText, statusColor: statusColor,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: status == 'submitted' ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(status == 'submitted' ? Icons.check_circle : Icons.edit, size: 16,
                    color: status == 'submitted' ? Colors.orange : Colors.grey),
                const SizedBox(width: 4),
                Text(status == 'submitted' ? 'Submitted' : 'In Progress',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: status == 'submitted' ? Colors.orange : Colors.grey)),
              ]),
            ),
            onTap: canAccess
    ? () async {
        final hasFeatureAccess = await _canAccessExamPrep(creatorId);
        if (hasFeatureAccess) {
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PaperViewScreen(paper: paper)),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Exam papers require a premium plan. Upgrade to access.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    : null,
          );
        },
      ),
    );
  }

  Widget _buildMarkedTab() {
    if (_markedPapers.isEmpty) return _emptyTab('No marked papers yet', 'Your marked papers with results will appear here');
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _markedPapers.length,
        itemBuilder: (context, index) {
          final paper = _markedPapers[index];
          final sub = _submissions[paper['id']];
          final marks = sub?['total_marks_awarded'] as int?;
          final totalMarks = paper['total_marks'] as int? ?? 0;
          final creatorId = paper['creator_id'] as String? ?? '';
          final canAccess = _canAccess(creatorId);
          final statusText = _getStatusText(creatorId);
          final statusColor = _getStatusColor(statusText);

          return _PaperCard(
            paper: paper, canAccess: canAccess, statusText: statusText, statusColor: statusColor,
            onTap: canAccess && sub != null
    ? () async {
        final hasFeatureAccess = await _canAccessExamPrep(creatorId);
        if (hasFeatureAccess) {
          if (context.mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StudentPaperResultsScreen(paper: paper, submission: sub),
              ),
            );
          }
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Exam papers require a premium plan. Upgrade to access.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF4CAF50).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle, size: 16, color: Color(0xFF4CAF50)),
                const SizedBox(width: 4),
                Text(marks != null ? '$marks / $totalMarks' : 'Marked ✅',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4CAF50))),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyTab(String title, String subtitle) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 16)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ]),
    );
  }
}

class _PaperCard extends StatelessWidget {
  final Map<String, dynamic> paper;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool canAccess;
  final String statusText;
  final Color statusColor;

  const _PaperCard({
    required this.paper,
    this.trailing,
    this.onTap,
    this.canAccess = true,
    this.statusText = '',
    this.statusColor = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: canAccess ? const Color(0xFF00897B).withOpacity(0.1) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(canAccess ? Icons.assignment : Icons.lock_outline,
                    color: canAccess ? const Color(0xFF00897B) : Colors.grey),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(paper['title'] ?? 'Untitled',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                          color: canAccess ? Colors.black87 : Colors.grey)),
                  const SizedBox(height: 3),
                  Text('${paper['subjects']?['name'] ?? ''} • ${paper['curriculum'] ?? ''} ${paper['paper_type'] ?? ''}',
                      style: TextStyle(fontSize: 12, color: canAccess ? Colors.grey : Colors.grey.shade400)),
                  Text('${paper['total_marks'] ?? 0} marks • ${paper['duration_minutes'] ?? 0} min',
                      style: TextStyle(fontSize: 11, color: canAccess ? Colors.grey : Colors.grey.shade400)),
                  if (paper['profiles'] != null)
                    Text('By: ${paper['profiles']['display_name'] ?? paper['profiles']['full_name'] ?? ''}',
                        style: TextStyle(fontSize: 11, color: canAccess ? const Color(0xFF1A237E) : Colors.grey)),
                  if (statusText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                    ),
                  ],
                ]),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}