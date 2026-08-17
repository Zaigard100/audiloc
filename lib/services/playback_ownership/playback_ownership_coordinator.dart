import 'dart:async';

import '../../data/models/track.dart';
import '../../data/repositories/devices_repository.dart';
import '../../data/repositories/profile_settings_repository.dart';
import '../../data/repositories/tracks_repository.dart';
import '../playback/player_service.dart';
import '../sync/discovery/discovered_peer.dart';
import '../sync/discovery/discovery_event.dart';
import '../sync/discovery/discovery_service.dart';
import 'playback_ownership_client.dart';
import 'playback_ownership_link.dart';
import 'playback_ownership_models.dart';
import 'playback_ownership_server.dart';

/// The "who's currently allowed to make sound" glue — keeps a live
/// [PlaybackOwnershipLink] to every online, paired, sync-enabled peer
/// (mirroring `SyncOrchestrator`'s always-on mesh, not
/// `RemoteControlServer`'s "only while a `DeviceTile` is on screen"
/// scoping — exclusivity has to hold whether or not anyone's looking),
/// resolves claims, and exposes [currentOwner]/[ownerChanges] for
/// `ActivePlaybackTarget` to follow. See
/// docs/adr/0033-playback-ownership-and-handoff.md.
///
/// Inert whenever [ProfileSettingsRepository.watchSyncPlaybackEnabled] is
/// off — no links, no claims, no effect on local playback. Devices with
/// sync off are entirely outside this system: never dialed, never
/// accepted, never forced to pause.
class PlaybackOwnershipCoordinator {
  PlaybackOwnershipCoordinator({
    required this.selfDeviceId,
    required this.selfDeviceName,
    required DiscoveryService discoveryService,
    required DevicesRepository devicesRepository,
    required ProfileSettingsRepository profileSettingsRepository,
    required PlayerService playerService,
    required TracksRepository tracksRepository,
    required PlaybackOwnershipServer server,
    this.port = 8547,
  }) : _devicesRepository = devicesRepository,
       _playerService = playerService,
       _tracksRepository = tracksRepository,
       _server = server {
    _discoverySub = discoveryService.events.listen(_handleDiscoveryEvent);
    _acceptedSub = server.onAccepted.listen(_registerLink);
    _syncEnabledSub = profileSettingsRepository
        .watchSyncPlaybackEnabled()
        .listen(_handleSyncEnabledChanged);
    // Belt-and-braces on top of the reactive `PeerFound`-triggered
    // dial in `_maybeDial`: that alone depends on mDNS re-announcing a
    // peer again after a failed/dropped dial attempt (it does, but on
    // its own schedule, not ours) — this instead periodically checks
    // every peer we already know is online for a link we *should* have
    // but don't, and retries. Directly targets "handoff silently stops
    // working"/"both devices end up playing" once a link has quietly
    // gone missing and nothing happened to prompt a retry.
    _reconcileTimer = Timer.periodic(const Duration(seconds: 15), (_) => _reconcileLinks());
  }

  final String selfDeviceId;
  final String selfDeviceName;
  final int port;
  final DevicesRepository _devicesRepository;
  final PlayerService _playerService;
  final TracksRepository _tracksRepository;
  final PlaybackOwnershipServer _server;

  late final StreamSubscription<DiscoveryEvent> _discoverySub;
  late final StreamSubscription<PlaybackOwnershipLink> _acceptedSub;
  late final StreamSubscription<bool> _syncEnabledSub;
  Timer? _reconcileTimer;

  final _links = <String, PlaybackOwnershipLink>{};
  final _linkMessageSubs = <String, StreamSubscription<OwnershipMessage>>{};
  final _onlinePeers = <String, DiscoveredPeer>{};

  bool _syncEnabled = false;
  String? _currentOwner;
  OwnershipClaim? _selfClaim;

  final _ownerController = StreamController<String?>.broadcast();

  /// `null` means unclaimed — no device currently owns playback.
  String? get currentOwner => _currentOwner;
  Stream<String?> get ownerChanges => _ownerController.stream;

  /// Paired, online devices this coordinator currently has a live
  /// ownership link to — i.e. confirmed sync-enabled *right now*, not
  /// just paired. Backs the device picker's list.
  Set<String> get linkedDeviceIds => _links.keys.toSet();

  Future<void> start() => _server.start();

  /// Reactive claim — "I just started playing locally" (or "pull
  /// playback back to this device", which is the same broadcast, no
  /// third party to ack). Fire-and-forget: local audio isn't gated on
  /// the outcome. No-op while sync is off.
  void claimSelf({ClaimReason reason = ClaimReason.localPlay}) {
    if (!_syncEnabled) return;
    final claim = OwnershipClaim.now(deviceId: selfDeviceId, reason: reason);
    _setOwner(selfDeviceId, claim: claim);
    for (final link in _links.values) {
      link.send(claim);
    }
  }

  /// Manual handoff — asks [targetDeviceId] to become owner *and*
  /// carries the whole queue+position to hand it right in the claim
  /// itself (see [OwnershipClaim.queueTrackIds]'s doc for why this
  /// is one round trip, not claim-then-separately-transfer-the-queue).
  /// Waits for ack/reject/time out (5s — longer than the pre-atomicity
  /// version's 3s, since the target now has to actually load and start
  /// the queue before it can ack, not just reply). Returns `false`
  /// without touching anything if there's no live link to that device,
  /// sync is off, or the target declines/doesn't answer in time —
  /// callers must not touch local playback unless this returns `true`
  /// (see `playback_target_picker_sheet.dart`): a `false` here
  /// guarantees the target never actually started playing anything, so
  /// there's nothing to roll back.
  Future<bool> claimForDevice(
    String targetDeviceId, {
    required List<String> queueTrackIds,
    required int queueIndex,
    required int positionMs,
  }) async {
    if (!_syncEnabled) return false;
    final link = _links[targetDeviceId];
    if (link == null) return false;

    final claim = OwnershipClaim.now(
      deviceId: targetDeviceId,
      reason: ClaimReason.manualHandoff,
      queueTrackIds: queueTrackIds,
      queueIndex: queueIndex,
      positionMs: positionMs,
    );
    final completer = Completer<bool>();
    late StreamSubscription<OwnershipMessage> sub;
    sub = link.messages.listen((message) {
      if (completer.isCompleted) return;
      if (message is OwnershipClaimAck && message.claimId == claim.claimId) {
        completer.complete(true);
      } else if (message is OwnershipClaimReject &&
          message.claimId == claim.claimId) {
        completer.complete(false);
      }
    });

    link.send(claim);
    final accepted = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    await sub.cancel();
    if (accepted) {
      _setOwner(targetDeviceId);
      _gossipOwner(exclude: targetDeviceId);
    }
    return accepted;
  }

  Future<void> _handleDiscoveryEvent(DiscoveryEvent event) async {
    switch (event) {
      case PeerFound(:final peer):
        _onlinePeers[peer.deviceId] = peer;
        await _maybeDial(peer);
      case PeerLost(:final deviceId):
        _onlinePeers.remove(deviceId);
        _handlePeerGone(deviceId);
    }
  }

  void _handleSyncEnabledChanged(bool enabled) {
    final wasEnabled = _syncEnabled;
    _syncEnabled = enabled;
    if (wasEnabled && !enabled) {
      // Leaving the system entirely — release every link and any
      // ownership belief, don't leave a device that just opted out
      // still reachable for claims or still "controlled".
      for (final link in _links.values.toList()) {
        link.dispose();
      }
      _links.clear();
      for (final sub in _linkMessageSubs.values) {
        sub.cancel();
      }
      _linkMessageSubs.clear();
      _setOwner(null);
    } else if (!wasEnabled && enabled) {
      // Peers already online never re-fire PeerFound just because sync
      // turned on — reconcile explicitly against what's already known.
      _reconcileLinks();
    }
  }

  /// Retries [_maybeDial] for every peer we currently believe is
  /// online but don't have a link to — see the periodic timer in the
  /// constructor and the sync-just-turned-on case above, its two
  /// callers.
  void _reconcileLinks() {
    for (final peer in _onlinePeers.values.toList()) {
      if (!_links.containsKey(peer.deviceId)) unawaited(_maybeDial(peer));
    }
  }

  Future<void> _maybeDial(DiscoveredPeer peer) async {
    if (!_syncEnabled) return;
    if (_links.containsKey(peer.deviceId)) return;
    final paired = await _devicesRepository.byId(peer.deviceId) != null;
    if (!paired) return;
    // Same "only the lower id dials out" dedup as SyncOrchestrator
    // (docs/adr/0025-sync-and-discovery-reliability.md) — both sides
    // compute the same comparison, so exactly one of them ever dials.
    if (selfDeviceId.compareTo(peer.deviceId) >= 0) return;
    final link = await connectPlaybackOwnershipLink(
      host: peer.host,
      port: port,
      selfId: selfDeviceId,
      selfName: selfDeviceName,
      remoteDeviceId: peer.deviceId,
    );
    if (link != null) _registerLink(link);
  }

  void _registerLink(PlaybackOwnershipLink link) {
    final deviceId = link.remoteDeviceId;
    if (_links.containsKey(deviceId)) {
      link.dispose();
      return;
    }
    link.onLost = () => _handlePeerGone(deviceId);
    _links[deviceId] = link;
    _linkMessageSubs[deviceId] = link.messages.listen(
      (message) => _handleMessage(link, message),
    );
  }

  void _handlePeerGone(String deviceId) {
    _linkMessageSubs.remove(deviceId)?.cancel();
    _links.remove(deviceId);
    if (_currentOwner == deviceId) _setOwner(null);
  }

  void _handleMessage(PlaybackOwnershipLink link, OwnershipMessage message) {
    switch (message) {
      case OwnershipClaim(:final deviceId):
        if (deviceId == selfDeviceId) {
          unawaited(_handleTargetedClaim(link, message));
        } else {
          _handleIncomingSelfClaim(message);
        }
      case OwnershipOwner(:final deviceId):
        _handleGossip(deviceId);
      case OwnershipClaimAck() || OwnershipClaimReject():
        // Handled by the completer set up in claimForDevice() — nothing
        // to do here.
        break;
      case OwnershipHeartbeat():
        break; // liveness alone already updates the link's watchdog.
    }
  }

  /// Only ever sends [OwnershipClaimAck] *after* successfully loading
  /// and starting [claim]'s queue — see [OwnershipClaim.queueTrackIds]'s
  /// doc for why the ack itself needs to mean "actually playing now",
  /// not "agreed to try". Rejects (never partially applies) if the
  /// queue is empty, sync is off, or the requested start track isn't
  /// resolvable here — same "resolve ids -> tracks this device
  /// actually has, re-find the start by id since dropping unavailable
  /// ones shifts indices" logic `RemoteControlServer._apply` already
  /// applies to `RemoteLoadAndPlay` (ADR 0030), duplicated rather than
  /// shared since that lives in a different service with its own
  /// dependencies.
  Future<void> _handleTargetedClaim(PlaybackOwnershipLink link, OwnershipClaim claim) async {
    if (!_syncEnabled) {
      link.send(OwnershipClaimReject(claimId: claim.claimId, reason: 'sync_disabled'));
      return;
    }
    if (claim.queueTrackIds.isEmpty || claim.queueIndex < 0 || claim.queueIndex >= claim.queueTrackIds.length) {
      link.send(OwnershipClaimReject(claimId: claim.claimId, reason: 'empty_queue'));
      return;
    }

    final startId = claim.queueTrackIds[claim.queueIndex];
    final tracks = <Track>[];
    for (final id in claim.queueTrackIds) {
      final track = await _tracksRepository.byId(id);
      if (track != null && track.isAvailableLocally) tracks.add(track);
    }
    final resolvedIndex = tracks.indexWhere((t) => t.id == startId);
    if (resolvedIndex < 0) {
      link.send(OwnershipClaimReject(claimId: claim.claimId, reason: 'track_not_available'));
      return;
    }

    await _playerService.setQueue(
      tracks,
      startIndex: resolvedIndex,
      autoPlay: true,
      seekTo: Duration(milliseconds: claim.positionMs),
    );

    link.send(OwnershipClaimAck(claimId: claim.claimId));
    _setOwner(selfDeviceId, claim: claim);
    _gossipOwner(exclude: link.remoteDeviceId);
  }

  /// A peer claiming ownership for itself — either an ordinary handover
  /// (I'm not currently playing, nothing contested) or a genuine race
  /// (I believe *I'm* the owner too, from a claim of my own close enough
  /// in time to be ambiguous). Both are resolved by the same comparison:
  /// see [OwnershipClaim.compareTo].
  void _handleIncomingSelfClaim(OwnershipClaim incoming) {
    if (_currentOwner == selfDeviceId &&
        _selfClaim != null &&
        _selfClaim!.compareTo(incoming) > 0) {
      // I win — the peer will independently reach the same conclusion
      // from its own copy of my claim and pause itself; nothing more to
      // do here.
      return;
    }
    final iWasOwner = _currentOwner == selfDeviceId;
    _setOwner(incoming.deviceId);
    if (iWasOwner) unawaited(_playerService.pause());
  }

  void _handleGossip(String? deviceId) {
    if (_currentOwner == selfDeviceId && deviceId != selfDeviceId) {
      // Trusted like a claim — gossip only ever originates from an
      // already-resolved claim elsewhere in the mesh.
      unawaited(_playerService.pause());
    }
    _setOwner(deviceId);
  }

  void _gossipOwner({String? exclude}) {
    final message = OwnershipOwner(
      deviceId: _currentOwner,
      since: DateTime.now().millisecondsSinceEpoch,
    );
    for (final entry in _links.entries) {
      if (entry.key == exclude) continue;
      entry.value.send(message);
    }
  }

  void _setOwner(String? deviceId, {OwnershipClaim? claim}) {
    if (_currentOwner == deviceId) {
      if (deviceId == selfDeviceId && claim != null) _selfClaim = claim;
      return;
    }
    _currentOwner = deviceId;
    _selfClaim = deviceId == selfDeviceId ? claim : null;
    _ownerController.add(deviceId);
  }

  Future<void> dispose() async {
    _reconcileTimer?.cancel();
    await _discoverySub.cancel();
    await _acceptedSub.cancel();
    await _syncEnabledSub.cancel();
    for (final link in _links.values.toList()) {
      link.dispose();
    }
    _links.clear();
    for (final sub in _linkMessageSubs.values) {
      await sub.cancel();
    }
    _linkMessageSubs.clear();
    await _ownerController.close();
  }
}
