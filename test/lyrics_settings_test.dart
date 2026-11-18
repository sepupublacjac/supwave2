import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/state/lyrics_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A fresh instance, as after an app restart, once it has finished loading.
  Future<LyricsSettings> reloaded() async {
    final settings = LyricsSettings();
    await settings.load();
    return settings;
  }

  test('defaults: server first, internet off, both providers in order, no translations, no offset', () {
    final settings = LyricsSettings();

    expect(settings.preferLocal, isTrue);
    expect(settings.fetchFromInternet, isFalse, reason: 'sending song info to third parties must be opt-in');
    expect(settings.providerIds, ['netease', 'lrclib']);
    expect(settings.neteaseTranslations, isFalse);
    expect(settings.offsetMs, 0);
    expect(settings.offset, Duration.zero);
  });

  test('every setting survives a restart', () async {
    final settings = LyricsSettings();
    await settings.setPreferLocal(false);
    await settings.setFetchFromInternet(true);
    await settings.setNeteaseTranslations(true);
    await settings.setOffsetMs(-250);
    await settings.setProviderEnabled('netease', false);

    final restored = LyricsSettings();
    await restored.load();

    expect(restored.preferLocal, isFalse);
    expect(restored.fetchFromInternet, isTrue);
    expect(restored.neteaseTranslations, isTrue);
    expect(restored.offsetMs, -250);
    expect(restored.providerIds, ['lrclib']);
  });

  test('the order the providers were enabled in is kept, also across restarts', () async {
    final settings = LyricsSettings();
    await settings.setProviderEnabled('netease', false);
    await settings.setProviderEnabled('netease', true);

    expect(settings.providerIds, ['lrclib', 'netease']);
    expect((await reloaded()).providerIds, ['lrclib', 'netease']);
  });

  test('an empty provider list is remembered as empty, not reset to the defaults', () async {
    final settings = LyricsSettings();
    await settings.setProviderEnabled('netease', false);
    await settings.setProviderEnabled('lrclib', false);

    expect((await reloaded()).providerIds, isEmpty);
  });

  test('unknown provider ids (from another version) are ignored, and enabling one is a no-op', () async {
    SharedPreferences.setMockInitialValues({
      'lyrics_providers': ['musixmatch', 'lrclib'],
    });
    final settings = await reloaded();
    expect(settings.providerIds, ['lrclib']);

    await settings.setProviderEnabled('genius', true);
    expect(settings.providerIds, ['lrclib']);
  });

  test('the offset is kept within a sensible range, when set and when loaded', () async {
    final settings = LyricsSettings();

    await settings.setOffsetMs(999999);
    expect(settings.offsetMs, LyricsSettings.maxOffsetMs);
    await settings.setOffsetMs(-999999);
    expect(settings.offsetMs, -LyricsSettings.maxOffsetMs);

    SharedPreferences.setMockInitialValues({'lyrics_offset_ms': 5000000});
    expect((await reloaded()).offsetMs, LyricsSettings.maxOffsetMs);
  });

  test('changing a setting notifies listeners, setting the same value does not', () async {
    final settings = LyricsSettings();
    var notifications = 0;
    settings.addListener(() => notifications++);

    await settings.setFetchFromInternet(true);
    expect(notifications, 1);
    await settings.setFetchFromInternet(true);
    await settings.setOffsetMs(0);
    await settings.setProviderEnabled('netease', true); // already on
    expect(notifications, 1);

    await settings.setOffsetMs(100);
    await settings.setProviderEnabled('netease', false);
    expect(notifications, 3);
  });

  test('sourceSignature moves with source settings but not with the display offset', () async {
    final settings = LyricsSettings();
    final start = settings.sourceSignature;

    await settings.setOffsetMs(400);
    expect(settings.sourceSignature, start);

    for (final change in <Future<void> Function()>[
      () => settings.setPreferLocal(false),
      () => settings.setFetchFromInternet(true),
      () => settings.setNeteaseTranslations(true),
      () => settings.setProviderEnabled('netease', false),
    ]) {
      final before = settings.sourceSignature;
      await change();
      expect(settings.sourceSignature, isNot(before));
    }
  });
}
