import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/subject_service.dart';
import '../../core/auth_service.dart';
import '../../core/teacher_service.dart';

import 'web_recorder_stub.dart'
    if (dart.library.html) 'web_recorder_screen.dart' as recorder;

class UploadLessonScreen extends StatefulWidget {
  // ✅ Pre-selected values from Topic Manager
  final String? preSelectedLevelId;
  final String? preSelectedLevelName;
  final String? preSelectedSubjectId;
  final String? preSelectedSubjectName;
  final String? preSelectedTopicId;
  final String? preSelectedTopicName;

  const UploadLessonScreen({
    super.key,
    this.preSelectedLevelId,
    this.preSelectedLevelName,
    this.preSelectedSubjectId,
    this.preSelectedSubjectName,
    this.preSelectedTopicId,
    this.preSelectedTopicName,
  });

  @override
  State<UploadLessonScreen> createState() => _UploadLessonScreenState();
}

class _UploadLessonScreenState extends State<UploadLessonScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final TeacherService _teacherService = TeacherService();
  final ImagePicker _imagePicker = ImagePicker();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _videoUrlController = TextEditingController();
  final _durationController = TextEditingController();

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

  bool _isPremium = false;
  bool _isSaving = false;
  double _uploadProgress = 0;
  String _uploadStatus = '';

  PlatformFile? _selectedFile;
  Uint8List? _recordedVideoBytes;
  String _recordedFileName = '';
  String _videoSource = 'none';

  @override
  void initState() {
    super.initState();
    _loadLevels();
    
    // ✅ Pre-select values if coming from Topic Manager
    if (widget.preSelectedLevelId != null) {
      _selectedLevelId = widget.preSelectedLevelId;
      _selectedLevelName = widget.preSelectedLevelName;
      _selectedSubjectId = widget.preSelectedSubjectId;
      _selectedSubjectName = widget.preSelectedSubjectName;
      _selectedTopicId = widget.preSelectedTopicId;
      // Load subjects for this level
      _loadSubjectsForLevel(widget.preSelectedLevelId!);
      // Load topics for this subject+level
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
          .select('level_id, levels!inner(name, description)')
          .eq('teacher_id', userId)
          .order('display_order', referencedTable: 'levels', ascending: true);

      if (mounted) {
        setState(() {
          _levels = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error loading levels: $e');
    }
  }

  Future<void> _loadSubjectsForLevel(String levelId) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('teacher_subjects')
          .select('subject_id, subjects!inner(name, color_hex, icon_name)')
          .eq('teacher_id', userId)
          .eq('level_id', levelId)
          .order('name', referencedTable: 'subjects', ascending: true);

      if (mounted) {
        setState(() {
          _subjects = List<Map<String, dynamic>>.from(response);
          _topics = [];
          _selectedTopicId = null;
        });
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
    }
  }

 Future<void> _loadTopicsForSubject(String subjectId) async {
    try {
      final userId = _authService.currentUserId;
      if (userId == null) return;

      // ✅ Use Map<String, Object> instead of Map<String, dynamic>
      final filters = <String, Object>{
        'teacher_id': userId,
        'subject_id': subjectId,
      };
      
      final levelId = _selectedLevelId;
      if (levelId != null) {
        filters['level_id'] = levelId;
      }

      final response = await Supabase.instance.client
          .from('teacher_topics')
          .select()
          .match(filters)
          .order('display_order', ascending: true);

      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(response);
          if (widget.preSelectedTopicId == null) {
            _selectedTopicId = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading topics: $e');
    }
  }

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFile = result.files.first;
        _videoSource = 'file';
        _recordedVideoBytes = null;
        _videoUrlController.clear();
      });
    }
  }

  Future<void> _recordVideo() async {
    if (kIsWeb) {
      final result = await recorder.openWebRecorder(context);
      if (result != null && mounted) {
        setState(() {
          _recordedVideoBytes = result['bytes'] as Uint8List?;
          _recordedFileName = result['fileName'] as String? ?? '';
          _videoSource = 'record';
          _selectedFile = null;
          _videoUrlController.clear();
        });
      }
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final XFile? video = await _imagePicker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 60),
        );
        if (video != null) {
          final bytes = await video.readAsBytes();
          setState(() {
            _recordedVideoBytes = Uint8List.fromList(bytes);
            _recordedFileName = 'recorded_${DateTime.now().millisecondsSinceEpoch}.mp4';
            _videoSource = 'record';
            _selectedFile = null;
            _videoUrlController.clear();
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Camera error: $e'), backgroundColor: Colors.red),
          );
        }
      }
      return;
    }

    _showDesktopRecordingGuide();
  }

  void _showDesktopRecordingGuide() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            const Text('📹 How to Record Lessons', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 20),
            _guideStep('1', 'OBS Studio (Recommended)', 'Free at obsproject.com\nRecord screen + webcam + mic together\nExport as MP4 and upload'),
            const SizedBox(height: 14),
            _guideStep('2', 'Xbox Game Bar (Windows)', 'Press Win+G → Capture → Record\nSaves to Videos/Captures folder'),
            const SizedBox(height: 14),
            _guideStep('3', 'QuickTime (Mac)', 'File → New Screen Recording\nOr File → New Movie Recording'),
            const SizedBox(height: 14),
            _guideStep('4', 'Upload Your File', 'Use "Upload from Device" to select your MP4'),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Got it!', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _guideStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(color: Color(0xFF1A237E), shape: BoxShape.circle),
          child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(description, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\[\]\(\)\{\}\#\?\&\%\~\|\^\<\>\:\;]'), '_').replaceAll(RegExp(r'\s+'), '_');
  }

  Future<void> _saveLesson() async {
    if (!_formKey.currentState!.validate()) return;
    final topicId = _selectedTopicId ?? widget.preSelectedTopicId;
    if (topicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a topic'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_videoSource == 'none') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select, record, or paste a video URL'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _uploadProgress = 0;
      _uploadStatus = 'Preparing video...';
    });

    try {
      final userId = _authService.currentUserId!;
      final title = _titleController.text.trim();
      final description = _descriptionController.text.trim();
      final durationMin = int.tryParse(_durationController.text);

      if (_videoSource == 'url') {
        // Save with video URL
        await Supabase.instance.client.from('lessons').insert({
          'teacher_topic_id': topicId,
          'teacher_id': userId,
          'title': title,
          'description': description,
          'video_url': _videoUrlController.text.trim(),
          'duration_minutes': durationMin,
          'is_premium': _isPremium,
          'level_id': _selectedLevelId ?? null,
          'is_published': true,
          
        });
      } else {
        // Upload video file
        List<int> videoBytes;
        String fileName;

        if (_videoSource == 'file' && _selectedFile != null) {
          setState(() => _uploadStatus = 'Reading file...');
          if (_selectedFile!.bytes != null) {
            videoBytes = _selectedFile!.bytes!;
          } else if (_selectedFile!.path != null) {
            videoBytes = await File(_selectedFile!.path!).readAsBytes();
          } else {
            throw Exception('Cannot read video file');
          }
          fileName = _sanitizeFileName(_selectedFile!.name);
        } else if (_videoSource == 'record' && _recordedVideoBytes != null) {
          setState(() => _uploadStatus = 'Processing recording...');
          videoBytes = _recordedVideoBytes!;
          fileName = _sanitizeFileName(_recordedFileName);
        } else {
          throw Exception('No video selected');
        }

        setState(() {
          _uploadStatus = 'Uploading ${(videoBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB...';
          _uploadProgress = 0.3;
        });

        // Upload to Supabase Storage
        final storagePath = 'lessons/${userId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
        
        await Supabase.instance.client
    .storage
    .from('lessons')
    .uploadBinary(storagePath, Uint8List.fromList(videoBytes));

        setState(() => _uploadProgress = 0.7);

        // Get public URL
        final videoUrl = Supabase.instance.client
            .storage
            .from('lessons')
            .getPublicUrl(storagePath);

        setState(() => _uploadProgress = 0.9);

        // Save lesson record
        await Supabase.instance.client.from('lessons').insert({
          'teacher_topic_id': topicId,
          'teacher_id': userId,
          'title': title,
          'description': description,
          'video_url': videoUrl,
          'duration_minutes': durationMin,
          'is_premium': _isPremium,
          'level_id': _selectedLevelId,
          'is_published': true,
          
        });

        setState(() => _uploadProgress = 1.0);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson uploaded successfully! ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { 
        _isSaving = false; 
        _uploadProgress = 0; 
        _uploadStatus = ''; 
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _videoUrlController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  String get _recordSubtitle {
    if (kIsWeb) return '🎥 Record using your laptop camera';
    if (Platform.isAndroid || Platform.isIOS) return '📱 Record using your phone camera';
    return '📹 See recording options for desktop';
  }

  @override
  Widget build(BuildContext context) {
    final isFromTopicManager = widget.preSelectedTopicId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isFromTopicManager ? 'Upload to ${widget.preSelectedTopicName}' : 'Upload New Lesson'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ✅ Level, Subject, Topic chain
            if (isFromTopicManager)
              // Show pre-selected path as read-only
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A237E).withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Uploading to:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text('${widget.preSelectedLevelName} → ${widget.preSelectedSubjectName} → ${widget.preSelectedTopicName}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A237E))),
                  ],
                ),
              )
            else ...[
              // Level dropdown
              DropdownButtonFormField<String>(
                value: _selectedLevelId,
                decoration: InputDecoration(
                  labelText: 'Class Level',
                  prefixIcon: const Icon(Icons.school_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _levels.map((row) {
                  final level = row['levels'] as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: row['level_id'] as String,
                    child: Text(level['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedLevelId = value;
                    _selectedLevelName = _levels
                        .firstWhere((l) => l['level_id'] == value)['levels']['name'];
                    _subjects = [];
                    _selectedSubjectId = null;
                    _topics = [];
                    _selectedTopicId = null;
                  });
                  if (value != null) _loadSubjectsForLevel(value);
                },
                validator: (v) => v == null ? 'Select a class' : null,
              ),
              const SizedBox(height: 16),

              // Subject dropdown
              DropdownButtonFormField<String>(
                value: _selectedSubjectId,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  prefixIcon: const Icon(Icons.book_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _subjects.map((row) {
                  final subject = row['subjects'] as Map<String, dynamic>;
                  return DropdownMenuItem<String>(
                    value: row['subject_id'] as String,
                    child: Text(subject['name'] ?? ''),
                  );
                }).toList(),
                onChanged: _subjects.isEmpty ? null : (value) {
                  setState(() {
                    _selectedSubjectId = value;
                    _selectedSubjectName = _subjects
                        .firstWhere((s) => s['subject_id'] == value)['subjects']['name'];
                    _topics = [];
                    _selectedTopicId = null;
                  });
                  if (value != null) _loadTopicsForSubject(value);
                },
                validator: (v) => v == null ? 'Select a subject' : null,
              ),
              const SizedBox(height: 16),

              // Topic dropdown
              if (_topics.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedTopicId,
                  decoration: InputDecoration(
                    labelText: 'Topic',
                    prefixIcon: const Icon(Icons.topic_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _topics.map((t) {
                    return DropdownMenuItem<String>(
                      value: t['id'] as String,
                      child: Text(t['name'] ?? ''),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedTopicId = value),
                  validator: (v) => v == null ? 'Select a topic' : null,
                ),
            ],

            const SizedBox(height: 24),
            const Text('Video Source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 12),

            _VideoSourceCard(icon: Icons.folder_open, title: 'Upload from Device', subtitle: 'Select a video file', isSelected: _videoSource == 'file', onTap: _pickVideoFile),
            const SizedBox(height: 8),
            _VideoSourceCard(icon: Icons.videocam, title: 'Record Video', subtitle: _recordSubtitle, isSelected: _videoSource == 'record', onTap: _recordVideo),
            const SizedBox(height: 8),
            _VideoSourceCard(icon: Icons.link, title: 'Video URL', subtitle: 'Paste a link from YouTube, etc.', isSelected: _videoSource == 'url', onTap: () => setState(() { _videoSource = 'url'; _selectedFile = null; _recordedVideoBytes = null; })),

            if (_selectedFile != null)
              _SelectedFileInfo(name: _selectedFile!.name, size: '${(_selectedFile!.size / (1024 * 1024)).toStringAsFixed(1)} MB'),
            if (_recordedVideoBytes != null)
              _SelectedFileInfo(name: _recordedFileName, size: '${(_recordedVideoBytes!.length / (1024 * 1024)).toStringAsFixed(1)} MB'),

            if (_videoSource == 'url') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _videoUrlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'Video URL', hintText: 'https://...', prefixIcon: const Icon(Icons.link), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                validator: (v) => _videoSource == 'url' && (v == null || v.isEmpty) ? 'Enter video URL' : null,
              ),
            ],

            const SizedBox(height: 24),
            const Text('Lesson Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
            const SizedBox(height: 12),

            TextFormField(controller: _titleController, decoration: InputDecoration(labelText: 'Lesson Title', hintText: 'e.g., Introduction to Mechanics', prefixIcon: const Icon(Icons.title), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), validator: (v) => v!.isEmpty ? 'Enter lesson title' : null),
            const SizedBox(height: 16),
            TextFormField(controller: _descriptionController, maxLines: 3, decoration: InputDecoration(labelText: 'Description', hintText: 'What will students learn?', prefixIcon: const Icon(Icons.description), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _durationController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Duration (min)', hintText: 'e.g., 45', prefixIcon: const Icon(Icons.timer_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
                const SizedBox(width: 12),
                Expanded(child: SwitchListTile(title: const Text('Premium', style: TextStyle(fontSize: 14)), subtitle: const Text('Exclusive content', style: TextStyle(fontSize: 11)), value: _isPremium, onChanged: (v) => setState(() => _isPremium = v), activeColor: const Color(0xFFFF9800), contentPadding: EdgeInsets.zero)),
              ],
            ),

            if (_isSaving) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _uploadProgress, backgroundColor: Colors.grey.shade200, color: const Color(0xFFFF9800)),
              const SizedBox(height: 8),
              Text(_uploadStatus, style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 32),
            SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: _isSaving ? null : _saveLesson, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Upload Lesson', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ===== HELPER WIDGETS (keep existing) =====
class _VideoSourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _VideoSourceCard({required this.icon, required this.title, required this.subtitle, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFF1A237E).withOpacity(0.05) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade300, width: isSelected ? 2 : 1)),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: isSelected ? const Color(0xFF1A237E).withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: isSelected ? const Color(0xFF1A237E) : Colors.grey.shade600, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isSelected ? const Color(0xFF1A237E) : Colors.black87)), Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey))])),
            if (isSelected) const Icon(Icons.check_circle, color: Color(0xFF1A237E), size: 22),
          ],
        ),
      ),
    );
  }
}

class _SelectedFileInfo extends StatelessWidget {
  final String name;
  final String size;
  const _SelectedFileInfo({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
        child: Row(children: [const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), Text(size, style: const TextStyle(fontSize: 11, color: Colors.grey))]))]),
      ),
    );
  }
}