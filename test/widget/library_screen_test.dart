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

void main() {
  testWidgets('LibraryScreen: empty state, then lists tracks once imported', (tester) async {
    final db = await AudilocDatabase.openInMemory();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
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
    // Plain pump() drains the event loop each call, letting the
    // sqflite_common_ffi isolate's initial (empty) query response land.
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      if (find.text('Библиотека пуста').evaluate().isNotEmpty) break;
    }

    expect(find.text('Библиотека пуста'), findsOneWidget);

    await TracksRepository(db.crdt).upsert(const Track(id: 't1', path: '/a.mp3', title: 'Song A'));
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      if (find.text('Song A').evaluate().isNotEmpty) break;
    }

    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Библиотека пуста'), findsNothing);
  });
}
