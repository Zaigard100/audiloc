import 'package:audiloc/core/providers.dart';
import 'package:audiloc/core/theme/app_theme.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/features/library/widgets/track_tile.dart';
import 'package:audiloc/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_service.dart';

void main() {
  late AudilocDatabase db;

  // Opening the (Isolate-backed, sqflite_common_ffi) db here rather than
  // as the first `await` inside the `testWidgets` body — doing it there
  // deadlocks `pumpWidget` right after, apparently because the Isolate
  // port round-trip and flutter_test's own zone/frame-pumping don't mix
  // when both happen inside the same test-body zone. `setUp` runs
  // outside that zone, so this dodges it entirely — same pattern already
  // used successfully in mini_player_test.dart.
  setUp(() async {
    db = await AudilocDatabase.openInMemory();
  });

  tearDown(() => db.close());

  testWidgets('TrackTile: renders, favorite toggles offline-first, onTap fires', (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      // TrackTile now watches currentTrackProvider/isPlayingProvider (the
      // "highlight what's playing" feature, docs/adr/0029) — those chain
      // to playerServiceProvider, whose real implementation is
      // MediaKitPlayerService and needs libmpv initialized. Not overriding
      // it here is what made this test hang.
      playerServiceProvider.overrideWithValue(FakePlayerService()),
    ]);
    addTearDown(container.dispose);

    const track = Track(id: 't1', path: '/a.mp3', title: 'Song', artist: 'Artist', album: 'Album');
    var tapped = false;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TrackTile(track: track, onTap: () => tapped = true)),
      ),
    ));
    await tester.pump();

    expect(find.text('Song'), findsOneWidget);
    expect(find.textContaining('Artist'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    // The write goes through sqflite_common_ffi's background isolate.
    // Plain `pump()` never gives that real Isolate round trip a chance to
    // land — it only drains already-queued microtasks/frame callbacks, so
    // `favoriteIdsProvider` sits on AsyncLoading forever without this.
    // `runAsync` is what actually lets real async I/O interleave with
    // pumped frames (the standard Flutter-test way to do this); a real
    // delay between pumps is needed too, not just the pumps themselves.
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byIcon(Icons.favorite).evaluate().isNotEmpty) break;
      }
    });

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.text('Song'));
    expect(tapped, isTrue);
  });

  testWidgets('tapping the already-current track toggles play/pause instead of restarting it',
      (tester) async {
    // `runAsync` — `TrackTile` now watches `activePlaybackCurrentTrackProvider`/
    // `activePlaybackIsPlayingProvider` (docs/adr/0033-playback-ownership-and-handoff.md),
    // which chain to a real CRDT/sqflite query
    // (`profileSyncEnabledProvider`); without this the underlying
    // sqflite transaction lock's own internal timer never gets to
    // actually resolve inside the fake-async test zone — same
    // reasoning as `mini_player_test.dart`'s use of `runAsync`.
    await tester.runAsync(() async {
      final player = FakePlayerService();
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(player),
      ]);
      addTearDown(container.dispose);

      const track = Track(id: 't1', path: '/a.mp3', title: 'Song', artist: 'Artist', album: 'Album');
      var tapped = false;

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TrackTile(track: track, onTap: () => tapped = true)),
        ),
      ));
      await tester.pump();

      // Not current yet — tapping still just fires the caller's onTap
      // (opens/starts the queue at this row), same as any other tile.
      await tester.tap(find.text('Song'));
      expect(tapped, isTrue);
      expect(player.isPlaying, isFalse);

      tapped = false;
      player.emitTrack(track);
      player.emitPlaying(true);
      // `isCurrent`/`isPlaying` now come from
      // `activePlaybackCurrentTrackProvider`/`activePlaybackIsPlayingProvider`
      // (docs/adr/0033-playback-ownership-and-handoff.md), which chain
      // through `activePlaybackTargetProvider` -> `profileSyncEnabledProvider`
      // -> a real CRDT/sqflite query — same real-Isolate-round-trip
      // reasoning as the favorite-toggle poll loop above, not just an
      // extra same-tick provider hop, so a fixed couple of `pump()`s
      // isn't reliably enough; poll for the "now playing" badge instead.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.byIcon(Icons.volume_up).evaluate().isNotEmpty) break;
      }
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Now current and playing — tapping the same row pauses it instead
      // of restarting it from 0, and does *not* call the caller's onTap.
      await tester.tap(find.text('Song'));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (!player.isPlaying) break;
      }
      expect(tapped, isFalse);
      expect(player.isPlaying, isFalse);

      // Tapping again while current and paused resumes it.
      await tester.tap(find.text('Song'));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (player.isPlaying) break;
      }
      expect(tapped, isFalse);
      expect(player.isPlaying, isTrue);
    });
  });
}
