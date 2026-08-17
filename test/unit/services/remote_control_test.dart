import 'dart:async';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/devices_repository.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/playback/player_service.dart';
import 'package:audiloc/services/remote_control/remote_control_client.dart';
import 'package:audiloc/services/remote_control/remote_control_server.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePlayerService implements PlayerService {
  final _playingController = StreamController<bool>.broadcast();
  final _trackController = StreamController<Track?>.broadcast();

  bool _isPlaying = false;
  Track? _currentTrack;
  Duration _position = Duration.zero;

  List<Track>? lastQueue;
  Duration? lastSeekTo;
  int playCalls = 0;
  int pauseCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;

  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<PlaybackPositionState> get positionStream =>
      Stream.value(const PlaybackPositionState(position: Duration.zero, duration: Duration(minutes: 3)));
  @override
  Stream<Track?> get currentTrackStream => _trackController.stream;
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  Stream<bool> get shuffleStream => const Stream.empty();
  @override
  Stream<PlaybackRepeatMode> get repeatModeStream => const Stream.empty();
  @override
  bool get isPlaying => _isPlaying;
  @override
  Track? get currentTrack => _currentTrack;
  @override
  Duration get position => _position;

  @override
  List<Track> get queue => lastQueue ?? const [];
  @override
  bool get isShuffleEnabled => false;
  @override
  PlaybackRepeatMode get repeatMode => PlaybackRepeatMode.all;

  @override
  Future<void> setQueue(List<Track> tracks, {int startIndex = 0, bool autoPlay = true, Duration? seekTo}) async {
    lastQueue = tracks;
    lastSeekTo = seekTo;
    _currentTrack = tracks.isEmpty ? null : tracks[startIndex];
    _position = seekTo ?? Duration.zero;
    if (autoPlay) {
      _isPlaying = true;
      _playingController.add(true);
    }
    _trackController.add(_currentTrack);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _isPlaying = true;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> playOrPause() async => _isPlaying ? pause() : play();
  @override
  Future<void> seek(Duration position) async => _position = position;
  @override
  Future<void> next() async => nextCalls++;
  @override
  Future<void> previous() async => previousCalls++;
  @override
  Future<void> setShuffle(bool enabled) async {}
  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}
  @override
  Future<void> dispose() async {
    await _playingController.close();
    await _trackController.close();
  }
}

/// Real (non-mocked) WebSocket round-trips for remote playback control —
/// see docs/adr/0030-remote-playback-control.md.
void main() {
  late AudilocDatabase db;
  late DevicesRepository devicesRepository;
  late TracksRepository tracksRepository;
  late _FakePlayerService player;
  late RemoteControlServer server;
  var allowed = true;

  const port = 8590;
  const controllerId = 'controller-device';
  const track = Track(id: 't1', path: '/a.mp3', title: 'Song', artist: 'Artist');

  setUp(() async {
    db = await AudilocDatabase.openInMemory();
    devicesRepository = DevicesRepository(db.crdt);
    tracksRepository = TracksRepository(db.crdt);
    player = _FakePlayerService();
    allowed = true;
    server = RemoteControlServer(
      playerService: player,
      devicesRepository: devicesRepository,
      tracksRepository: tracksRepository,
      isAllowed: (_) => allowed,
      port: port,
    );
    await server.start();
  });

  tearDown(() async {
    await server.dispose();
    await player.dispose();
    await db.close();
  });

  test('a device that has never been paired is rejected, even with the setting on', () async {
    final client = RemoteControlClient();
    addTearDown(client.dispose);

    final accepted = await client.connect(
      host: '127.0.0.1',
      port: port,
      selfId: controllerId,
      selfName: 'Controller',
    );

    expect(accepted, isFalse);
  });

  test('a paired device is rejected when the local "allow remote control" setting is off', () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    allowed = false;
    final client = RemoteControlClient();
    addTearDown(client.dispose);

    final accepted = await client.connect(
      host: '127.0.0.1',
      port: port,
      selfId: controllerId,
      selfName: 'Controller',
    );

    expect(accepted, isFalse);
  });

  test('a paired device is accepted when the setting is on, and immediately gets a state push', () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    final client = RemoteControlClient();
    addTearDown(client.dispose);

    final firstState = client.states.first.timeout(const Duration(seconds: 5));
    final accepted = await client.connect(
      host: '127.0.0.1',
      port: port,
      selfId: controllerId,
      selfName: 'Controller',
    );

    expect(accepted, isTrue);
    final state = await firstState;
    expect(state, isNotNull);
    expect(state!.trackId, isNull); // nothing loaded yet
    expect(state.isPlaying, isFalse);
  });

  test('play/pause/next/previous commands reach the controlled device\'s player', () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    final client = RemoteControlClient();
    addTearDown(client.dispose);
    await client.connect(host: '127.0.0.1', port: port, selfId: controllerId, selfName: 'Controller');

    client.play();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.playCalls, 1);

    client.pause();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.pauseCalls, 1);

    client.next();
    client.previous();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(player.nextCalls, 1);
    expect(player.previousCalls, 1);
  });

  test('loadAndPlay opens the requested track at the requested position and starts playing', () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    await tracksRepository.upsert(track);
    final client = RemoteControlClient();
    addTearDown(client.dispose);
    await client.connect(host: '127.0.0.1', port: port, selfId: controllerId, selfName: 'Controller');

    client.loadAndPlay(['t1'], 0, const Duration(seconds: 42));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.lastQueue?.map((t) => t.id), ['t1']);
    expect(player.lastSeekTo, const Duration(seconds: 42));
    expect(player.isPlaying, isTrue);
  });

  test('loadAndPlay resolves the whole queue, dropping tracks not available locally, so '
      "next/previous have something to move through", () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    await tracksRepository.upsert(track);
    const other = Track(id: 't2', path: '/b.mp3', title: 'Other');
    await tracksRepository.upsert(other);
    final client = RemoteControlClient();
    addTearDown(client.dispose);
    await client.connect(host: '127.0.0.1', port: port, selfId: controllerId, selfName: 'Controller');

    // 'missing' isn't in the local library at all — dropped, but the
    // requested start track (t2) is still found and started correctly.
    client.loadAndPlay(['t1', 'missing', 't2'], 2, Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.lastQueue?.map((t) => t.id), ['t1', 't2']);
    expect(player.currentTrack?.id, 't2');
  });

  test('loadAndPlay for a track this device does not have locally does nothing', () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    // Metadata only, no local file — Track.isAvailableLocally is false.
    await tracksRepository.upsert(track);
    await db.crdt.execute("UPDATE track_locations SET is_deleted = 1 WHERE track_id = 't1'");
    final client = RemoteControlClient();
    addTearDown(client.dispose);
    await client.connect(host: '127.0.0.1', port: port, selfId: controllerId, selfName: 'Controller');

    client.loadAndPlay(['does-not-exist'], 0, Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(player.lastQueue, isNull);
  });

  test('a state push reflects a change made directly on the controlled device', () async {
    await devicesRepository.upsert(const Device(id: controllerId, name: 'Controller'));
    final client = RemoteControlClient();
    addTearDown(client.dispose);
    await client.connect(host: '127.0.0.1', port: port, selfId: controllerId, selfName: 'Controller');

    final nextState = client.states.firstWhere((s) => s?.trackId == 't1').timeout(const Duration(seconds: 5));
    await tracksRepository.upsert(track);
    await player.setQueue([track], autoPlay: true);

    final state = await nextState;
    expect(state!.trackId, 't1');
    expect(state.title, 'Song');
    expect(state.isPlaying, isTrue);
  });
}
