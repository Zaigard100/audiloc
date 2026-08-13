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
/// Pairing means "this is the same device/profile" — see
/// docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md. A request
/// always carries the requester's
/// [profileHash][IncomingPairingRequest.profileHash]; if it doesn't match
/// this device's own, the request is auto-rejected *before* it ever
/// reaches [incomingRequests] — the UI never even sees a dialog it
/// couldn't meaningfully approve. The one exception is
/// [canJoinDifferentProfile] (ADR 0013's "Ждать сопряжения" — a fresh
/// placeholder profile explicitly waiting to join another device's
/// profile): while that's true, a mismatched request is let through, and
/// approving it hands off to [onJoinDifferentProfile] to switch this
/// device onto a local copy of the requester's profile first. Moving
/// content between two genuinely different profiles is what "Поделиться"
/// (docs/services/sync/share) is for instead — pairing itself no longer
/// does that.
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
    required Future<bool> Function() canJoinDifferentProfile,
    this.pairingPort = 8543,
    this.metadataSyncPort = 8541,
  })  : _server = server,
        _client = client,
        _devicesRepository = devicesRepository,
        _metadataSyncService = metadataSyncService,
        _selfId = selfId,
        _selfName = selfName,
        _selfProfileHash = selfProfileHash,
        _onJoinDifferentProfile = onJoinDifferentProfile,
        _canJoinDifferentProfile = canJoinDifferentProfile {
    _responsesSub = _server.responses.listen(_handleResponse);
    _requestsSub = _server.requests.listen(_handleIncomingRequest);
  }

  final PairingServer _server;
  final PairingClient _client;
  final DevicesRepository _devicesRepository;
  final MetadataSyncService _metadataSyncService;
  final String _selfId;
  final String _selfName;
  final String _selfProfileHash;
  final Future<void> Function(IncomingPairingRequest request) _onJoinDifferentProfile;
  final Future<bool> Function() _canJoinDifferentProfile;
  final int pairingPort;
  final int metadataSyncPort;

  late final StreamSubscription<PairingResponse> _responsesSub;
  late final StreamSubscription<IncomingPairingRequest> _requestsSub;
  final _filteredRequests = StreamController<IncomingPairingRequest>.broadcast();

  /// Requests from other devices waiting on *this* device's user to
  /// approve/reject — UI shows a dialog for each. Already filtered: a
  /// request for a profile this device can't legitimately join never
  /// reaches this stream (see the class doc).
  Stream<IncomingPairingRequest> get incomingRequests => _filteredRequests.stream;

  Future<void> _handleIncomingRequest(IncomingPairingRequest request) async {
    if (request.profileHash == _selfProfileHash || await _canJoinDifferentProfile()) {
      _filteredRequests.add(request);
      return;
    }
    // Different profile, and this device isn't explicitly waiting to
    // join one — auto-decline. No dialog: there's nothing the user could
    // meaningfully approve here, see docs/adr/0017.
    await _client.sendResponse(
      host: request.fromHost,
      port: pairingPort,
      fromId: _selfId,
      fromName: _selfName,
      accepted: false,
      profileHash: _selfProfileHash,
    );
  }

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

  /// The user approved an incoming request — only ever called for a
  /// request that reached [incomingRequests], so it's already known to be
  /// legitimate (same profile, or an explicitly-allowed join).
  ///
  /// Same profile: acknowledge and pair immediately, under this device's
  /// current (and, since the hash matches, permanent) identity.
  ///
  /// Different profile: **does not respond here at all** — this
  /// [PairingService] instance belongs to a session that [onJoinDifferentProfile]
  /// is about to close, and a CRDT node id is per-database, not
  /// per-device (docs/adr/0013-account-profiles.md): the identity
  /// (`_selfId`/`_selfName`) this instance would respond with is about to
  /// become permanently stale the moment the switch happens. Responding
  /// now would leave the requester holding a `devices` row for an id that
  /// no longer exists anywhere, which nothing ever cleans up — the
  /// requester would show two entries for what's really one device: a
  /// dead one under the old name, and (once sync catches up, if it even
  /// gets authorized to — the requester never learns the new id any
  /// other way) a live one under the new name. `onJoinDifferentProfile`
  /// is expected to switch profiles and then call `approve` *again*, this
  /// time on the new session's `PairingService` — where the hash matches
  /// by construction, so it responds and pairs correctly, exactly once,
  /// under the one identity that's actually going to stick around.
  Future<void> approve(IncomingPairingRequest request) async {
    if (request.profileHash != _selfProfileHash) {
      await _onJoinDifferentProfile(request);
      return;
    }
    await _client.sendResponse(
      host: request.fromHost,
      port: pairingPort,
      fromId: _selfId,
      fromName: _selfName,
      accepted: true,
      profileHash: _selfProfileHash,
    );
    await _pair(id: request.fromId, name: request.fromName, host: request.fromHost);
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

  Future<void> _handleResponse(PairingResponse response) async {
    if (!response.accepted) return;
    // We're always the requester here, and pairing only ever means "same
    // profile" now (docs/adr/0017) — nothing to switch, just pair.
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

  Future<void> dispose() async {
    await _responsesSub.cancel();
    await _requestsSub.cancel();
    await _filteredRequests.close();
  }
}
