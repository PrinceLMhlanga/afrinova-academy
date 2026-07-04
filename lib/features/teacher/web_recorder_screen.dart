import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class WebRecorderScreen extends StatefulWidget {
  const WebRecorderScreen({super.key});

  @override
  State<WebRecorderScreen> createState() => _WebRecorderScreenState();
}

class _WebRecorderScreenState extends State<WebRecorderScreen> {
  final String _viewID = "webcam-${DateTime.now().millisecondsSinceEpoch}";
  final html.VideoElement _videoElement = html.VideoElement();
  html.MediaStream? _mediaStream;
  html.MediaRecorder? _recorder;
  final List<html.Blob> _chunks = [];

  // States: 'preview', 'recording', 'paused', 'review'
  String _state = 'preview';
  int _seconds = 0;
  String _timerText = '00:00';
  Uint8List? _recordedBytes;
  String _recordedFileName = '';
  String _recordedMimeType = 'video/webm';
  bool _isTimerRunning = false;

  @override
  void initState() {
    super.initState();
    ui.platformViewRegistry.registerViewFactory(_viewID, (int viewId) => _videoElement);
    _startCamera();
  }

  Future<void> _startCamera() async {
    try {
      _mediaStream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
          'facingMode': 'user',
        },
        'audio': true,
      });

      _videoElement
        ..srcObject = _mediaStream
        ..autoplay = true
        ..muted = true
        ..controls = false
        ..loop = false
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.backgroundColor = '#000000';

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera access denied. Please allow permissions.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===== START RECORDING =====
  void _startRecording() {
    if (_mediaStream == null) return;
    _chunks.clear();
    _recordedBytes = null;

    // Determine best MIME type
   // Determine best MIME type — prefer MP4 for compatibility
if (html.MediaRecorder.isTypeSupported('video/mp4')) {
  _recordedMimeType = 'video/mp4';
} else if (html.MediaRecorder.isTypeSupported('video/webm;codecs=vp9')) {
  _recordedMimeType = 'video/webm;codecs=vp9';
} else if (html.MediaRecorder.isTypeSupported('video/webm;codecs=vp8')) {
  _recordedMimeType = 'video/webm;codecs=vp8';
} else {
  _recordedMimeType = 'video/webm';
}

    _recorder = html.MediaRecorder(_mediaStream!, {
      'mimeType': _recordedMimeType,
      'videoBitsPerSecond': 2500000,
    });

    _recorder!.on['dataavailable'].listen((html.Event event) {
      final blobEvent = event as html.BlobEvent;
      if (blobEvent.data != null && blobEvent.data!.size > 0) {
        _chunks.add(blobEvent.data!);
      }
    });

    _recorder!.on['stop'].listen((html.Event event) {
      _finalizeRecording();
    });

    _recorder!.start(1000);

    setState(() {
      _state = 'recording';
      _seconds = 0;
      _timerText = '00:00';
      _isTimerRunning = true;
    });
    _runTimer();
  }

  // ===== PAUSE RECORDING =====
  void _pauseRecording() {
    if (_recorder != null && _recorder!.state == 'recording') {
      _recorder!.pause();
      setState(() {
        _state = 'paused';
        _isTimerRunning = false;
      });
    }
  }

  // ===== RESUME RECORDING =====
  void _resumeRecording() {
    if (_recorder != null && _recorder!.state == 'paused') {
      _recorder!.resume();
      setState(() {
        _state = 'recording';
        _isTimerRunning = true;
      });
      _runTimer();
    }
  }

  // ===== STOP RECORDING =====
  // ===== STOP RECORDING =====
void _stopRecording() {
  if (_recorder != null && _recorder!.state != 'inactive') {
    _recorder!.stop();
  }
  setState(() {
    _isTimerRunning = false;
    _state = 'processing'; // ← Show processing state immediately
  });
}

// ===== FINALIZE — Combine chunks into a single blob =====
void _finalizeRecording() {
  if (_chunks.isEmpty) {
    debugPrint('No recorded chunks');
    if (mounted) setState(() => _state = 'preview');
    return;
  }

  final blob = html.Blob(_chunks, _recordedMimeType.split(';').first);
  debugPrint('Recording size: ${(blob.size / (1024 * 1024)).toStringAsFixed(1)} MB');

  // Create preview URL
  final url = html.Url.createObjectUrlFromBlob(blob);

  // Stop camera
  _mediaStream?.getTracks().forEach((track) => track.stop());

  // Update video element for preview
  _videoElement
    ..srcObject = null
    ..src = url
    ..controls = true
    ..muted = false
    ..loop = false
    ..autoplay = false;

  // Use fetch + arrayBuffer (more reliable than FileReader)
  html.window.fetch(url).then((response) {
    return response.arrayBuffer();
  }).then((buffer) {
    if (mounted) {
      setState(() {
        _recordedBytes = Uint8List.view(buffer as ByteBuffer);
        final extension = _recordedMimeType.contains('mp4') ? 'mp4' : 'webm';
_recordedFileName = 'recording_${DateTime.now().millisecondsSinceEpoch}.$extension';
        _state = 'review';
      });
      debugPrint('✅ Recording ready: ${_recordedBytes!.length} bytes');
    }
  }).catchError((e) {
    debugPrint('❌ Fetch error: $e');
    if (mounted) setState(() => _state = 'preview');
  });
}
  // ===== SAVE — Return to upload screen =====
  void _saveAndExit() {
    if (_recordedBytes != null) {
      // Stop any remaining tracks
      _mediaStream?.getTracks().forEach((track) => track.stop());
      // Return data to upload screen
      Navigator.pop(context, {
        'bytes': _recordedBytes,
        'fileName': _recordedFileName,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording not ready yet. Please wait...'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ===== DISCARD =====
  void _discard() {
    _chunks.clear();
    _recordedBytes = null;
    _videoElement
      ..controls = false
      ..src = ''
      ..srcObject = null;

    // Restart camera preview
    _startCamera();
    setState(() => _state = 'preview');
  }

  // ===== TIMER =====
  void _runTimer() {
    if (!_isTimerRunning || !mounted) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (_isTimerRunning && mounted && _state == 'recording') {
        setState(() {
          _seconds++;
          final m = (_seconds ~/ 60).toString().padLeft(2, '0');
          final s = (_seconds % 60).toString().padLeft(2, '0');
          _timerText = '$m:$s';
        });
        _runTimer();
      }
    });
  }

  @override
  void dispose() {
    _isTimerRunning = false;
    _mediaStream?.getTracks().forEach((track) => track.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ===== TOP BAR =====
                        // ===== TOP BAR =====
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              color: Colors.black,
              child: Row(
                children: [
                  // Close button
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      _isTimerRunning = false;
                      _mediaStream?.getTracks().forEach((t) => t.stop());
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 8),
                  // Recording indicator
                  if (_state == 'recording' || _state == 'paused')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _state == 'paused'
                            ? Colors.orange.withOpacity(0.9)
                            : Colors.red.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _state == 'paused' ? Icons.pause_circle_filled : Icons.circle,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _state == 'paused' ? 'PAUSED $_timerText' : 'REC $_timerText',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  // Save button (visible in review state)
                  if (_state == 'review' && _recordedBytes != null)
                    ElevatedButton.icon(
                      onPressed: _saveAndExit,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Save'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                ],
              ),
            ),

            // ===== MAIN CONTENT =====
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera/Preview feed
                  HtmlElementView(viewType: _viewID),

                  // Review overlay with info
                  if (_state == 'review' && _recordedBytes != null)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Recording complete — ${(_recordedBytes!.length / (1024 * 1024)).toStringAsFixed(1)} MB',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ===== BOTTOM CONTROLS =====
            Container(
              color: const Color(0xFF141414),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              child: _buildControls(),
            ),
          ],
        ),
      ),
    );
  }

  // ===== PROCESSING STATE: Show loading =====
Widget _processingControls() {
  return Column(
    children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: SizedBox(
            width: 30, height: 30,
            child: CircularProgressIndicator(color: Color(0xFFFF9800), strokeWidth: 3),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        'Processing recording...',
        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
      ),
    ],
  );
}

  Widget _buildControls() {
  switch (_state) {
    case 'preview':
      return _previewControls();
    case 'recording':
      return _recordingControls();
    case 'paused':
      return _pausedControls();
    case 'processing':
      return _processingControls(); // ← NEW
    case 'review':
      return _reviewControls();
    default:
      return _previewControls();
  }
}

  // ===== PREVIEW STATE: Start button only =====
  Widget _previewControls() {
    return Column(
      children: [
        GestureDetector(
          onTap: _startRecording,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A237E).withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 3,
                )
              ],
            ),
            child: const Center(
              child: Icon(Icons.fiber_manual_record, color: Colors.white, size: 36),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Tap to start recording',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        ),
      ],
    );
  }

  // ===== RECORDING STATE: Pause + Stop =====
  Widget _recordingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Pause button
        GestureDetector(
          onTap: _pauseRecording,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.4), width: 3),
            ),
            child: const Center(
              child: Icon(Icons.pause, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(width: 32),
        // Stop button
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 24,
                  spreadRadius: 4,
                )
              ],
            ),
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 32),
        // Placeholder for symmetry
        const SizedBox(width: 56, height: 56),
      ],
    );
  }

  // ===== PAUSED STATE: Resume + Stop =====
  Widget _pausedControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Resume button
        GestureDetector(
          onTap: _resumeRecording,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4CAF50), width: 3),
            ),
            child: const Center(
              child: Icon(Icons.play_arrow, color: Color(0xFF4CAF50), size: 30),
            ),
          ),
        ),
        const SizedBox(width: 32),
        // Stop button
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.5),
                  blurRadius: 24,
                  spreadRadius: 4,
                )
              ],
            ),
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 32),
        const SizedBox(width: 56, height: 56),
      ],
    );
  }

  // ===== REVIEW STATE: Discard + Save =====
  Widget _reviewControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Discard button
        InkWell(
          onTap: _discard,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.delete_outline, color: Colors.red, size: 26),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Discard',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 48),
        // Save button
        InkWell(
          onTap: _saveAndExit,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4CAF50).withOpacity(0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.check, color: Colors.white, size: 32),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  

}
Future<Map<String, dynamic>?> openWebRecorder(BuildContext context) async {
  return await Navigator.push<Map<String, dynamic>>(
    context,
    MaterialPageRoute(builder: (_) => const WebRecorderScreen()),
  );
}