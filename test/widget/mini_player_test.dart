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

  // `runAsync` + real-delay poll loops (not just `pump`/`pumpAndSettle`)
  // in every test below — `MiniPlayer`/`FullPlayerScreen` now read the
  // profile-wide sync toggle (docs/adr/0032, ADR 0033's
  // `activePlayback*` providers), a real CRDT/sqflite query; without
  // this the underlying sqflite transaction lock's own internal timer
  // never gets to actually resolve inside the fake-async test zone, and
  // the test fails at teardown with "A Timer is still pending" — same
  // reasoning as `resume_playback_test.dart`'s use of `runAsync`.

  testWidgets('renders nothing when nothing is playing', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.byType(SizedBox), findsWidgets); // the shrink-wrapped empty state
    });
  });

  testWidgets('shows track title and artist once playback starts', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      playerService.emitTrack(const Track(id: 't1', path: '/a.mp3', title: 'My Song', artist: 'My Artist'));
      for (var i = 0; i < 20 && find.text('My Song').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(find.text('My Song'), findsOneWidget);
      expect(find.text('My Artist'), findsOneWidget);
    });
  });

  testWidgets('tapping play/pause toggles the fake player', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      playerService.emitTrack(const Track(id: 't1', path: '/a.mp3', title: 'My Song'));
      for (var i = 0; i < 100 && find.byIcon(Icons.play_circle_filled).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
      expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_circle_filled));
      for (var i = 0; i < 100 && find.byIcon(Icons.pause_circle_filled).evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(playerService.isPlaying, isTrue);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    });
  });

  testWidgets('tapping the bar opens the full player', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(buildApp());
      playerService.emitTrack(const Track(id: 't1', path: '/a.mp3', title: 'My Song'));
      for (var i = 0; i < 100 && find.text('My Song').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      await tester.tap(find.text('My Song'));
      for (var i = 0; i < 30 && find.text('Сейчас играет').evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(find.text('Сейчас играет'), findsOneWidget);
    });
  });
}
