import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/features/library/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TrackTile: renders, favorite toggles offline-first, onTap fires', (tester) async {
    final db = await AudilocDatabase.openInMemory();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    const track = Track(id: 't1', path: '/a.mp3', title: 'Song', artist: 'Artist', album: 'Album');
    var tapped = false;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: TrackTile(track: track, onTap: () => tapped = true)),
      ),
    ));
    await tester.pump();

    expect(find.text('Song'), findsOneWidget);
    expect(find.textContaining('Artist'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    // The write goes through sqflite_common_ffi's background isolate.
    // Plain pump() still drains the event loop each call (unlike
    // pump(duration), which only fast-forwards flutter_test's simulated
    // clock) — a handful of them is enough for the isolate round trip to
    // land without needing runAsync()/container.listen(), both of which
    // were observed to hang the *next* test's teardown in this Flutter
    // version when mixed with real async I/O inside a widget test.
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      if (find.byIcon(Icons.favorite).evaluate().isNotEmpty) break;
    }

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);

    await tester.tap(find.text('Song'));
    expect(tapped, isTrue);
  });
}
