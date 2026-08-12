import 'dart:async';

import 'package:crdt/crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_server.dart' as crdt_sync_server;

import 'sync_stats.dart';

enum PeerSyncState { connecting, connected, disconnected }

/// P2P synchronization of CRDT metadata deltas (ТЗ п.3, "Сетевая
/// синхронизация CRDT-узлов" → crdt_sync).
///
/// `crdt_sync` ships client/server primitives for a hub topology; there's
/// no central server here, so every device runs *both* sides: a
/// [startServer] listening for incoming peers, and one [connectToPeer]
/// outbound connection per peer discovered by `DiscoveryService`. Whichever
/// side dials in, the same `Crdt` instance ends up synchronized both ways.
///
/// Known limitation: `crdt_sync`'s `listen()` helper doesn't expose a
/// handle to stop the underlying `HttpServer` — see
/// docs/adr/0005-crdt-sync-for-p2p-metadata.md. Acceptable for an
/// app-lifetime service; would need upstreaming or a custom server loop to
/// fix properly.
class MetadataSyncService {
  MetadataSyncService({required Crdt crdt, this.port = 8541}) : _crdt = crdt;

  final Crdt _crdt;
  final int port;

  final _clients = <String, CrdtSyncClient>{};
  final _states = <String, PeerSyncState>{};

  final _statsController = StreamController<SyncStats>.broadcast();
  final _stateController = StreamController<(String deviceId, PeerSyncState)>.broadcast();

  bool _serverStarted = false;

  Stream<SyncStats> get onChangesetApplied => _statsController.stream;
  Stream<(String, PeerSyncState)> get onPeerStateChanged => _stateController.stream;

  PeerSyncState stateOf(String deviceId) => _states[deviceId] ?? PeerSyncState.disconnected;

  /// Starts accepting incoming connections from peers. Safe to call once;
  /// subsequent calls are ignored.
  Future<void> startServer() async {
    if (_serverStarted) return;
    _serverStarted = true;
    // `listen` runs an internal accept loop for the app's lifetime.
    unawaited(crdt_sync_server.listen(
      _crdt,
      port,
      onChangesetReceived: (nodeId, counts) =>
          _statsController.add(SyncStats(deviceId: nodeId, recordCounts: counts)),
      onDisconnect: (peerId, code, reason) => _setState(peerId, PeerSyncState.disconnected),
    ));
  }

  /// Opens (or reuses) an outbound sync connection to a peer discovered on
  /// the LAN. Idempotent per [deviceId].
  void connectToPeer(String deviceId, Uri metadataSyncUri) {
    if (_clients.containsKey(deviceId)) return;

    final client = CrdtSyncClient(
      _crdt,
      metadataSyncUri,
      onConnecting: () => _setState(deviceId, PeerSyncState.connecting),
      onConnect: (_, _) => _setState(deviceId, PeerSyncState.connected),
      onDisconnect: (_, _, _) => _setState(deviceId, PeerSyncState.disconnected),
      onChangesetReceived: (nodeId, counts) =>
          _statsController.add(SyncStats(deviceId: nodeId, recordCounts: counts)),
    );
    _clients[deviceId] = client;
    client.connect();
  }

  Future<void> disconnectFromPeer(String deviceId) async {
    final client = _clients.remove(deviceId);
    await client?.disconnect();
    _setState(deviceId, PeerSyncState.disconnected);
  }

  void _setState(String deviceId, PeerSyncState state) {
    _states[deviceId] = state;
    _stateController.add((deviceId, state));
  }

  Future<void> dispose() async {
    for (final client in _clients.values) {
      await client.disconnect();
    }
    _clients.clear();
    await _statsController.close();
    await _stateController.close();
  }
}
