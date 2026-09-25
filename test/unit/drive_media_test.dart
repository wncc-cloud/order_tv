// Tests for the Google Drive idle-screen media service — DISABLED, along
// with `lib/services/drive_media.dart` itself (see that file for why).

void main() {}

/*
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kitchen_display/services/drive_media.dart';

void main() {
  group('DriveMediaItem', () {
    test('isVideo/isImage classify by mime type prefix', () {
      expect(const DriveMediaItem(id: 'a', mimeType: 'video/mp4').isVideo, isTrue);
      expect(const DriveMediaItem(id: 'a', mimeType: 'video/mp4').isImage, isFalse);
      expect(const DriveMediaItem(id: 'b', mimeType: 'image/jpeg').isImage, isTrue);
      expect(const DriveMediaItem(id: 'b', mimeType: 'image/jpeg').isVideo, isFalse);
    });

    test('mediaUrl builds a direct alt=media Drive API URL with the key', () {
      const item = DriveMediaItem(id: 'FILE123', mimeType: 'image/png');
      expect(
        item.mediaUrl('KEY456'),
        'https://www.googleapis.com/drive/v3/files/FILE123?alt=media&key=KEY456',
      );
    });
  });

  group('fetchDriveFolderMedia', () {
    Future<List<DriveMediaItem>> fetchWith(http.Client client) => fetchDriveFolderMedia(
          apiKey: 'test-key',
          folderId: 'folder-1',
          client: client,
        );

    test('parses a well-formed response into items', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['key'], 'test-key');
        expect(request.url.queryParameters['q'], contains('folder-1'));
        return http.Response(
          jsonEncode({
            'files': [
              {'id': 'img1', 'mimeType': 'image/jpeg'},
              {'id': 'vid1', 'mimeType': 'video/mp4'},
            ],
          }),
          200,
        );
      });

      final items = await fetchWith(client);

      expect(items, hasLength(2));
      expect(items[0].id, 'img1');
      expect(items[0].isImage, isTrue);
      expect(items[1].id, 'vid1');
      expect(items[1].isVideo, isTrue);
    });

    test('a document with no files field resolves to an empty list, never throws', () async {
      final client = MockClient((request) async => http.Response(jsonEncode({}), 200));

      expect(await fetchWith(client), isEmpty);
    });

    test('an empty folder (files: []) resolves to an empty list', () async {
      final client = MockClient((request) async => http.Response(jsonEncode({'files': []}), 200));

      expect(await fetchWith(client), isEmpty);
    });

    test('malformed entries (missing id/mimeType) are skipped, not thrown on', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'files': [
                {'id': 'ok1', 'mimeType': 'image/png'},
                {'id': 'no-mime'},
                {'mimeType': 'image/png'},
                {'id': 123, 'mimeType': 'image/png'},
              ],
            }),
            200,
          ));

      final items = await fetchWith(client);

      expect(items, hasLength(1));
      expect(items.single.id, 'ok1');
    });

    test('a non-200 response throws DriveMediaException, not a generic error', () async {
      final client = MockClient((request) async => http.Response('bad key', 403));

      await expectLater(fetchWith(client), throwsA(isA<DriveMediaException>()));
    });

    test('unparseable JSON throws DriveMediaException', () async {
      final client = MockClient((request) async => http.Response('not json', 200));

      await expectLater(fetchWith(client), throwsA(isA<DriveMediaException>()));
    });

    test('a JSON array at the top level (unexpected shape) throws DriveMediaException', () async {
      final client = MockClient((request) async => http.Response(jsonEncode([1, 2, 3]), 200));

      await expectLater(fetchWith(client), throwsA(isA<DriveMediaException>()));
    });

    test('a network failure throws DriveMediaException', () async {
      final client = MockClient((request) async => throw Exception('socket closed'));

      await expectLater(fetchWith(client), throwsA(isA<DriveMediaException>()));
    });
  });
}
*/
