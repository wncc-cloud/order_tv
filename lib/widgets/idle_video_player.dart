// Video player for the Google Drive-backed idle-screen slideshow — DISABLED.
//
// The kitchen display's idle screen now shows a static logo
// (`_IdleView` in `lib/screens/kitchen_display_screen.dart`) instead of
// rotating through photos/videos from a shared Google Drive folder. Left
// here, commented out, rather than deleted, in case the slideshow needs to
// come back. See also `lib/widgets/idle_media_slideshow.dart` (the widget
// that used this player) and `lib/services/drive_media.dart` (the Drive
// API client).

/*
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../services/drive_media.dart' show driveAndroidAuthHeaders;

/// Real implementation of [IdleVideoPlayerBuilder] (see
/// `idle_media_slideshow.dart`) for native Android — a plain
/// `VideoPlayerController` playing directly from the Drive `alt=media` URL,
/// muted (matches the web version's autoplay-safe default) and not looping
/// (advancing to the next slide on end is `IdleMediaSlideshow`'s job, not
/// this player's).
///
/// Unlike the web version (`billing_cafe`'s `idle_video_player_web.dart`),
/// there's no singleton/registry constraint here — `video_player` controllers
/// are cheap to create and dispose per slide, so each new URL gets its own
/// fresh controller.
Widget buildIdleVideoPlayer({
  Key? key,
  required String url,
  required VoidCallback onEnded,
  required VoidCallback onError,
}) =>
    _IdleVideoPlayer(key: key, url: url, onEnded: onEnded, onError: onError);

class _IdleVideoPlayer extends StatefulWidget {
  const _IdleVideoPlayer({
    super.key,
    required this.url,
    required this.onEnded,
    required this.onError,
  });

  final String url;
  final VoidCallback onEnded;
  final VoidCallback onError;

  @override
  State<_IdleVideoPlayer> createState() => _IdleVideoPlayerState();
}

class _IdleVideoPlayerState extends State<_IdleVideoPlayer> {
  VideoPlayerController? _controller;
  Timer? _stallTimer;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _attach(widget.url);
  }

  @override
  void didUpdateWidget(covariant _IdleVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _attach(widget.url);
  }

  void _attach(String url) {
    _advanced = false;
    _stallTimer?.cancel();
    final old = _controller;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: driveAndroidAuthHeaders,
    )
      ..setLooping(false)
      ..setVolume(0);
    controller.addListener(() => _onTick(controller));
    _controller = controller;
    old?.dispose();

    controller.initialize().then((_) {
      if (!mounted || _controller != controller) return;
      controller.play();
      setState(() {});
    }).catchError((Object e) {
      _advanceOnce(widget.onError);
    });

    // Defensive backstop: a Drive file that returns 200 but never actually
    // starts playing (corrupt/incompatible codec, stalled connection)
    // shouldn't freeze the slideshow on this one slide forever — mirrors
    // the web version's 20s stall timer.
    _stallTimer = Timer(const Duration(seconds: 20), () {
      if (_controller == controller && !controller.value.isPlaying) {
        _advanceOnce(widget.onError);
      }
    });
  }

  void _onTick(VideoPlayerController controller) {
    if (_controller != controller || !mounted) return;
    final value = controller.value;
    if (value.hasError) {
      _advanceOnce(widget.onError);
      return;
    }
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _advanceOnce(widget.onEnded);
    }
  }

  void _advanceOnce(VoidCallback callback) {
    if (_advanced) return;
    _advanced = true;
    callback();
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }
}
*/
