/// A pairing request received from another device — surfaced to the UI so
/// the user can approve/reject it. See docs/adr/0011.
class IncomingPairingRequest {
  const IncomingPairingRequest({
    required this.fromId,
    required this.fromName,
    required this.fromHost,
  });

  /// The requester's CRDT node id — what becomes the `devices.id` if
  /// approved.
  final String fromId;
  final String fromName;

  /// Taken from the request's actual socket address, not anything the
  /// request body claims — see [PairingServer].
  final String fromHost;
}

/// The other side's answer to a request *we* sent via
/// [PairingService.requestPairing].
class PairingResponse {
  const PairingResponse({
    required this.fromId,
    required this.fromName,
    required this.fromHost,
    required this.accepted,
  });

  final String fromId;
  final String fromName;
  final String fromHost;
  final bool accepted;
}
