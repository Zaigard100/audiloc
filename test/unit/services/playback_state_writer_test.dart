import 'dart:async';
import 'dart:io';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/local_playback_state_store.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/playback_state.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/playback_state_repository.dart';
import 'package:audiloc/features/player/models/queue_source.dart';
import 'package:audiloc/services/playback/player_service.dart';
import 'package:audiloc/services/playback/playback_state_writer.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlayerService implements PlayerService {
  final _playingController = StreamController<bool>.broadcast();

  Track? currentTrackValue;
  Duration positionValue = Duration.zero;

  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<PlaybackPositionState> get positionStream => const Stream.empty();
  @override
  Stream<Track?> get currentTrackStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  bool get isPlaying => throw UnimplementedError();
  @override
  Track? get currentTrack => currentTrackValue;
  @override
  Duration get position => positionValue;
  @override
  Future<void> setQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool autoPlay = true,
    Duration? seekTo,
  }) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> playOrPause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> dispose() async => _playingController.close();

  void emitPlaying(bool playing) => _playingController.add(playing);
}

void main() {
  late AudilocDatabase db;
  late PlaybackStateRepository repository;
  late Directory profileDir;
  late LocalPlaybackStateStore localStore;
  late _FakePlayerService player;
  late PlaybackStateWriter writer;

  const device = Device(id: 'device-a', name: 'Ноутбук');
  const track = Track(id: 't1', path: '/a.mp3', title: 'Song');

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    repository = PlaybackStateRepository(db.crdt);
    profileDir = await Directory.systemTemp.createTemp('audiloc_playback_writer_test_');
    localStore = LocalPlaybackStateStore(profileDir);
    player = _FakePlayerService();
    writer = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      localStore: localStore,
      selfDevice: device,
      currentQueueSource: () => const LibraryQueueSource(),
      isSendEnabled: () => true,
      isLocalSaveEnabled: () => true,
    );
    writer.start();
  });

  tearDown(() async {
    await writer.dispose();
    await player.dispose();
    await db.close();
    await profileDir.delete(recursive: true);
  });

  test('a playing -> paused edge saves the current track and position to both stores', () async {
    player.currentTrackValue = track;
    player.positionValue = const Duration(seconds: 42);

    player.emitPlaying(true);
    player.emitPlaying(false);
    await Future<void>.delayed(Duration.zero);

    final saved = await repository.get();
    expect(saved?.trackId, 't1');
    expect(saved?.positionMs, 42000);
    expect(saved?.deviceId, 'device-a');

    final local = await localStore.read();
    expect(local?.trackId, 't1');
    expect(local?.positionMs, 42000);
  });

  test('starting or resuming playback does not save anything', () async {
    player.currentTrackValue = track;
    player.emitPlaying(true);
    await Future<void>.delayed(Duration.zero);

    expect(await repository.get(), isNull);
    expect(await localStore.read(), isNull);
  });

  test('saveCurrentState() writes regardless of playing/paused — used when the app is '
      'closing mid-playback, not just on an explicit pause', () async {
    player.currentTrackValue = track;
    player.positionValue = const Duration(seconds: 7);
    player.emitPlaying(true); // still "playing" — no pause edge fired

    await writer.saveCurrentState();

    final saved = await repository.get();
    expect(saved?.trackId, 't1');
    expect(saved?.positionMs, 7000);
  });

  test('saveCurrentState() is a no-op when nothing is loaded', () async {
    await writer.saveCurrentState();
    expect(await repository.get(), isNull);
    expect(await localStore.read(), isNull);
  });

  test('saveCurrentState() records the playlist id for a playlist queue', () async {
    final playlistWriter = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      localStore: localStore,
      selfDevice: device,
      currentQueueSource: () => const PlaylistQueueSource('pl-1', 'Моя подборка'),
      isSendEnabled: () => true,
      isLocalSaveEnabled: () => true,
    );
    player.currentTrackValue = track;

    await playlistWriter.saveCurrentState();

    final saved = await repository.get();
    expect(saved?.queueType, PlaybackQueueType.playlist);
    expect(saved?.playlistId, 'pl-1');
  });

  test('saveCurrentState() writes nothing to either store when both toggles are off', () async {
    final disabledWriter = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      localStore: localStore,
      selfDevice: device,
      currentQueueSource: () => const LibraryQueueSource(),
      isSendEnabled: () => false,
      isLocalSaveEnabled: () => false,
    );
    player.currentTrackValue = track;

    await disabledWriter.saveCurrentState();

    expect(await repository.get(), isNull);
    expect(await localStore.read(), isNull);
  });

  test('"отправлять" and "сохранять локально" are independent — send off, local on, '
      'only writes locally', () async {
    final localOnlyWriter = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      localStore: localStore,
      selfDevice: device,
      currentQueueSource: () => const LibraryQueueSource(),
      isSendEnabled: () => false,
      isLocalSaveEnabled: () => true,
    );
    player.currentTrackValue = track;

    await localOnlyWriter.saveCurrentState();

    expect(await repository.get(), isNull);
    expect((await localStore.read())?.trackId, 't1');
  });

  test('local on, send off — the other way around, only writes to the CRDT table', () async {
    final sendOnlyWriter = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      localStore: localStore,
      selfDevice: device,
      currentQueueSource: () => const LibraryQueueSource(),
      isSendEnabled: () => true,
      isLocalSaveEnabled: () => false,
    );
    player.currentTrackValue = track;

    await sendOnlyWriter.saveCurrentState();

    expect((await repository.get())?.trackId, 't1');
    expect(await localStore.read(), isNull);
  });

  test('a pause does not write either when both toggles are off — not just saveCurrentState()',
      () async {
    // A fresh player, not the shared `player`/`writer` from `setUp` — the
    // outer `writer` is already listening to `player.playingStream` with
    // both toggles on, and would itself write on the same pause edge,
    // masking whatever this test is actually checking.
    final isolatedPlayer = _FakePlayerService();
    addTearDown(isolatedPlayer.dispose);
    final disabledWriter = PlaybackStateWriter(
      playerService: isolatedPlayer,
      repository: repository,
      localStore: localStore,
      selfDevice: device,
      currentQueueSource: () => const LibraryQueueSource(),
      isSendEnabled: () => false,
      isLocalSaveEnabled: () => false,
    );
    disabledWriter.start();
    addTearDown(disabledWriter.dispose);
    isolatedPlayer.currentTrackValue = track;

    isolatedPlayer.emitPlaying(true);
    isolatedPlayer.emitPlaying(false);
    await Future<void>.delayed(Duration.zero);

    expect(await repository.get(), isNull);
    expect(await localStore.read(), isNull);
  });
}
