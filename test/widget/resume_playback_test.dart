import 'package:audiloc/core/providers.dart';
import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/playback_state.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/playback_state_repository.dart';
import 'package:audiloc/data/repositories/profile_settings_repository.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/features/player/providers/player_providers.dart';
import 'package:audiloc/features/player/widgets/resume_playback_prompt.dart';
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
      if (state != null) handleIncomingPlaybackState(ref, state);
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
      await ProfileSettingsRepository(db.crdt).setSyncPlaybackEnabled(true);

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        selfDeviceProvider.overrideWithValue(self),
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
      'a different device\'s row is left alone entirely when something is already loaded '
      'locally — no prompt, nothing overwritten (the old "Продолжить" snackbar was removed '
      'at the user\'s request once the live ownership protocol, docs/adr/0033, made it '
      'redundant)', (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      await PlaybackStateRepository(db.crdt).save(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'other-device',
        deviceName: 'Телефон',
      ));
      await ProfileSettingsRepository(db.crdt).setSyncPlaybackEnabled(true);
      playerService.emitTrack(const Track(id: 'already-playing', path: '/b.mp3', title: 'Other'));

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        selfDeviceProvider.overrideWithValue(self),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _RestoreHarness()),
      ));

      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }

      expect(find.text('Продолжить'), findsNothing);
      // The already-loaded track is untouched — nothing from the
      // incoming row was ever applied.
      expect(playerService.lastQueue, isEmpty);
    });
  });

  testWidgets(
      'a state from a different device is ignored entirely when the sync toggle is off — '
      'nothing applied', (tester) async {
    await tester.runAsync(() async {
      await TracksRepository(db.crdt).upsert(track);
      await PlaybackStateRepository(db.crdt).save(const PlaybackState(
        trackId: 't1',
        positionMs: 65000,
        queueType: PlaybackQueueType.library,
        deviceId: 'other-device',
        deviceName: 'Телефон',
      ));
      // Off by default — no explicit write needed, but left implicit on
      // purpose so this test exercises the real default, not a value it
      // set itself.

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        playerServiceProvider.overrideWithValue(playerService),
        selfDeviceProvider.overrideWithValue(self),
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
