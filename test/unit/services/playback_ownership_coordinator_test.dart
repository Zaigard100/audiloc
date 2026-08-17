import 'dart:async';
import 'dart:io';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/devices_repository.dart';
import 'package:audiloc/data/repositories/profile_settings_repository.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/playback/player_service.dart';
import 'package:audiloc/services/playback_ownership/playback_ownership_coordinator.dart';
import 'package:audiloc/services/playback_ownership/playback_ownership_server.dart';
import 'package:audiloc/services/sync/discovery/discovered_peer.dart';
import 'package:audiloc/services/sync/discovery/discovery_event.dart';
import 'package:audiloc/services/sync/discovery/discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Never touches the real bonsoir platform channel — same trick as
/// `sync_orchestrator_test.dart` (docs/adr/0025-sync-and-discovery-reliability.md):
/// overrides everything `PlaybackOwnershipCoordinator` actually calls, so
/// found/lost events can be pushed synthetically while the ownership link
/// itself is a real WebSocket round-trip over localhost.
class _FakeDiscoveryService extends DiscoveryService {
  _FakeDiscoveryService()
    : super(selfDeviceId: 'unused', selfDeviceName: 'unused');

  final _controller = StreamController<DiscoveryEvent>.broadcast();

  @override
  Stream<DiscoveryEvent> get events => _controller.stream;

  @override
  Future<void> startAdvertising(int port) async {}

  @override
  Future<void> startDiscovery() async {}

  void emit(DiscoveryEvent event) => _controller.add(event);

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _RecordingPlayerService implements PlayerService {
  int pauseCalls = 0;

  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<PlaybackPositionState> get positionStream => const Stream.empty();
  @override
  Stream<Track?> get currentTrackStream => const Stream.empty();
  @override
  Stream<bool> get completedStream => const Stream.empty();
  @override
  Stream<bool> get shuffleStream => const Stream.empty();
  @override
  Stream<PlaybackRepeatMode> get repeatModeStream => const Stream.empty();
  @override
  bool get isPlaying => false;
  @override
  Track? get currentTrack => null;
  @override
  Duration get position => Duration.zero;
  @override
  List<Track> get queue => const [];
  @override
  bool get isShuffleEnabled => false;
  @override
  PlaybackRepeatMode get repeatMode => PlaybackRepeatMode.all;
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
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> playOrPause() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> setShuffle(bool enabled) async {}
  @override
  Future<void> setRepeatMode(PlaybackRepeatMode mode) async {}
  @override
  Future<void> dispose() async {}
}

/// Every node in a test shares this one port — matching production,
/// where `playbackOwnershipPort` really is identical on every device
/// (each has its own IP, so no clash). Two nodes in the *same* test
/// process instead get distinct loopback [_Node.host] addresses so
/// their servers can both bind it without colliding.
const _testOwnershipPort = 8697;

/// One device's whole ownership stack — a real `PlaybackOwnershipServer`
/// bound to a real (loopback) address, a real
/// `PlaybackOwnershipCoordinator`, and a fake discovery service to drive
/// found/lost events synthetically.
class _Node {
  _Node(this.id, this.name, this.host);

  final String id;
  final String name;
  final String host;

  late AudilocDatabase db;
  late DevicesRepository devicesRepository;
  late ProfileSettingsRepository profileSettingsRepository;
  late TracksRepository tracksRepository;
  late _RecordingPlayerService player;
  late PlaybackOwnershipServer server;
  late PlaybackOwnershipCoordinator coordinator;
  late _FakeDiscoveryService discovery;

  /// Mirrors what `ref.read(profileSyncEnabledProvider).value` gives the
  /// real `PlaybackOwnershipServer` in production — a synchronous,
  /// already-known value — kept in lockstep with
  /// [profileSettingsRepository] (which the coordinator itself watches
  /// directly) by [setSyncEnabled].
  bool syncEnabled = false;

  Future<void> open() async {
    db = await AudilocDatabase.openInMemory();
    devicesRepository = DevicesRepository(db.crdt);
    profileSettingsRepository = ProfileSettingsRepository(db.crdt);
    tracksRepository = TracksRepository(db.crdt);
    player = _RecordingPlayerService();
    discovery = _FakeDiscoveryService();
    server = PlaybackOwnershipServer(
      devicesRepository: devicesRepository,
      isSyncEnabled: () => syncEnabled,
      port: _testOwnershipPort,
      bindAddress: InternetAddress(host),
    );
    coordinator = PlaybackOwnershipCoordinator(
      selfDeviceId: id,
      selfDeviceName: name,
      discoveryService: discovery,
      devicesRepository: devicesRepository,
      profileSettingsRepository: profileSettingsRepository,
      playerService: player,
      tracksRepository: tracksRepository,
      server: server,
      port: _testOwnershipPort,
    );
    await coordinator.start();
  }

  /// A claim's target only acks once it's resolved the queue against its
  /// *own* `TracksRepository` (see `_handleTargetedClaim`) — in
  /// production that row arrives via ordinary metadata sync before any
  /// handoff is possible, but this test never wires the two nodes' DBs
  /// together, so tests exercising a successful handoff must seed the
  /// target's copy directly.
  Future<void> putTrack(String id) => tracksRepository.upsert(Track(id: id, path: '/fake/$id.flac'));

  /// Pairs [other] and marks it found — the two calls a real mDNS
  /// discovery + pairing flow would together produce, condensed for the
  /// test.
  Future<void> discover(_Node other) async {
    await devicesRepository.upsert(Device(id: other.id, name: other.name));
    discovery.emit(
      PeerFound(
        DiscoveredPeer(
          deviceId: other.id,
          name: other.name,
          host: other.host,
          port: _testOwnershipPort,
        ),
      ),
    );
  }

  Future<void> setSyncEnabled(bool value) async {
    syncEnabled = value;
    await profileSettingsRepository.setSyncPlaybackEnabled(value);
  }

  Future<void> close() async {
    await coordinator.dispose();
    await server.dispose();
    await discovery.dispose();
    await db.close();
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Real (non-mocked) WebSocket round-trips for the ownership/exclusivity
/// protocol — see docs/adr/0033-playback-ownership-and-handoff.md.
void main() {
  late _Node a;
  late _Node b;

  setUp(() async {
    // 'a' < 'b' lexicographically — 'a' is always the dialer, matching
    // the "lower id dials out" dedup rule. Distinct loopback addresses
    // (not distinct ports — see `_testOwnershipPort`'s doc) so both
    // servers can bind the same port within this one test process.
    a = _Node('a-device', 'A', '127.0.0.1');
    b = _Node('b-device', 'B', '127.0.0.2');
    await a.open();
    await b.open();
    await a.setSyncEnabled(true);
    await b.setSyncEnabled(true);
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<void> connectBothWays() async {
    await a.discover(b);
    await b.discover(a);
    await _waitUntil(() => a.coordinator.linkedDeviceIds.contains(b.id));
    await _waitUntil(() => b.coordinator.linkedDeviceIds.contains(a.id));
  }

  test('two sync-enabled paired devices establish exactly one ownership link between them', () async {
    await connectBothWays();
    expect(a.coordinator.linkedDeviceIds, {b.id});
    expect(b.coordinator.linkedDeviceIds, {a.id});
  });

  test(
    'claiming locally on one device is seen as ownership by the other',
    () async {
      await connectBothWays();

      a.coordinator.claimSelf();

      await _waitUntil(() => b.coordinator.currentOwner == a.id);
      expect(a.coordinator.currentOwner, a.id);
    },
  );

  test('a peer starting playback forces the current owner to pause', () async {
    await connectBothWays();
    a.coordinator.claimSelf();
    await _waitUntil(() => b.coordinator.currentOwner == a.id);

    b.coordinator.claimSelf();

    await _waitUntil(() => a.player.pauseCalls == 1);
    expect(a.coordinator.currentOwner, b.id);
    expect(b.coordinator.currentOwner, b.id);
  });

  test('a manual handoff waits for the target to accept before either side updates', () async {
    await connectBothWays();
    await b.putTrack('t1');

    final accepted = await a.coordinator.claimForDevice(
      b.id,
      queueTrackIds: ['t1'],
      queueIndex: 0,
      positionMs: 1234,
    );

    expect(accepted, isTrue);
    expect(a.coordinator.currentOwner, b.id);
    await _waitUntil(() => b.coordinator.currentOwner == b.id);
  });

  test('a manual handoff to a target missing the track is rejected', () async {
    await connectBothWays();

    final accepted = await a.coordinator.claimForDevice(
      b.id,
      queueTrackIds: ['does-not-exist'],
      queueIndex: 0,
      positionMs: 0,
    );

    expect(accepted, isFalse);
    expect(a.coordinator.currentOwner, isNull);
    expect(b.coordinator.currentOwner, isNull);
  });

  test(
    'a handoff target that has since turned sync off rejects the claim',
    () async {
      await connectBothWays();
      await b.setSyncEnabled(false);
      // Turning sync off tears the link down on b's side — give it a
      // moment, same as a real toggle flip would need to propagate.
      await _waitUntil(() => !b.coordinator.linkedDeviceIds.contains(a.id));

      final accepted = await a.coordinator.claimForDevice(
        b.id,
        queueTrackIds: ['t1'],
        queueIndex: 0,
        positionMs: 0,
      );

      expect(accepted, isFalse);
    },
  );

  test('claiming a device with no live link fails immediately without touching ownership', () async {
    final accepted = await a.coordinator.claimForDevice(
      'nobody-here',
      queueTrackIds: ['t1'],
      queueIndex: 0,
      positionMs: 0,
    );
    expect(accepted, isFalse);
    expect(a.coordinator.currentOwner, isNull);
  });

  test('losing the link to the current owner clears ownership rather than reassigning it', () async {
    await connectBothWays();
    a.coordinator.claimSelf();
    await _waitUntil(() => b.coordinator.currentOwner == a.id);

    b.discovery.emit(const PeerLost('a-device'));

    await _waitUntil(() => b.coordinator.currentOwner == null);
    expect(b.coordinator.linkedDeviceIds, isEmpty);
  });
}
