// Tests for the Google Drive idle-screen slideshow widget — DISABLED,
// along with `lib/widgets/idle_media_slideshow.dart` itself (see that file
// for why).

void main() {}

/*
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitchen_display/services/drive_media.dart';
import 'package:kitchen_display/widgets/idle_media_slideshow.dart';

const _fallbackKey = Key('fallback');
const _fallback = SizedBox(key: _fallbackKey, child: Text('fallback'));

/// Fake video player for tests — there's no web-vs-VM conditional import to
/// lean on here (this project only ever targets native Android), so
/// [IdleMediaSlideshow.videoPlayerBuilder] is injectable instead. This fake
/// reports `onError` one frame after mounting, standing in for "the video
/// couldn't be verified in a headless test environment" the same way the
/// web app's own VM-safe stub does.
class _FakeVideoPlayer extends StatefulWidget {
  const _FakeVideoPlayer({super.key, required this.onError});

  final VoidCallback onError;

  @override
  State<_FakeVideoPlayer> createState() => _FakeVideoPlayerState();
}

class _FakeVideoPlayerState extends State<_FakeVideoPlayer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onError());
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Widget _fakeVideoPlayerBuilder({
  Key? key,
  required String url,
  required VoidCallback onEnded,
  required VoidCallback onError,
}) =>
    _FakeVideoPlayer(key: key, onError: onError);

Future<void> _pumpSlideshow(
  WidgetTester tester, {
  DriveMediaFetcher? fetchMedia,
  Duration imageDuration = const Duration(seconds: 8),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: IdleMediaSlideshow(
        fallback: _fallback,
        fetchMedia: fetchMedia,
        videoPlayerBuilder: _fakeVideoPlayerBuilder,
        imageDuration: imageDuration,
        // Long enough that no test below ever accidentally triggers a
        // background refetch mid-assertion.
        refetchInterval: const Duration(hours: 1),
      ),
    ),
  );
}

void main() {
  group('IdleMediaSlideshow', () {
    testWidgets('with no Drive API key configured, shows the fallback and never fetches',
        (tester) async {
      // No `fetchMedia` override AND the real Env.driveApiKey is empty in
      // every test run (no --dart-define passed) — this is the actual
      // "no key configured" production default path, not a stand-in.
      await tester.pumpWidget(
        MaterialApp(
          home: IdleMediaSlideshow(fallback: _fallback, videoPlayerBuilder: _fakeVideoPlayerBuilder),
        ),
      );
      await tester.pump();

      expect(find.byKey(_fallbackKey), findsOneWidget);
    });

    testWidgets('an empty Drive folder falls back to the plain idle view', (tester) async {
      await _pumpSlideshow(tester, fetchMedia: () async => const []);
      await tester.pump();

      expect(find.byKey(_fallbackKey), findsOneWidget);
    });

    testWidgets('a Drive fetch error falls back to the plain idle view, never throws',
        (tester) async {
      await _pumpSlideshow(tester, fetchMedia: () async => throw const DriveMediaException('boom'));
      await tester.pump();

      expect(find.byKey(_fallbackKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an image-only playlist auto-advances to the next slide after imageDuration',
        (tester) async {
      await _pumpSlideshow(
        tester,
        imageDuration: const Duration(seconds: 1),
        fetchMedia: () async => const [
          DriveMediaItem(id: 'imgA', mimeType: 'image/jpeg'),
          DriveMediaItem(id: 'imgB', mimeType: 'image/jpeg'),
        ],
      );
      await tester.pump();

      expect(find.byKey(_fallbackKey), findsNothing);
      final firstImage = tester.widget<Image>(find.byType(Image));
      final firstUrl = (firstImage.image as NetworkImage).url;
      expect(firstUrl, anyOf(contains('imgA'), contains('imgB')));

      await tester.pump(const Duration(seconds: 1));

      final secondImage = tester.widget<Image>(find.byType(Image));
      final secondUrl = (secondImage.image as NetworkImage).url;
      expect(secondUrl, isNot(firstUrl));
    });

    testWidgets('a video-only playlist advances once the (fake) player reports onError',
        (tester) async {
      await _pumpSlideshow(
        tester,
        fetchMedia: () async => const [
          DriveMediaItem(id: 'vidA', mimeType: 'video/mp4'),
          DriveMediaItem(id: 'vidB', mimeType: 'video/mp4'),
        ],
      );
      await tester.pump();
      // The fake video player reports onError one frame after mounting —
      // that's the trigger that should advance the slideshow off the first
      // video.
      await tester.pump();

      expect(find.byKey(_fallbackKey), findsNothing);
      // Whichever of the two shuffled videos is now showing, it's the fake
      // player (SizedBox.shrink) rather than the fallback — confirms the
      // slideshow didn't collapse to the empty/fallback state.
    });

    testWidgets(
        'a failed slide is dropped immediately and triggers a background refetch '
        'instead of waiting for the next scheduled poll', (tester) async {
      var fetchCount = 0;
      await _pumpSlideshow(
        tester,
        fetchMedia: () async {
          fetchCount++;
          return const [
            DriveMediaItem(id: 'vidA', mimeType: 'video/mp4'),
            DriveMediaItem(id: 'vidB', mimeType: 'video/mp4'),
          ];
        },
      );
      expect(fetchCount, 1);

      // The fake video player reports onError one frame after mounting —
      // that error should drop the dead slide and immediately kick off
      // another fetch, rather than sitting on it for the (1-hour, in this
      // test) scheduled refetchInterval.
      await tester.pump();

      expect(fetchCount, 2);
      expect(find.byKey(_fallbackKey), findsNothing);
    });
  });
}
*/
