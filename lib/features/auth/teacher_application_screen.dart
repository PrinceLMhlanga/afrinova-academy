import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;
import '../auth/pending_approval_screen.dart';

class TeacherApplicationScreen extends StatefulWidget {
  final String userId;
  final String userEmail;
  final String userName;

  const TeacherApplicationScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.userName,
  });

  @override
  State<TeacherApplicationScreen> createState() => _TeacherApplicationScreenState();
}

class _TeacherApplicationScreenState extends State<TeacherApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _bioController = TextEditingController();
  final _experienceController = TextEditingController();
  
  String _selectedProvince = 'Harare';
  String _highestQualification = 'Degree';
  List<String> _selectedSubjects = [];
  List<String> _selectedLevels = [];
  List<PlatformFile> _qualificationFiles = [];
  List<PlatformFile> _cvFiles = [];
  List<String> _uploadedQualificationUrls = [];
  List<String> _uploadedCvUrls = [];
  List<Map<String, dynamic>> _allSubjects = [];
  bool _isLoadingSubjects = true;
  bool _isSubmitting = false;
  bool _isUploading = false;
  final int _maxFileSize = 5 * 1024 * 1024; // 5MB
  final int _maxFiles = 5;
  Map<String, List<String>> _subjectLevels = {}; // subject -> [levels]
String? _selectedSubjectForLevels; // Currently editing subject's levels

  final List<String> _provinces = [
    'Harare', 'Bulawayo', 'Manicaland', 'Mashonaland Central',
    'Mashonaland East', 'Mashonaland West', 'Masvingo', 'Matabeleland North',
    'Matabeleland South', 'Midlands'
  ];

  final List<String> _qualifications = [
    'Certificate', 'Diploma', 'Degree', 'Masters', 'PhD'
  ];

  final List<String> _availableLevels = [
    'Form 1', 'Form 2', 'O-Level', 'A-Level'
  ];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    try {
      final response = await Supabase.instance.client
          .from('subjects')
          .select('name')
          .eq('is_active', true)
          .order('name');

      if (mounted) {
        setState(() {
          _allSubjects = List<Map<String, dynamic>>.from(response);
          _isLoadingSubjects = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading subjects: $e');
      if (mounted) setState(() => _isLoadingSubjects = false);
    }
  }

  Future<String?> _uploadFile(PlatformFile file, String folder) async {
    try {
      Uint8List? bytes;
      
      if (file.bytes != null) {
        bytes = file.bytes;
      } else if (file.path != null) {
        // Read from file path
        bytes = await File(file.path!).readAsBytes();
      } else {
        return null;
      }

      if (bytes == null) return null;

      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final filePath = '${widget.userId}/$folder/$fileName';

      await Supabase.instance.client
          .storage
          .from('teacher-documents')
          .uploadBinary(filePath, bytes);

      final url = Supabase.instance.client
          .storage
          .from('teacher-documents')
          .getPublicUrl(filePath);

      return url;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<List<String>> _uploadFiles(List<PlatformFile> files, String folder) async {
    final urls = <String>[];
    for (final file in files) {
      final url = await _uploadFile(file, folder);
      if (url != null) {
        urls.add(url);
      }
    }
    return urls;
  }

  Future<void> _pickFiles({required bool isQualification}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        // Check file sizes
        for (final file in result.files) {
          if (file.size > _maxFileSize) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${file.name} exceeds 5MB limit'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }

        setState(() {
          if (isQualification) {
            if (_qualificationFiles.length + result.files.length > _maxFiles) {
              _qualificationFiles = result.files.take(_maxFiles).toList();
            } else {
              _qualificationFiles.addAll(result.files);
            }
          } else {
            if (_cvFiles.length + result.files.length > _maxFiles) {
              _cvFiles = result.files.take(_maxFiles).toList();
            } else {
              _cvFiles.addAll(result.files);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking files: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeFile(int index, {required bool isQualification}) {
    setState(() {
      if (isQualification) {
        _qualificationFiles.removeAt(index);
      } else {
        _cvFiles.removeAt(index);
      }
    });
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_subjectLevels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one subject'), backgroundColor: Colors.red),
      );
      return;
    }
    
    // Check each subject has at least one level
    for (final entry in _subjectLevels.entries) {
      if (entry.value.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Select at least one class for ${entry.key}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      setState(() => _isUploading = true);
      
      _uploadedQualificationUrls = await _uploadFiles(_qualificationFiles, 'qualifications');
      _uploadedCvUrls = await _uploadFiles(_cvFiles, 'cv');

      setState(() => _isUploading = false);

      // Get all unique subjects and levels
      final allSubjects = _subjectLevels.keys.toList();
      final allLevels = _subjectLevels.values.expand((l) => l).toSet().toList();

      await Supabase.instance.client.from('teacher_applications').insert({
        'user_id': widget.userId,
        'phone_number': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'province': _selectedProvince,
        'highest_qualification': _highestQualification,
        'teaching_experience_years': int.tryParse(_experienceController.text) ?? 0,
        'bio': _bioController.text.trim(),
        'preferred_subjects': allSubjects,
        'preferred_levels': allLevels,
        'subject_levels': _subjectLevels, // ✅ Save the linked mapping
        'qualifications_url': _uploadedQualificationUrls.isNotEmpty ? _uploadedQualificationUrls[0] : null,
        'certificates_urls': _uploadedQualificationUrls,
        'cv_url': _uploadedCvUrls.isNotEmpty ? _uploadedCvUrls[0] : null,
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Application submitted! We will review and notify you. ✅'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const PendingApprovalScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _bioController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teacher Application'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.verified_user, color: Color(0xFF1A237E)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Complete your profile to start teaching on AfriNova Academy',
                        style: TextStyle(color: Color(0xFF1A237E), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Personal Details
              const Text('Personal Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  prefixText: '+263 ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedProvince,
                      decoration: InputDecoration(
                        labelText: 'Province',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      items: _provinces.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setState(() => _selectedProvince = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Professional Details
              const Text('Professional Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<String>(
                value: _highestQualification,
                decoration: InputDecoration(
                  labelText: 'Highest Qualification',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _qualifications.map((q) => DropdownMenuItem(value: q, child: Text(q))).toList(),
                onChanged: (v) => setState(() => _highestQualification = v!),
              ),
              const SizedBox(height: 12),
              
              TextFormField(
                controller: _experienceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Years of Teaching Experience',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              
              TextFormField(
                controller: _bioController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Bio / Teaching Philosophy',
                  hintText: 'Tell us about yourself and your teaching experience...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),

             // Instead of separate subject and level lists, use a Map


// In the build method, replace the Subjects & Classes section:

// Subjects & Levels
const Text('Subjects & Classes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
const Text('Select subjects and the classes you can teach them for:',
    style: TextStyle(color: Colors.grey, fontSize: 13)),
const SizedBox(height: 16),

// First select subjects
const Text('1. Choose your subjects:', style: TextStyle(fontWeight: FontWeight.w600)),
const SizedBox(height: 8),

_isLoadingSubjects
    ? const Center(child: CircularProgressIndicator())
    : Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _allSubjects.map((subject) {
          final subjectName = subject['name'] as String;
          final isSelected = _subjectLevels.containsKey(subjectName);
          final levelCount = _subjectLevels[subjectName]?.length ?? 0;
          return FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(subjectName, style: const TextStyle(fontSize: 12)),
                if (isSelected && levelCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$levelCount', style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50))),
                  ),
                ],
              ],
            ),
            selected: isSelected,
            onSelected: (v) {
              setState(() {
                if (v) {
                  _subjectLevels[subjectName] = [];
                  _selectedSubjectForLevels = subjectName;
                } else {
                  _subjectLevels.remove(subjectName);
                  if (_selectedSubjectForLevels == subjectName) {
                    _selectedSubjectForLevels = null;
                  }
                }
              });
            },
            selectedColor: const Color(0xFF1A237E).withOpacity(0.2),
            checkmarkColor: const Color(0xFF1A237E),
          );
        }).toList(),
      ),

const SizedBox(height: 20),

// Then select levels for each subject
if (_subjectLevels.isNotEmpty) ...[
  const Text('2. Assign classes to each subject:', style: TextStyle(fontWeight: FontWeight.w600)),
  const SizedBox(height: 8),
  
  ..._subjectLevels.entries.map((entry) {
    final subjectName = entry.key;
    final selectedLevels = entry.value;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF1A237E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(subjectName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _subjectLevels.remove(subjectName);
                  });
                },
                child: const Icon(Icons.close, size: 16, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _availableLevels.map((level) {
              final isLevelSelected = selectedLevels.contains(level);
              return FilterChip(
                label: Text(level, style: const TextStyle(fontSize: 11)),
                selected: isLevelSelected,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _subjectLevels[subjectName]!.add(level);
                    } else {
                      _subjectLevels[subjectName]!.remove(level);
                    }
                  });
                },
                selectedColor: const Color(0xFF4CAF50).withOpacity(0.2),
                checkmarkColor: const Color(0xFF4CAF50),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          if (selectedLevels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Select at least one class for $subjectName',
                  style: const TextStyle(color: Colors.red, fontSize: 11)),
            ),
        ],
      ),
    );
  }),
],
              const SizedBox(height: 24),

              // Documents
              const Text('Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Max $_maxFiles files, 5MB each (PDF only)', 
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 16),

              // Qualifications
              const Text('Qualifications:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._qualificationFiles.asMap().entries.map((entry) {
                return _FileChip(
                  fileName: entry.value.name,
                  fileSize: entry.value.size,
                  onRemove: () => _removeFile(entry.key, isQualification: true),
                );
              }),
              OutlinedButton.icon(
                onPressed: _qualificationFiles.length >= _maxFiles
                    ? null
                    : () => _pickFiles(isQualification: true),
                icon: const Icon(Icons.upload_file),
                label: Text(_qualificationFiles.isEmpty
                    ? 'Upload Qualifications (PDF)'
                    : 'Add More (${_qualificationFiles.length}/$_maxFiles)'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
              const SizedBox(height: 16),

              // CV
              const Text('CV / Resume:', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._cvFiles.asMap().entries.map((entry) {
                return _FileChip(
                  fileName: entry.value.name,
                  fileSize: entry.value.size,
                  onRemove: () => _removeFile(entry.key, isQualification: false),
                );
              }),
              OutlinedButton.icon(
                onPressed: _cvFiles.length >= _maxFiles ? null : () => _pickFiles(isQualification: false),
                icon: const Icon(Icons.upload_file),
                label: Text(_cvFiles.isEmpty
                    ? 'Upload CV (PDF)'
                    : 'Add More (${_cvFiles.length}/$_maxFiles)'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitApplication,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSubmitting
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 4),
                            const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            const SizedBox(height: 4),
                            Text(
                              _isUploading ? 'Uploading files...' : 'Submitting...',
                              style: const TextStyle(fontSize: 11, color: Colors.white70),
                            ),
                          ],
                        )
                      : const Text('Submit Application', 
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final String fileName;
  final int fileSize;
  final VoidCallback onRemove;

  const _FileChip({required this.fileName, required this.fileSize, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(fileName, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          Text('${(fileSize / 1024).toStringAsFixed(0)} KB',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 16, color: Colors.red),
          ),
        ],
      ),
    );
  }
}