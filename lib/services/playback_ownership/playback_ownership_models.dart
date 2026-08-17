/// Wire messages for `PlaybackOwnershipLink` — plain JSON over a single
/// `dart:io` `WebSocket` per pair of sync-enabled devices, symmetric once
/// established (either side can claim/gossip/heartbeat). See
/// docs/adr/0033-playback-ownership-and-handoff.md.
///
/// Separate protocol/port from `remote_control_models.dart` — deliberately:
/// ownership must be gated by the profile-wide sync toggle alone, never by
/// the (usually off) "allow remote control" toggle those messages are
/// gated by.

/// Why a given device is claiming ownership — carried for debugging/UI
/// purposes only, doesn't change how a claim is resolved.
enum ClaimReason { localPlay, manualHandoff }

sealed class OwnershipMessage {
  const OwnershipMessage();

  Map<String, Object?> toJson();

  static OwnershipMessage? fromJson(Map<String, Object?> json) =>
      switch (json['type']) {
        'claim' when json['deviceId'] is String && json['claimId'] is String =>
          OwnershipClaim(
            deviceId: json['deviceId']! as String,
            claimId: json['claimId']! as String,
            reason: ClaimReason.values.firstWhere(
              (r) => r.name == json['reason'],
              orElse: () => ClaimReason.localPlay,
            ),
            queueTrackIds:
                json['queueTrackIds'] is List ? (json['queueTrackIds']! as List).cast<String>() : const [],
            queueIndex: json['queueIndex'] as int? ?? -1,
            positionMs: json['positionMs'] as int? ?? 0,
          ),
        'claim_ack' when json['claimId'] is String => OwnershipClaimAck(
          claimId: json['claimId']! as String,
        ),
        'claim_reject' when json['claimId'] is String => OwnershipClaimReject(
          claimId: json['claimId']! as String,
          reason: json['reason'] as String? ?? '',
        ),
        'owner' => OwnershipOwner(
          deviceId: json['deviceId'] as String?,
          since: json['since'] as int? ?? 0,
        ),
        'heartbeat' => const OwnershipHeartbeat(),
        _ => null,
      };
}

/// `claimId` is `'<millisSinceEpoch>-<deviceId becoming owner>'` — unique
/// enough for ack/reject correlation, and directly comparable (see
/// [OwnershipClaim.compareTo]) to resolve two near-simultaneous claims
/// without a round trip: higher millis wins, ties broken by comparing
/// `deviceId` lexicographically (same tiebreak idiom already used for
/// sync's dial-out dedup, docs/adr/0025-sync-and-discovery-reliability.md).
class OwnershipClaim extends OwnershipMessage {
  OwnershipClaim({
    required this.deviceId,
    required this.claimId,
    required this.reason,
    this.queueTrackIds = const [],
    this.queueIndex = -1,
    this.positionMs = 0,
  });

  factory OwnershipClaim.now({
    required String deviceId,
    required ClaimReason reason,
    List<String> queueTrackIds = const [],
    int queueIndex = -1,
    int positionMs = 0,
  }) => OwnershipClaim(
    deviceId: deviceId,
    claimId: '${DateTime.now().millisecondsSinceEpoch}-$deviceId',
    reason: reason,
    queueTrackIds: queueTrackIds,
    queueIndex: queueIndex,
    positionMs: positionMs,
  );

  /// The device becoming owner — usually the sender itself (a reactive
  /// "I just started playing" claim), but for a manual handoff this is
  /// the *target* device, sent by the initiator to that target
  /// specifically asking it to become owner.
  final String deviceId;
  final String claimId;
  final ClaimReason reason;

  /// Only meaningful for [ClaimReason.manualHandoff] — the initiator's
  /// whole queue and position, carried *in the claim itself* rather
  /// than as a separate follow-up message, so accepting a handoff is a
  /// single round trip: the target only ever sends [OwnershipClaimAck]
  /// after it has *already* successfully loaded and started this queue
  /// (see `PlaybackOwnershipCoordinator._handleTargetedClaim`), never
  /// before. This is what makes the ack mean "I am now actually
  /// playing this", not just "I agree to try" — a separate
  /// claim-then-loadAndPlay sequence left a window where the claim
  /// half could succeed (ownership flips) while the follow-up
  /// queue-transfer half failed independently (a `RemoteControlServer`
  /// connection timeout, say), stranding the initiator paused with
  /// nothing actually playing anywhere.
  final List<String> queueTrackIds;
  final int queueIndex;
  final int positionMs;

  int get _millis =>
      int.tryParse(claimId.substring(0, claimId.indexOf('-'))) ?? 0;

  /// Higher millis wins; ties broken by comparing `deviceId`. A positive
  /// result means `this` wins over [other].
  int compareTo(OwnershipClaim other) {
    final millisCompare = _millis.compareTo(other._millis);
    return millisCompare != 0
        ? millisCompare
        : deviceId.compareTo(other.deviceId);
  }

  @override
  Map<String, Object?> toJson() => {
    'type': 'claim',
    'deviceId': deviceId,
    'claimId': claimId,
    'reason': reason.name,
    'queueTrackIds': queueTrackIds,
    'queueIndex': queueIndex,
    'positionMs': positionMs,
  };
}

class OwnershipClaimAck extends OwnershipMessage {
  const OwnershipClaimAck({required this.claimId});
  final String claimId;
  @override
  Map<String, Object?> toJson() => {'type': 'claim_ack', 'claimId': claimId};
}

class OwnershipClaimReject extends OwnershipMessage {
  const OwnershipClaimReject({required this.claimId, required this.reason});
  final String claimId;
  final String reason;
  @override
  Map<String, Object?> toJson() => {
    'type': 'claim_reject',
    'claimId': claimId,
    'reason': reason,
  };
}

/// Gossiped on every ownership change — `deviceId` is `null` when
/// ownership is unclaimed (a former owner's link was lost, and nothing's
/// claimed it since).
class OwnershipOwner extends OwnershipMessage {
  const OwnershipOwner({required this.deviceId, required this.since});
  final String? deviceId;
  final int since;
  @override
  Map<String, Object?> toJson() => {
    'type': 'owner',
    'deviceId': deviceId,
    'since': since,
  };
}

class OwnershipHeartbeat extends OwnershipMessage {
  const OwnershipHeartbeat();
  @override
  Map<String, Object?> toJson() => const {'type': 'heartbeat'};
}
