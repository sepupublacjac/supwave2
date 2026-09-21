import 'package:flutter_test/flutter_test.dart';
import 'package:supwave_gen2/navidrome/subsonic_client.dart';

void main() {
  test(
    'coverArtUrl/streamUrl return the same URL across repeated calls '
    '(regression: a fresh salt+token per call made cover art flicker, since '
    'Image/CachedNetworkImage treat a changed URL as a brand-new resource)',
    () {
      final client = SubsonicClient(
        serverUrl: 'music.example.com',
        username: 'alice',
        password: 'hunter2',
      );

      final first = client.coverArtUrl('al-123', size: 300);
      final second = client.coverArtUrl('al-123', size: 300);
      expect(second, equals(first));

      final firstStream = client.streamUrl('song-1');
      final secondStream = client.streamUrl('song-1');
      expect(secondStream, equals(firstStream));

      // Different ids still resolve to different URLs, obviously.
      expect(client.coverArtUrl('al-999'), isNot(equals(first)));
    },
  );

  test('a new SubsonicClient instance uses its own salt/token', () {
    final a = SubsonicClient(serverUrl: 'music.example.com', username: 'alice', password: 'x');
    final b = SubsonicClient(serverUrl: 'music.example.com', username: 'alice', password: 'x');
    expect(a.coverArtUrl('al-1'), isNot(equals(b.coverArtUrl('al-1'))));
  });
}
