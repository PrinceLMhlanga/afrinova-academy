// lib/features/live/live_classroom_screen.dart
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'dart:convert';  // ✅ Add this for jsonDecode
import 'package:flutter/services.dart';
import '../live/whiteboard/whiteboard_canvas.dart';
import 'dart:async';

class LiveClassroomScreen extends StatefulWidget {
  final String roomName;
  final String lessonId;
  final bool isTeacher;

  const LiveClassroomScreen({
    super.key,
    required this.roomName,
    required this.lessonId,
    required this.isTeacher,
  });

  @override
  State<LiveClassroomScreen> createState() => _LiveClassroomScreenState();
}

class _LiveClassroomScreenState extends State<LiveClassroomScreen> {
  final AuthService _authService = AuthService();
  late final Room _room;
  late final EventsListener<RoomEvent> _listener;
  bool _isLoading = true;

  Participant? _mainFocusParticipant;
  List<Participant> _allParticipants = [];
  bool _isMuted = false;
  bool _isVideoOff = false;
  bool _isChatOpen = false;
  bool _showParticipants = false;
  final TextEditingController _chatController = TextEditingController();
  final List<_ChatMessage> _messages = [];
  // ✅ Add this: Map to store participant names
  final Map<String, String> _participantNames = {};
  String? _myName;

  bool _showWhiteboard = false;
  bool _isTeacherDrawing = false;
  Timer? _drawingTimer;

  // Add this import at the top


// Add these state variables
bool _isFullScreen = false;
bool _showControls = true;
late Timer _controlsTimer;

  @override
  void initState() {
    super.initState();
    _controlsTimer = Timer(const Duration(seconds: 0), () {}); // Dummy timer
    _setupClassroom();
  }

  Future<void> _setupClassroom() async {
    _room = Room();
    _listener = _room.createListener();

    _listener.on<RoomEvent>((event) {
      if (mounted) {
        if (event is ParticipantConnectedEvent ||
            event is ParticipantDisconnectedEvent ||
            event is TrackMutedEvent ||
            event is TrackUnmutedEvent ||
            event is TrackPublishedEvent ||
            event is TrackUnpublishedEvent ||
            event is TrackSubscribedEvent ||
            event is TrackUnsubscribedEvent ||
            event is RoomDisconnectedEvent) {
          _updateParticipants();
        }
        
        // ✅ Listen for new participants to get their metadata
        if (event is ParticipantConnectedEvent) {
          _onParticipantConnected(event.participant);
        }
      }
    });

    try {
      final profile = await _authService.getProfile();
      final userId = _authService.currentUserId;
      final userName = profile?['display_name'] ?? profile?['full_name'] ?? (widget.isTeacher ? 'Teacher' : 'Student');
      
      _myName = userName;
      _participantNames[userId ?? 'unknown'] = userName;

      // ✅ Get all participants' names from Supabase
      await _loadParticipantNames();

      final tokenResponse = await Supabase.instance.client.functions.invoke(
        'generate-livekit-token',
        body: {
          'roomName': widget.roomName,
          'participantName': userName,
          'participantId': userId ?? 'unknown',
        },
      );

      final token = tokenResponse.data['token'] as String;

      final settings = await Supabase.instance.client
          .from('platform_settings')
          .select('value')
          .eq('key', 'livekit_ws_url')
          .single();

      final serverUrl = settings['value'] as String;

      await _room.connect(serverUrl, token);
      
      // ✅ Set metadata with name so other participants can see it
      await _room.localParticipant?.setMetadata(jsonEncode({
        'name': userName,
        'role': widget.isTeacher ? 'teacher' : 'student',
        'userId': userId ?? 'unknown',
      }));
      
      await _room.localParticipant?.setCameraEnabled(true);
      await _room.localParticipant?.setMicrophoneEnabled(true);

      _updateParticipants();
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Classroom connection error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect: $e'), backgroundColor: Colors.red),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // ✅ Add this method to load participant names
  Future<void> _loadParticipantNames() async {
  try {
    // 1. Get the lesson info
    final lesson = await Supabase.instance.client
        .from('live_lessons')
        .select('teacher_id, profiles!teacher_id(display_name, full_name)')
        .eq('id', widget.lessonId)
        .single();

    // Add teacher name
    if (lesson['teacher_id'] != null) {
      final profiles = lesson['profiles'] as Map<String, dynamic>?;
      final teacherName = profiles?['display_name'] ?? profiles?['full_name'] ?? 'Teacher';
      _participantNames[lesson['teacher_id'] as String] = teacherName;
    }

    // 2. For students, get enrolled students for this teacher+subject combo
    final lessonSubject = await Supabase.instance.client
        .from('live_lessons')
        .select('teacher_id, subject_id')
        .eq('id', widget.lessonId)
        .single();

    if (lessonSubject != null) {
      final teacherId = lessonSubject['teacher_id'] as String;
      final subjectId = lessonSubject['subject_id'] as String;

      // Get enrolled students
      final enrollments = await Supabase.instance.client
          .from('enrollments')
          .select('student_id, profiles!student_id(display_name, full_name)')
          .eq('teacher_id', teacherId)
          .eq('subject_id', subjectId)
          .inFilter('status', ['approved', 'paid']);

      for (final enrollment in enrollments) {
        final studentId = enrollment['student_id'] as String;
        final profiles = enrollment['profiles'] as Map<String, dynamic>?;
        final studentName = profiles?['display_name'] ?? profiles?['full_name'] ?? 'Student';
        _participantNames[studentId] = studentName;
      }
    }

    debugPrint('✅ Loaded participant names: $_participantNames');
  } catch (e) {
    debugPrint('❌ Error loading participant names: $e');
  }
}
  void _toggleFullScreen() {
  setState(() {
    _isFullScreen = !_isFullScreen;
    _showControls = true;
  });
  
  if (_isFullScreen) {
    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Allow all orientations on fullscreen
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    
    // Auto-hide controls after 3 seconds
    _startControlsTimer();
  } else {
    // Restore normal UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _controlsTimer.cancel();
  }
}

void _onTeacherDrawingStart() {
  if (!widget.isTeacher) return;
  
  setState(() {
    _isTeacherDrawing = true;
    _showWhiteboard = true;  // Auto-show whiteboard
  });
  
  // Cancel any existing timer
  _drawingTimer?.cancel();
}

void _onTeacherDrawingEnd() {
  if (!widget.isTeacher) return;
  
  // Wait 2 seconds after teacher stops drawing before switching back
  _drawingTimer?.cancel();
  _drawingTimer = Timer(const Duration(seconds: 2), () {
    if (mounted) {
      setState(() {
        _isTeacherDrawing = false;
        // Don't auto-hide whiteboard, let teacher control that
      });
    }
  });
}

// For students: Listen for whiteboard data to auto-switch
void _setupWhiteboardListener() {
  // Listen for data channel messages
  _room.addListener(() {
    // When student receives whiteboard data, auto-show whiteboard
    if (!widget.isTeacher && !_showWhiteboard) {
      // Check if there's whiteboard activity
      // This would be triggered by your LiveKit data channel
    }
  });
}

void _startControlsTimer() {
  _controlsTimer.cancel();
  _controlsTimer = Timer(const Duration(seconds: 3), () {
    if (mounted && _isFullScreen) {
      setState(() => _showControls = false);
    }
  });
}

void _onScreenTap() {
  if (_isFullScreen) {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startControlsTimer();
    }
  }
}

  void _onParticipantConnected(Participant participant) {
  // Try to get metadata from the new participant
  final metadata = participant.metadata;
  if (metadata != null && metadata.isNotEmpty) {
    try {
      final meta = jsonDecode(metadata);
      if (meta['name'] != null && meta['userId'] != null) {
        _participantNames[meta['userId']] = meta['name'];
        setState(() {}); // Refresh UI to show names
      }
    } catch (e) {
      debugPrint('Error parsing participant metadata: $e');
    }
  }
}

 String _getParticipantName(Participant participant) {
  final identity = participant.identity ?? '';
  
  // Check our name map
  if (_participantNames.containsKey(identity) && _participantNames[identity] != 'Teacher' && _participantNames[identity] != 'Student') {
    return _participantNames[identity]!;
  }
  
  // Check if it's the local participant
  if (_myName != null && participant == _room.localParticipant) {
    return _myName!;
  }
  
  // Try metadata
  final metadata = participant.metadata;
  if (metadata != null && metadata.isNotEmpty) {
    try {
      final meta = jsonDecode(metadata);
      if (meta['name'] != null) {
        _participantNames[identity] = meta['name'];
        return meta['name'];
      }
    } catch (_) {}
  }
  
  // Fallback: Use the identity if it looks like a name, otherwise role
  if (!identity.contains('-') && identity.length < 30) {
    return identity;
  }
  
  return widget.isTeacher ? 'Student' : 'Teacher';
}

// ✅ Helper to get role from metadata
String _getParticipantRole(Participant participant) {
  final metadata = participant.metadata;
  if (metadata != null && metadata.isNotEmpty) {
    try {
      final meta = jsonDecode(metadata);
      return meta['role'] ?? (widget.isTeacher ? 'student' : 'teacher');
    } catch (_) {}
  }
  return widget.isTeacher ? 'student' : 'teacher';
}
  void _updateParticipants() {
  if (!mounted) return;
  setState(() {
    final localParticipant = _room.localParticipant;
    _allParticipants = [
      if (localParticipant != null) localParticipant,
      ..._room.remoteParticipants.values,
    ];

    // ✅ Extract metadata from all participants
    for (final participant in _allParticipants) {
      _extractParticipantName(participant);
    }

    if (_allParticipants.isEmpty) {
      _mainFocusParticipant = null;
      return;
    }

    // Priority 1: Someone ELSE sharing screen (remote participant)
    final remoteScreenSharer = _allParticipants.firstWhere(
      (p) => p != localParticipant && p.isScreenShareEnabled(),
      orElse: () => _allParticipants.first,
    );
    
    if (remoteScreenSharer != localParticipant && remoteScreenSharer.isScreenShareEnabled()) {
      _mainFocusParticipant = remoteScreenSharer;
    } 
    // Priority 2: Teacher (if no screen share)
    else {
      _mainFocusParticipant = _allParticipants.firstWhere(
        (p) => (p.identity ?? '').toLowerCase().contains('teacher'),
        orElse: () => _allParticipants.first,
      );
    }
  });
}

void _extractParticipantName(Participant participant) {
  final identity = participant.identity ?? '';
  
  // Skip if we already have this participant's name
  if (_participantNames.containsKey(identity)) return;
  
  // Try to get from metadata first
  final metadata = participant.metadata;
  if (metadata != null && metadata.isNotEmpty) {
    try {
      final meta = jsonDecode(metadata);
      if (meta['name'] != null) {
        _participantNames[identity] = meta['name'];
        return;
      }
    } catch (_) {}
  }
  
  // If still unknown, assign a default name based on role
  final isTeacherParticipant = identity == _room.localParticipant?.identity 
      ? widget.isTeacher 
      : !widget.isTeacher;
  
  _participantNames[identity] = isTeacherParticipant ? 'Teacher' : 'Student';
}
  Future<void> _endLesson() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Lesson?'),
        content: const Text('This will end the lesson for all participants.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('End Lesson'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client
          .from('live_lessons')
          .update({'status': 'ended', 'ended_at': DateTime.now().toIso8601String()})
          .eq('id', widget.lessonId);
      _room.disconnect();
      _room.dispose();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _leaveLesson() async {
    _room.disconnect();
    _room.dispose();
    if (mounted) Navigator.pop(context);
  }

  void _sendMessage() {
  if (_chatController.text.trim().isEmpty) return;
  
  final senderName = _myName ?? 'You';
  
  _messages.add(_ChatMessage(
    sender: senderName,
    message: _chatController.text.trim(),
    isMe: true,
  ));
  _chatController.clear();
  setState(() {});
}

  @override
void dispose() {
  _chatController.dispose();
  _listener.dispose();
  _controlsTimer.cancel();
  _room.disconnect();
  _room.dispose();
  // Restore normal orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  super.dispose();
}
  @override
Widget build(BuildContext context) {
  if (_isLoading) {
    return const Scaffold(
      backgroundColor: Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 16),
            Text('Entering classroom...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  return GestureDetector(
    onTap: _onScreenTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: _isFullScreen && !_showControls
            ? null
            : _buildAppBar() as PreferredSizeWidget?,
        body: SafeArea(
          child: Stack(  // ✅ Everything must be inside this Stack
            children: [
              // Main column content
              Column(
                children: [
                  // Main content area
                  Expanded(
                    flex: _isFullScreen ? 1 : 3,
                    child: _buildMainContentArea(),
                  ),

                  // Filmstrip
                  if (!_isFullScreen && _allParticipants.length > 1)
                    _buildFilmstrip(),

                  // Control bar
                  if (!_isFullScreen || _showControls)
                    _buildControlBar(),
                ],
              ),

              // ✅ PiP video - now correctly inside Stack
              if (_showWhiteboard && _mainFocusParticipant != null)
                Positioned(
                  bottom: widget.isTeacher ? 140 : 20,
                  right: 20,
                  child: _buildPiPVideo(),
                ),

              // Chat panel
              if (_isChatOpen && (!_isFullScreen || _showControls))
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: _isFullScreen ? 100 : 160,
                  width: 300,
                  child: _buildChatPanel(),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildPiPVideo() {
  return GestureDetector(
    onTap: () {
      setState(() => _showWhiteboard = false);
    },
    child: Container(
      width: 160,
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            _ParticipantVideoTile(
              participant: _mainFocusParticipant!,
              isMain: false,
              localParticipant: _room.localParticipant,
              getName: _getParticipantName,
            ),
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getParticipantName(_mainFocusParticipant!),
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => setState(() => _showWhiteboard = false),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildMainContentArea() {
  final isMobile = MediaQuery.of(context).size.width < 600;
  
  if (_showWhiteboard) {
    return Padding(
      padding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(8),  // ✅ No padding on mobile
      child: ClipRRect(
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(16),  // ✅ No border on mobile
        child: WhiteboardCanvas(
          room: _room,
          isTeacher: widget.isTeacher,
          userName: _myName ?? 'Teacher',
          onDrawingStart: _onTeacherDrawingStart,
          onDrawingEnd: _onTeacherDrawingEnd,
        ),
      ),
    );
  }
  
  return _isFullScreen && !_showControls
      ? _buildFullScreenContent()
      : _buildMainContent();
}


PreferredSizeWidget _buildAppBar() {
  return AppBar(
    backgroundColor: const Color(0xFF1A1A1A),
    elevation: 0,
    title: Text(
      widget.roomName, 
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
    ),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      onPressed: widget.isTeacher ? _endLesson : _leaveLesson,
    ),
    actions: [
      // Fullscreen toggle button
      IconButton(
        icon: Icon(
          _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
          color: Colors.white70,
        ),
        onPressed: _toggleFullScreen,
        tooltip: _isFullScreen ? 'Exit Fullscreen' : 'Fullscreen',
      ),
      // Name badge
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: widget.isTeacher ? Colors.redAccent.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            _myName ?? (widget.isTeacher ? 'Teacher' : 'Student'),
            style: TextStyle(
              color: widget.isTeacher ? Colors.redAccent : Colors.blueAccent,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
      // Participant count
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8, 
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${_allParticipants.length}', 
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildFullScreenContent() {
  return ClipRRect(
    borderRadius: _showControls ? BorderRadius.circular(16) : BorderRadius.zero,
    child: Container(
      color: const Color(0xFF252525),
      child: Stack(
        children: [
          if (_mainFocusParticipant != null)
            _ParticipantVideoTile(
              participant: _mainFocusParticipant!,
              isMain: true,
              localParticipant: _room.localParticipant,
              getName: _getParticipantName,
            ),
          _buildIdentityOverlay(_mainFocusParticipant, isMain: true),
        ],
      ),
    ),
  );
}

Widget _buildMainContent() {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Container(
      color: const Color(0xFF252525),
      child: Stack(
        children: [
          if (_mainFocusParticipant != null)
            _ParticipantVideoTile(
              participant: _mainFocusParticipant!,
              isMain: true,
              localParticipant: _room.localParticipant,
              getName: _getParticipantName,
            ),
          _buildIdentityOverlay(_mainFocusParticipant, isMain: true),
        ],
      ),
    ),
  );
}

Widget _buildFilmstrip() {
  return SizedBox(
    height: 120,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _allParticipants.where((p) => p != _mainFocusParticipant).length,
      itemBuilder: (context, index) {
        final participant = _allParticipants.where((p) => p != _mainFocusParticipant).toList()[index];
        return GestureDetector(
          onTap: () => setState(() => _mainFocusParticipant = participant),
          child: Container(
            width: 140,
            margin: const EdgeInsets.only(right: 8, bottom: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: participant == _mainFocusParticipant ? Colors.blueAccent : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: const Color(0xFF1E1E1E),
                child: Stack(
                  children: [
                    _ParticipantVideoTile(
                      participant: participant,
                      isMain: false,
                      localParticipant: _room.localParticipant,
                      getName: _getParticipantName,
                    ),
                    _buildIdentityOverlay(participant, isMain: false),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget _buildControlBar() {
  return AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    decoration: const BoxDecoration(
      color: Color(0xFF1A1A1A),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24), 
        topRight: Radius.circular(24),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: _isMuted ? Icons.mic_off : Icons.mic,
          color: _isMuted ? Colors.redAccent : const Color(0xFF2D2D2D),
          onPressed: () async {
            setState(() => _isMuted = !_isMuted);
            await _room.localParticipant?.setMicrophoneEnabled(!_isMuted);
          },
        ),
        _buildControlButton(
          icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
          color: _isVideoOff ? Colors.redAccent : const Color(0xFF2D2D2D),
          onPressed: () async {
            setState(() => _isVideoOff = !_isVideoOff);
            await _room.localParticipant?.setCameraEnabled(!_isVideoOff);
          },
        ),
        if (widget.isTeacher)
          _buildControlButton(
            icon: Icons.screen_share,
            color: Colors.blueAccent,
            onPressed: () async {
              final enabled = _room.localParticipant?.isScreenShareEnabled() ?? false;
              await _room.localParticipant?.setScreenShareEnabled(!enabled);
              setState(() {});
            },
          ),
          _buildControlButton(
  icon: _showWhiteboard ? Icons.videocam : Icons.draw,
  color: _showWhiteboard ? Colors.blueAccent : const Color(0xFF2D2D2D),
  onPressed: () {
    setState(() {
      _showWhiteboard = !_showWhiteboard;
      // If hiding whiteboard, reset drawing state
      if (!_showWhiteboard) {
        _isTeacherDrawing = false;
      }
    });
  },
),
        _buildControlButton(
          icon: Icons.chat_bubble_outline,
          color: _isChatOpen ? Colors.blueAccent : const Color(0xFF2D2D2D),
          onPressed: () => setState(() {
            _isChatOpen = !_isChatOpen;
            _showParticipants = false;
          }),
        ),
        // ✅ Fullscreen button in control bar too
        _buildControlButton(
          icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
          color: _isFullScreen ? Colors.blueAccent : const Color(0xFF2D2D2D),
          onPressed: _toggleFullScreen,
        ),
        _buildControlButton(
          icon: Icons.call_end,
          color: Colors.red,
          iconColor: Colors.white,
          onPressed: widget.isTeacher ? _endLesson : _leaveLesson,
        ),
      ],
    ),
  );
}

  

  Widget _buildIdentityOverlay(Participant? participant, {required bool isMain}) {
  final name = participant != null ? _getParticipantName(participant) : 'Connecting...';
  final isMicMuted = !(participant?.isMicrophoneEnabled() ?? true);

  return Positioned(
    bottom: 8, left: 8, right: 8,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            name, 
            style: TextStyle(
              color: Colors.white, 
              fontSize: isMain ? 12 : 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isMicMuted)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.8), 
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic_off, color: Colors.white, size: 12),
          ),
      ],
    ),
  );
}
  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    Color iconColor = Colors.white70,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        shape: const CircleBorder(),
        padding: const EdgeInsets.all(16),
        backgroundColor: color,
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Icon(icon, color: iconColor, size: 24),
    );
  }

  Widget _buildChatPanel() {
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black,
            child: const Row(
              children: [
                Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Chat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(msg.sender, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: msg.isMe ? Colors.blue.shade700 : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(msg.message, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true, fillColor: Colors.grey.shade800,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ParticipantVideoTile extends StatefulWidget {
  final Participant participant;
  final bool isMain;
  final Participant? localParticipant;
  final String Function(Participant) getName;  // ✅ Add this

  const _ParticipantVideoTile({
    required this.participant,
    this.isMain = false,
    this.localParticipant,
    required this.getName,  // ✅ Add this
  });

  @override
  State<_ParticipantVideoTile> createState() => _ParticipantVideoTileState();
}

class _ParticipantVideoTileState extends State<_ParticipantVideoTile> {
  late final EventsListener<ParticipantEvent> _listener;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _listener = widget.participant.createListener();
    
    _listener.on<TrackSubscribedEvent>((_) {
      if (!_disposed && mounted) setState(() {});
    });
    
    _listener.on<TrackUnsubscribedEvent>((_) {
      if (!_disposed && mounted) setState(() {});
    });
    
    _listener.on<TrackMutedEvent>((_) {
      if (!_disposed && mounted) setState(() {});
    });
    
    _listener.on<TrackUnmutedEvent>((_) {
      if (!_disposed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildVideoContent(widget.participant, widget.isMain);
  }

  Widget _buildVideoContent(Participant participant, bool isMain) {
    final isLocal = participant == widget.localParticipant;
    
    final videoPubs = participant.videoTrackPublications;
    
    if (videoPubs.isEmpty) {
      return _buildAvatar(participant, isMain);
    }

    if (isLocal) {
      try {
        final cameraPub = videoPubs.cast<TrackPublication>().firstWhere(
          (p) => p.source == TrackSource.camera,
        );
        
        if (cameraPub.track != null && cameraPub.subscribed) {
          return VideoTrackRenderer(cameraPub.track as VideoTrack);
        }
      } catch (_) {}
      
      return _buildAvatar(participant, isMain);
    }

    try {
      final screenPub = videoPubs.cast<TrackPublication>().firstWhere(
        (p) => p.source == TrackSource.screenShareVideo,
      );
      
      if (screenPub.track != null && screenPub.subscribed) {
        return VideoTrackRenderer(screenPub.track as VideoTrack);
      }
    } catch (_) {}

    try {
      final cameraPub = videoPubs.cast<TrackPublication>().firstWhere(
        (p) => p.source == TrackSource.camera,
      );
      
      if (cameraPub.track != null && cameraPub.subscribed) {
        return VideoTrackRenderer(cameraPub.track as VideoTrack);
      }
    } catch (_) {}

    return _buildAvatar(participant, isMain);
  }

  Widget _buildAvatar(Participant participant, bool isMain) {
    final name = widget.getName(participant);  // ✅ Use the passed function
    
    return Center(
      child: CircleAvatar(
        radius: isMain ? 50 : 20,
        backgroundColor: Colors.blueAccent.withOpacity(0.1),
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.blueAccent,
            fontWeight: FontWeight.bold,
            fontSize: isMain ? 28 : 14,
          ),
        ),
      ),
    );
  }
}

class _ChatMessage {
  final String sender;
  final String message;
  final bool isMe;
  _ChatMessage({required this.sender, required this.message, required this.isMe});
}