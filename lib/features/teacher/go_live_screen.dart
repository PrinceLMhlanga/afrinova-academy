import 'package:flutter/material.dart';
import '../../core/live_lesson_service.dart';
import '../../core/auth_service.dart';
import '../../core/teacher_service.dart';
//import '../live/live_classroom_screen.dart';

class GoLiveScreen extends StatefulWidget {
  const GoLiveScreen({super.key});

  @override
  State<GoLiveScreen> createState() => _GoLiveScreenState();
}

class _GoLiveScreenState extends State<GoLiveScreen> {
  final LiveLessonService _liveService = LiveLessonService();
  final AuthService _authService = AuthService();
  final TeacherService _teacherService = TeacherService();
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _isScheduling = false; // Track whether scheduling or going live now
  DateTime? _scheduledDateTime;
final _dateController = TextEditingController();
final _timeController = TextEditingController();

  List<Map<String, dynamic>> _subjects = [];
  String? _selectedSubjectId;
  bool _isLoading = true;
  bool _isGoingLive = false;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final mySubjects = await _teacherService.getMySubjects(userId);
      final subjects = mySubjects
          .where((s) => s['subjects'] != null)
          .map((s) => s['subjects'] as Map<String, dynamic>)
          .toList();

      if (mounted) {
        setState(() {
          _subjects = subjects;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _goLive({required bool joinImmediately}) async {
  if (!_formKey.currentState!.validate()) return;
  if (_selectedSubjectId == null) return;

  if (!joinImmediately && _scheduledDateTime == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please select a date and time for the scheduled lesson'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  setState(() => _isGoingLive = true);

  try {
    final userId = _authService.currentUserId!;
    final lesson = await _liveService.createLiveLesson(
      teacherId: userId,
      subjectId: _selectedSubjectId!,
      topic: _topicController.text.trim(),
      description: _descriptionController.text.trim(),
      scheduledAt: _scheduledDateTime,
    );

    final lessonId = lesson['id'];
    final roomId = lesson['room_id'];

    if (lessonId == null || roomId == null) {
      throw Exception('Failed to create lesson');
    }

    if (joinImmediately) {
      // Update to live and join now
      await _liveService.updateStatus(lessonId as String, 'live');

      if (mounted) {
        await _liveService.joinLesson(
          context: context, 
          roomName: roomId as String,
          userName: "Teacher",
          lessonId: lessonId,
          isTeacher: true,
        );
      }
    } else {
      // Just scheduled — go back
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lesson scheduled! Students can see it.'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        Navigator.pop(context);
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
    _topicController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Live'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade600, Colors.red.shade800],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.live_tv, color: Colors.white, size: 48),
                        SizedBox(height: 12),
                        Text('Start a Live Lesson',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text('Your students can join instantly',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _topicController,
                    decoration: InputDecoration(
                      labelText: 'Topic',
                      hintText: 'e.g., Mechanics Revision',
                      prefixIcon: const Icon(Icons.topic),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v!.isEmpty ? 'Enter topic' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'What will you cover?',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),

                   DropdownButtonFormField<String>(
                    value: _selectedSubjectId,
                    decoration: InputDecoration(
                      labelText: 'Subject',
                      prefixIcon: const Icon(Icons.book),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _subjects.map<DropdownMenuItem<String>>((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'] as String?,
                        child: Text(s['name'] ?? ''),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _selectedSubjectId = v),
                    validator: (v) => v == null ? 'Select subject' : null,
                  ),
                  // Replace the single "Go Live Now" button with two buttons:
const SizedBox(height: 24),

                  // Go Live Now button
SizedBox(
  width: double.infinity,
  height: 56,
  child: ElevatedButton.icon(
    onPressed: _isGoingLive ? null : () {
      setState(() => _isScheduling = false);
      _goLive(joinImmediately: true);
    },
    icon: _isGoingLive
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.live_tv),
    label: const Text('Go Live Now'),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.red.shade700,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  ),
),
const SizedBox(height: 12),

// Schedule button
SizedBox(
  width: double.infinity,
  height: 52,
  child: OutlinedButton.icon(
    onPressed: _isGoingLive ? null : () {
      setState(() => _isScheduling = true); // ← Show date/time fields
    },
    icon: const Icon(Icons.schedule),
    label: Text(_isScheduling ? 'Set Date & Time Below' : 'Schedule for Later'),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF1A237E),
      side: const BorderSide(color: Color(0xFF1A237E)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 16),
    ),
  ),
),


                  // Show only when scheduling
if (_isScheduling) ...[
  const SizedBox(height: 12),
  
  // Date Picker
  TextFormField(
    controller: _dateController,
    readOnly: true,
    decoration: InputDecoration(
      labelText: 'Date',
      hintText: 'Tap to select date',
      prefixIcon: const Icon(Icons.calendar_today),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onTap: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 90)),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF1A237E)),
            ),
            child: child!,
          );
        },
      );
      if (date != null) {
        setState(() {
          _scheduledDateTime = DateTime(
            date.year, date.month, date.day,
            _scheduledDateTime?.hour ?? 9,
            _scheduledDateTime?.minute ?? 0,
          );
          _dateController.text = '${date.day}/${date.month}/${date.year}';
        });
      }
    },
  ),
  const SizedBox(height: 12),

  // Time Picker
  TextFormField(
    controller: _timeController,
    readOnly: true,
    decoration: InputDecoration(
      labelText: 'Time',
      hintText: 'Tap to select time',
      prefixIcon: const Icon(Icons.access_time),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onTap: () async {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_scheduledDateTime ?? DateTime.now()),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF1A237E)),
            ),
            child: child!,
          );
        },
      );
      if (time != null) {
        setState(() {
          _scheduledDateTime = DateTime(
            _scheduledDateTime?.year ?? DateTime.now().year,
            _scheduledDateTime?.month ?? DateTime.now().month,
            _scheduledDateTime?.day ?? DateTime.now().day,
            time.hour,
            time.minute,
          );
          final period = time.hour >= 12 ? 'PM' : 'AM';
          final hour = time.hour > 12 ? time.hour - 12 : time.hour;
          _timeController.text = '${hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $period';
        });
      }
    },
  ),
  const SizedBox(height: 12),

  // Confirm Schedule button
  SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton.icon(
      onPressed: _isGoingLive ? null : () => _goLive(joinImmediately: false),
      icon: _isGoingLive
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_circle),
      label: Text(_isGoingLive ? 'Scheduling...' : 'Confirm Schedule'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  ),
],
                  const SizedBox(height: 12),

                 

// Go Live Now button
                ],
              ),
            ),
    );
  }
}