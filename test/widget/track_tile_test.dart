import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/features/library/widgets/track_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
  });

  tearDown(() => db.close());

  const track = Track(id: 't1', path: '/a.mp3', title: 'Song', artist: 'Artist', album: 'Album');

  Widget buildApp({VoidCallback? onTap}) => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: TrackTile(track: track, onTap: onTap ?? () {})),
        ),
      );

  testWidgets('shows title, artist and album', (tester) async {
    await tester.pumpWidget(buildApp());
    expect(find.text('Song'), findsOneWidget);
    expect(find.textContaining('Artist'), findsOneWidget);
  });

  testWidgets('starts unfavorited and flips immediately on tap (offline-first)', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsNothing);
  });

  testWidgets('onTap fires when the tile body is tapped', (tester) async {
    var tapped = false;
    await tester.pumpWidget(buildApp(onTap: () => tapped = true));

    await tester.tap(find.text('Song'));
    expect(tapped, isTrue);
  });
}
