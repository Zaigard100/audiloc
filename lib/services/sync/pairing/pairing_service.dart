import 'dart:async';

import '../../../data/models/device.dart';
import '../../../data/repositories/devices_repository.dart';
import '../discovery/discovered_peer.dart';
import '../metadata/metadata_sync_service.dart';
import 'pairing_client.dart';
import 'pairing_models.dart';
import 'pairing_server.dart';

/// Glues [PairingServer]/[PairingClient] to [DevicesRepository] and
/// [MetadataSyncService]: turns a user's "Добавить"/"Разрешить" tap into
/// an actual paired device and an open sync connection. See
/// docs/adr/0011-mutual-pairing-confirmation.md.
///
/// Deliberately not transactional: if a response never arrives (the peer
/// went offline, a packet got lost), the requester just sees nothing
/// happen and can try again — not worth a retry/ack protocol for how
/// rarely that actually happens on a LAN.
class PairingService {
  PairingService({
    required PairingServer server,
    required PairingClient client,
    required DevicesRepository devicesRepository,
    required MetadataSyncService metadataSyncService,
    required String selfId,
    required String selfName,
    this.pairingPort = 8543,
    this.metadataSyncPort = 8541,
  })  : _server = server,
        _client = client,
        _devicesRepository = devicesRepository,
        _metadataSyncService = metadataSyncService,
        _selfId = selfId,
        _selfName = selfName {
    _responsesSub = _server.responses.listen(_handleResponse);
  }

  final PairingServer _server;
  final PairingClient _client;
  final DevicesRepository _devicesRepository;
  final MetadataSyncService _metadataSyncService;
  final String _selfId;
  final String _selfName;
  final int pairingPort;
  final int metadataSyncPort;

  late final StreamSubscription<PairingResponse> _responsesSub;

  /// Requests from other devices waiting on *this* device's user to
  /// approve/reject — UI shows a dialog for each.
  Stream<IncomingPairingRequest> get incomingRequests => _server.requests;

  /// Asks [peer] to pair with this device. Fire-and-forget: the answer
  /// (if it comes) arrives later via [incomingRequests]' sibling stream,
  /// handled internally by [_handleResponse] — callers don't await a
  /// decision here, only that the request was sent.
  Future<void> requestPairing(DiscoveredPeer peer) => _client.sendRequest(
        host: peer.host,
        port: pairingPort,
        fromId: _selfId,
        fromName: _selfName,
      );

  /// The user approved an incoming request: pair on this side and tell
  /// the requester so it can pair on its side too.
  Future<void> approve(IncomingPairingRequest request) async {
    await _pair(id: request.fromId, name: request.fromName, host: request.fromHost);
    await _client.sendResponse(
      host: request.fromHost,
      port: pairingPort,
      fromId: _selfId,
      fromName: _selfName,
      accepted: true,
    );
  }

  /// The user declined — nothing is written to `devices`, just tell the
  /// requester so its UI can stop waiting.
  Future<void> reject(IncomingPairingRequest request) => _client.sendResponse(
        host: request.fromHost,
        port: pairingPort,
        fromId: _selfId,
        fromName: _selfName,
        accepted: false,
      );

  Future<void> _handleResponse(PairingResponse response) async {
    if (!response.accepted) return;
    await _pair(id: response.fromId, name: response.fromName, host: response.fromHost);
  }

  Future<void> _pair({required String id, required String name, required String host}) async {
    await _devicesRepository.upsert(Device(
      id: id,
      name: name,
      host: host,
      syncPort: metadataSyncPort,
      lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _metadataSyncService.connectToPeer(id, Uri(scheme: 'ws', host: host, port: metadataSyncPort));
  }

  Future<void> dispose() => _responsesSub.cancel();
}
