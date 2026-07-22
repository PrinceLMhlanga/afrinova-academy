import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/auth_service.dart';
import '../../core/tutoring_service.dart';
import '../live/live_classroom_screen.dart';
import 'tutoring_whiteboard.dart';

class TutoringScreen extends StatefulWidget {
  final String teacherId;
  final String studentId;
  final String teacherName;
  final String? subjectId;
  final String? subjectName;

  const TutoringScreen({
    super.key,
    required this.teacherId,
    required this.studentId,
    required this.teacherName,
    this.subjectId,
    this.subjectName,
  });

  @override
  State<TutoringScreen> createState() => _TutoringScreenState();
}

class _TutoringScreenState extends State<TutoringScreen> {
  final AuthService _authService = AuthService();
  final TutoringService _tutoringService = TutoringService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final FocusNode _focusNode = FocusNode();

  String? _sessionId;
  String? _currentUserId;

  Map<String, dynamic>? _sessionState;
  
  // ✅ Local state like AI Tutor
  final List<Map<String, dynamic>> _messages = [];
  Map<String, String> _userNames = {};
  StreamSubscription? _realtimeSubscription;
  bool _isInitializing = true;
  bool _isSending = false;
  bool _showWhiteboard = false;
  bool _showResources = false;
  List<Map<String, dynamic>> _resources = [];
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _showScrollToBottom = false;

  bool _isTyping = false;
Timer? _typingTimer;
StreamSubscription? _sessionSubscription;
bool _whiteboardVisible = false;

// Attachment state
File? _pendingFile;
String? _pendingFileName;
String? _pendingFileType; // 'image', 'pdf', 'document', 'video'
String? _pendingFileUrl;
bool _isUploading = false;
double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 TutoringScreen initialized');
    debugPrint('👨‍🏫 Teacher: ${widget.teacherName} (${widget.teacherId})');
    _initSession();
    _startTimer();
    _setupTypingDetection();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final show = currentScroll < maxScroll - 100;
      if (show != _showScrollToBottom) {
        setState(() => _showScrollToBottom = show);
      }
    }
  }

  Future<void> _initSession() async {
    _currentUserId = _authService.currentUserId;
    if (_currentUserId == null) {
      debugPrint('❌ No current user ID');
      setState(() => _isInitializing = false);
      return;
    }

    debugPrint('🔑 Current user ID: $_currentUserId');

    try {
      // Get or create session
      _sessionId = await _tutoringService.getOrCreateSession(
        studentId: widget.studentId,
        teacherId: widget.teacherId,
        subjectId: widget.subjectId,
      );
      debugPrint('📝 Session ID: $_sessionId');

      // ✅ Get session state once (combine both queries)
      final session = await _supabase
          .from('tutoring_sessions')
          .select('*')
          .eq('id', _sessionId!)
          .single();

      debugPrint('📊 Session state: ${session}');
      
      // Store session state for whiteboard
      _sessionState = session;
      
      // Set initial whiteboard visibility
      if (session['whiteboard_visible'] == true && mounted) {
        setState(() => _showWhiteboard = true);
        debugPrint('📡 Whiteboard is visible from previous state');
      }

      // ✅ Set up session subscription FIRST (before other operations)
      _subscribeToSession();

      // Load resources
      _resources = await _tutoringService.loadResources(_sessionId!);
      debugPrint('📚 Loaded ${_resources.length} resources');

      // Load user profiles
      await _loadUserProfiles();

      // Load existing messages
      await _loadExistingMessages();

      // Set up real-time subscription for new messages
      _setupRealtimeSubscription();

    } catch (e) {
      debugPrint('❌ Error initializing session: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _subscribeToSession() {
    _sessionSubscription?.cancel();
    
    debugPrint('📡 Subscribing to session changes for session: $_sessionId');
    
    _sessionSubscription = _supabase
        .from('tutoring_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', _sessionId!)
        .listen(
          (data) {
            debugPrint('📡 STREAM: Received ${data.length} session rows');
            
            if (!mounted) {
              debugPrint('📡 STREAM: Widget not mounted, ignoring');
              return;
            }
            
            if (data.isEmpty) {
              debugPrint('📡 STREAM: Empty data, ignoring');
              return;
            }
            
            final session = data.first;
            final showBoard = session['whiteboard_visible'] == true;
            
            debugPrint('📡 STREAM: whiteboard_visible=$showBoard, current=$_showWhiteboard');
            
            // Update whiteboard visibility if changed
            if (showBoard != _showWhiteboard) {
              debugPrint('📡 STREAM: Updating whiteboard to $showBoard');
              setState(() {
                _showWhiteboard = showBoard;
                _sessionState = session;
              });
            }
          },
          onError: (error) {
            debugPrint('❌ Session stream error: $error');
          },
        );
    
    debugPrint('📡 Session subscription created successfully');
  }

  void _toggleWhiteboard() async {
    final newState = !_showWhiteboard;
    debugPrint('🔄 Toggling whiteboard to: $newState (session: $_sessionId)');
    
    // ✅ Update local state immediately
    setState(() => _showWhiteboard = newState);
    
    // ✅ Update database
    try {
      final result = await _supabase
          .from('tutoring_sessions')
          .update({'whiteboard_visible': newState})
          .eq('id', _sessionId!)
          .select();
      
      debugPrint('✅ Whiteboard toggle saved: ${result}');
      
      // ✅ Verify the update took effect
      final verify = await _supabase
          .from('tutoring_sessions')
          .select('whiteboard_visible')
          .eq('id', _sessionId!)
          .single();
      
      debugPrint('🔍 Database verification: whiteboard_visible=${verify['whiteboard_visible']}');
      
    } catch (e) {
      debugPrint('❌ Failed to toggle whiteboard: $e');
      // Revert if save fails
      setState(() => _showWhiteboard = !newState);
    }
  }

  

  Future<void> _loadUserProfiles() async {
    try {
      debugPrint('🔍 Loading user profiles...');
      
      final profiles = await _supabase
          .from('profiles')
          .select('id, display_name, full_name')
          .inFilter('id', [_currentUserId!, widget.teacherId]);

      debugPrint('📊 Found ${profiles.length} profiles');
      
      for (final profile in profiles) {
        final name = profile['display_name'] ?? profile['full_name'] ?? 'Unknown';
        _userNames[profile['id']] = name;
        debugPrint('  ✅ ${profile['id']} -> $name');
      }

      // Set teacher name if not found in profiles
      if (!_userNames.containsKey(widget.teacherId)) {
        _userNames[widget.teacherId] = widget.teacherName;
        debugPrint('  ⚠️ Teacher profile not found, using: ${widget.teacherName}');
      }
    } catch (e) {
      debugPrint('❌ Error loading profiles: $e');
      // Set fallback names
      _userNames[widget.teacherId] = widget.teacherName;
    }
  }

  Future<void> _loadExistingMessages() async {
    try {
      debugPrint('📥 Loading existing messages for session: $_sessionId');
      
      final messages = await _supabase
          .from('tutoring_messages')
          .select('*')
          .eq('session_id', _sessionId!)
          .order('created_at', ascending: true);

      debugPrint('📊 Found ${messages.length} existing messages');
      
      // ✅ Fix: Process messages and ensure sender_name exists
      final processedMessages = <Map<String, dynamic>>[];
      
      for (int i = 0; i < messages.length; i++) {
        final msg = Map<String, dynamic>.from(messages[i]);
        
        // ✅ If sender_name is null, fill it from cache or set default
        if (msg['sender_name'] == null) {
          final senderId = msg['sender_id'] as String?;
          if (senderId != null && _userNames.containsKey(senderId)) {
            msg['sender_name'] = _userNames[senderId];
          } else if (senderId == _currentUserId) {
            msg['sender_name'] = _userNames[_currentUserId] ?? 'You';
          } else if (senderId == widget.teacherId) {
            msg['sender_name'] = widget.teacherName;
          } else {
            msg['sender_name'] = 'Unknown';
          }
          
          // ✅ Update the database with the sender_name for future
          try {
            await _supabase
                .from('tutoring_messages')
                .update({'sender_name': msg['sender_name']})
                .eq('id', msg['id']);
          } catch (e) {
            debugPrint('  ⚠️ Could not update sender_name for message ${msg['id']}: $e');
          }
        }
        
        // ✅ Safe debug print (handle null content)
        final contentPreview = msg['content']?.toString() ?? '';
        final preview = contentPreview.length > 30 
            ? '${contentPreview.substring(0, 30)}...' 
            : contentPreview;
        
        debugPrint('  [$i] sender=${msg['sender_id']}, name=${msg['sender_name']}, content=$preview');
        
        processedMessages.add(msg);
      }
      
      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(processedMessages);
        });
        debugPrint('✅ Loaded ${_messages.length} messages into local state');
      }
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
    }
  }

  void _setupTypingDetection() {
  _messageController.addListener(() {
    final hasText = _messageController.text.isNotEmpty;
    if (hasText && !_isTyping) {
      setState(() => _isTyping = true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isTyping = false);
    });
  });
}

  void _setupRealtimeSubscription() {
    debugPrint('🎧 Setting up real-time subscription for session: $_sessionId');
    
    _realtimeSubscription?.cancel();
    
    _realtimeSubscription = _supabase
        .from('tutoring_messages')
        .stream(primaryKey: ['id'])
        .eq('session_id', _sessionId!)
        .order('created_at', ascending: true)
        .listen(
          (messages) {
            debugPrint('🔔 Real-time update: received ${messages.length} messages');
            
            // Process messages to ensure sender_name exists
            final processedMessages = messages.map((msg) {
              final processed = Map<String, dynamic>.from(msg);
              if (processed['sender_name'] == null) {
                final senderId = processed['sender_id'] as String?;
                processed['sender_name'] = _userNames[senderId] ?? 
                    (senderId == widget.teacherId ? widget.teacherName : 'Unknown');
              }
              return processed;
            }).toList();
            
            // Check for new messages
            final existingIds = _messages.map((m) => m['id']).toSet();
            final newMessages = processedMessages.where((msg) => !existingIds.contains(msg['id'])).toList();
            
            if (newMessages.isNotEmpty) {
              debugPrint('🆕 ${newMessages.length} new message(s) detected!');
              for (final msg in newMessages) {
                debugPrint('  New: sender=${msg['sender_id']}, name=${msg['sender_name']}, content=${msg['content']}');
              }
            } else {
              debugPrint('  No new messages (all ${messages.length} already in local state)');
            }
            
            if (mounted) {
              setState(() {
                _messages.clear();
                _messages.addAll(processedMessages);
              });
              _scrollToBottom();
            }
          },
          onError: (error) {
            debugPrint('❌ Stream error: $error');
          },
        );
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _sessionId == null || _currentUserId == null) return;

    debugPrint('📤 Sending message: "$text"');
    
    setState(() => _isSending = true);
    _messageController.clear();

    try {
      // ✅ Get sender name from cache
      final senderName = _userNames[_currentUserId] ?? 'Unknown';
      debugPrint('  👤 Sender name: $senderName');

      // Insert into database
      final result = await _supabase
          .from('tutoring_messages')
          .insert({
            'session_id': _sessionId,
            'sender_id': _currentUserId,
            'content': text,
            'message_type': 'text',
            'sender_name': senderName, // ✅ Always include sender_name
          })
          .select()
          .single();

      debugPrint('✅ Message inserted with ID: ${result['id']}');

      // ✅ Add to local state immediately (with sender_name)
      final localMessage = Map<String, dynamic>.from(result);
      localMessage['sender_name'] = senderName;

      if (mounted) {
        setState(() {
          _messages.add(localMessage);
        });
        _scrollToBottom();
      }

    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

 void _showAttachmentSheet() {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          
          // Attachment options only
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _attachmentOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromCamera();
                },
              ),
              _attachmentOption(
                icon: Icons.image_rounded,
                label: 'Gallery',
                color: Colors.purple,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery();
                },
              ),
              _attachmentOption(
                icon: Icons.description_rounded,
                label: 'Document',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickDocument();
                },
              ),
              _attachmentOption(
                icon: Icons.folder_rounded,
                label: 'Browse',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendFile();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

Future<void> _uploadAndSend({
  required Uint8List bytes,
  required String fileName,
  required String fileType,
  String caption = '',
}) async {
  if (_sessionId == null || _currentUserId == null) return;
  
  final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
  
  // Add optimistic message
  setState(() {
    _messages.add({
      'id': tempId,
      'sender_id': _currentUserId,
      'content': caption.isNotEmpty ? caption : (fileType == 'image' ? '📷 Image' : '📎 $fileName'),
      'message_type': fileType,
      'file_url': null,
      'file_name': fileName,
      'sender_name': _userNames[_currentUserId] ?? 'You',
      'created_at': DateTime.now().toIso8601String(),
      '_uploading': true,
    });
  });
  _scrollToBottom();
  
  try {
    final filePath = 'tutoring/$_sessionId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    
    await _supabase.storage
        .from('tutoring')
        .uploadBinary(filePath, bytes);  // ✅ Upload bytes directly
    
    final url = _supabase.storage.from('tutoring').getPublicUrl(filePath);
    
    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempId);
      });
    }
    
    final content = caption.isNotEmpty ? caption : (fileType == 'image' ? '📷 Image' : '📎 $fileName');
    
    await _sendFileMessage(
      content: content,
      fileUrl: url,
      fileName: fileName,
      messageType: fileType,
    );
    
  } catch (e) {
    debugPrint('Upload error: $e');
    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m['id'] == tempId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
}


Widget _attachmentOption({
  required IconData icon,
  required String label,
  required Color color,
  required VoidCallback onTap,
}) {
  return GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    ),
  );
}

Future<void> _pickFromCamera() async {
  try {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image == null) return;
    
    final bytes = await image.readAsBytes();
    _showCaptionDialog(bytes, image.name, 'image');
  } catch (e) {
    debugPrint('Camera error: $e');
  }
}

Future<void> _pickFromGallery() async {
  try {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (image == null) return;
    
    final bytes = await image.readAsBytes();
    _showCaptionDialog(bytes, image.name, 'image');
  } catch (e) {
    debugPrint('Gallery error: $e');
  }
}

Future<void> _pickDocument() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'],
    );
    if (result == null || result.files.isEmpty) return;
    
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    
    _showCaptionDialog(bytes, file.name, _getFileType(file.name));
  } catch (e) {
    debugPrint('Document error: $e');
  }
}

// Also fix the existing file picker
Future<void> _pickAndSendFile() async {
  try {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    
    _showCaptionDialog(bytes, file.name, _getFileType(file.name));
  } catch (e) {
    debugPrint('File error: $e');
  }
}

final TextEditingController _captionController = TextEditingController();

void _showCaptionDialog(Uint8List bytes, String fileName, String fileType) {
  _captionController.clear();
  
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 16, right: 16, top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File preview
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: fileType == 'image'
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(bytes, fit: BoxFit.cover),  // ✅ Use memory
                      )
                    : Icon(
                        fileType == 'pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file,
                        color: const Color(0xFF075E54),
                        size: 28,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  fileName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Caption input
          TextField(
            controller: _captionController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Add a caption...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 12),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _uploadAndSend(
                  bytes: bytes,
                  fileName: fileName,
                  fileType: fileType,
                  caption: _captionController.text.trim(),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF075E54),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Send', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
Future<void> _uploadAndSendFile({String caption = ''}) async {
  if (_pendingFile == null || _sessionId == null) return;
  
  setState(() => _isUploading = true);
  
  try {
    final bytes = await _pendingFile!.readAsBytes();
    final fileName = _pendingFileName ?? 'file';
    final filePath = 'tutoring/$_sessionId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    
    await _supabase.storage
        .from('tutoring')
        .uploadBinary(filePath, Uint8List.fromList(bytes));
    
    final url = _supabase.storage.from('tutoring').getPublicUrl(filePath);
    
    // Send message with file
    await _sendFileMessage(
      content: caption.isNotEmpty ? caption : (_pendingFileType == 'image' ? '📷 Image' : '📎 $fileName'),
      fileUrl: url,
      fileName: fileName,
      messageType: _pendingFileType ?? 'file',
    );
    
    // Clear pending
    setState(() {
      _pendingFile = null;
      _pendingFileName = null;
      _pendingFileType = null;
      _pendingFileUrl = null;
      _isUploading = false;
    });
    
  } catch (e) {
    debugPrint('Upload error: $e');
    setState(() => _isUploading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

void _cancelAttachment() {
  setState(() {
    _pendingFile = null;
    _pendingFileName = null;
    _pendingFileType = null;
    _pendingFileUrl = null;
    _isUploading = false;
  });
}

  Future<void> _sendFileMessage({
    required String content,
    required String fileUrl,
    required String fileName,
    required String messageType,
  }) async {
    if (_isSending || _sessionId == null || _currentUserId == null) return;

    debugPrint('📎 Sending file message: $fileName');
    setState(() => _isSending = true);

    try {
      final senderName = _userNames[_currentUserId] ?? 'Unknown';

      final result = await _supabase
          .from('tutoring_messages')
          .insert({
            'session_id': _sessionId,
            'sender_id': _currentUserId,
            'content': content,
            'message_type': messageType,
            'file_url': fileUrl,
            'file_name': fileName,
            'sender_name': senderName, // ✅ Always include sender_name
          })
          .select()
          .single();

      debugPrint('✅ File message inserted: ${result['id']}');

      final localMessage = Map<String, dynamic>.from(result);
      localMessage['sender_name'] = senderName;

      if (mounted) {
        setState(() {
          _messages.add(localMessage);
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('❌ Error sending file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending file: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  

  Future<void> _pickAndSendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      final fileName = image.name;
      final filePath = 'tutoring/${_sessionId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploading image...'), duration: Duration(seconds: 2)),
        );
      }

      await _supabase.storage
          .from('tutoring')
          .uploadBinary(filePath, Uint8List.fromList(bytes));

      final url = _supabase.storage.from('tutoring').getPublicUrl(filePath);

      await _sendFileMessage(
        content: '📷 Image',
        fileUrl: url,
        fileName: fileName,
        messageType: 'image',
      );
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading image: $e')),
        );
      }
    }
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return 'pdf';
    if (['doc', 'docx'].contains(ext)) return 'document';
    if (['mp3', 'wav', 'm4a'].contains(ext)) return 'audio';
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return 'video';
    return 'file';
  }

  void _startVideoCall() {
    final roomName = 'tutoring_${_sessionId}';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveClassroomScreen(
          roomName: roomName,
          lessonId: _sessionId!,
          isTeacher: false,
        ),
      ),
    );
  }

  Future<void> _endSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Session?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Session duration: ${_formatDuration(_elapsedSeconds)}'),
            const SizedBox(height: 8),
            const Text('Are you sure you want to end this tutoring session?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _tutoringService.endSession(_sessionId!, (_elapsedSeconds / 60).ceil());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session ended successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to end session: $e')),
          );
        }
      }
    }
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// ✅ Get display name for a sender
  String _getSenderName(Map<String, dynamic> message) {
    // First check if the message has sender_name
    if (message['sender_name'] != null && message['sender_name'].toString().isNotEmpty) {
      return message['sender_name'];
    }
    
    // Fall back to cache
    final senderId = message['sender_id'] as String?;
    if (senderId != null && _userNames.containsKey(senderId)) {
      return _userNames[senderId]!;
    }
    
    // Fall back to defaults
    if (senderId == _currentUserId) return 'You';
    if (senderId == widget.teacherId) return widget.teacherName;
    
    return 'Unknown';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _timer?.cancel();
    _realtimeSubscription?.cancel();
    _sessionSubscription?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: _buildAppBar(),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Whiteboard area
                if (_showWhiteboard)
  Container(
    height: 300,
    color: Colors.white,
    child: TutoringWhiteboard(
      sessionId: _sessionId!,
      initialSessionState: _sessionState,
      onStateChanged: (updates) {
        setState(() {
          _sessionState = {...?_sessionState, ...updates};
        });
      },
    ),
  ),
                
                // Resources panel
                if (_showResources)
                  Container(
                    height: 200,
                    color: Colors.grey.shade100,
                    child: _buildResourcesPanel(),
                  ),
                
                // ✅ Chat messages - using local state like AI Tutor
                Expanded(
                  child: _messages.isEmpty
                      ? _buildWelcomeScreen()
                      : Stack(
                          children: [
                            ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                final isMe = message['sender_id'] == _currentUserId;
                                final senderName = _getSenderName(message);

                                return ChatBubble(
                                  content: message['content'] ?? '',
                                  isMe: isMe,
                                  senderName: senderName,
                                  fileUrl: message['file_url'],
                                  fileName: message['file_name'],
                                  messageType: message['message_type'] ?? 'text',
                                  createdAt: message['created_at'],
                                );
                              },
                            ),
                            // Scroll to bottom button
                            if (_showScrollToBottom)
                              Positioned(
                                bottom: 16,
                                right: 16,
                                child: GestureDetector(
                                  onTap: _scrollToBottom,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF075E54),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.arrow_downward_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),

                // In the Column, after the Expanded chat area:

                
                // Pending attachment preview
if (_pendingFile != null)
  _buildAttachmentPreview(),

// Message input
_buildMessageInput(),
              ],
            ),
    );
  }

  Widget _buildAttachmentPreview() {
  return Container(
    padding: const EdgeInsets.all(12),
    color: Colors.grey.shade100,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File preview
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: _pendingFileType == 'image'
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(_pendingFile!, fit: BoxFit.cover),
                )
              : Icon(
                  _pendingFileType == 'pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file,
                  color: const Color(0xFF075E54),
                  size: 30,
                ),
        ),
        const SizedBox(width: 12),
        
        // Caption input
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _pendingFileName ?? 'File',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Add a caption...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (caption) => _uploadAndSendFile(caption: caption),
                    ),
                  ),
                  if (_isUploading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
        
        // Send button
        IconButton(
          icon: const Icon(Icons.send, color: Color(0xFF075E54), size: 22),
          onPressed: _isUploading ? null : () => _uploadAndSendFile(),
        ),
        
        // Cancel
        IconButton(
          icon: const Icon(Icons.close, color: Colors.red, size: 20),
          onPressed: _cancelAttachment,
        ),
      ],
    ),
  );
}

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF075E54),
      foregroundColor: Colors.white,
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white.withOpacity(0.2),
            child: Text(
              widget.teacherName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.teacherName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.subjectName != null)
                  Text(
                    widget.subjectName!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Timer
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _formatDuration(_elapsedSeconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // Video call
        IconButton(
          icon: const Icon(Icons.video_call, color: Colors.white),
          onPressed: _startVideoCall,
          tooltip: 'Video Call',
        ),
        // More options
        PopupMenuButton<String>(
          iconColor: Colors.white,
          onSelected: (value) {
            switch (value) {
              case 'whiteboard':
  _toggleWhiteboard();
  break;
              case 'resources':
                setState(() => _showResources = !_showResources);
                break;
              case 'end':
                _endSession();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'whiteboard',
              child: Row(
                children: [
                  Icon(_showWhiteboard ? Icons.close : Icons.draw, size: 20),
                  const SizedBox(width: 8),
                  Text(_showWhiteboard ? 'Hide Whiteboard' : 'Whiteboard'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'resources',
              child: Row(
                children: [
                  Icon(_showResources ? Icons.close : Icons.folder, size: 20),
                  const SizedBox(width: 8),
                  Text(_showResources ? 'Hide Resources' : 'Resources'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'end',
              child: const Row(
                children: [
                  Icon(Icons.call_end, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('End Session', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF075E54).withOpacity(0.1),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: const Color(0xFF075E54).withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start chatting with ${widget.teacherName}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.white,
      child: SafeArea(
        child: Row(
          children: [
            // With this:
IconButton(
  icon: const Icon(Icons.attach_file, color: Color(0xFF075E54)),
  onPressed: _showAttachmentSheet,
  iconSize: 22,
),
            Expanded(
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 0,
                color: Colors.grey.shade50,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    enabled: !_isSending,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            CircleAvatar(
              backgroundColor: const Color(0xFF075E54),
              child: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
                      padding: EdgeInsets.zero,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResourcesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.folder, size: 18, color: Color(0xFF075E54)),
              const SizedBox(width: 8),
              const Text(
                'Shared Resources',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF075E54),
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF075E54).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_resources.length} files',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF075E54),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _resources.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No resources shared yet',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _resources.length,
                  itemBuilder: (context, index) {
                    final resource = _resources[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          resource['file_type'] == 'pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file,
                          color: const Color(0xFF075E54),
                          size: 20,
                        ),
                        title: Text(
                          resource['title'] ?? 'Resource',
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.download, size: 18),
                          onPressed: () {
                            final url = resource['file_url'];
                            if (url != null) {
                              debugPrint('Downloading: $url');
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ===== CHAT BUBBLE =====
class ChatBubble extends StatelessWidget {
  final String content;
  final bool isMe;
  final String senderName;
  final String? fileUrl;
  final String? fileName;
  final String messageType;
  final String? createdAt;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isMe,
    required this.senderName,
    this.fileUrl,
    this.fileName,
    this.messageType = 'text',
    this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                senderName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
                bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMessageContent(context),
                if (createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _formatTime(createdAt!),
                      style: TextStyle(
                        fontSize: 9,
                        color: isMe ? Colors.grey.shade700 : Colors.grey.shade500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Hero(
            tag: url,
            child: InteractiveViewer(
              child: Image.network(url),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildMessageContent(BuildContext context) {
    switch (messageType) {
      case 'image':
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (fileUrl != null)
        GestureDetector(
          onTap: () => _showFullImage(context, fileUrl!), // Open full screen
          child: Hero(
            tag: fileUrl!,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                fileUrl!,
                fit: BoxFit.cover,
                width: 200,
                height: 150,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 200,
                    height: 150,
                    color: Colors.grey.shade200,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                            : null,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 200,
                    height: 150,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.error_outline, size: 40, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
        ),
      if (content.isNotEmpty && content != '📷 Image')
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(content, style: TextStyle(fontSize: 16, color: isMe ? Colors.black87 : Colors.black87)),
        ),
    ],
  );
      case 'file':
      case 'pdf':
      case 'document':
        return GestureDetector(
          onTap: () {
            if (fileUrl != null) {
              debugPrint('Opening file: $fileUrl');
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF075E54).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  messageType == 'pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file,
                  color: const Color(0xFF075E54),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName ?? 'File',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text('Tap to view', style: TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'video':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fileUrl != null)
              Container(
                width: 200,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.play_circle_filled, size: 48, color: Colors.white),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Video', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ),
                  ],
                ),
              ),
            if (content.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(content, style: const TextStyle(fontSize: 16, color: Colors.black87)),
              ),
          ],
        );
      default:
        return Text(content, style: const TextStyle(fontSize: 16, color: Colors.black87));
    }
  }

  String _formatTime(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        return DateFormat('HH:mm').format(date);
      } else if (difference.inDays == 1) {
        return 'Yesterday ${DateFormat('HH:mm').format(date)}';
      } else if (difference.inDays < 7) {
        return DateFormat('EEE HH:mm').format(date);
      } else {
        return DateFormat('MMM d HH:mm').format(date);
      }
    } catch (_) {
      return '';
    }
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(  // ✅ Correct Flutter widget name
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3 + (_controller.value * 0.5)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}