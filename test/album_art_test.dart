import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supwave_gen2/widgets/album_art.dart';

/// Regression coverage for the album art cache surviving app restarts.
///
/// SubsonicClient generates a fresh random auth token on every app launch,
/// so the same cover art gets a *different* `coverArtUrl` each time the app
/// is cold-started. CachedNetworkImage keys its disk cache by URL unless
/// told otherwise, so without a stable `cacheKey`, every restart would look
/// like a brand-new image and re-hit the server instead of using what's
/// already on disk.
void main() {
  Future<CachedNetworkImage> pumpAndFindImage(WidgetTester tester, String coverUrl) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: AlbumArt(coverUrl: coverUrl, seed: 'song-1'))),
    );
    return tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
  }

  testWidgets(
    'the same cover art gets the same cacheKey across two different session tokens',
    (tester) async {
      // Same server/id/size, but different u/t/s (as if from two separate
      // app launches, each generating its own random salt+token).
      const sessionOneUrl =
          'https://server.test/rest/getCoverArt.view'
          '?id=cover-1&size=300&u=alice&t=aaa111&s=saltone&v=1.16.1&c=Supwave';
      const sessionTwoUrl =
          'https://server.test/rest/getCoverArt.view'
          '?id=cover-1&size=300&u=alice&t=bbb222&s=salttwo&v=1.16.1&c=Supwave';

      final imageOne = await pumpAndFindImage(tester, sessionOneUrl);
      final imageTwo = await pumpAndFindImage(tester, sessionTwoUrl);

      expect(imageOne.cacheKey, isNotNull);
      expect(imageOne.cacheKey, equals(imageTwo.cacheKey));
      // The auth token really did change - this isn't a trivial pass.
      expect(sessionOneUrl, isNot(equals(sessionTwoUrl)));
    },
  );

  testWidgets('different cover ids still get different cacheKeys', (tester) async {
    const coverOneUrl =
        'https://server.test/rest/getCoverArt.view?id=cover-1&size=300&u=a&t=x&s=y&v=1&c=Supwave';
    const coverTwoUrl =
        'https://server.test/rest/getCoverArt.view?id=cover-2&size=300&u=a&t=x&s=y&v=1&c=Supwave';

    final imageOne = await pumpAndFindImage(tester, coverOneUrl);
    final imageTwo = await pumpAndFindImage(tester, coverTwoUrl);

    expect(imageOne.cacheKey, isNot(equals(imageTwo.cacheKey)));
  });
}
