import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import '../../core/access_checker.dart';
import 'lessons_screen.dart';
import '../payment/payment_screen.dart';

class TeacherContentScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String subjectName;
  final Color subjectColor;
  final String subjectId;
  final String? levelId;

  const TeacherContentScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.subjectName,
    required this.subjectColor,
    required this.subjectId,
    this.levelId,
  });

  @override
  State<TeacherContentScreen> createState() => _TeacherContentScreenState();
}

class _TeacherContentScreenState extends State<TeacherContentScreen> {
  final AuthService _authService = AuthService();
  List<Map<String, dynamic>> _topics = [];
  Map<String, dynamic>? _enrollment;
  int _totalLessons = 0;
  int _totalResources = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final userId = _authService.currentUserId;
      
      // Load enrollment + plan features
      if (userId != null && widget.subjectId != null) {
        final enrollment = await Supabase.instance.client
            .from('enrollments')
            .select('id, plan_features, is_subscribed, subscription_expires_at, trial_ends_at, status')
            .eq('student_id', userId)
            .eq('teacher_id', widget.teacherId)
            .eq('subject_id', widget.subjectId)
            .maybeSingle();
        _enrollment = enrollment;
      }

      // Load topics
      final topics = await Supabase.instance.client
          .from('teacher_topics')
          .select()
          .eq('teacher_id', widget.teacherId)
          .eq('subject_id', widget.subjectId ?? '')
          .order('display_order', ascending: true);

      // Count lessons
      int totalLessons = 0;
      int totalResources = 0;
      for (final topic in topics) {
        final lessonCount = await Supabase.instance.client
            .from('lessons')
            .select('id')
            .eq('teacher_topic_id', topic['id'] as String)
            .eq('is_published', true)
            .count(CountOption.exact);
        totalLessons += lessonCount.count ?? 0;

        final resourceCount = await Supabase.instance.client
            .from('resources')
            .select('id')
            .eq('teacher_topic_id', topic['id'] as String)
            .count(CountOption.exact);
        totalResources += resourceCount.count ?? 0;
      }

      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(topics);
          _totalLessons = totalLessons;
          _totalResources = totalResources;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading content: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _canAccessFeature(String feature) {
    return AccessChecker.hasFeature(_enrollment, feature);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5F7FA), Color(0xFFE8ECF1)],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              backgroundColor: widget.subjectColor,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(widget.subjectName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [widget.subjectColor, widget.subjectColor.withOpacity(0.7)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 70),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                child: Text(
                                  widget.teacherName.isNotEmpty ? widget.teacherName[0].toUpperCase() : 'T',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.teacherName,
                                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(widget.subjectName,
                                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_isLoading)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(color: Color(0xFF1A237E)),
                    ))
                  else ...[
                    // Stats row
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            icon: Icons.topic_rounded,
                            label: 'Topics',
                            value: '${_topics.length}',
                            color: widget.subjectColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.video_library_rounded,
                            label: 'Lessons',
                            value: '$_totalLessons',
                            color: const Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _StatCard(
                            icon: Icons.folder_rounded,
                            label: 'Resources',
                            value: '$_totalResources',
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Topics header
                    Row(
                      children: [
                        Container(width: 4, height: 20,
                          decoration: BoxDecoration(color: widget.subjectColor, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 10),
                        Text('Topics & Content',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: widget.subjectColor)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_topics.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(children: [
                            Icon(Icons.topic_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text('No content yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text('${widget.teacherName} hasn\'t added any topics for ${widget.subjectName} yet.',
                                textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                          ]),
                        ),
                      )
                    else
                      ..._topics.map((topic) {
                        final topicId = topic['id'] as String;
                        final topicName = topic['name'] ?? '';
                        final topicDesc = topic['description'] as String?;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            elevation: 1,
                            shadowColor: widget.subjectColor.withOpacity(0.15),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => TopicContentScreen(
      topicId: topicId,
      topicName: topicName,
      subjectColor: widget.subjectColor,
      teacherId: widget.teacherId,
    ),
  ));
},
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48, height: 48,
                                      decoration: BoxDecoration(
                                        color: widget.subjectColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text('${_topics.indexOf(topic) + 1}',
                                            style: TextStyle(color: widget.subjectColor, fontWeight: FontWeight.bold, fontSize: 18)),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(topicName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                          if (topicDesc != null && topicDesc.isNotEmpty)
                                            Text(topicDesc, style: const TextStyle(fontSize: 12, color: Colors.grey), maxLines: 2),
                                          const SizedBox(height: 4),
                                          FutureBuilder<Map<String, int>>(
                                            future: _getTopicCounts(topicId),
                                            builder: (context, snapshot) {
                                              final counts = snapshot.data ?? {'lessons': 0, 'resources': 0};
                                              return Row(
                                                children: [
                                                  Icon(Icons.video_library_rounded, size: 13, color: Colors.grey.shade400),
                                                  const SizedBox(width: 3),
                                                  Text('${counts['lessons']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                                  const SizedBox(width: 10),
                                                  Icon(Icons.folder_rounded, size: 13, color: Colors.grey.shade400),
                                                  const SizedBox(width: 3),
                                                  Text('${counts['resources']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 34, height: 34,
                                      decoration: BoxDecoration(
                                        color: widget.subjectColor.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.chevron_right, color: widget.subjectColor, size: 20),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, int>> _getTopicCounts(String topicId) async {
    try {
      final lessonCount = await Supabase.instance.client
          .from('lessons')
          .select('id')
          .eq('teacher_topic_id', topicId)
          .eq('is_published', true)
          .count(CountOption.exact);

      final resourceCount = await Supabase.instance.client
          .from('resources')
          .select('id')
          .eq('teacher_topic_id', topicId)
          .count(CountOption.exact);

      return {
        'lessons': lessonCount.count ?? 0,
        'resources': resourceCount.count ?? 0,
      };
    } catch (_) {
      return {'lessons': 0, 'resources': 0};
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 8)],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }
}