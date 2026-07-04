import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/resource_service.dart';
import '../../core/auth_service.dart';
import '../../core/subject_service.dart';

class UploadResourceScreen extends StatefulWidget {
  const UploadResourceScreen({super.key});

  @override
  State<UploadResourceScreen> createState() => _UploadResourceScreenState();
}

class _UploadResourceScreenState extends State<UploadResourceScreen> {
  final _formKey = GlobalKey<FormState>();
  final ResourceService _resourceService = ResourceService();
  final AuthService _authService = AuthService();
  final SubjectService _subjectService = SubjectService();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _topics = [];
  String? _selectedSubjectId;
  String? _selectedTopicId;
  String _resourceType = 'notes';
  PlatformFile? _selectedFile;
  bool _isUploading = false;
  String? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await _subjectService.getSubjects();
      if (mounted) setState(() => _subjects = subjects);
    } catch (_) {}
  }

  Future<void> _loadTopics(String subjectId) async {
    try {
      // Get all subject offerings for this subject
      final offerings = await _subjectService.getSubjectOfferings();
      final matchingTopics = <Map<String, dynamic>>[];

      for (final offering in offerings) {
        if (offering['subjects']?['id'] == subjectId ||
            offering['subject_id'] == subjectId) {
          final topics = await _subjectService.getTopics(offering['id']);
          matchingTopics.addAll(topics);
        }
      }

      if (mounted) {
        setState(() {
          _topics = matchingTopics;
          _selectedTopicId = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'png', 'jpg'],
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
    }
  }

 Future<void> _upload() async {
  if (!_formKey.currentState!.validate()) return;
  if (_selectedFile == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please select a file'),
        backgroundColor: Colors.red,
      ),
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
    final filePath = '$userId/$timestamp-$fileName';

    // Read file bytes
    List<int> fileBytes;
    if (_selectedFile!.bytes != null) {
      fileBytes = _selectedFile!.bytes!;
    } else if (_selectedFile!.path != null) {
      fileBytes = await File(_selectedFile!.path!).readAsBytes();
    } else {
      throw Exception('Cannot read file');
    }

    // Upload using the simplified method
    await _resourceService.uploadResource(
      filePath: filePath,
      fileBytes: fileBytes,
      fileName: fileName,
      fileSizeBytes: _selectedFile!.size,
      fileType: _getFileType(fileName),
      title: _titleController.text.trim(),
      resourceType: _resourceType,
      uploadedById: userId,
      subjectId: _selectedSubjectId,
      topicId: _selectedTopicId,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resource uploaded successfully! ✅'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      Navigator.pop(context, true);
    }
  } catch (e) {
    debugPrint('Upload error details: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
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

  String _getContentType(String fileName) {
    if (fileName.endsWith('.pdf')) return 'application/pdf';
    if (fileName.endsWith('.doc')) return 'application/msword';
    if (fileName.endsWith('.docx'))
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    if (fileName.endsWith('.png')) return 'image/png';
    if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg'))
      return 'image/jpeg';
    return 'application/octet-stream';
  }

  String _getFileType(String fileName) {
    if (fileName.endsWith('.pdf')) return 'pdf';
    if (fileName.endsWith('.doc') || fileName.endsWith('.docx')) return 'doc';
    if (fileName.endsWith('.ppt') || fileName.endsWith('.pptx')) return 'ppt';
    return 'other';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Resource'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // File Picker
            GestureDetector(
              onTap: _isUploading ? null : _pickFile,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: Colors.grey.shade300, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFile != null
                          ? Icons.check_circle
                          : Icons.cloud_upload_outlined,
                      size: 48,
                      color: _selectedFile != null
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF1A237E),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFile != null
                          ? _selectedFile!.name
                          : 'Tap to select a file',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _selectedFile != null
                            ? const Color(0xFF1A237E)
                            : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_selectedFile != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'PDF, DOC, PPT, Images (Max 20MB)',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) =>
                  v!.isEmpty ? 'Enter a title' : null,
            ),
            const SizedBox(height: 16),

            // Resource Type
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'notes',
                    label: Text('Notes', style: TextStyle(fontSize: 13)),
                    icon: Icon(Icons.menu_book, size: 18)),
                ButtonSegment(
                    value: 'question_paper',
                    label: Text('Question Paper', style: TextStyle(fontSize: 13)),
                    icon: Icon(Icons.quiz, size: 18)),
                ButtonSegment(
                    value: 'other',
                    label: Text('Other', style: TextStyle(fontSize: 13)),
                    icon: Icon(Icons.attach_file, size: 18)),
              ],
              selected: {_resourceType},
              onSelectionChanged: (v) =>
                  setState(() => _resourceType = v.first),
            ),
            const SizedBox(height: 16),

            // Subject Dropdown
            DropdownButtonFormField<String>(
              value: _selectedSubjectId,
              decoration: InputDecoration(
                labelText: 'Subject (Optional)',
                prefixIcon: const Icon(Icons.book),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              items: _subjects.map<DropdownMenuItem<String>>((s) {
                return DropdownMenuItem<String>(
                  value: s['id'] as String?,
                  child: Text(s['name'] ?? ''),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedSubjectId = value);
                if (value != null) _loadTopics(value);
              },
            ),
            const SizedBox(height: 16),

            // Topic Dropdown
            if (_topics.isNotEmpty)
              DropdownButtonFormField<String>(
                value: _selectedTopicId,
                decoration: InputDecoration(
                  labelText: 'Topic (Optional)',
                  prefixIcon: const Icon(Icons.topic),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                items: _topics.map<DropdownMenuItem<String>>((t) {
                  return DropdownMenuItem<String>(
                    value: t['id'] as String?,
                    child: Text(t['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (value) =>
                    setState(() => _selectedTopicId = value),
              ),
            if (_topics.isNotEmpty) const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'Brief description of this resource',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isUploading
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text(_uploadProgress ?? 'Uploading...'),
                        ],
                      )
                    : const Text(
                        'Upload Resource',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}