import 'package:audiloc/core/providers.dart';
import 'package:audiloc/core/theme/app_theme.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/features/library/library_screen.dart';
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

  testWidgets('LibraryScreen: empty state, then lists tracks once imported', (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      // Rendered tracks go through TrackTile, which now watches
      // currentTrackProvider/isPlayingProvider (docs/adr/0029) — those
      // chain to playerServiceProvider, whose real implementation needs
      // libmpv initialized. Not overriding it here hangs the test.
      playerServiceProvider.overrideWithValue(FakePlayerService()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LibraryScreen(),
      ),
    ));
    // Plain `pump()` never gives the real sqflite_common_ffi Isolate round
    // trip a chance to land — only `runAsync` actually interleaves real
    // async I/O with pumped frames (see track_tile_test.dart for how this
    // was diagnosed); a real delay between pumps is needed too.
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('Библиотека пуста').evaluate().isNotEmpty) break;
      }
    });

    expect(find.text('Библиотека пуста'), findsOneWidget);

    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(const Track(id: 't1', path: '/a.mp3', title: 'Song A'));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('Song A').evaluate().isNotEmpty) break;
      }
    });

    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Библиотека пуста'), findsNothing);
  });
}
