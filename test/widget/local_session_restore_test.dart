import 'dart:io';

import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/local_playback_state_store.dart';
import 'package:audiloc/data/models/playback_state.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/features/player/widgets/local_session_restore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_service.dart';

/// Reproduces exactly what `AppShell.initState()` does for local-session
/// restore, without pulling in the rest of `AppShell`.
class _RestoreHarness extends ConsumerStatefulWidget {
  const _RestoreHarness();

  @override
  ConsumerState<_RestoreHarness> createState() => _RestoreHarnessState();
}

class _RestoreHarnessState extends ConsumerState<_RestoreHarness> {
  @override
  void initState() {
    super.initState();
    restoreLocalSession(ref);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late AudilocDatabase db;
  late Directory profileDir;
  late LocalPlaybackStateStore localStore;
  late FakePlayerService playerService;

  const track = Track(id: 't1', path: '/a.mp3', title: 'Song A', artist: 'Artist');

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    profileDir = await Directory.systemTemp.createTemp('audiloc_local_restore_test_');
    localStore = LocalPlaybackStateStore(profileDir);
    playerService = FakePlayerService();
  });

  tearDown(() async {
    await playerService.dispose();
    await db.close();
    await profileDir.delete(recursive: true);
  });

  testWidgets('a locally-saved session is restored, paused, at the saved position', (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      await localStore.write(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'self',
        deviceName: 'Ноутбук',
      ));

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        localPlaybackStateStoreProvider.overrideWithValue(localStore),
        currentSaveLocalSessionProvider.overrideWith((ref) => true),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _RestoreHarness()),
      ));

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (playerService.lastQueue.isNotEmpty) break;
      }

      expect(playerService.lastQueue.map((t) => t.id), ['t1']);
      expect(playerService.position, const Duration(milliseconds: 65000));
      expect(playerService.isPlaying, isFalse);
    });
  });

  testWidgets('nothing is restored when "сохранять состояние прошлой сессии" is off, '
      'even though a session is saved locally', (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      await localStore.write(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'self',
        deviceName: 'Ноутбук',
      ));

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        localPlaybackStateStoreProvider.overrideWithValue(localStore),
        currentSaveLocalSessionProvider.overrideWith((ref) => false),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _RestoreHarness()),
      ));

      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(playerService.lastQueue, isEmpty);
    });
  });

  testWidgets('nothing to restore is a no-op', (tester) async {
    await tester.runAsync(() async {
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        localPlaybackStateStoreProvider.overrideWithValue(localStore),
        currentSaveLocalSessionProvider.overrideWith((ref) => true),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _RestoreHarness()),
      ));

      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(playerService.lastQueue, isEmpty);
    });
  });
}
