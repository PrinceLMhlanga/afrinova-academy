import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/live_lesson_service.dart';
import '../../core/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GoLiveScreen extends StatefulWidget {
  final String? preSelectedLevelId;
  final String? preSelectedLevelName;
  final String? preSelectedSubjectId;
  final String? preSelectedSubjectName;
  final String? preSelectedTopicId;
  final String? preSelectedTopicName;

  const GoLiveScreen({
    super.key,
    this.preSelectedLevelId,
    this.preSelectedLevelName,
    this.preSelectedSubjectId,
    this.preSelectedSubjectName,
    this.preSelectedTopicId,
    this.preSelectedTopicName,
  });

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen> {
  final LiveLessonService _liveService = LiveLessonService();
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeController = TextEditingController();

  bool _isScheduling = false;
  DateTime? _scheduledDateTime;
  bool _isGoingLive = false;

  // Level
  List<Map<String, dynamic>> _levels = [];
  String? _selectedLevelId;
  String? _selectedLevelName;

  // Subject
  List<Map<String, dynamic>> _subjects = [];
  String? _selectedSubjectId;
  String? _selectedSubjectName;

  // Topic
  List<Map<String, dynamic>> _topics = [];
  String? _selectedTopicId;

  @override
  void initState() {
    super.initState();
    _loadLevels();
    
    if (widget.preSelectedLevelId != null) {
      _selectedLevelId = widget.preSelectedLevelId;
      _selectedLevelName = widget.preSelectedLevelName;
      _selectedSubjectId = widget.preSelectedSubjectId;
      _selectedSubjectName = widget.preSelectedSubjectName;
      _selectedTopicId = widget.preSelectedTopicId;
      _loadSubjectsForLevel(widget.preSelectedLevelId!);
      if (widget.preSelectedSubjectId != null) {
        _loadTopicsForSubject(widget.preSelectedSubjectId!);
      }
    }
  }

  Future<void> _loadLevels() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;
      final response = await Supabase.instance.client
          .from('teacher_levels')
          .select('level_id, levels!inner(name)')
          .eq('teacher_id', userId);
      if (mounted) setState(() => _levels = List<Map<String, dynamic>>.from(response));
    } catch (_) {}
  }

  Future<void> _loadSubjectsForLevel(String levelId) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;
      final response = await Supabase.instance.client
          .from('teacher_subjects')
          .select('subject_id, subjects!inner(name)')
          .eq('teacher_id', userId)
          .eq('level_id', levelId);
      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(response);
          _topics = [];
          _selectedTopicId = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTopicsForSubject(String subjectId) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;
      final filters = <String, Object>{'teacher_id': userId, 'subject_id': subjectId};
      final levelId = _selectedLevelId;
      if (levelId != null) filters['level_id'] = levelId;
      
      final response = await Supabase.instance.client
          .from('teacher_topics')
          .select()
          .match(filters)
          .order('display_order', ascending: true);
      if (mounted) setState(() => _topics = List<Map<String, dynamic>>.from(response));
    } catch (_) {}
  }

  Future<void> _goLive({required bool joinImmediately}) async {
    if (!_formKey.currentState!.validate()) return;
    
    final subjectId = _selectedSubjectId ?? widget.preSelectedSubjectId;
    if (subjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a subject'), backgroundColor: Colors.red),
      );
      return;
    }

    if (!joinImmediately && _scheduledDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date and time'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isGoingLive = true);

    try {
      final userId = _authService.currentUserId!;
      final levelId = _selectedLevelId ?? widget.preSelectedLevelId;
      final topicId = _selectedTopicId ?? widget.preSelectedTopicId;

      // ✅ Use LiveLessonService
      final lesson = await _liveService.createLiveLesson(
        teacherId: userId,
        subjectId: subjectId,
        topic: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        scheduledAt: _scheduledDateTime,
        levelId: levelId,
        teacherTopicId: topicId,
      );

      final lessonId = lesson['id'] as String?;
      final roomId = lesson['room_id'] as String?;

      if (lessonId == null || roomId == null) throw Exception('Failed to create lesson');

      if (joinImmediately) {
  await _liveService.updateStatus(lessonId, 'live');
  
  if (kIsWeb) {
    // Open Jitsi in new tab
    final uri = Uri.parse('https://meet.ffmuc.net/$roomId#userInfo.displayName=Teacher&config.prejoinPageEnabled=false');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    
    // ✅ Show End Lesson button
    if (mounted) {
      _showEndLessonDialog(lessonId);
    }
  } else {
    // Mobile - join in-app
    if (mounted) {
      await _liveService.joinLesson(
        context: context,
        roomName: roomId,
        userName: 'Teacher',
        lessonId: lessonId,
        isTeacher: true,
      );
    }
  }
}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoingLive = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFromTopicManager = widget.preSelectedTopicId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isFromTopicManager ? 'Live: ${widget.preSelectedTopicName}' : 'Go Live'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Header card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.red.shade600, Colors.red.shade800]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                children: [
                  Icon(Icons.live_tv, color: Colors.white, size: 48),
                  SizedBox(height: 12),
                  Text('Start a Live Lesson', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Your students can join instantly', style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Pre-selected path
            if (isFromTopicManager)
              Container(
                padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.withOpacity(0.2))),
                child: Text('${widget.preSelectedLevelName} → ${widget.preSelectedSubjectName} → ${widget.preSelectedTopicName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              )
            else ...[
              // Level dropdown
              DropdownButtonFormField<String>(
                value: _selectedLevelId,
                decoration: InputDecoration(labelText: 'Class Level', prefixIcon: const Icon(Icons.school_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: _levels.map((row) => DropdownMenuItem<String>(value: row['level_id'] as String, child: Text((row['levels'] as Map)['name'] ?? ''))).toList(),
                onChanged: (v) { setState(() { _selectedLevelId = v; _subjects = []; _selectedSubjectId = null; _topics = []; _selectedTopicId = null; }); if (v != null) _loadSubjectsForLevel(v); },
              ),
              const SizedBox(height: 16),
              // Subject dropdown
              DropdownButtonFormField<String>(
                value: _selectedSubjectId,
                decoration: InputDecoration(labelText: 'Subject', prefixIcon: const Icon(Icons.book_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                items: _subjects.map((row) => DropdownMenuItem<String>(value: row['subject_id'] as String, child: Text((row['subjects'] as Map)['name'] ?? ''))).toList(),
                onChanged: _subjects.isEmpty ? null : (v) { setState(() { _selectedSubjectId = v; _topics = []; _selectedTopicId = null; }); if (v != null) _loadTopicsForSubject(v); },
                validator: (v) => v == null ? 'Select a subject' : null,
              ),
              const SizedBox(height: 16),
              // Topic dropdown
              if (_topics.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedTopicId,
                  decoration: InputDecoration(labelText: 'Topic', prefixIcon: const Icon(Icons.topic_rounded), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: _topics.map((t) => DropdownMenuItem<String>(value: t['id'] as String, child: Text(t['name'] ?? ''))).toList(),
                  onChanged: (v) => setState(() => _selectedTopicId = v),
                ),
              if (_topics.isNotEmpty) const SizedBox(height: 16),
            ],

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(labelText: 'Lesson Title', hintText: 'e.g., Mechanics Revision', prefixIcon: const Icon(Icons.title), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              validator: (v) => v!.isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 12),
            // Description
            TextFormField(controller: _descriptionController, maxLines: 2, decoration: InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 24),

            // Go Live Now
            SizedBox(width: double.infinity, height: 56, child: ElevatedButton.icon(
              onPressed: _isGoingLive ? null : () { setState(() => _isScheduling = false); _goLive(joinImmediately: true); },
              icon: _isGoingLive ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.live_tv),
              label: const Text('Go Live Now'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            )),
            const SizedBox(height: 12),
            // Schedule
            SizedBox(width: double.infinity, height: 52, child: OutlinedButton.icon(
              onPressed: _isGoingLive ? null : () => setState(() => _isScheduling = !_isScheduling),
              icon: const Icon(Icons.schedule), label: Text(_isScheduling ? 'Hide Schedule' : 'Schedule for Later'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A237E), side: const BorderSide(color: Color(0xFF1A237E)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            )),

            // Schedule fields
            if (_isScheduling) ...[
              const SizedBox(height: 12),
              TextFormField(controller: _dateController, readOnly: true, decoration: InputDecoration(labelText: 'Date', prefixIcon: const Icon(Icons.calendar_today), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                onTap: () async {
                  final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)));
                  if (date != null) setState(() { _scheduledDateTime = DateTime(date.year, date.month, date.day, _scheduledDateTime?.hour ?? 9, _scheduledDateTime?.minute ?? 0); _dateController.text = '${date.day}/${date.month}/${date.year}'; });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _timeController, readOnly: true, decoration: InputDecoration(labelText: 'Time', prefixIcon: const Icon(Icons.access_time), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                onTap: () async {
                  final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledDateTime ?? DateTime.now()));
                  if (time != null) setState(() { _scheduledDateTime = DateTime(_scheduledDateTime?.year ?? DateTime.now().year, _scheduledDateTime?.month ?? DateTime.now().month, _scheduledDateTime?.day ?? DateTime.now().day, time.hour, time.minute); final period = time.hour >= 12 ? 'PM' : 'AM'; final hour = time.hour > 12 ? time.hour - 12 : time.hour; _timeController.text = '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $period'; });
                },
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 52, child: ElevatedButton.icon(
                onPressed: _isGoingLive ? null : () => _goLive(joinImmediately: false),
                icon: const Icon(Icons.check_circle), label: const Text('Confirm Schedule'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              )),
            ],
          ],
        ),
      ),
    );
  }
  void _showEndLessonDialog(String lessonId) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Lesson in Progress'),
      content: const Text('Your live lesson is running in another tab.\n\nClick "End Lesson" when you\'re done to notify students.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Keep Teaching'),
        ),
        ElevatedButton(
          onPressed: () async {
            await _liveService.updateStatus(lessonId, 'ended');
            await Supabase.instance.client.from('live_lessons').update({
              'status': 'ended',
              'ended_at': DateTime.now().toIso8601String(),
            }).eq('id', lessonId);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lesson ended ✅'), backgroundColor: Color(0xFF4CAF50)),
              );
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('End Lesson'),
        ),
      ],
    ),
  );
}
}