import 'dart:async';
import 'dart:io';

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
/// [startServer] deliberately does **not** use `crdt_sync_server.listen()`:
/// that helper binds to `InternetAddress.loopbackIPv4`, which only accepts
/// connections from the same machine — useless for LAN sync, and the
/// actual reason two real devices could discover each other (mDNS is
/// OS-level, unaffected) but never sync (this app's own socket was
/// unreachable from outside). This runs the same accept loop `listen()`
/// does internally, but bound to all interfaces, using `upgrade()`
/// directly. As a side benefit we keep the `HttpServer` handle, so
/// [dispose] can actually close it — `listen()` doesn't expose one.
class MetadataSyncService {
  MetadataSyncService({required Crdt crdt, this.port = 8541}) : _crdt = crdt;

  final Crdt _crdt;
  final int port;

  final _clients = <String, CrdtSyncClient>{};
  final _states = <String, PeerSyncState>{};

  final _statsController = StreamController<SyncStats>.broadcast();
  final _stateController = StreamController<(String deviceId, PeerSyncState)>.broadcast();

  HttpServer? _server;

  Stream<SyncStats> get onChangesetApplied => _statsController.stream;
  Stream<(String, PeerSyncState)> get onPeerStateChanged => _stateController.stream;

  PeerSyncState stateOf(String deviceId) => _states[deviceId] ?? PeerSyncState.disconnected;

  /// Starts accepting incoming connections from peers on all network
  /// interfaces. Safe to call once; subsequent calls are ignored.
  Future<void> startServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(_acceptLoop(server));
  }

  Future<void> _acceptLoop(HttpServer server) async {
    await for (final request in server) {
      _handleConnection(request);
    }
  }

  void _handleConnection(HttpRequest request) {
    unawaited(() async {
      try {
        await crdt_sync_server.upgrade(
          _crdt,
          request,
          onConnect: (crdtSync, _) {
            final peerId = crdtSync.peerId;
            if (peerId != null) _setState(peerId, PeerSyncState.connected);
          },
          onDisconnect: (peerId, code, reason) => _setState(peerId, PeerSyncState.disconnected),
          onChangesetReceived: (nodeId, counts) => _reportStats(nodeId, counts),
        );
      } catch (_) {
        // A single bad handshake/upgrade shouldn't kill the accept loop.
      }
    }());
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
      onChangesetReceived: (nodeId, counts) => _reportStats(nodeId, counts),
    );
    _clients[deviceId] = client;
    client.connect();
  }

  Future<void> disconnectFromPeer(String deviceId) async {
    final client = _clients.remove(deviceId);
    await client?.disconnect();
    _setState(deviceId, PeerSyncState.disconnected);
  }

  // `crdt_sync` callbacks can fire asynchronously after dispose() has
  // already closed these controllers (e.g. a peer disconnect event
  // in flight when the app/service is torn down) — guard both sinks.
  void _setState(String deviceId, PeerSyncState state) {
    if (_stateController.isClosed) return;
    _states[deviceId] = state;
    _stateController.add((deviceId, state));
  }

  void _reportStats(String nodeId, Map<String, int> counts) {
    if (_statsController.isClosed) return;
    _statsController.add(SyncStats(deviceId: nodeId, recordCounts: counts));
  }

  Future<void> dispose() async {
    for (final client in _clients.values) {
      await client.disconnect();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    await _statsController.close();
    await _stateController.close();
  }
}
