// Google Drive-backed idle-screen media service — DISABLED.
//
// The kitchen display's idle screen now shows a static logo
// (`_IdleView` in `lib/screens/kitchen_display_screen.dart`) instead of a
// slideshow pulled from a shared Google Drive folder. Left here, commented
// out, rather than deleted, in case the slideshow needs to come back.
//
// Also disabled: `lib/widgets/idle_media_slideshow.dart` (the widget that
// used this service) and `lib/widgets/idle_video_player.dart` (its video
// player), plus the `driveApiKey`/`driveIdleMediaFolderId` constants in
// `lib/config/env.dart` and the tests in `test/unit/drive_media_test.dart`
// and `test/unit/idle_media_slideshow_test.dart`.

/*
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One playable item from a public Google Drive folder (Kitchen Display's
/// idle-screen slideshow — `IdleMediaSlideshow`). Only `image` / `video`
/// mime types are ever returned by [fetchDriveFolderMedia]'s query — any
/// other file dropped in the folder (a doc, a zip, ...) is simply invisible
/// to the display.
///
/// Ported unchanged from `billing_cafe`'s web Kitchen Display
/// (`app/lib/services/drive_media.dart`) — pure `http` calls, no
/// platform-specific code, so it works identically on native Android.
class DriveMediaItem {
  final String id;
  final String mimeType;

  const DriveMediaItem({required this.id, required this.mimeType});

  bool get isVideo => mimeType.startsWith('video/');
  bool get isImage => mimeType.startsWith('image/');

  /// Direct byte-serving URL — works as-is for both an `Image.network` and a
  /// video player source, no separate download/confirmation step (unlike
  /// Drive's `uc?export=download` links, which can interpose a virus-scan
  /// warning page for larger files).
  String mediaUrl(String apiKey) =>
      'https://www.googleapis.com/drive/v3/files/$id?alt=media&key=$apiKey';

  factory DriveMediaItem.fromJson(Map<String, dynamic> json) =>
      DriveMediaItem(id: json['id'] as String, mimeType: json['mimeType'] as String);
}

class DriveMediaException implements Exception {
  final String message;
  const DriveMediaException(this.message);

  @override
  String toString() => 'DriveMediaException: $message';
}

/// Headers required on every Drive API request because the API key is
/// restricted to "Android apps" in Google Cloud Console, and these are
/// plain REST calls rather than calls made through Google's native Android
/// SDK (which sets these headers automatically). Without them Google sees
/// the request as coming from no app at all (`androidPackage: <empty>`)
/// and blocks it outright, regardless of what app is actually calling.
///
/// NOTE: `android/app/build.gradle.kts` currently signs the release build
/// with the debug keystore (see the TODO there), so this is the debug
/// key's SHA-1 fingerprint. Update this constant *and* the Android app
/// restriction entry in Cloud Console together whenever the signing
/// config switches to a real release keystore.
const Map<String, String> driveAndroidAuthHeaders = {
  'X-Android-Package': 'com.whynotcafe.kitchen_display',
  'X-Android-Cert': '6de40c32a5b8dfde2893271bf3768ec7e500524f',
};

/// Lists the image/video files directly inside [folderId] via the Google
/// Drive API v3 `files.list` endpoint. The folder must be shared "Anyone
/// with the link" for an unauthenticated, API-key-only request to see it.
///
/// Never throws on an empty or genuinely-empty-of-media folder (returns
/// `[]`) — only throws [DriveMediaException] on an actual request failure
/// (bad/missing key, network error, non-200, unexpected response shape),
/// so a caller can tell "no media configured" apart from "something's
/// actually wrong" and react differently (see `IdleMediaSlideshow`).
Future<List<DriveMediaItem>> fetchDriveFolderMedia({
  required String apiKey,
  required String folderId,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
    'q': "'$folderId' in parents and trashed = false and "
        "(mimeType contains 'image/' or mimeType contains 'video/')",
    'fields': 'files(id,mimeType)',
    'pageSize': '1000',
    'key': apiKey,
  });

  final http.Response response;
  try {
    response = await httpClient.get(uri, headers: driveAndroidAuthHeaders);
  } catch (e) {
    throw DriveMediaException('Drive API request failed: $e');
  } finally {
    if (client == null) httpClient.close();
  }

  if (response.statusCode != 200) {
    throw DriveMediaException('Drive API returned ${response.statusCode}: ${response.body}');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } catch (e) {
    throw DriveMediaException('Drive API returned unparseable JSON: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const DriveMediaException('Unexpected Drive API response shape (not an object)');
  }

  final rawFiles = decoded['files'];
  if (rawFiles is! List) return const [];

  return rawFiles
      .whereType<Map<String, dynamic>>()
      .where((f) => f['id'] is String && f['mimeType'] is String)
      .map(DriveMediaItem.fromJson)
      .toList();
}
*/
