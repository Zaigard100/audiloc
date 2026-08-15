import 'dart:async';

import 'package:audiloc/data/db/audiloc_database.dart';
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
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool autoPlay = true}) async {}
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
  late _FakePlayerService player;
  late PlaybackStateWriter writer;

  const device = Device(id: 'device-a', name: 'Ноутбук');
  const track = Track(id: 't1', path: '/a.mp3', title: 'Song');

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    repository = PlaybackStateRepository(db.crdt);
    player = _FakePlayerService();
    writer = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      selfDevice: device,
      currentQueueSource: () => const LibraryQueueSource(),
    );
    writer.start();
  });

  tearDown(() async {
    await writer.dispose();
    await player.dispose();
    await db.close();
  });

  test('a playing -> paused edge saves the current track and position', () async {
    player.currentTrackValue = track;
    player.positionValue = const Duration(seconds: 42);

    player.emitPlaying(true);
    player.emitPlaying(false);
    await Future<void>.delayed(Duration.zero);

    final saved = await repository.get();
    expect(saved?.trackId, 't1');
    expect(saved?.positionMs, 42000);
    expect(saved?.deviceId, 'device-a');
  });

  test('starting or resuming playback does not save anything', () async {
    player.currentTrackValue = track;
    player.emitPlaying(true);
    await Future<void>.delayed(Duration.zero);

    expect(await repository.get(), isNull);
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
  });

  test('saveCurrentState() records the playlist id for a playlist queue', () async {
    final playlistWriter = PlaybackStateWriter(
      playerService: player,
      repository: repository,
      selfDevice: device,
      currentQueueSource: () => const PlaylistQueueSource('pl-1', 'Моя подборка'),
    );
    player.currentTrackValue = track;

    await playlistWriter.saveCurrentState();

    final saved = await repository.get();
    expect(saved?.queueType, PlaybackQueueType.playlist);
    expect(saved?.playlistId, 'pl-1');
  });
}
