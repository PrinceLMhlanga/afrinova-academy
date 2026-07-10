import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';

class UploadResourceScreen extends StatefulWidget {
  // ✅ Pre-selected values from Topic Manager
  final String? preSelectedLevelId;
  final String? preSelectedLevelName;
  final String? preSelectedSubjectId;
  final String? preSelectedSubjectName;
  final String? preSelectedTopicId;
  final String? preSelectedTopicName;

  const UploadResourceScreen({
    super.key,
    this.preSelectedLevelId,
    this.preSelectedLevelName,
    this.preSelectedSubjectId,
    this.preSelectedSubjectName,
    this.preSelectedTopicId,
    this.preSelectedTopicName,
  });

  @override
  State<UploadResourceScreen> createState() => _UploadResourceScreenState();
}

class _UploadResourceScreenState extends State<UploadResourceScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

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

  String _resourceType = 'notes';
  PlatformFile? _selectedFile;
  bool _isUploading = false;
  String? _uploadProgress;

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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'png', 'jpg', 'jpeg'],
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      // Check file size (20MB max)
      if (file.size > 20 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File too large. Maximum 20MB.'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      setState(() => _selectedFile = file);
    }
  }

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) return;
    
    final topicId = _selectedTopicId ?? widget.preSelectedTopicId;
    
    if (topicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a topic'), backgroundColor: Colors.red),
      );
      return;
    }

    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 'Uploading...';
    });

    try {
      final userId = _authService.currentUserId!;
      final fileName = _selectedFile!.name;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = 'resources/$userId/$timestamp-$fileName';

      // Read file bytes
      List<int> fileBytes;
      if (_selectedFile!.bytes != null) {
        fileBytes = _selectedFile!.bytes!;
      } else if (_selectedFile!.path != null) {
        fileBytes = await File(_selectedFile!.path!).readAsBytes();
      } else {
        throw Exception('Cannot read file');
      }

      setState(() => _uploadProgress = 'Uploading ${(fileBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB...');

      // Upload to Supabase Storage
      await Supabase.instance.client
          .storage
          .from('resources')
          .uploadBinary(filePath, Uint8List.fromList(fileBytes));

      // Get public URL
      final fileUrl = Supabase.instance.client
          .storage
          .from('resources')
          .getPublicUrl(filePath);

      // Save record to database
      await Supabase.instance.client.from('resources').insert({
        'teacher_topic_id': topicId,
        'teacher_id': userId,
        'level_id': _selectedLevelId,
        'subject_id': _selectedSubjectId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'file_url': fileUrl,
        'file_type': _getFileType(fileName),
        'file_size_bytes': _selectedFile!.size,
        'download_count': 0,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Resource uploaded successfully! ✅'), backgroundColor: Color(0xFF4CAF50)),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return 'pdf';
      case 'doc':
      case 'docx': return 'doc';
      case 'ppt':
      case 'pptx': return 'ppt';
      case 'png':
      case 'jpg':
      case 'jpeg': return 'image';
      default: return 'other';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFromTopicManager = widget.preSelectedTopicId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isFromTopicManager ? 'Add Resource to ${widget.preSelectedTopicName}' : 'Upload Resource'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Pre-selected path indicator
            if (isFromTopicManager)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
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
              if (_topics.isNotEmpty) const SizedBox(height: 16),
            ],

            // File Picker
            GestureDetector(
              onTap: _isUploading ? null : _pickFile,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
                      size: 48,
                      color: _selectedFile != null ? const Color(0xFF4CAF50) : const Color(0xFF1A237E),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFile != null ? _selectedFile!.name : 'Tap to select a file',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _selectedFile != null ? const Color(0xFF1A237E) : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_selectedFile != null) ...[
                      const SizedBox(height: 4),
                      Text('${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                    const SizedBox(height: 4),
                    const Text('PDF, DOC, PPT, Images (Max 20MB)',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Resource Title',
                hintText: 'e.g., Physics Form 4 Notes - Mechanics',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => v!.isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),

            // Resource Type
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'notes', label: Text('Notes', style: TextStyle(fontSize: 13)), icon: Icon(Icons.menu_book, size: 18)),
                ButtonSegment(value: 'question_paper', label: Text('Question Paper', style: TextStyle(fontSize: 13)), icon: Icon(Icons.quiz, size: 18)),
                ButtonSegment(value: 'other', label: Text('Other', style: TextStyle(fontSize: 13)), icon: Icon(Icons.attach_file, size: 18)),
              ],
              selected: {_resourceType},
              onSelectionChanged: (v) => setState(() => _resourceType = v.first),
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'Brief description of this resource',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),

            // Upload Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _upload,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isUploading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 12),
                          Text(_uploadProgress ?? 'Uploading...'),
                        ],
                      )
                    : const Text('Upload Resource', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}