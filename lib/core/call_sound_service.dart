import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_vibrate/flutter_vibrate.dart'; // Import new package

class CallSoundService {
  static Timer? _vibrateTimer;
  static bool _isActive = false;

  static void startRinging() async {
    if (_isActive || kIsWeb) return;
    _isActive = true;

    // Check if device can vibrate
    bool canVibrate = await Vibrate.canVibrate;
    if (!canVibrate) return;

    // Continuous loop for ringing
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      Vibrate.vibrate(); // Default distinct vibration
    });
  }

  static void startCalling() async {
    if (_isActive || kIsWeb) return;
    _isActive = true;

    bool canVibrate = await Vibrate.canVibrate;
    if (!canVibrate) return;

    // Lighter feedback loop for outgoing call
    _vibrateTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      Vibrate.feedback(FeedbackType.medium); 
    });
  }

  static void stop() {
    _vibrateTimer?.cancel();
    _vibrateTimer = null;
    _isActive = false;
  }
}
