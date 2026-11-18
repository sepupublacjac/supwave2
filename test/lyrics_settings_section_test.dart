import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart' show Color, Scaffold, SingleChildScrollView, Size;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supwave_gen2/state/lyrics_settings.dart';
import 'package:supwave_gen2/widgets/lyrics_settings_section.dart';

void main() {
  late LyricsSettings settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    settings = LyricsSettings();
  });

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      M3EMaterialApp(
        data: M3EThemeData.light(seedColor: const Color(0xFF6750A4)),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChangeNotifierProvider<LyricsSettings>.value(
              value: settings,
              child: const LyricsSettingsSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows every lyrics option with the providers from the design', (tester) async {
    await pumpSection(tester);

    expect(find.text('Lyrics'), findsOneWidget);
    expect(find.text('Prefer local lyrics'), findsOneWidget);
    expect(find.text('Fetch lyrics from the internet'), findsOneWidget);
    expect(find.text('Providers to fetch lyrics from'), findsOneWidget);
    expect(find.text('NetEase'), findsOneWidget);
    expect(find.text('lrclib.net'), findsOneWidget);
    expect(find.text('Enable NetEase translations'), findsOneWidget);
    expect(find.text('Lyric offset (ms)'), findsOneWidget);
    expect(find.byType(M3ETextField), findsOneWidget);
  });

  testWidgets('tapping a row flips its setting', (tester) async {
    await pumpSection(tester);

    expect(settings.preferLocal, isTrue);
    await tapAndSettle(tester, find.text('Prefer local lyrics'));
    expect(settings.preferLocal, isFalse);

    expect(settings.fetchFromInternet, isFalse);
    await tapAndSettle(tester, find.text('Fetch lyrics from the internet'));
    expect(settings.fetchFromInternet, isTrue);
  });

  testWidgets('the providers and translations are inert until internet lookup is on', (tester) async {
    await pumpSection(tester);

    await tapAndSettle(tester, find.text('lrclib.net'));
    await tapAndSettle(tester, find.text('Enable NetEase translations'));
    expect(settings.providerIds, ['netease', 'lrclib'], reason: 'chips must not respond while offline');
    expect(settings.neteaseTranslations, isFalse);

    await tapAndSettle(tester, find.text('Fetch lyrics from the internet'));
    await tapAndSettle(tester, find.text('lrclib.net'));
    await tapAndSettle(tester, find.text('Enable NetEase translations'));

    expect(settings.providerIds, ['netease']);
    expect(settings.neteaseTranslations, isTrue);
  });

  testWidgets('the order the providers are tried in is shown and follows the selection', (tester) async {
    await settings.setFetchFromInternet(true);
    await pumpSection(tester);
    expect(find.text('Tried in this order: NetEase → lrclib.net'), findsOneWidget);

    await tapAndSettle(tester, find.text('NetEase')); // off
    expect(find.text('Tried in this order: lrclib.net'), findsOneWidget);

    await tapAndSettle(tester, find.text('NetEase')); // on again, now last
    expect(find.text('Tried in this order: lrclib.net → NetEase'), findsOneWidget);

    await tapAndSettle(tester, find.text('NetEase'));
    await tapAndSettle(tester, find.text('lrclib.net'));
    expect(find.text('No provider selected'), findsOneWidget);
  });

  testWidgets('the offset buttons step by 100 ms and the field follows', (tester) async {
    await pumpSection(tester);

    await tapAndSettle(tester, find.byIcon(M3EIcons.add));
    await tapAndSettle(tester, find.byIcon(M3EIcons.add));
    expect(settings.offsetMs, 200);
    expect(find.text('200'), findsOneWidget);

    await tapAndSettle(tester, find.byIcon(M3EIcons.remove));
    await tapAndSettle(tester, find.byIcon(M3EIcons.remove));
    await tapAndSettle(tester, find.byIcon(M3EIcons.remove));
    expect(settings.offsetMs, -100);
    expect(find.text('-100'), findsOneWidget);
  });

  testWidgets('typing an offset applies it, and a half-typed value changes nothing', (tester) async {
    await pumpSection(tester);

    await tester.enterText(find.byType(M3ETextField), '250');
    await tester.pump();
    expect(settings.offsetMs, 250);

    await tester.enterText(find.byType(M3ETextField), '-');
    await tester.pump();
    expect(settings.offsetMs, 250, reason: '"-" is not a number yet');

    await tester.enterText(find.byType(M3ETextField), '-1500');
    await tester.pump();
    expect(settings.offsetMs, -1500);
  });

  testWidgets('the field only takes digits and a leading minus', (tester) async {
    await pumpSection(tester);

    await tester.enterText(find.byType(M3ETextField), 'ab12.5x');
    await tester.pump();

    expect(settings.offsetMs, 125);
  });

  testWidgets('opens showing the saved settings', (tester) async {
    await settings.setFetchFromInternet(true);
    await settings.setOffsetMs(750);
    await settings.setProviderEnabled('netease', false);
    await pumpSection(tester);

    expect(find.text('750'), findsOneWidget);
    expect(find.text('Tried in this order: lrclib.net'), findsOneWidget);
  });
}
