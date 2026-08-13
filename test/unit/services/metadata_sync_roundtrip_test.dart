import 'package:audiloc/data/db/audiloc_database.dart';
import 'package:audiloc/data/models/track.dart';
import 'package:audiloc/data/repositories/tracks_repository.dart';
import 'package:audiloc/services/sync/metadata/metadata_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real, live sync between two `SqliteCrdt` nodes over an actual
/// localhost WebSocket — the one piece of the P2P story this project can
/// verify end-to-end without a second physical device, since both "nodes"
/// are just two in-memory databases in this same test process.
///
/// `crdt_sync`'s `listen()` has no stop handle (see
/// `MetadataSyncService` docs), so this file deliberately binds its port
/// exactly once and keeps everything in a single test.
void main() {
  test('a track written on node A reaches node B over localhost', () async {
    const port = 8551;

    final dbA = await AudilocDatabase.openInMemory();
    final dbB = await AudilocDatabase.openInMemory();
    addTearDown(() async {
      await dbA.close();
      await dbB.close();
    });

    final tracksA = TracksRepository(dbA.crdt);
    final tracksB = TracksRepository(dbB.crdt);

    final serverSide = MetadataSyncService(crdt: dbA.crdt, port: port);
    final clientSide = MetadataSyncService(crdt: dbB.crdt, port: port);
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
}
