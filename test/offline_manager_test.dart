import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/models/song.dart';
import 'package:supwave_gen2/state/offline_manager.dart';

import 'fakes/fake_navidrome_repository.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Test song $id',
  artist: 'Test Artist',
  artistId: 'ar1',
  album: 'Test Album',
  albumId: 'al1',
  duration: const Duration(seconds: 30),
);

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('supwave_offline_manager_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('download writes the file to disk and marks the song as downloaded', () async {
    final mockClient = MockClient((request) async {
      return http.Response.bytes(List.generate(64, (i) => i), 200);
    });
    final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
    await manager.init(directoryOverride: tempDir);
    final song = _song('s1');

    expect(manager.isDownloaded(song.id), isFalse);
    expect(manager.localPathFor(song.id), isNull);

    await manager.download(song);

    expect(manager.isDownloaded(song.id), isTrue);
    expect(manager.isDownloading(song.id), isFalse);
    final path = manager.localPathFor(song.id);
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    expect(File(path).lengthSync(), 64);
  });

  test('remove deletes the file and clears the downloaded flag', () async {
    final mockClient = MockClient((request) async => http.Response.bytes([1, 2, 3], 200));
    final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
    await manager.init(directoryOverride: tempDir);
    final song = _song('s2');

    await manager.download(song);
    expect(manager.isDownloaded(song.id), isTrue);

    await manager.remove(song);

    expect(manager.isDownloaded(song.id), isFalse);
    expect(manager.localPathFor(song.id), isNull);
    expect(File('${tempDir.path}/${song.id}').existsSync(), isFalse);
  });

  test('a failed download (non-200) leaves the song not downloaded', () async {
    final mockClient = MockClient((request) async => http.Response('nope', 404));
    final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
    await manager.init(directoryOverride: tempDir);
    final song = _song('s3');

    await manager.download(song);

    expect(manager.isDownloaded(song.id), isFalse);
    expect(manager.isDownloading(song.id), isFalse);
  });

  test('init reconciles ids whose file no longer exists on disk', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('offline_downloaded_song_ids', ['ghost-song']);

    final manager = OfflineManager(
      FakeNavidromeRepository(),
      httpClient: MockClient((request) async => http.Response('', 200)),
    );
    await manager.init(directoryOverride: tempDir);

    expect(manager.isDownloaded('ghost-song'), isFalse);
  });

  test('init survives across a fresh manager instance (persisted across restarts)', () async {
    final mockClient = MockClient((request) async => http.Response.bytes([9, 9], 200));
    final song = _song('s4');

    final first = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
    await first.init(directoryOverride: tempDir);
    await first.download(song);
    expect(first.isDownloaded(song.id), isTrue);

    // Simulate an app restart: a brand new manager pointed at the same dir.
    final second = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
    await second.init(directoryOverride: tempDir);

    expect(second.isDownloaded(song.id), isTrue);
    expect(second.localPathFor(song.id), isNotNull);
  });

  group('streaming download', () {
    List<String> filesIn(Directory dir) =>
        dir.listSync().map((e) => e.uri.pathSegments.where((p) => p.isNotEmpty).last).toList()..sort();

    test('writes to disk as it receives data instead of buffering the whole file', () async {
      int? partialBytesMidDownload;
      final mockClient = MockClient.streaming((request, body) async {
        Stream<List<int>> chunks() async* {
          yield List.filled(1024, 7);
          // Give the sink time to flush, then look at what's on disk while
          // the response is still open: a buffering implementation has
          // written nothing yet at this point.
          final partial = File('${tempDir.path}/big.part');
          for (var i = 0; i < 40; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (partial.existsSync() && partial.lengthSync() > 0) break;
          }
          partialBytesMidDownload = partial.existsSync() ? partial.lengthSync() : 0;
          yield List.filled(1024, 8);
        }

        return http.StreamedResponse(chunks(), 200, contentLength: 2048);
      });
      final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
      await manager.init(directoryOverride: tempDir);

      await manager.download(_song('big'));

      expect(partialBytesMidDownload, greaterThan(0));
      expect(manager.isDownloaded('big'), isTrue);
      expect(File(manager.localPathFor('big')!).lengthSync(), 2048);
      expect(filesIn(tempDir), ['big'], reason: 'the .part file must be renamed away');
    });

    test('a connection that drops mid-download leaves no file and no .part behind', () async {
      final mockClient = MockClient.streaming((request, body) async {
        Stream<List<int>> chunks() async* {
          yield List.filled(512, 1);
          throw const SocketException('connection reset');
        }

        return http.StreamedResponse(chunks(), 200, contentLength: 4096);
      });
      final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
      await manager.init(directoryOverride: tempDir);

      await manager.download(_song('dropped'));

      expect(manager.isDownloaded('dropped'), isFalse);
      expect(manager.isDownloading('dropped'), isFalse);
      expect(filesIn(tempDir), isEmpty);
    });

    test('a response shorter than its Content-Length is rejected, not kept', () async {
      final mockClient = MockClient.streaming((request, body) async {
        return http.StreamedResponse(Stream.value(List.filled(10, 1)), 200, contentLength: 100);
      });
      final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
      await manager.init(directoryOverride: tempDir);

      await manager.download(_song('short'));

      expect(manager.isDownloaded('short'), isFalse);
      expect(filesIn(tempDir), isEmpty);
    });

    test('an HTTP error status leaves nothing on disk', () async {
      final mockClient = MockClient((request) async => http.Response('nope', 500));
      final manager = OfflineManager(FakeNavidromeRepository(), httpClient: mockClient);
      await manager.init(directoryOverride: tempDir);

      await manager.download(_song('err'));

      expect(manager.isDownloaded('err'), isFalse);
      expect(manager.isDownloading('err'), isFalse);
      expect(filesIn(tempDir), isEmpty);
    });

    test('init removes .part files left behind by a download that was killed', () async {
      File('${tempDir.path}/killed.part').writeAsBytesSync([1, 2, 3]);
      final manager = OfflineManager(
        FakeNavidromeRepository(),
        httpClient: MockClient((request) async => http.Response('', 200)),
      );

      await manager.init(directoryOverride: tempDir);

      expect(filesIn(tempDir), isEmpty);
    });
  });
}
