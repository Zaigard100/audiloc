/// A pairing request received from another device — surfaced to the UI so
/// the user can approve/reject it. See docs/adr/0011 and, for
/// [profileHash]'s role, docs/adr/0015-profile-identity-in-pairing.md.
class IncomingPairingRequest {
  const IncomingPairingRequest({
    required this.fromId,
    required this.fromName,
    required this.fromHost,
    required this.profileHash,
  });

  /// The requester's CRDT node id — what becomes the `devices.id` if
  /// approved.
  final String fromId;
  final String fromName;

  /// Taken from the request's actual socket address, not anything the
  /// request body claims — see [PairingServer].
  final String fromHost;

  /// The profile the requester wants this device added to. If this
  /// device's own current profile has a different hash, approving joins
  /// (creating a local copy if none exists yet) that profile instead of
  /// merging two independently-populated libraries together — see
  /// docs/adr/0015-profile-identity-in-pairing.md.
  final String profileHash;
}

/// The other side's answer to a request *we* sent via
/// [PairingService.requestPairing].
class PairingResponse {
  const PairingResponse({
    required this.fromId,
    required this.fromName,
    required this.fromHost,
    required this.accepted,
    required this.profileHash,
  });

  final String fromId;
  final String fromName;
  final String fromHost;
  final bool accepted;

  /// The responder's profile hash at the moment they answered. The
  /// requester never acts on this (its own profile is authoritative by
  /// convention — docs/adr/0015) — carried for symmetry/debugging only.
  final String profileHash;
}
