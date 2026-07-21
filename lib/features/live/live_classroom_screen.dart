// lib/features/live/live_classroom_screen.dart
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth_service.dart';
import 'dart:convert';  // ✅ Add this for jsonDecode
import 'package:flutter/services.dart';
import '../live/whiteboard/whiteboard_canvas.dart';
import 'dart:async';
import 'dart:typed_data';
import '../live/poll_widgets.dart';
import '../live/poll_models.dart';


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

  // Add this in your state variables
final GlobalKey<WhiteboardCanvasState> _whiteboardKey = GlobalKey();
final GlobalKey _videoContentKey = GlobalKey();  // ✅ Add this
final GlobalKey _filmstripKey = GlobalKey();

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

  // Hand raise state
bool _handRaised = false;
final List<String> _raisedHands = []; // List of participant identities
bool _showRaisedHands = false;
final Set<String> _mutedParticipants = {};

// Add these state variables
String? _notificationMessage;
Timer? _notificationTimer;
Color _notificationColor = Colors.blueAccent;

// Add this state variable
final Map<String, String> _handRaiseReasons = {};


// Add these state variables
bool _isFullScreen = false;
bool _showControls = true;
late Timer _controlsTimer;

// Poll state
Poll? _activePoll;
bool _showPollPanel = false;
bool _showCreatePoll = false;


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
      
      await _room.localParticipant?.setMetadata(jsonEncode({
        'name': userName,
        'role': widget.isTeacher ? 'teacher' : 'student',
        'userId': userId ?? 'unknown',
      }));
      
      await _room.localParticipant?.setCameraEnabled(true);
      if (widget.isTeacher) {
  await _room.localParticipant?.setMicrophoneEnabled(true);
} else {
  await _room.localParticipant?.setMicrophoneEnabled(false);
  setState(() => _isMuted = true);
}

      // ✅ SETUP WHITEBOARD LISTENER FOR STUDENTS
      _setupDataListener();

      _updateParticipants();
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Classroom connection error: $e');
      _showNotification('Failed to connect: $e', backgroundColor: Colors.red);
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




// Teacher requests a student to mute
void _requestMute(String participantId, String participantName) {
  final data = utf8.encode(jsonEncode({
    'type': 'mute_request',
    'participantId': participantId,
    'requestedBy': _myName ?? 'Teacher',
  }));
  
  _room.localParticipant?.publishData(data, reliable: true);
  _showNotification('Mute request sent to $participantName', backgroundColor: Colors.orange);
}

// Request all to mute
void _requestMuteAll() {
  final data = utf8.encode(jsonEncode({
    'type': 'mute_all_request',
    'requestedBy': _myName ?? 'Teacher',
  }));
  
  _room.localParticipant?.publishData(data, reliable: true);
  _showNotification('Mute all requested 🔇', backgroundColor: Colors.orange);
}

void _openCreatePoll() {
  showDialog(
    context: context,
    builder: (ctx) => CreatePollDialog(
      onCreate: (question, options) {
        _createPoll(question, options);
      },
    ),
  );
}

// Teacher creates a poll
void _createPoll(String question, List<String> options) {
  final poll = Poll(
    id: DateTime.now().millisecondsSinceEpoch.toString(),
    question: question,
    options: options,
    createdAt: DateTime.now(),
    createdBy: _myName ?? 'Teacher',
  );
  
  setState(() {
    _activePoll = poll;
    _showPollPanel = true;  // ✅ Show for teacher too
  });
  
  // Send poll to all students immediately
  _sendPollUpdate(poll);
}

// Send poll data to participants
void _sendPollUpdate(Poll poll) {
  final message = jsonEncode({
    'type': 'poll_update',
    'poll': poll.toJson(),
  });
  
  debugPrint('📤 Sending poll update: $message');
  
  final data = utf8.encode(message);
  
  _room.localParticipant?.publishData(data, reliable: true).then((_) {
    debugPrint('✅ Poll sent successfully');
  }).catchError((e) {
    debugPrint('❌ Failed to send poll: $e');
  });
}

// Student votes
void _vote(int optionIndex) {
  if (_activePoll == null || !_activePoll!.isActive) return;
  
  final participantId = _room.localParticipant?.identity ?? '';
  
  // Check if already voted
  if (_activePoll!.participantVotes.containsKey(participantId)) {
    _showNotification('You already voted!', backgroundColor: Colors.orange);
    return;
  }
  
  setState(() {
    _activePoll!.participantVotes[participantId] = optionIndex;
    _activePoll!.votes[optionIndex.toString()] = 
        (_activePoll!.votes[optionIndex.toString()] ?? 0) + 1;
  });
  
  // Send vote to teacher
  _sendVote(optionIndex);
}

void _sendVote(int optionIndex) {
  final data = utf8.encode(jsonEncode({
    'type': 'poll_vote',
    'optionIndex': optionIndex,
    'participantId': _room.localParticipant?.identity ?? '',
  }));
  
  _room.localParticipant?.publishData(data, reliable: true);
}

void _closePoll() {
  if (_activePoll == null) return;
  
  // ✅ Mark poll as inactive
  setState(() {
    _activePoll!.isActive = false;
    _showPollPanel = false;
  });
  
  // Send final update
  _sendPollUpdate(_activePoll!);
  
  // Send explicit close
  final data = utf8.encode(jsonEncode({
    'type': 'poll_closed',
  }));
  _room.localParticipant?.publishData(data, reliable: true);
  
  // ✅ Reset poll after a delay so the button goes back to "create"
  Future.delayed(const Duration(seconds: 2), () {
    if (mounted) {
      setState(() {
        _activePoll = null; // Clear the poll so button shows create icon
      });
    }
  });
}

// Handle incoming poll data
void _handlePollMessage(Map<String, dynamic> message) {
  switch (message['type']) {
    case 'poll_update':
      final poll = Poll.fromJson(message['poll']);
      setState(() {
        _activePoll = poll;
        // ✅ Auto-show poll panel for everyone
        _showPollPanel = true;
      });
      break;
      
    case 'poll_vote':
      if (widget.isTeacher && _activePoll != null) {
        final optionIndex = message['optionIndex'] as int;
        final participantId = message['participantId'] as String;
        
        setState(() {
          _activePoll!.participantVotes[participantId] = optionIndex;
          _activePoll!.votes[optionIndex.toString()] = 
              (_activePoll!.votes[optionIndex.toString()] ?? 0) + 1;
        });
      }
      break;
  }
}




void _showNotification(String message, {Color backgroundColor = Colors.blueAccent}) {
  setState(() {
    _notificationMessage = message;
    _notificationColor = backgroundColor; // ✅ Add this state variable
  });
  
  _notificationTimer?.cancel();
  _notificationTimer = Timer(const Duration(seconds: 3), () {
    if (mounted) {
      setState(() {
        _notificationMessage = null;
      });
    }
  });
}

// Toggle hand raise (for students)
void _toggleHandRaise() {
  if (_handRaised) {
    // Lower hand immediately
    setState(() {
      _handRaised = false;
    });
    
    final data = utf8.encode(jsonEncode({
      'type': 'hand_raise',
      'action': 'lower',
      'participantId': _room.localParticipant?.identity ?? '',
      'participantName': _myName ?? 'Unknown',
    }));
    
    _room.localParticipant?.publishData(data, reliable: true);
  } else {
    // ✅ Show dialog to ask for reason
    _showRaiseHandDialog();
  }
}

void _showRaiseHandDialog() {
  final reasonController = TextEditingController();
  
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.pan_tool, color: Colors.amber, size: 24),
          const SizedBox(width: 8),
          const Text('Raise Hand', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'What would you like to say?',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonController,
            autofocus: true,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'E.g., I have a question about...',
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 8),
          // Quick reasons
          Wrap(
            spacing: 6,
            children: [
              _buildQuickReasonChip('Question', reasonController),
              _buildQuickReasonChip('Answer', reasonController),
              _buildQuickReasonChip('Technical issue', reasonController),
              _buildQuickReasonChip('Break', reasonController),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            _sendHandRaise(reasonController.text.trim());
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.amber,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Raise Hand ✋'),
        ),
      ],
    ),
  );
}

Widget _buildQuickReasonChip(String label, TextEditingController controller) {
  return GestureDetector(
    onTap: () => controller.text = label,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.amber),
      ),
    ),
  );
}

void _sendHandRaise(String reason) {
  setState(() {
    _handRaised = true;
  });
  
  final data = utf8.encode(jsonEncode({
    'type': 'hand_raise',
    'action': 'raise',
    'participantId': _room.localParticipant?.identity ?? '',
    'participantName': _myName ?? 'Unknown',
    'reason': reason.isNotEmpty ? reason : null, // ✅ Include reason
  }));
  
  _room.localParticipant?.publishData(data, reliable: true);
}

// Handle incoming hand raise data
void _handleHandRaise(Map<String, dynamic> message) {
  final participantId = message['participantId'] as String? ?? '';
  final participantName = message['participantName'] as String? ?? 'Unknown';
  final reason = message['reason'] as String?;
  
  if (message['action'] == 'raise') {
    if (!_raisedHands.contains(participantId)) {
      setState(() {
        _raisedHands.add(participantId);
        _participantNames[participantId] = participantName;
        // ✅ Store the reason
        if (reason != null && reason.isNotEmpty) {
          _handRaiseReasons[participantId] = reason;
        }
      });
      
      // Show notification with reason
      if (widget.isTeacher && mounted) {
        final notificationMsg = reason != null && reason.isNotEmpty
            ? '$participantName raised their hand: "$reason"'
            : '$participantName raised their hand ✋';
        _showNotification(notificationMsg, backgroundColor: Colors.blueAccent);
      }
    }
  } else if (message['action'] == 'lower') {
    setState(() {
      _raisedHands.remove(participantId);
      _handRaiseReasons.remove(participantId); // ✅ Clean up
    });
  }
}

void _lowerHand(String participantId) {
  setState(() {
    _raisedHands.remove(participantId);
    // ✅ Auto-hide panel if no more raised hands
    if (_raisedHands.isEmpty) {
      _showRaisedHands = false;
    }
  });
  
  final data = utf8.encode(jsonEncode({
    'type': 'hand_lowered',
    'participantId': participantId,
  }));
  
  _room.localParticipant?.publishData(data, reliable: true);
}

void _lowerAllHands() {
  setState(() {
    _raisedHands.clear();
    _handRaiseReasons.clear(); // ✅ Clear reasons too
    _showRaisedHands = false;
  });
  
  // ✅ Send to ALL students that their hands were lowered
  final data = utf8.encode(jsonEncode({
    'type': 'hand_all_lowered',
    'sentBy': _myName ?? 'Teacher',
  }));
  
  _room.localParticipant?.publishData(data, reliable: true);
  
  _showNotification('All hands lowered', backgroundColor: Colors.green);
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

void _toggleFullScreen() {
  setState(() {
    _isFullScreen = !_isFullScreen;
    _showControls = true;
  });
  
  if (_isFullScreen) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _startControlsTimer();
  } else {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _controlsTimer.cancel();
  }
}

void _onScreenTap() {
  if (_isFullScreen) {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    }
  }
}

void _startControlsTimer() {
  _controlsTimer.cancel();
  _controlsTimer = Timer(const Duration(seconds: 6), () {
    if (mounted && _isFullScreen) {
      setState(() => _showControls = false);
    }
  });
}

// For students: Listen for whiteboard data to auto-switch
void _setupDataListener() {
  final dataListener = _room.createListener();
  
  dataListener.on<DataReceivedEvent>((event) async {
    try {
      final data = event.data is Uint8List 
          ? event.data as Uint8List 
          : Uint8List.fromList(event.data);
      
      final message = jsonDecode(utf8.decode(data));
      
      debugPrint('📱 Received message: ${message['type']}');
      
      // ✅ Handle poll messages for EVERYONE (before teacher-only check)
      if (message['type'] == 'poll_update' || message['type'] == 'poll_vote') {
        _handlePollMessage(message);
        return;
      }
      // Handle poll closed
if (message['type'] == 'poll_closed') {
  if (!widget.isTeacher) {
    setState(() {
      _activePoll?.isActive = false;
      _showPollPanel = false; // Hide for students too
    });
  }
  return;
}

// Handle mute request from teacher
if (message['type'] == 'mute_request') {
  if (!widget.isTeacher && message['participantId'] == _room.localParticipant?.identity) {
    await _room.localParticipant?.setMicrophoneEnabled(false);
    setState(() => _isMuted = true);
    _showNotification('Teacher requested you to mute', backgroundColor: Colors.orange);
  }
  return;
}

// Handle mute all request
if (message['type'] == 'mute_all_request') {
  if (!widget.isTeacher) {
    await _room.localParticipant?.setMicrophoneEnabled(false);
    setState(() => _isMuted = true);
    _showNotification('Teacher muted all students', backgroundColor: Colors.orange);
  }
  return;
}
      
      // Handle hand raise events
      if (message['type'] == 'hand_raise') {
        _handleHandRaise(message);
        return;
      }
      
      // Handle hand lowered
      if (message['type'] == 'hand_lowered' && !widget.isTeacher) {
        if (message['participantId'] == _room.localParticipant?.identity) {
          setState(() => _handRaised = false);
          _showNotification('Teacher lowered your hand', backgroundColor: Colors.orange);
        }
        return;
      }
      
      // Handle all hands lowered
      if (message['type'] == 'hand_all_lowered' && !widget.isTeacher) {
        setState(() => _handRaised = false);
        return;
      }
      
      // ✅ Skip rest if teacher
      if (widget.isTeacher) return;
      
      // Handle whiteboard toggle
      if (message['type'] == 'whiteboard_toggle') {
        final show = message['show'] as bool;
        if (mounted) {
          setState(() => _showWhiteboard = show);
        }
        return;
      }
      
      // Auto-switch to whiteboard when teacher draws
      if (message['type'] == 'whiteboard_stroke') {
        if (mounted && !_showWhiteboard) {
          setState(() => _showWhiteboard = true);
        }
      }
    } catch (e) {
      debugPrint('Error in data listener: $e');
    }
  });
  
  debugPrint('👂 Data listener ready');
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

  void _sendWhiteboardToggle(bool show) {
  final data = utf8.encode(jsonEncode({
    'type': 'whiteboard_toggle',
    'show': show,
    'sentBy': _myName ?? 'Teacher',
  }));
  
  debugPrint('📤 Teacher sending toggle: ${show ? "SHOW" : "HIDE"}');
  
  _room.localParticipant?.publishData(
    data,
    reliable: true,
    // ❌ Remove topic filter - use no topic so all participants receive it
    // topic: 'whiteboard',
  );
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
  _notificationTimer?.cancel();
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

  if (_isFullScreen && !_showControls) {
  return Scaffold(
    backgroundColor: const Color(0xFF121212),
    body: SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _buildMainContentArea(),
              ),
            ],
          ),
          // ✅ Poll panel in fullscreen
          if (_showPollPanel && _activePoll != null)
            Positioned(
              top: 60,
              right: 16,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: PollResultCard(
                  poll: _activePoll!,
                  showVoteButton: !widget.isTeacher && _activePoll!.isActive,
                  onVote: (index) => _vote(index),
                  onClose: widget.isTeacher ? _closePoll : null,
                ),
              ),
            ),
          // Notification overlay
          if (_notificationMessage != null)
            _buildNotificationOverlay(),
          // Tap area
          Positioned(
            bottom: 0, left: 0, right: 0, height: 50,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onScreenTap,
              child: Container(
                color: Colors.white.withOpacity(0.05),
                child: const Center(
                  child: Text('👆 Tap here to show controls',
                      style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  // Normal mode with AppBar and controls
  return GestureDetector(
    onTap: _onScreenTap,
    child: Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: _isFullScreen 
          ? null
          : _buildAppBar() as PreferredSizeWidget?,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: _isFullScreen ? 1 : 3,
                  child: _buildMainContentArea(),
                ),
                if (!_isFullScreen && _allParticipants.length > 1)
                  _buildFilmstrip(),
                if (!_isFullScreen || _showControls)
                  _buildControlBar(),
              ],
            ),
 
            // PiP video
            if (_showWhiteboard && _mainFocusParticipant != null)
              Positioned(
                bottom: _isFullScreen ? 80 : 140,
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
            // ✅ Notification overlay for normal mode
            if (_notificationMessage != null)
              _buildNotificationOverlay(),
            // Raised hands panel
            if (_showRaisedHands && widget.isTeacher && _raisedHands.isNotEmpty)
              Positioned(
                top: 60,
                right: 16,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  child: _buildRaisedHandsPanel(),
                ),
              ),
              // Poll panel - ✅ ADD THIS
if (_showPollPanel && _activePoll != null)
  Positioned(
    top: 60,
    right: 16,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: PollResultCard(
        poll: _activePoll!,
        showVoteButton: !widget.isTeacher && _activePoll!.isActive,
        onVote: (index) => _vote(index),
        onClose: widget.isTeacher ? _closePoll : null, 
      ),
    ),
  ),

  // Participants panel
if (_showParticipants)
  Positioned(
    top: 60,
    right: 16,
    child: Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(16),
      child: _buildParticipantsPanel(),
    ),
  ),
          ],
        ),
      ),
    ),
  );
}

// ✅ Extracted notification widget to avoid duplication
Widget _buildNotificationOverlay() {
  return Positioned(
    top: 8,
    left: 16,
    right: 16,
    child: Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _notificationColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _notificationMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _notificationMessage = null),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ],
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
      padding: isMobile ? EdgeInsets.zero : const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(16),
        child: WhiteboardCanvas(
          key: _whiteboardKey,
          room: _room,
          isTeacher: widget.isTeacher,
          userName: _myName ?? 'Teacher',
          onDrawingStart: _onTeacherDrawingStart,
          onDrawingEnd: _onTeacherDrawingEnd,
        ),
      ),
    );
  }
  
  // ✅ Use key to prevent video reload
  return Container(
    key: _videoContentKey,
    child: _isFullScreen && !_showControls
        ? _buildFullScreenContent()
        : _buildMainContent(),
  );
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
      // Recording indicator

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

      // Raised hands indicator (teacher only)
if (widget.isTeacher && _raisedHands.isNotEmpty)
  GestureDetector(
    onTap: () => setState(() => _showRaisedHands = !_showRaisedHands),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pan_tool, color: Colors.amber, size: 14),
          const SizedBox(width: 4),
          Text(
            '${_raisedHands.length}',
            style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    ),
  ),
  if (widget.isTeacher)
  IconButton(
    icon: const Icon(Icons.poll, color: Colors.white70),
    onPressed: _openCreatePoll,  // ✅ Use the method
    tooltip: 'Create Poll',
  ),
    ],
  );
}

Widget _buildRaisedHandsPanel() {
  return Container(
    width: 280,
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.amber.withOpacity(0.3)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.pan_tool, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Raised Hands (${_raisedHands.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _lowerAllHands,
                child: const Icon(Icons.clear_all, color: Colors.white54, size: 20),
              ),
            ],
          ),
        ),
        // List
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _raisedHands.length,
            itemBuilder: (context, index) {
              final participantId = _raisedHands[index];
              final name = _participantNames[participantId] ?? 'Student';
              final reason = _handRaiseReasons[participantId]; // ✅ Get reason
              
              return ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.amber.withOpacity(0.2),
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ),
                title: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: reason != null
                    ? Text(
                        '"$reason"',
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    : const Text('Raised hand', style: TextStyle(color: Colors.white38, fontSize: 11)),
                trailing: Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    // Mute request button (teacher only)
    if (widget.isTeacher)
      IconButton(
        icon: Icon(
          _allParticipants.firstWhere((p) => p.identity == participantId).isMicrophoneEnabled()
              ? Icons.mic 
              : Icons.mic_off,
          color: _allParticipants.firstWhere((p) => p.identity == participantId).isMicrophoneEnabled()
              ? Colors.green 
              : Colors.red,
          size: 18,
        ),
        onPressed: () {
          final name = _participantNames[participantId] ?? 'Student';
          _requestMute(participantId, name);
        },
        tooltip: 'Mute',
      ),
    // Lower hand
    IconButton(
      icon: const Icon(Icons.check, color: Colors.green, size: 20),
      onPressed: () => _lowerHand(participantId),
      tooltip: 'Lower hand',
    ),
  ],
),
              );
            },
          ),
        ),
      ],
    ),
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
    key: _filmstripKey, 
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
  final isMobile = MediaQuery.of(context).size.width < 600;
  
  return AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    padding: EdgeInsets.symmetric(
      vertical: isMobile ? 10 : 16, 
      horizontal: isMobile ? 8 : 24,
    ),
    decoration: const BoxDecoration(
      color: Color(0xFF1A1A1A),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(24), 
        topRight: Radius.circular(24),
      ),
    ),
    child: isMobile ? _buildMobileControlBar() : _buildDesktopControlBar(),
  );
}

Widget _buildParticipantsPanel() {
  return Container(
    width: 280,
    decoration: BoxDecoration(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.withOpacity(0.3)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.people, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                'Participants (${_allParticipants.length})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              if (widget.isTeacher)
                GestureDetector(
                  onTap: _requestMuteAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Mute All', style: TextStyle(color: Colors.orange, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ),
        // List
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _allParticipants.length,
            itemBuilder: (context, index) {
              final participant = _allParticipants[index];
              final name = _getParticipantName(participant);
              final identity = participant.identity ?? '';
              final isMicOn = participant.isMicrophoneEnabled();
              final hasHandRaised = _raisedHands.contains(identity);
              final role = _getParticipantRole(participant);
              
              return ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: role == 'teacher' 
                      ? Colors.red.withOpacity(0.2) 
                      : Colors.blueAccent.withOpacity(0.2),
                  child: Text(
                    name[0].toUpperCase(),
                    style: TextStyle(
                      color: role == 'teacher' ? Colors.red : Colors.blueAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                    if (hasHandRaised)
                      const Icon(Icons.pan_tool, color: Colors.amber, size: 14),
                  ],
                ),
                subtitle: Text(
                  role == 'teacher' ? 'Teacher' : 'Student',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                trailing: widget.isTeacher && participant != _room.localParticipant
                    ? IconButton(
                        icon: Icon(
                          isMicOn ? Icons.mic : Icons.mic_off,
                          color: isMicOn ? Colors.green : Colors.red,
                          size: 18,
                        ),
                        onPressed: () => _requestMute(identity, name),
                        tooltip: isMicOn ? 'Request Mute' : 'Muted',
                      )
                    : Icon(
                        isMicOn ? Icons.mic : Icons.mic_off,
                        color: isMicOn ? Colors.green : Colors.red,
                        size: 18,
                      ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

Widget _buildDesktopControlBar() {
  return Row(
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
            if (!_showWhiteboard) _isTeacherDrawing = false;
          });
          _sendWhiteboardToggle(_showWhiteboard);
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
      // Hand raise button (students only)
if (!widget.isTeacher)
  _buildControlButton(
    icon: _handRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
    color: _handRaised ? Colors.amber : const Color(0xFF2D2D2D),
    iconColor: _handRaised ? Colors.white : Colors.white70,
    onPressed: _toggleHandRaise,
  ),
  // People/Participants button
_buildControlButton(
  icon: Icons.people,
  color: _showParticipants ? Colors.blueAccent : const Color(0xFF2D2D2D),
  iconColor: _showParticipants ? Colors.white : Colors.white70,
  onPressed: () => setState(() {
    _showParticipants = !_showParticipants;
    if (_showParticipants) _showRaisedHands = false;
  }),
),
 // Poll button (teacher) - handles both create and view
if (widget.isTeacher)
  _buildControlButton(
    icon: _activePoll != null 
        ? (_activePoll!.isActive ? Icons.bar_chart : Icons.poll) 
        : Icons.poll_outlined,
    color: _activePoll != null && _activePoll!.isActive 
        ? Colors.green 
        : const Color(0xFF2D2D2D),
    iconColor: _activePoll != null && _activePoll!.isActive 
        ? Colors.white 
        : Colors.white70,
    onPressed: () {
      if (_activePoll != null) {
        // Toggle poll results view
        setState(() => _showPollPanel = !_showPollPanel);
      } else {
        // Open create poll dialog
        _openCreatePoll();
      }
    },
  ),
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
  );
}

Widget _buildMobileControlBar() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      // Mic - essential
      _buildControlButton(
        icon: _isMuted ? Icons.mic_off : Icons.mic,
        color: _isMuted ? Colors.redAccent : const Color(0xFF2D2D2D),
        onPressed: () async {
          setState(() => _isMuted = !_isMuted);
          await _room.localParticipant?.setMicrophoneEnabled(!_isMuted);
        },
        isMobile: true,
      ),
      
      // Video - essential
      _buildControlButton(
        icon: _isVideoOff ? Icons.videocam_off : Icons.videocam,
        color: _isVideoOff ? Colors.redAccent : const Color(0xFF2D2D2D),
        onPressed: () async {
          setState(() => _isVideoOff = !_isVideoOff);
          await _room.localParticipant?.setCameraEnabled(!_isVideoOff);
        },
        isMobile: true,
      ),
      
      // Whiteboard - essential for teacher
      _buildControlButton(
        icon: _showWhiteboard ? Icons.videocam : Icons.draw,
        color: _showWhiteboard ? Colors.blueAccent : const Color(0xFF2D2D2D),
        onPressed: () {
          setState(() {
            _showWhiteboard = !_showWhiteboard;
            if (!_showWhiteboard) _isTeacherDrawing = false;
          });
          _sendWhiteboardToggle(_showWhiteboard);
        },
        isMobile: true,
      ),

 

      
      // More options menu
      _buildMoreButton(),
      
      // End call - always visible
      _buildControlButton(
        icon: Icons.call_end,
        color: Colors.red,
        iconColor: Colors.white,
        onPressed: widget.isTeacher ? _endLesson : _leaveLesson,
        isMobile: true,
      ),
    ],
  );
}

// More options popup menu
Widget _buildMoreButton() {
  return PopupMenuButton<String>(
    color: const Color(0xFF2D2D2D),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    offset: const Offset(0, -240),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D2D),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.more_horiz, color: Colors.white70, size: 20),
    ),
    onSelected: (value) {
      switch (value) {
        case 'chat':
          setState(() => _isChatOpen = !_isChatOpen);
          break;
        case 'fullscreen':
          _toggleFullScreen();
          break;
        case 'screenshare':
          if (widget.isTeacher) {
            final enabled = _room.localParticipant?.isScreenShareEnabled() ?? false;
            _room.localParticipant?.setScreenShareEnabled(!enabled);
            setState(() {});
          }
          break;
        case 'handraise':
          _toggleHandRaise();
          break;
        case 'raisedhands':
          setState(() => _showRaisedHands = !_showRaisedHands);
          break;
        case 'mute_all':
  _requestMuteAll();
  break;
        case 'create_poll':
  _openCreatePoll();  // ✅ Instead of setState
  break;
case 'view_poll':
  setState(() => _showPollPanel = !_showPollPanel);
  break;  
        
        
      }
    },
    itemBuilder: (context) => [
      // Chat
      PopupMenuItem(
        value: 'chat',
        child: Row(
          children: [
            Icon(
              _isChatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
              color: _isChatOpen ? Colors.blueAccent : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              _isChatOpen ? 'Hide Chat' : 'Chat',
              style: TextStyle(color: _isChatOpen ? Colors.blueAccent : Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
      
      
      // Hand Raise (students only)
      if (!widget.isTeacher)
        PopupMenuItem(
          value: 'handraise',
          child: Row(
            children: [
              Icon(
                _handRaised ? Icons.pan_tool : Icons.pan_tool_outlined,
                color: _handRaised ? Colors.amber : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                _handRaised ? 'Lower Hand ✋' : 'Raise Hand ✋',
                style: TextStyle(color: _handRaised ? Colors.amber : Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),

        // Mute All / Unmute All (teacher only)
if (widget.isTeacher)
  PopupMenuItem(
    value: 'mute_all',
    child: Row(
      children: [
        Icon(
          _allParticipants.every((p) => _mutedParticipants.contains(p.identity)) 
              ? Icons.mic 
              : Icons.mic_off,
          color: Colors.white70,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(
          _allParticipants.every((p) => p == _room.localParticipant || _mutedParticipants.contains(p.identity))
              ? 'Allow Talking'
              : 'Mute All',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    ),
  ),
      
      // Raised Hands (teacher only)
      if (widget.isTeacher && _raisedHands.isNotEmpty)
        PopupMenuItem(
          value: 'raisedhands',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pan_tool, color: Colors.amber, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      '${_raisedHands.length}',
                      style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _showRaisedHands ? 'Hide Raised Hands' : 'View Raised Hands',
                style: TextStyle(color: _showRaisedHands ? Colors.amber : Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      
      // Create Poll (teacher only)
if (widget.isTeacher)
  PopupMenuItem(
    value: 'create_poll',
    child: Row(
      children: [
        const Icon(Icons.poll, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        const Text('Create Poll', style: TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    ),
  ),

// View Poll
if (_activePoll != null)
  PopupMenuItem(
    value: 'view_poll',
    child: Row(
      children: [
        Icon(
          _showPollPanel ? Icons.poll : Icons.poll_outlined,
          color: _activePoll!.isActive ? Colors.green : Colors.white70,
          size: 20,
        ),
        const SizedBox(width: 12),
        Text(
          _showPollPanel ? 'Hide Poll' : 'View Poll',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    ),
  ),
      
      
      // Fullscreen
      PopupMenuItem(
        value: 'fullscreen',
        child: Row(
          children: [
            Icon(
              _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: _isFullScreen ? Colors.blueAccent : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              _isFullScreen ? 'Exit Fullscreen' : 'Fullscreen',
              style: TextStyle(color: _isFullScreen ? Colors.blueAccent : Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
      
      // Screen Share (teacher only)
      if (widget.isTeacher)
        PopupMenuItem(
          value: 'screenshare',
          child: Row(
            children: [
              Icon(
                Icons.screen_share,
                color: (_room.localParticipant?.isScreenShareEnabled() ?? false) ? Colors.blueAccent : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                (_room.localParticipant?.isScreenShareEnabled() ?? false) ? 'Stop Sharing' : 'Share Screen',
                style: TextStyle(
                  color: (_room.localParticipant?.isScreenShareEnabled() ?? false) ? Colors.blueAccent : Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
// Update _buildControlButton to accept mobile flag
Widget _buildControlButton({
  required IconData icon,
  required Color color,
  Color iconColor = Colors.white70,
  required VoidCallback onPressed,
  bool isMobile = false,
}) {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      shape: const CircleBorder(),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      backgroundColor: color,
      elevation: 0,
    ),
    onPressed: onPressed,
    child: Icon(icon, color: iconColor, size: isMobile ? 20 : 24),
  );
}
  

 Widget _buildIdentityOverlay(Participant? participant, {required bool isMain}) {
  final name = participant != null ? _getParticipantName(participant) : 'Connecting...';
  final isMicMuted = !(participant?.isMicrophoneEnabled() ?? true);
  final identity = participant?.identity ?? '';

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
            style: TextStyle(color: Colors.white, fontSize: isMain ? 12 : 10),
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
            child: Icon(
              _mutedParticipants.contains(identity) 
                  ? Icons.voice_over_off  // Teacher muted them
                  : Icons.mic_off,        // Self-muted
              color: Colors.white, 
              size: 12,
            ),
          ),
      ],
    ),
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

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3 + (_controller.value * 0.7)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}