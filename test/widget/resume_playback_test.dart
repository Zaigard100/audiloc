import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/playback_state.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/playback_state_repository.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/features/player/providers/player_providers.dart';
import 'package:audiloc/features/player/widgets/resume_playback_prompt.dart';
import 'package:audiloc/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_player_service.dart';

/// Reproduces exactly what `AppShell.initState()` does for the
/// cross-device half of docs/adr/0029-playback-state-sync.md — subscribes
/// to `playbackStateProvider` with `fireImmediately: true`, same as the
/// real app — without pulling in all of `AppShell`'s other unrelated
/// providers (pairing/share-offer listeners, the four tab screens, ...).
/// Restoring *this* device's own last session is a separate mechanism now
/// — see `local_session_restore_test.dart`.
class _RestoreHarness extends ConsumerStatefulWidget {
  const _RestoreHarness();

  @override
  ConsumerState<_RestoreHarness> createState() => _RestoreHarnessState();
}

class _RestoreHarnessState extends ConsumerState<_RestoreHarness> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(playbackStateProvider, (previous, next) {
      final state = next.value;
      if (state != null) handleIncomingPlaybackState(context, ref, state);
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late AudilocDatabase db;
  late FakePlayerService playerService;

  const self = Device(id: 'self', name: 'Ноутбук');
  const track = Track(id: 't1', path: '/a.mp3', title: 'Song A', artist: 'Artist');

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    playerService = FakePlayerService();
  });

  tearDown(() async {
    await playerService.dispose();
    await db.close();
  });

  testWidgets(
      'a row this same device wrote is never applied through the cross-device path — '
      "restoring this device's own session is local_session_restore.dart's job now",
      (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      await PlaybackStateRepository(db.crdt).save(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'self',
        deviceName: 'Ноутбук',
      ));

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        selfDeviceProvider.overrideWithValue(self),
        currentReceivePlaybackStateSyncProvider.overrideWith((ref) => true),
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

  testWidgets(
      'tapping "Продолжить" on the resume snackbar seeks to the saved position and '
      'starts playing immediately — regression: it previously always restarted from 0, '
      'and required a second manual tap on play',
      (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      // A different device's row — with something already loaded locally
      // (below), this is exactly the "ask first" branch, not the silent
      // cold-start one covered by the test above.
      await PlaybackStateRepository(db.crdt).save(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'other-device',
        deviceName: 'Телефон',
      ));
      playerService.emitTrack(const Track(id: 'already-playing', path: '/b.mp3', title: 'Other'));

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        selfDeviceProvider.overrideWithValue(self),
        // The row's deviceId ('other-device') isn't self, so
        // handleIncomingPlaybackState now gates on the "принимать"
        // setting before it even resolves the queue — on here since
        // this test is specifically about that "ask first" path, not
        // about the setting itself.
        currentReceivePlaybackStateSyncProvider.overrideWith((ref) => true),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: _RestoreHarness()),
        ),
      ));

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.text('Продолжить').evaluate().isNotEmpty) break;
      }
      expect(find.text('Продолжить'), findsOneWidget);
      // Just showing the snackbar must not have applied anything yet.
      expect(playerService.lastQueue, isEmpty);

      // Let the snackbar's entrance animation finish — tapping mid-slide-in
      // hits nothing (flutter_test's hit-test warning) and the action
      // never fires.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить'));
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (playerService.lastQueue.isNotEmpty) break;
      }

      expect(playerService.lastQueue.map((t) => t.id), ['t1']);
      expect(playerService.position, const Duration(milliseconds: 65000));
      expect(playerService.isPlaying, isTrue);
    });
  });

  testWidgets(
      'a state from a different device is ignored entirely when "принимать" is off — '
      'no snackbar, nothing applied', (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      await PlaybackStateRepository(db.crdt).save(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'other-device',
        deviceName: 'Телефон',
      ));

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        selfDeviceProvider.overrideWithValue(self),
        currentReceivePlaybackStateSyncProvider.overrideWith((ref) => false),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: _RestoreHarness()),
        ),
      ));

      for (var i = 0; i < 15; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(find.text('Продолжить'), findsNothing);
      expect(playerService.lastQueue, isEmpty);
    });
  });
}
