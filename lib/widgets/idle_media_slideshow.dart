// Google Drive-backed idle-screen slideshow — DISABLED.
//
// The kitchen display's idle screen now shows a static logo
// (`_IdleView` in `lib/screens/kitchen_display_screen.dart`) instead of
// rotating through photos/videos from a shared Google Drive folder. Left
// here, commented out, rather than deleted, in case the slideshow needs to
// come back. See also `lib/services/drive_media.dart` (the Drive API
// client this widget called) and `lib/widgets/idle_video_player.dart` (the
// video player it used).

/*
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../config/env.dart';
import '../debug/debug_log.dart';
import '../main.dart' show kDebugOverlay;
import '../services/drive_media.dart';
import 'idle_video_player.dart';

const _tag = '[IDLE-SLIDESHOW]';

typedef DriveMediaFetcher = Future<List<DriveMediaItem>> Function();

/// Builds the widget that plays one video slide. Injectable so tests don't
/// need a real `video_player` platform channel (there's no web-vs-VM
/// conditional-import trick to lean on here, unlike the original web app —
/// this project only ever targets native Android) — production code uses
/// the default, [buildIdleVideoPlayer].
typedef IdleVideoPlayerBuilder = Widget Function({
  Key? key,
  required String url,
  required VoidCallback onEnded,
  required VoidCallback onError,
});

/// Kitchen Display's idle-screen slideshow — ported from `billing_cafe`'s
/// web Kitchen Display (`app/lib/widgets/idle_media_slideshow.dart`): while
/// no orders are ready, rotates through whatever photos/videos are
/// currently sitting in a shared Google Drive folder
/// (`Env.driveIdleMediaFolderId`) — random order, however many of each the
/// folder happens to hold at any moment, no rebuild needed to add/remove
/// media.
///
/// Fails closed, never stuck or blank: no API key configured, an empty or
/// inaccessible folder, a request error, or a single bad file all fall
/// back to [fallback] (the plain "no orders" idle view) — this is a
/// nice-to-have on top of a working kitchen display, never allowed to
/// break it.
class IdleMediaSlideshow extends StatefulWidget {
  const IdleMediaSlideshow({
    super.key,
    required this.fallback,
    this.fetchMedia,
    this.videoPlayerBuilder = buildIdleVideoPlayer,
    this.imageDuration = const Duration(seconds: 8),
    this.refetchInterval = const Duration(minutes: 10),
  });

  final Widget fallback;

  /// Overridable for tests; defaults to a real Drive API call using
  /// [Env.driveApiKey]/[Env.driveIdleMediaFolderId].
  final DriveMediaFetcher? fetchMedia;
  final IdleVideoPlayerBuilder videoPlayerBuilder;
  final Duration imageDuration;
  final Duration refetchInterval;

  @override
  State<IdleMediaSlideshow> createState() => _IdleMediaSlideshowState();
}

class _IdleMediaSlideshowState extends State<IdleMediaSlideshow> {
  List<DriveMediaItem> _playlist = const [];
  int _index = 0;
  bool _loaded = false;
  Timer? _imageTimer;
  Timer? _refetchTimer;
  DateTime? _lastErrorRefetch;

  /// Floor between error-triggered refetches (separate from the normal
  /// [IdleMediaSlideshow.refetchInterval] timer). A file that's gone from
  /// Drive entirely is fixed for good by one refetch, but a file that's
  /// still *listed* (visible in `files.list`) yet permanently fails
  /// `alt=media` (e.g. a per-file download restriction) would otherwise
  /// come back on every refetch and re-trigger another one immediately —
  /// this bounds that worst case to once a minute instead of a tight loop.
  static const _errorRefetchCooldown = Duration(minutes: 1);

  DriveMediaFetcher get _fetch =>
      widget.fetchMedia ??
      (() => fetchDriveFolderMedia(
            apiKey: Env.driveApiKey,
            folderId: Env.driveIdleMediaFolderId,
          ));

  @override
  void initState() {
    super.initState();
    if (widget.fetchMedia == null && Env.driveApiKey.isEmpty) {
      // No key configured at all — fail closed without ever attempting a
      // request. Set directly, not via setState: initState runs before the
      // first build, so there's nothing to mark dirty yet.
      _loaded = true;
      return;
    }
    unawaited(_refresh(initial: true));
    _refetchTimer = Timer.periodic(widget.refetchInterval, (_) => _refresh(initial: false));
  }

  Future<void> _refresh({required bool initial}) async {
    final currentId =
        _playlist.isNotEmpty && _index < _playlist.length ? _playlist[_index].id : null;
    try {
      final items = await _fetch();
      if (!mounted) return;
      final shuffled = List<DriveMediaItem>.of(items)..shuffle(Random());
      final keepIndex = currentId == null ? -1 : shuffled.indexWhere((i) => i.id == currentId);
      setState(() {
        _playlist = shuffled;
        _loaded = true;
        _index = keepIndex >= 0 ? keepIndex : 0;
      });
      // Only (re)schedule the current slide if it's actually a new slide
      // (first load, or the previously-playing item fell out of the
      // folder) — a background refetch that finds the same item still
      // playing must not restart/interrupt it.
      if (initial || keepIndex < 0) _scheduleCurrent();
    } catch (e) {
      if (kDebugOverlay) DebugLog.add(_tag, 'fetch failed: $e');
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  void _scheduleCurrent() {
    _imageTimer?.cancel();
    _imageTimer = null;
    if (_playlist.isEmpty) return;
    // A video advances itself via its player's onEnded/onError; only images
    // need a local timer.
    if (_playlist[_index].isImage) {
      _imageTimer = Timer(widget.imageDuration, _advance);
    }
  }

  void _advance() {
    if (!mounted || _playlist.isEmpty) return;
    setState(() => _index = (_index + 1) % _playlist.length);
    _scheduleCurrent();
  }

  /// A slide actually failed to load (as opposed to a video simply
  /// finishing) — most often because it was replaced/removed in Drive
  /// since the last folder refetch, so the cached playlist is stale.
  /// Drops the dead item locally right away (so this run stops retrying
  /// it every rotation) and kicks off a fresh `files.list` fetch — rather
  /// than sitting on the stale playlist for up to [refetchInterval] —
  /// bounded by [_errorRefetchCooldown] so a file that's genuinely,
  /// persistently broken can't cause a refetch loop.
  void _handleMediaError(DriveMediaItem failed) {
    if (kDebugOverlay) DebugLog.add(_tag, 'dropping stale slide: ${failed.id}');
    if (!mounted) return;
    setState(() {
      final idx = _playlist.indexWhere((i) => i.id == failed.id);
      if (idx == -1) return;
      _playlist = List.of(_playlist)..removeAt(idx);
      if (_playlist.isNotEmpty) _index %= _playlist.length;
    });
    _scheduleCurrent();

    final now = DateTime.now();
    if (_lastErrorRefetch != null && now.difference(_lastErrorRefetch!) < _errorRefetchCooldown) {
      return;
    }
    _lastErrorRefetch = now;
    unawaited(_refresh(initial: false));
  }

  @override
  void dispose() {
    _imageTimer?.cancel();
    _refetchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_playlist.isEmpty) return widget.fallback;

    final current = _playlist[_index];
    final url = current.mediaUrl(Env.driveApiKey);

    if (current.isVideo) {
      return widget.videoPlayerBuilder(
        key: ValueKey('video-${current.id}'),
        url: url,
        onEnded: _advance,
        onError: () => _handleMediaError(current),
      );
    }

    return Image.network(
      url,
      key: ValueKey('image-${current.id}'),
      headers: driveAndroidAuthHeaders,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        if (kDebugOverlay) DebugLog.add(_tag, 'image load failed: $error');
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleMediaError(current));
        return const SizedBox.shrink();
      },
    );
  }
}
*/
