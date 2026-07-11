import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

class UniversalVideoPlayer extends StatefulWidget {
  final String? videoUrl;

  const UniversalVideoPlayer({super.key, this.videoUrl});

  @override
  State<UniversalVideoPlayer> createState() => _UniversalVideoPlayerState();
}

class _UniversalVideoPlayerState extends State<UniversalVideoPlayer> {
  // YouTube
  YoutubePlayerController? _youtubeController;
  
  // Regular video
  VideoPlayerController? _videoController;
  
  bool _isYoutube = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) {
      setState(() {
        _error = 'No video URL provided';
        _isLoading = false;
      });
      return;
    }

    // Detect if it's a YouTube URL
    final youtubeId = YoutubePlayerController.convertUrlToId(url);
    
    if (youtubeId != null) {
      _isYoutube = true;
      _youtubeController = YoutubePlayerController.fromVideoId(
        videoId: youtubeId,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          mute: false,
        ),
      );
      
      _youtubeController!.listen((event) {
        if (event.playerState == PlayerState.ended) {
          // Video finished
        }
      });
      
      setState(() => _isLoading = false);
    } else {
      // Regular video URL
      try {
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
        await _videoController!.initialize();
        setState(() => _isLoading = false);
      } catch (e) {
        setState(() {
          _error = 'Could not load video: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _youtubeController?.close();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 220,
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_error != null) {
      return Container(
        height: 220,
        color: Colors.grey.shade900,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (_isYoutube && _youtubeController != null) {
      return YoutubePlayer(
        controller: _youtubeController!,
        aspectRatio: 16 / 9,
      );
    }

    if (_videoController != null) {
      return AspectRatio(
        aspectRatio: _videoController!.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(_videoController!),
            // Play/Pause button
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_videoController!.value.isPlaying) {
                    _videoController!.pause();
                  } else {
                    _videoController!.play();
                  }
                });
              },
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: Icon(
                    _videoController!.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                    size: 64,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}