import 'package:livekit_client/livekit_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LiveKitService {
  static Room? _room;
  static Room get room => _room!;
  
  // ✅ Use listener-based approach
  static bool _isConnected = false;
  static bool get isConnected => _isConnected;

  // Get token from Supabase Edge Function
  static Future<String> _getToken({
    required String roomName,
    required String participantName,
    required String participantId,
  }) async {
    final response = await Supabase.instance.client.functions.invoke(
      'generate-livekit-token',
      body: {
        'roomName': roomName,
        'participantName': participantName,
        'participantId': participantId,
      },
    );

    if (response.data?['token'] == null) {
      throw Exception('Failed to generate token');
    }

    return response.data['token'] as String;
  }

  // Connect to a room
  static Future<Room> connect({
    required String url,
    required String roomName,
    required String participantName,
    required String participantId,
  }) async {
    // Disconnect if already connected
    await disconnect();

    _room = Room();

    // ✅ Listen for connection state changes
    _room!.addListener(_onRoomUpdate);

    // Get token
    final token = await _getToken(
      roomName: roomName,
      participantName: participantName,
      participantId: participantId,
    );

    // Connect
    await _room!.connect(url, token);

    // Enable camera and mic by default
    try {
      await _room!.localParticipant?.setCameraEnabled(true);
      await _room!.localParticipant?.setMicrophoneEnabled(true);
    } catch (_) {}

    return _room!;
  }

  // ✅ Room update listener
  static void _onRoomUpdate() {
    _isConnected = _room?.connectionState == ConnectionState.connected;
  }

  // Disconnect
  static Future<void> disconnect() async {
    if (_room != null) {
      _room!.removeListener(_onRoomUpdate);
      await _room!.disconnect();
      _room = null;
      _isConnected = false;
    }
  }

  // Toggle camera
  static Future<void> toggleCamera() async {
    final participant = _room?.localParticipant;
    if (participant != null) {
      await participant.setCameraEnabled(!participant.isCameraEnabled());
    }
  }

  // Toggle microphone
  static Future<void> toggleMicrophone() async {
    final participant = _room?.localParticipant;
    if (participant != null) {
      await participant.setMicrophoneEnabled(!participant.isMicrophoneEnabled());
    }
  }

  // Toggle screen share
  static Future<void> toggleScreenShare() async {
    final participant = _room?.localParticipant;
    if (participant != null) {
      if (participant.isScreenShareEnabled()) {
        await participant.setScreenShareEnabled(false);
      } else {
        await participant.setScreenShareEnabled(true);
      }
    }
  }
}