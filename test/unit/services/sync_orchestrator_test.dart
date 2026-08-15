import 'dart:async';

import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/repositories/devices_repository.dart';
import 'package:audiloc/services/sync/discovery/discovered_peer.dart';
import 'package:audiloc/services/sync/discovery/discovery_event.dart';
import 'package:audiloc/services/sync/discovery/discovery_service.dart';
import 'package:audiloc/services/sync/metadata/metadata_sync_service.dart';
import 'package:audiloc/services/sync/sync_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Never touches the real bonsoir platform channel — overrides everything
/// [SyncOrchestrator] actually calls on it, so events can be pushed
/// synthetically. See docs/adr/0025-sync-and-discovery-reliability.md.
class _FakeDiscoveryService extends DiscoveryService {
  _FakeDiscoveryService() : super(selfDeviceId: 'unused', selfDeviceName: 'unused');

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

/// Records which peers `connectToPeer` was asked to dial, instead of
/// actually opening a socket — the tie-break behavior under test is about
/// whether `SyncOrchestrator` *calls* it, which shouldn't depend on real
/// network timing/outcome.
class _RecordingMetadataSyncService extends MetadataSyncService {
  _RecordingMetadataSyncService({required super.crdt, required super.devicesRepository});

  final dialedPeers = <String>[];

  @override
  void connectToPeer(String deviceId, Uri metadataSyncUri) => dialedPeers.add(deviceId);
}

void main() {
  group('SyncOrchestrator', () {
    late AudilocDatabase db;
    late DevicesRepository devicesRepository;
    late _RecordingMetadataSyncService metadataSyncService;
    late _FakeDiscoveryService discovery;

    setUp(() async {
      db = await AudilocDatabase.openInMemory();
      devicesRepository = DevicesRepository(db.crdt);
      metadataSyncService = _RecordingMetadataSyncService(crdt: db.crdt, devicesRepository: devicesRepository);
      discovery = _FakeDiscoveryService();
    });

    tearDown(() async {
      await metadataSyncService.dispose();
      await discovery.dispose();
      await db.close();
    });

    test('only the side whose id sorts lower dials out — the other just waits', () async {
      const peerId = 'zzz-higher-id'; // 'aaa-lower-id' < peerId
      await devicesRepository.upsert(const Device(id: peerId, name: 'Peer'));

      // self id sorts lower than the peer's -> this side must dial.
      final lowerSelf = SyncOrchestrator(
        selfDeviceId: 'aaa-lower-id',
        discoveryService: discovery,
        metadataSyncService: metadataSyncService,
        devicesRepository: devicesRepository,
      );
      addTearDown(lowerSelf.dispose);

      const peer = DiscoveredPeer(deviceId: peerId, name: 'Peer', host: '127.0.0.1', port: 8551);
      discovery.emit(PeerFound(peer));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(metadataSyncService.dialedPeers, [peerId]);
    });

    test('the side whose id sorts higher never dials — waits for the incoming connection', () async {
      const peerId = 'aaa-lower-id'; // 'zzz-higher-id' > peerId
      await devicesRepository.upsert(const Device(id: peerId, name: 'Peer'));

      final higherSelf = SyncOrchestrator(
        selfDeviceId: 'zzz-higher-id',
        discoveryService: discovery,
        metadataSyncService: metadataSyncService,
        devicesRepository: devicesRepository,
      );
      addTearDown(higherSelf.dispose);

      const peer = DiscoveredPeer(deviceId: peerId, name: 'Peer', host: '127.0.0.1', port: 8551);
      discovery.emit(PeerFound(peer));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(metadataSyncService.dialedPeers, isEmpty);
    });

    test('an unchanged address is not rewritten to devices on every discovery event', () async {
      final orchestrator = SyncOrchestrator(
        selfDeviceId: 'aaa-lower-id',
        discoveryService: discovery,
        metadataSyncService: metadataSyncService,
        devicesRepository: devicesRepository,
      );
      addTearDown(orchestrator.dispose);

      const peerId = 'zzz-higher-id';
      const peer = DiscoveredPeer(deviceId: peerId, name: 'Peer', host: '127.0.0.1', port: 8551);
      // A fresh lastOnlineAt within the throttle window — a second
      // find for the same, unchanged address shouldn't touch it.
      await devicesRepository.upsert(Device(
        id: peerId,
        name: 'Peer',
        host: peer.host,
        syncPort: peer.port,
        lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
      ));
      final before = (await devicesRepository.byId(peerId))!.lastOnlineAt;

      discovery.emit(PeerFound(peer));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 100));

      final after = (await devicesRepository.byId(peerId))!.lastOnlineAt;
      expect(after, before);
    });

    test('a genuinely changed address is written immediately', () async {
      final orchestrator = SyncOrchestrator(
        selfDeviceId: 'aaa-lower-id',
        discoveryService: discovery,
        metadataSyncService: metadataSyncService,
        devicesRepository: devicesRepository,
      );
      addTearDown(orchestrator.dispose);

      const peerId = 'zzz-higher-id';
      await devicesRepository.upsert(Device(
        id: peerId,
        name: 'Peer',
        host: '192.168.1.5',
        syncPort: 8551,
        lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
      ));

      const movedPeer = DiscoveredPeer(deviceId: peerId, name: 'Peer', host: '192.168.1.99', port: 8551);
      discovery.emit(PeerFound(movedPeer));
      await pumpEventQueue();
      await Future.delayed(const Duration(milliseconds: 100));

      final after = await devicesRepository.byId(peerId);
      expect(after!.host, '192.168.1.99');
    });

    test('restartDiscovery before start() is a harmless no-op', () async {
      final orchestrator = SyncOrchestrator(
        selfDeviceId: 'aaa-lower-id',
        discoveryService: discovery,
        metadataSyncService: metadataSyncService,
        devicesRepository: devicesRepository,
      );
      addTearDown(orchestrator.dispose);

      // start() was never called -> no port remembered yet; must not throw.
      await orchestrator.restartDiscovery();
    });

    test('restartDiscovery after start() restarts discovery without throwing', () async {
      final orchestrator = SyncOrchestrator(
        selfDeviceId: 'aaa-lower-id',
        discoveryService: discovery,
        metadataSyncService: metadataSyncService,
        devicesRepository: devicesRepository,
      );
      addTearDown(orchestrator.dispose);

      // A test-only port, distinct from the app's real default (8541,
      // which other test files — profile_session_test.dart in particular —
      // bind for real, concurrently, in the same `flutter test` run.
      await orchestrator.start(8573);
      await orchestrator.restartDiscovery();
    });
  });
}
