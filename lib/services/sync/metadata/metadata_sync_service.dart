import 'dart:async';
import 'dart:io';

import 'package:crdt/crdt.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_server.dart' as crdt_sync_server;

import '../../../data/repositories/devices_repository.dart';
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
  MetadataSyncService({required Crdt crdt, required DevicesRepository devicesRepository, this.port = 8541})
      : _crdt = crdt,
        _devicesRepository = devicesRepository;

  final Crdt _crdt;
  final DevicesRepository _devicesRepository;
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
            if (peerId == null) return;
            unawaited(_authorizeOrReject(crdtSync, peerId));
          },
          onDisconnect: (peerId, code, reason) => _setState(peerId, PeerSyncState.disconnected),
          onChangesetReceived: (nodeId, counts) => _reportStats(nodeId, counts),
        );
      } catch (_) {
        // A single bad handshake/upgrade shouldn't kill the accept loop.
      }
    }());
  }

  /// Refuses the connection unless [peerId] is a device this side has
  /// paired with (see docs/adr/0011-mutual-pairing-confirmation.md) —
  /// closing happens before `crdt_sync` gets to building/sending its
  /// first changeset, so an unpaired peer never actually receives data.
  Future<void> _authorizeOrReject(CrdtSync crdtSync, String peerId) async {
    final paired = await _devicesRepository.byId(peerId) != null;
    if (!paired) {
      await crdtSync.close();
      return;
    }
    _setState(peerId, PeerSyncState.connected);
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
    // Each disconnect waits on `crdt_sync`'s own close handshake with that
    // peer — if a peer is unreachable or just slow to acknowledge, that
    // must never stop the port below from actually getting released
    // (switching profiles closes and immediately reopens this on the same
    // port — see docs/adr/0013-account-profiles.md). Bounded and run
    // together rather than one after another, so N stuck peers cost one
    // timeout, not N of them.
    await Future.wait([
      for (final client in _clients.values)
        client.disconnect().timeout(const Duration(seconds: 2), onTimeout: () {}),
    ]);
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    await _statsController.close();
    await _stateController.close();
  }
}
