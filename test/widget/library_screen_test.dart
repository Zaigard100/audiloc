import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/features/library/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AudilocDatabase db;

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
  });

  tearDown(() => db.close());

  Widget buildApp() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: LibraryScreen()),
      );

  testWidgets('shows the empty state when the library has no tracks', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('Библиотека пуста'), findsOneWidget);
  });

  testWidgets('lists tracks once they exist in the repository', (tester) async {
    await TracksRepository(db.crdt).upsert(const Track(id: 't1', path: '/a.mp3', title: 'Song A'));

    await tester.pumpWidget(buildApp());
    await tester.pump();

    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Библиотека пуста'), findsNothing);
  });
}
