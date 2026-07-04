import 'package:flutter/material.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';

class ProfessionalVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final void Function()? onVideoEnded;

  const ProfessionalVideoPlayer({
    super.key,
    required this.videoUrl,
    this.onVideoEnded,
  });

  @override
  State<ProfessionalVideoPlayer> createState() =>
      _ProfessionalVideoPlayerState();
}

class _ProfessionalVideoPlayerState extends State<ProfessionalVideoPlayer> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _videoPlayerController.initialize();

      // Listen for completion
      _videoPlayerController.addListener(() {
        if (_videoPlayerController.value.position >=
                _videoPlayerController.value.duration &&
            _videoPlayerController.value.duration > Duration.zero) {
          widget.onVideoEnded?.call();
        }
      });

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        showOptions: false, // Hide the options menu for cleaner look

        // AfriNova brand colors
        materialProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFFF9800),      // Gold
          handleColor: const Color(0xFFFF9800),       // Gold
          backgroundColor: Colors.grey.shade600,
          bufferedColor: Colors.grey.shade400,
        ),
        cupertinoProgressColors: ChewieProgressColors(
          playedColor: const Color(0xFFFF9800),
          handleColor: const Color(0xFFFF9800),
          backgroundColor: Colors.grey.shade600,
          bufferedColor: Colors.grey.shade400,
        ),

        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFFFF9800)),
                SizedBox(height: 16),
                Text(
                  'Loading video...',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.white70),
                    const SizedBox(height: 12),
                    const Text(
                      'Video Unavailable',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      errorMessage,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () {
                        _chewieController?.dispose();
                        _videoPlayerController.dispose();
                        setState(() {
                          _hasError = false;
                          _chewieController = null;
                        });
                        _initializePlayer();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFF9800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Video init error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Error state
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.signal_wifi_off,
                    size: 40, color: Colors.white54),
                const SizedBox(height: 12),
                const Text('Could not load video',
                    style:
                        TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  _errorMessage,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = '';
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF9800),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Player
    return Container(
      color: Colors.black,
      child: _chewieController != null &&
              _chewieController!
                  .videoPlayerController.value.isInitialized
          ? Chewie(controller: _chewieController!)
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF9800)),
                  SizedBox(height: 16),
                  Text(
                    'Preparing your lesson...',
                    style:
                        TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
}

// Export function for conditional import
Widget buildVideoPlayer(String videoUrl, VoidCallback? onVideoEnded) {
  return ProfessionalVideoPlayer(
    videoUrl: videoUrl,
    onVideoEnded: onVideoEnded,
  );
}