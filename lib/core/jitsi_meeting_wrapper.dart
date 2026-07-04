import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class JitsiMeetingWrapper {
  static final _jitsiMeet = JitsiMeet();
  static final _client = Supabase.instance.client;

  static Future<void> join({
    required BuildContext context,
    required String roomName,
    required String userName,
    required String lessonId,
    bool isTeacher = false,
  }) async {
    final meetUrl = 'https://meet.ffmuc.net/$roomName'
        '#userInfo.displayName=${Uri.encodeComponent(userName)}'
        '&config.prejoinPageEnabled=false'
        '&config.startWithAudioMuted=${!isTeacher}'
        '&config.startWithVideoMuted=${!isTeacher}';

    if (kIsWeb) {
      final uri = Uri.parse(meetUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      // ⚠️ Web: Cannot detect when tab closes — teacher must manually end lesson
    } else {
      var listener = JitsiMeetEventListener(
        conferenceTerminated: (url, error) async {
          debugPrint("Meeting ended for: $lessonId");
          // ✅ Auto-update status to 'ended' when meeting closes
          await _client.from('live_lessons').update({
            'status': 'ended',
            'ended_at': DateTime.now().toIso8601String(),
          }).eq('id', lessonId);
        },
      );

      var options = JitsiMeetConferenceOptions(
        serverURL: "https://meet.ffmuc.net",
        room: roomName,
        configOverrides: {
          "startWithAudioMuted": !isTeacher,
          "startWithVideoMuted": !isTeacher,
          "prejoinPageEnabled": false,
        },
        featureFlags: {
          "unsaferoomwarning.enabled": false,
          "welcomepage.enabled": false,
        },
        userInfo: JitsiMeetUserInfo(displayName: userName),
      );

      await _jitsiMeet.join(options, listener);
    }
  }
}