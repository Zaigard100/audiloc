import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/device.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/devices_repository.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/sync/metadata/metadata_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real, live sync between two `SqliteCrdt` nodes over an actual
/// localhost WebSocket — the one piece of the P2P story this project can
/// verify end-to-end without a second physical device, since both "nodes"
/// are just two in-memory databases in this same test process.
///
/// `crdt_sync`'s `listen()` has no stop handle (see
/// `MetadataSyncService` docs), so this file deliberately binds each
/// port exactly once and keeps everything in a single test per port.
void main() {
  test('a track written on node A reaches node B over localhost, once paired', () async {
    const port = 8551;

    final dbA = await AudilocDatabase.openInMemory();
    final dbB = await AudilocDatabase.openInMemory();
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });

    final tracksA = TracksRepository(dbA.crdt);
    final tracksB = TracksRepository(dbB.crdt);
    final devicesA = DevicesRepository(dbA.crdt);
    final devicesB = DevicesRepository(dbB.crdt);

    // Both sides must already consider each other paired (see
    // docs/adr/0011-mutual-pairing-confirmation.md) — normally
    // PairingService's job, done directly here since this test is about
    // the sync itself, not the pairing handshake.
    await devicesA.upsert(Device(id: dbB.nodeId, name: 'Node B'));
    await devicesB.upsert(Device(id: dbA.nodeId, name: 'Node A'));

    final serverSide = MetadataSyncService(crdt: dbA.crdt, devicesRepository: devicesA, port: port);
    final clientSide = MetadataSyncService(crdt: dbB.crdt, devicesRepository: devicesB, port: port);
    addTearDown(() async {
      await serverSide.dispose();
      await clientSide.dispose();
    });

    await serverSide.startServer();
    // listen() binds asynchronously in the background (see its docs);
    // give the loopback socket a moment to actually come up.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final connected = clientSide.onPeerStateChanged
        .firstWhere((event) => event.$2 == PeerSyncState.connected)
        .timeout(const Duration(seconds: 5));
    clientSide.connectToPeer(dbA.nodeId, Uri.parse('ws://127.0.0.1:$port'));
    await connected;

    await tracksA.upsert(const Track(id: 'shared-track', path: '/music/song.mp3', title: 'Shared Song'));

    await tracksB
        .watchAll()
        .map((tracks) => tracks.map((t) => t.id))
        .firstWhere((ids) => ids.contains('shared-track'))
        .timeout(const Duration(seconds: 5));

    final synced = await tracksB.byId('shared-track');
    expect(synced?.title, 'Shared Song');
  });

  test(
      'a node that is not a paired device gets disconnected instead of syncing '
      '(regression: the server used to accept any incoming crdt_sync connection '
      'unconditionally — see docs/adr/0011)', () async {
    const port = 8552;

    final dbA = await AudilocDatabase.openInMemory();
    final dbB = await AudilocDatabase.openInMemory();
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });

    final tracksA = TracksRepository(dbA.crdt);
    final tracksB = TracksRepository(dbB.crdt);

    // Note: neither side has upserted the other into `devices` — B is a
    // total stranger from A's point of view.
    final serverSide =
        MetadataSyncService(crdt: dbA.crdt, devicesRepository: DevicesRepository(dbA.crdt), port: port);
    final clientSide =
        MetadataSyncService(crdt: dbB.crdt, devicesRepository: DevicesRepository(dbB.crdt), port: port);
    addTearDown(() async {
      await serverSide.dispose();
      await clientSide.dispose();
    });

    await tracksA.upsert(const Track(id: 'private-track', path: '/music/song.mp3', title: 'Private Song'));

    await serverSide.startServer();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final disconnected = clientSide.onPeerStateChanged
        .firstWhere((event) => event.$2 == PeerSyncState.disconnected)
        .timeout(const Duration(seconds: 5));
    clientSide.connectToPeer(dbA.nodeId, Uri.parse('ws://127.0.0.1:$port'));
    await disconnected;

    // Give any (incorrectly) in-flight changeset a moment to land before
    // asserting it never did.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await tracksB.byId('private-track'), isNull);
  });
}
