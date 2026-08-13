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
/// "Pairing" doubles as "add this device to a profile"
/// (docs/adr/0015-profile-identity-in-pairing.md): a request always
/// carries the requester's [profileHash][IncomingPairingRequest.profileHash],
/// and by convention the *requester's* profile is authoritative — the
/// side that approves either pairs into its own current profile (if the
/// hashes already match) or hands off to [onJoinDifferentProfile], which
/// switches this device onto a local copy of the requester's profile
/// first. This is what stops two independently-populated libraries from
/// ever silently merging into one.
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
    required String selfProfileHash,
    required Future<void> Function(IncomingPairingRequest request) onJoinDifferentProfile,
    this.pairingPort = 8543,
    this.metadataSyncPort = 8541,
  })  : _server = server,
        _client = client,
        _devicesRepository = devicesRepository,
        _metadataSyncService = metadataSyncService,
        _selfId = selfId,
        _selfName = selfName,
        _selfProfileHash = selfProfileHash,
        _onJoinDifferentProfile = onJoinDifferentProfile {
    _responsesSub = _server.responses.listen(_handleResponse);
  }

  final PairingServer _server;
  final PairingClient _client;
  final DevicesRepository _devicesRepository;
  final MetadataSyncService _metadataSyncService;
  final String _selfId;
  final String _selfName;
  final String _selfProfileHash;
  final Future<void> Function(IncomingPairingRequest request) _onJoinDifferentProfile;
  final int pairingPort;
  final int metadataSyncPort;

  late final StreamSubscription<PairingResponse> _responsesSub;

  /// Requests from other devices waiting on *this* device's user to
  /// approve/reject — UI shows a dialog for each.
  Stream<IncomingPairingRequest> get incomingRequests => _server.requests;

  /// Asks [peer] to pair with this device, adding it to *our* current
  /// profile — see the class doc for why the requester is always the
  /// authoritative side. Fire-and-forget: the answer (if it comes)
  /// arrives later via [incomingRequests]' sibling stream, handled
  /// internally by [_handleResponse] — callers don't await a decision
  /// here, only that the request was sent.
  Future<void> requestPairing(DiscoveredPeer peer) => _client.sendRequest(
        host: peer.host,
        port: pairingPort,
        fromId: _selfId,
        fromName: _selfName,
        profileHash: _selfProfileHash,
      );

  /// The user approved an incoming request. Always acknowledges first,
  /// then either pairs directly (same profile already) or hands off to
  /// [onJoinDifferentProfile] to switch this device onto the requester's
  /// profile before pairing — see the class doc.
  Future<void> approve(IncomingPairingRequest request) async {
    await _client.sendResponse(
      host: request.fromHost,
      port: pairingPort,
      fromId: _selfId,
      fromName: _selfName,
      accepted: true,
      profileHash: _selfProfileHash,
    );

    if (request.profileHash == _selfProfileHash) {
      await _pair(id: request.fromId, name: request.fromName, host: request.fromHost);
    } else {
      await _onJoinDifferentProfile(request);
    }
  }

  /// The user declined — nothing is written to `devices`, just tell the
  /// requester so its UI can stop waiting.
  Future<void> reject(IncomingPairingRequest request) => _client.sendResponse(
        host: request.fromHost,
        port: pairingPort,
        fromId: _selfId,
        fromName: _selfName,
        accepted: false,
        profileHash: _selfProfileHash,
      );

  /// Pairs [id]/[name]/[host] into whatever profile is *currently*
  /// active, without sending a response — for use by the app shell right
  /// after switching into the profile an [approve]'d request asked to
  /// join: the response was already sent by the pre-switch `approve()`
  /// call, on the (now-closed) old session's `PairingService`.
  Future<void> pairWithoutResponding({required String id, required String name, required String host}) =>
      _pair(id: id, name: name, host: host);

  Future<void> _handleResponse(PairingResponse response) async {
    if (!response.accepted) return;
    // We're always the requester here, and our own profile is
    // authoritative by convention (docs/adr/0015) — no switch needed,
    // just pair as normal.
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
