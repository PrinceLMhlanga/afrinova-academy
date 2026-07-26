import 'dart:async';
import 'dart:io';
import 'dart:convert';
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
import '../pdf/pdf_viewer_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'markable_image_viewer.dart';
import '../../core/call_sound_service.dart';

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

// Call state
bool _isInCall = false;
bool _isCallIncoming = false;
String? _callRoomName;
StreamSubscription? _callSubscription;
bool _iAmCaller = false;

// Attachment state
File? _pendingFile;
String? _pendingFileName;
String? _pendingFileType; // 'image', 'pdf', 'document', 'video'
String? _pendingFileUrl;
bool _isUploading = false;
double _uploadProgress = 0;

Timer? _callTimeoutTimer;

BuildContext? _callingDialogContext;

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
  
  _sessionSubscription = _supabase
      .from('tutoring_sessions')
      .stream(primaryKey: ['id'])
      .eq('id', _sessionId!)
      .listen(
        (data) {
          if (!mounted || data.isEmpty) return;
          
          final session = data.first;
          
          // ✅ Handle whiteboard visibility
          final showBoard = session['whiteboard_visible'] == true;
          if (showBoard != _showWhiteboard) {
            setState(() {
              _showWhiteboard = showBoard;
              _sessionState = session;
            });
          }
          
          // ✅ Handle call events
          // ✅ Handle call events
final callStatus = session['call_status'] as String?;
final callRoom = session['call_room'] as String?;
final callInitiator = session['call_initiator'] as String?;

if (callStatus != null) {
  debugPrint('📞 Call event: status=$callStatus, room=$callRoom, initiator=$callInitiator');
  debugPrint('📞 DEBUG: _iAmCaller=$_iAmCaller, _isCallIncoming=$_isCallIncoming');
  
  if (callStatus == 'accepted' && callRoom != null) {
    CallSoundService.stop();
    // Accepted - join call
    if (_iAmCaller) {
      _iAmCaller = false;
      if (_callingDialogContext != null) {
        Navigator.of(_callingDialogContext!).pop();
        _callingDialogContext = null;
      }
    }
    if (_isCallIncoming) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    _joinCall(callRoom);
  } 
  else if (callStatus == 'declined') {
    CallSoundService.stop();
    // Declined
    if (_iAmCaller) {
      _iAmCaller = false;
      if (_callingDialogContext != null) {
        Navigator.of(_callingDialogContext!).pop();
        _callingDialogContext = null;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Call declined'), backgroundColor: Colors.orange),
      );
    }
    setState(() {
      _isInCall = false;
      _isCallIncoming = false;
      _callRoomName = null;
    });
  } 
  else if (callStatus == 'ended') {
    CallSoundService.stop();
    // ✅ Ended - close BOTH sides
    if (_iAmCaller) {
      _iAmCaller = false;
      if (_callingDialogContext != null) {
        Navigator.of(_callingDialogContext!).pop();
        _callingDialogContext = null;
      }
    }
    if (_isCallIncoming) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
    setState(() {
      _isInCall = false;
      _isCallIncoming = false;
      _callRoomName = null;
    });
  } 
  else if (callStatus == 'ringing' && !_iAmCaller) {
    // Incoming call
    if (!_isCallIncoming) {
      setState(() {
        _isCallIncoming = true;
        _callRoomName = callRoom;
      });
      _showIncomingCallDialog();
    }
  }
}
        },
        onError: (error) {
          debugPrint('❌ Session stream error: $error');
        },
      );
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
  icon: Icons.quiz_rounded,
  label: 'Quiz',
  color: Colors.indigo,
  onTap: () {
    Navigator.pop(ctx);
    _showCreateQuizDialog();
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

void _showCreateQuizDialog() {
  final List<Map<String, dynamic>> questions = [];
  
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _QuizCreator(
        onSave: (quizQuestions) {
          Navigator.pop(ctx);
          _sendQuiz(quizQuestions);
        },
      ),
    ),
  );
}

Future<void> _sendQuiz(List<Map<String, dynamic>> questions) async {
  if (_sessionId == null || _currentUserId == null) return;
  
  final senderName = _userNames[_currentUserId] ?? 'Unknown';
  
  for (final q in questions) {
    final quizData = jsonEncode({
      'question': q['question'],
      'options': q['options'],
      'correct': q['correct'],
      'answered': false,
      'selectedOption': null,
      'isCorrect': null,
    });
    
    await _supabase.from('tutoring_messages').insert({
      'session_id': _sessionId,
      'sender_id': _currentUserId,
      'content': quizData,
      'message_type': 'quiz',
      'sender_name': senderName,
    });
  }
  
  // ✅ Reload messages to get the real IDs
  await _loadExistingMessages();
}

Future<void> _submitQuizAnswer(String messageId, int selectedOption, Map<String, dynamic> quizData) async {
  final correctAnswer = quizData['correct'] as int;
  final isCorrect = selectedOption == correctAnswer;
  
  quizData['answered'] = true;
  quizData['selectedOption'] = selectedOption;
  quizData['isCorrect'] = isCorrect;
  
  final updatedContent = jsonEncode(quizData);
  
  // ✅ Update in database - real-time syncs to both users
  await _supabase
      .from('tutoring_messages')
      .update({'content': updatedContent})
      .eq('id', messageId);
  
  // ✅ Update local state immediately
  if (mounted) {
    setState(() {
      final index = _messages.indexWhere((m) => m['id'] == messageId);
      if (index != -1) {
        _messages[index]['content'] = updatedContent;
      }
    });
  }
  
}


void _dismissCallDialog() {
  setState(() {
    _isInCall = false;
    _isCallIncoming = false;
    _callRoomName = null;
  });
}



Future<void> _startCall() async {
  if (_sessionId == null) return;
  
  final roomName = 'tutoring_call_${_sessionId}_${DateTime.now().millisecondsSinceEpoch}';
  
  setState(() {
    _isInCall = true;
    _iAmCaller = true; 
    _callRoomName = roomName;
  });
  
  // Update session with call info
  await _supabase
      .from('tutoring_sessions')
      .update({
        'call_status': 'ringing',
        'call_room': roomName,
        'call_initiator': _currentUserId,
        'call_started_at': DateTime.now().toIso8601String(),
      })
      .eq('id', _sessionId!);
  
  // Show calling screen
  CallSoundService.startCalling();
  _showCallingScreen(roomName);
}

void _showCallingScreen(String roomName) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      _callingDialogContext = ctx;
      
      // ✅ Auto-cancel after 30 seconds
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer = Timer(const Duration(seconds: 30), () {
        if (_callingDialogContext != null) {
          Navigator.of(_callingDialogContext!).pop();
          _callingDialogContext = null;
        }
        _cancelCall();
      });
      
      return _CallingDialog(
        callerName: widget.teacherName,
        onCancel: () {
          _callTimeoutTimer?.cancel();
          Navigator.pop(ctx);
          _cancelCall();
        },
      );
    },
  ).then((_) {
    _callTimeoutTimer?.cancel();
    _callingDialogContext = null;
  });
}

void _showIncomingCallDialog() {
  CallSoundService.startRinging();
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _IncomingCallDialog(
      callerName: widget.teacherName,
      onAccept: () async {
        Navigator.pop(ctx); // ✅ Only dismiss dialog
        await _acceptCall();
      },
      onDecline: () async {
        Navigator.pop(ctx); // ✅ Only dismiss dialog
        await _declineCall();
      },
    ),
  ).then((_) => CallSoundService.stop());
}

Future<void> _acceptCall() async {
  CallSoundService.stop();
  if (_sessionId == null || _callRoomName == null) return;
  
  await _supabase
      .from('tutoring_sessions')
      .update({'call_status': 'accepted'})
      .eq('id', _sessionId!);
  
  _joinCall(_callRoomName!);
}

Future<void> _declineCall() async {
  CallSoundService.stop();
  if (_sessionId == null) return;
  
  debugPrint('📞 Declining call...');
  
  await _supabase
      .from('tutoring_sessions')
      .update({
        'call_status': 'declined',
        'call_room': null,
        'call_initiator': null,
      })
      .eq('id', _sessionId!);
  
  setState(() {
    _isCallIncoming = false;
    _callRoomName = null;
  });
}

Future<void> _cancelCall() async {
  CallSoundService.stop(); 
  if (_sessionId == null) return;
  
  _iAmCaller = false;
  
  await _supabase
      .from('tutoring_sessions')
      .update({
        'call_status': 'ended',
        'call_room': null,
        'call_initiator': null,
      })
      .eq('id', _sessionId!);
}

void _joinCall(String roomName) {
  setState(() {
    _isInCall = false;
    _isCallIncoming = false;
  });
  
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


Future<void> _uploadAndSend({
  required Uint8List bytes,
  required String fileName,
  required String fileType,
  String caption = '',
}) async {
  if (_sessionId == null || _currentUserId == null) return;
  
  final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
  final content = caption.isNotEmpty ? caption : (fileType == 'image' ? '📷 Image' : '📎 $fileName');
  
  // ✅ Add optimistic message IMMEDIATELY (before upload)
  setState(() {
    _messages.add({
      'id': tempId,
      'sender_id': _currentUserId,
      'content': content,
      'message_type': fileType,
      'file_url': null, // Will update after upload
      'file_name': fileName,
      'sender_name': _userNames[_currentUserId] ?? 'You',
      'created_at': DateTime.now().toIso8601String(),
      '_uploading': true,
      '_localBytes': bytes, // Store bytes locally for preview
    });
  });
  _scrollToBottom();
  
  // ✅ Upload in background
  try {
    final filePath = 'tutoring/$_sessionId/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    
    await _supabase.storage
        .from('tutoring')
        .uploadBinary(filePath, bytes);
    
    final url = _supabase.storage.from('tutoring').getPublicUrl(filePath);
    
    // ✅ Update the optimistic message with real URL
    final index = _messages.indexWhere((m) => m['id'] == tempId);
    if (index != -1 && mounted) {
      setState(() {
        _messages[index]['file_url'] = url;
        _messages[index]['_uploading'] = false;
        _messages[index]['created_at'] = DateTime.now().toIso8601String();
      });
    }
    
    // ✅ Also send to database for the other user
    await _supabase.from('tutoring_messages').insert({
      'session_id': _sessionId,
      'sender_id': _currentUserId,
      'content': content,
      'message_type': fileType,
      'file_url': url,
      'file_name': fileName,
      'file_size': bytes.length,
      'sender_name': _userNames[_currentUserId] ?? 'You',
    });
    
  } catch (e) {
    debugPrint('Upload error: $e');
    // ✅ Mark as failed but keep the message
    final index = _messages.indexWhere((m) => m['id'] == tempId);
    if (index != -1 && mounted) {
      setState(() {
        _messages[index]['_uploading'] = false;
        _messages[index]['_failed'] = true;
      });
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



void _openFile(Map<String, dynamic> message) async {
  final fileUrl = message['file_url'] as String?;
  final fileType = message['message_type'] as String? ?? 'file';
  final fileName = message['file_name'] as String? ?? 'File';
  
  if (fileUrl == null || fileUrl.isEmpty) return;
  
  if (fileType == 'pdf') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfViewerScreen(url: fileUrl, title: fileName),
      ),
    );
  } else if (fileType == 'image') {
    // ✅ Open markable image viewer
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MarkableImageViewer(
          imageUrl: fileUrl,
          fileName: fileName,
        ),
      ),
    );
    
    // If teacher marked and sent, upload and send back
    if (result != null && mounted) {
      final markedBytes = result['bytes'] as Uint8List;
      final markedFileName = result['fileName'] as String;
      _uploadAndSend(
        bytes: markedBytes,
        fileName: markedFileName,
        fileType: 'image',
        caption: '✏️ Marked assignment',
      );
    }
  } else {
    launchUrl(Uri.parse(fileUrl), mode: LaunchMode.externalApplication);
  }
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
  if (_sessionId == null || _currentUserId == null) return;

  try {
    final senderName = _userNames[_currentUserId] ?? 'Unknown';

    await _supabase
        .from('tutoring_messages')
        .insert({
          'session_id': _sessionId,
          'sender_id': _currentUserId,
          'content': content,
          'message_type': messageType,
          'file_url': fileUrl,
          'file_name': fileName,
          
          'sender_name': senderName,
        });
    
    // ✅ Don't add to local state - the real-time subscription will handle it
    // The optimistic bubble is already showing in the UI
    debugPrint('✅ File message sent to database');
    
  } catch (e) {
    debugPrint('❌ Error sending file: $e');
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
    _startCall();
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
    _callTimeoutTimer?.cancel();
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
  fileSize: message['file_size'] is int ? message['file_size'] : int.tryParse('${message['file_size']}'),
  messageType: message['message_type'] ?? 'text',
  createdAt: message['created_at'],
  isUploading: message['_uploading'] == true,
  messageId: message['id'] as String?,
  
  onCancelUpload: () {
    setState(() {
      _messages.removeWhere((m) => m['id'] == message['id']);
    });
  },
  onMarkedImage: (bytes, fileName) async {  // ✅ Add async
  _showCaptionDialog(bytes, fileName, 'image');
},
onQuizAnswer: (msgId, option, quizData) {
    _submitQuizAnswer(msgId, option, quizData);
  },
  onOpenFile: () => _openFile(message),
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
  final int? fileSize;
  final String? fileName;
  final String messageType;
  final String? createdAt;
  final bool isUploading;
  final bool isDownloading;
  final double? downloadProgress;
  final VoidCallback? onCancelUpload;
  final Future<void> Function(Uint8List bytes, String fileName)? onMarkedImage;
  final VoidCallback? onOpenFile;
  final void Function(String messageId, int option, Map<String, dynamic> quizData)? onQuizAnswer;
  final String? messageId;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isMe,
    required this.senderName,
    this.fileUrl,
    this.fileSize,
    this.fileName,
    this.messageType = 'text',
    this.createdAt,
    this.isUploading = false,
    this.isDownloading = false,
    this.downloadProgress,
    this.onCancelUpload,
    this.onMarkedImage,
    this.onOpenFile,
    this.onQuizAnswer,
    this.messageId,
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

  



  Widget _buildMessageContent(BuildContext context) {
    switch (messageType) {
      case 'image':
   return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Show local preview while uploading, network after
          if (fileUrl != null && fileUrl!.isNotEmpty)
            GestureDetector(
              onTap: () {
  // ✅ Don't make this async - call a separate method
  _handleImageTap(context);
},
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
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            // ✅ Show upload progress placeholder
            Container(
              width: 200,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 8),
                    Text('Uploading...', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          if (content.isNotEmpty && content != '📷 Image')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(content, style: const TextStyle(fontSize: 15, color: Colors.black87)),
            ),
        ],
      );
      case 'file':
case 'pdf':
case 'document':
  return _FileMessageCard(
    fileName: fileName ?? 'File',
    fileType: messageType,
    fileSize: fileSize,
    fileUrl: fileUrl,
    isMe: isMe,
    isUploading: isUploading,
    isDownloading: isDownloading,
    downloadProgress: downloadProgress,
    content: content,
    onCancel: onCancelUpload,
    
    onOpen: onOpenFile,
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
      case 'quiz':
  try {
    final quizData = jsonDecode(content);
    final msgId = messageId; // ✅ Local copy for promotion
    final quizAnswer = onQuizAnswer; // ✅ Local copy for promotion
    
    return _QuizCard(
      question: quizData['question'] ?? content,
      options: List<String>.from(quizData['options'] ?? []),
      correctAnswer: quizData['correct'] as int?,
      selectedOption: quizData['selectedOption'] as int?,
      isMe: isMe,
      isAnswered: quizData['answered'] == true,
      onAnswer: (option) {
        if (quizAnswer != null && msgId != null) {
          quizAnswer(msgId, option, quizData);
        }
      },
    );
  } catch (_) {
    return Text(content, style: const TextStyle(fontSize: 16, color: Colors.black87));
  }
      default:
        return Text(content, style: const TextStyle(fontSize: 16, color: Colors.black87));
    }
  }

  void _handleImageTap(BuildContext context) async {
  if (fileUrl == null || fileUrl!.isEmpty) return;
  
  final result = await Navigator.push<Map<String, dynamic>>(
    context,
    MaterialPageRoute(
      builder: (_) => MarkableImageViewer(
        imageUrl: fileUrl!,
        fileName: fileName ?? 'image',
      ),
    ),
  );
  
  if (result != null && onMarkedImage != null) {
    onMarkedImage!(result['bytes'] as Uint8List, result['fileName'] as String);
  }
}

  

  String _formatTime(String dateStr) {
  try {
    final date = DateTime.parse(dateStr).toLocal();  // ✅ Add .toLocal()
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
  String _formatFileSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

class _FileMessageCard extends StatelessWidget {
  final String fileName;
  final String fileType;
  final int? fileSize;
  final String? fileUrl;
  final bool isMe;
  final bool isUploading;
  final bool isDownloading;
  final double? downloadProgress;
  final String content;
  final VoidCallback? onCancel;
  
  final VoidCallback? onOpen;

  const _FileMessageCard({
    required this.fileName,
    required this.fileType,
    this.fileSize,
    this.fileUrl,
    required this.isMe,
    this.isUploading = false,
    this.isDownloading = false,
    this.downloadProgress,
    required this.content,
    this.onCancel,
   
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final hasCaption = content.isNotEmpty && 
        content != '📎 $fileName' && 
        content != '📷 Image';

    return GestureDetector(
      onTap: fileUrl != null && fileUrl!.isNotEmpty && !isUploading ? onOpen : null,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail area with upload/download overlay
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _getFileColor(fileType).withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // File icon
                  Icon(
                    _getFileIcon(fileType),
                    color: _getFileColor(fileType),
                    size: 48,
                  ),
                  
                  // Uploading overlay
                  if (isUploading)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Cancel button (X)
                          GestureDetector(
                            onTap: onCancel,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  
                  
                  // Download button (receiver, not downloaded yet)
                  
                ],
              ),
            ),
            
            // File info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _getFileTypeLabel(fileType),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      if (fileSize != null) ...[
                        const Text(' • ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          _formatFileSize(fileSize),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                  if (hasCaption)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        content,
                        style: const TextStyle(fontSize: 15, color: Colors.black87),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getFileColor(String type) {
    switch (type) {
      case 'pdf': return Colors.red;
      case 'document': return Colors.blue;
      case 'video': return Colors.purple;
      default: return const Color(0xFF075E54);
    }
  }

  IconData _getFileIcon(String type) {
    switch (type) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'document': return Icons.description;
      case 'video': return Icons.videocam;
      default: return Icons.insert_drive_file;
    }
  }

  String _getFileTypeLabel(String type) {
    switch (type) {
      case 'pdf': return 'PDF Document';
      case 'document': return 'Document';
      case 'video': return 'Video';
      default: return 'File';
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _QuizCard extends StatefulWidget {
  final String question;
  final List<String> options;
  final int? correctAnswer;
  final int? selectedOption;
  final bool isMe;
  final bool isAnswered;
  final void Function(int option)? onAnswer;

  const _QuizCard({
    required this.question,
    required this.options,
    this.correctAnswer,
    this.selectedOption,
    required this.isMe,
    this.isAnswered = false,
    this.onAnswer,
  });

  @override
  State<_QuizCard> createState() => _QuizCardState();
}

class _QuizCardState extends State<_QuizCard> {
  int? _selected;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedOption;
    _submitted = widget.isAnswered;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: widget.isMe ? const Color(0xFFDCF8C6) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quiz header
Container(
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  decoration: BoxDecoration(
    color: Colors.indigo.withOpacity(0.08),
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
  ),
  child: Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.indigo.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.quiz_rounded, color: Colors.indigo, size: 18),
      ),
      const SizedBox(width: 10),
      const Expanded(
        child: Text('Quick Quiz', style: TextStyle(
          color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 14,
        )),
      ),
      // ✅ Show answered/not answered badge
      if (widget.isAnswered)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 14),
              SizedBox(width: 4),
              Text('Answered', style: TextStyle(
                color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600,
              )),
            ],
          ),
        )
      else if (!widget.isMe) // Only show "Waiting" for teacher's view
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.2)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, color: Colors.orange, size: 14),
              SizedBox(width: 4),
              Text('Waiting...', style: TextStyle(
                color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
    ],
  ),
),
          
          // Question
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              widget.question,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
          ),
          
          // Options
          ...widget.options.asMap().entries.map((entry) {
            final index = entry.key;
            final option = entry.value;
            final isSelected = _selected == index;
            final showResult = _submitted && widget.correctAnswer != null;
            final isCorrect = showResult && index == widget.correctAnswer;
            final isWrong = showResult && isSelected && !isCorrect;
            
            Color bgColor = Colors.grey.shade50;
            if (showResult && isCorrect) bgColor = Colors.green.withOpacity(0.15);
            if (isWrong) bgColor = Colors.red.withOpacity(0.1);
            if (isSelected && !showResult) bgColor = Colors.indigo.withOpacity(0.1);
            
            return GestureDetector(
              onTap: _submitted ? null : () => setState(() => _selected = index),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected 
                        ? (showResult && isCorrect ? Colors.green : showResult && isWrong ? Colors.red : Colors.indigo)
                        : Colors.grey.shade200,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? Colors.indigo : Colors.grey.shade400, width: 2),
                        color: isSelected ? Colors.indigo : Colors.transparent,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 14)
                          : Text('${String.fromCharCode(65 + index)}', 
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(option, style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      )),
                    ),
                    if (showResult && isCorrect)
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    if (isWrong)
                      const Icon(Icons.cancel, color: Colors.red, size: 20),
                  ],
                ),
              ),
            );
          }),
          
          // Submit button
          if (!_submitted && !widget.isMe)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected != null
                      ? () {
                          setState(() => _submitted = true);
                          widget.onAnswer?.call(_selected!);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Submit Answer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          
          // Result
          if (_submitted)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  Icon(
                    _selected == widget.correctAnswer ? Icons.emoji_events : Icons.info_outline,
                    color: _selected == widget.correctAnswer ? Colors.amber : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _selected == widget.correctAnswer ? 'Correct! 🎉' : 'Wrong answer',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _selected == widget.correctAnswer ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _QuizCreator extends StatefulWidget {
  final void Function(List<Map<String, dynamic>> questions) onSave;

  const _QuizCreator({required this.onSave});

  @override
  State<_QuizCreator> createState() => _QuizCreatorState();
}

class _QuizCreatorState extends State<_QuizCreator> {
  final List<_QuestionData> _questions = [];
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _addQuestion() {
  setState(() {
    _questions.add(_QuestionData());
  });
  
  // ✅ Use a post-frame callback to change page after build
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      setState(() {
        _currentPage = _questions.length - 1;
      });
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  });
}

  void _removeQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
      if (_currentPage >= _questions.length) {
        _currentPage = _questions.length - 1;
      }
    });
  }

  void _saveAll() {
    final validQuestions = _questions
        .where((q) => q.questionController.text.trim().isNotEmpty && 
                     q.options.where((o) => o.text.trim().isNotEmpty).length >= 2)
        .map((q) => {
              'question': q.questionController.text.trim(),
              'options': q.options
                  .where((o) => o.text.trim().isNotEmpty)
                  .map((o) => o.text.trim())
                  .toList(),
              'correct': q.correctAnswer,
            })
        .toList();

    if (validQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one complete question')),
      );
      return;
    }

    widget.onSave(validQuestions);
  }

  @override
  void dispose() {
    for (final q in _questions) {
      q.questionController.dispose();
      for (final o in q.options) {
        o.dispose();
      }
    }
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.quiz_rounded, color: Colors.indigo, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Create Quiz', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ),
              // Add question button
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add, color: Colors.indigo, size: 20),
                ),
                onPressed: _addQuestion,
                tooltip: 'Add Question',
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Question counter
          if (_questions.isNotEmpty)
            Row(
              children: [
                Text('Question ${_currentPage + 1} of ${_questions.length}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
                const Spacer(),
                if (_questions.length > 1)
                  TextButton(
                    onPressed: () => _removeQuestion(_currentPage),
                    child: const Text('Remove', style: TextStyle(color: Colors.red, fontSize: 13)),
                  ),
              ],
            ),

          const SizedBox(height: 12),

          // Questions or empty state
          Expanded(
            child: _questions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text('No questions yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _addQuestion,
                          icon: const Icon(Icons.add),
                          label: const Text('Add First Question'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  )
                : PageView.builder(
  controller: _pageController,
  onPageChanged: (page) => setState(() => _currentPage = page),
  itemCount: _questions.length,
  itemBuilder: (context, index) {
    return _buildQuestionEditor(_questions[index], index);
  },
),
          ),

          // Bottom bar
          if (_questions.isNotEmpty) ...[
            const Divider(),
            Row(
              children: [
                // Navigation dots
                if (_questions.length > 1)
                  Row(
                    children: List.generate(_questions.length, (i) {
                      return Container(
                        width: 8, height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _currentPage ? Colors.indigo : Colors.grey.shade300,
                        ),
                      );
                    }),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _saveAll,
                  icon: const Icon(Icons.send, size: 18),
                  label: Text('Send ${_questions.length} question${_questions.length > 1 ? 's' : ''}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionEditor(_QuestionData questionData, int index) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question field
          TextField(
            controller: questionData.questionController,
            decoration: InputDecoration(
              labelText: 'Question ${index + 1}',
              hintText: 'Enter your question...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            maxLines: 2,
            minLines: 1,
          ),
          const SizedBox(height: 16),

          // Options
          const Text('Options (tap ✓ for correct answer)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),

          ...List.generate(4, (i) {
            return StatefulBuilder(
              builder: (context, setOptionState) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => questionData.correctAnswer = i),
                        child: Container(
                          width: 30, height: 30,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: questionData.correctAnswer == i ? Colors.green : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check,
                            color: questionData.correctAnswer == i ? Colors.white : Colors.grey,
                            size: 16,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: questionData.options[i],
                          decoration: InputDecoration(
                            hintText: 'Option ${i + 1}',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          }),
        ],
      ),
    );
  }
}

class _QuestionData {
  final TextEditingController questionController = TextEditingController();
  final List<TextEditingController> options = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  int correctAnswer = 0;
}

// ===== CALLING DIALOG =====
class _CallingDialog extends StatefulWidget {
  final String callerName;
  
  final VoidCallback onCancel;
  

  const _CallingDialog({
    required this.callerName,
    
    required this.onCancel,
    
  });

  @override
  State<_CallingDialog> createState() => _CallingDialogState();
}

class _CallingDialogState extends State<_CallingDialog> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF075E54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            // Pulsing avatar
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 100 + (_pulseController.value * 20),
                  height: 100 + (_pulseController.value * 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2 + (_pulseController.value * 0.3)),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      child: Text(
                        widget.callerName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Calling ${widget.callerName}...',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Waiting for answer',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 30),
            // Cancel button
            GestureDetector(
              onTap: widget.onCancel,
              child: Container(
                width: 60, height: 60,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ===== INCOMING CALL DIALOG =====
class _IncomingCallDialog extends StatelessWidget {
  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingCallDialog({
    required this.callerName,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF075E54),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 45,
              backgroundColor: Colors.white.withOpacity(0.3),
              child: Text(
                callerName[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '$callerName is calling...',
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Video call',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 30),
            // Accept / Decline buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline
                GestureDetector(
                  onTap: onDecline,
                  child: Column(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 6),
                      const Text('Decline', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                // Accept
                GestureDetector(
                  onTap: onAccept,
                  child: Column(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.call, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 6),
                      const Text('Accept', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}