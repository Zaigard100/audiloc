import 'package:audiloc/core/providers.dart';
import 'package:audiloc/core/theme/app_theme.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/features/player/mini_player.dart';
import 'package:audiloc/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_service.dart';

void main() {
  late AudilocDatabase db;
  late FakePlayerService playerService;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    playerService = FakePlayerService();
  });

  tearDown(() async {
    await playerService.dispose();
    await db.close();
  });

  Widget buildApp() => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          selfDeviceProvider.overrideWithValue(const Device(id: 'self', name: 'Test device')),
          playerServiceProvider.overrideWithValue(playerService),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink(), bottomNavigationBar: MiniPlayer()),
        ),
      );

  testWidgets('renders nothing when nothing is playing', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.byType(SizedBox), findsWidgets); // the shrink-wrapped empty state
  });

  testWidgets('shows track title and artist once playback starts', (tester) async {
    await tester.pumpWidget(buildApp());
    playerService.emitTrack(const Track(id: 't1', path: '/a.mp3', title: 'My Song', artist: 'My Artist'));
    await tester.pump();

    expect(find.text('My Song'), findsOneWidget);
    expect(find.text('My Artist'), findsOneWidget);
  });

  testWidgets('tapping play/pause toggles the fake player', (tester) async {
    await tester.pumpWidget(buildApp());
    playerService.emitTrack(const Track(id: 't1', path: '/a.mp3', title: 'My Song'));
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_circle_filled));
    await tester.pump();

    expect(playerService.isPlaying, isTrue);
    expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
  });

  testWidgets('tapping the bar opens the full player', (tester) async {
    await tester.pumpWidget(buildApp());
    playerService.emitTrack(const Track(id: 't1', path: '/a.mp3', title: 'My Song'));
    await tester.pump();

    await tester.tap(find.text('My Song'));
    await tester.pumpAndSettle();

    expect(find.text('Сейчас играет'), findsOneWidget);
  });
}
