import 'dart:async';

import '../../data/repositories/devices_repository.dart';
import '../../data/repositories/profile_settings_repository.dart';
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
    required PlaybackOwnershipServer server,
    this.port = 8547,
  }) : _devicesRepository = devicesRepository,
       _playerService = playerService,
       _server = server {
    _discoverySub = discoveryService.events.listen(_handleDiscoveryEvent);
    _acceptedSub = server.onAccepted.listen(_registerLink);
    _syncEnabledSub = profileSettingsRepository
        .watchSyncPlaybackEnabled()
        .listen(_handleSyncEnabledChanged);
  }

  final String selfDeviceId;
  final String selfDeviceName;
  final int port;
  final DevicesRepository _devicesRepository;
  final PlayerService _playerService;
  final PlaybackOwnershipServer _server;

  late final StreamSubscription<DiscoveryEvent> _discoverySub;
  late final StreamSubscription<PlaybackOwnershipLink> _acceptedSub;
  late final StreamSubscription<bool> _syncEnabledSub;

  final _links = <String, PlaybackOwnershipLink>{};
  final _linkMessageSubs = <String, StreamSubscription<OwnershipMessage>>{};
  final _onlinePeers = <String, DiscoveredPeer>{};

  bool _syncEnabled = false;
  String? _currentOwner;
  OwnershipClaim? _selfClaim;
  String? _lastHandoffInitiator;

  final _ownerController = StreamController<String?>.broadcast();

  /// `null` means unclaimed — no device currently owns playback.
  String? get currentOwner => _currentOwner;
  Stream<String?> get ownerChanges => _ownerController.stream;

  /// The device that most recently handed playback off to this one, if
  /// any — used by `RemoteControlServer`'s additive accept path so that
  /// device can immediately remote-control the result of its own
  /// handoff. See [_handleTargetedClaim].
  String? get lastHandoffInitiator => _lastHandoffInitiator;

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

  /// Manual handoff — asks [targetDeviceId] specifically to become
  /// owner, and waits for it to ack/reject/time out (3s). Returns
  /// `false` without touching anything if there's no live link to that
  /// device, sync is off, or the target declines/doesn't answer in
  /// time — callers must not touch local playback unless this returns
  /// `true` (see `playback_target_picker_sheet.dart`).
  Future<bool> claimForDevice(String targetDeviceId) async {
    if (!_syncEnabled) return false;
    final link = _links[targetDeviceId];
    if (link == null) return false;

    final claim = OwnershipClaim.now(
      deviceId: targetDeviceId,
      reason: ClaimReason.manualHandoff,
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
      const Duration(seconds: 3),
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
      for (final peer in _onlinePeers.values.toList()) {
        unawaited(_maybeDial(peer));
      }
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
      case OwnershipClaim(:final deviceId, :final claimId):
        if (deviceId == selfDeviceId) {
          _handleTargetedClaim(link, claimId);
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

  void _handleTargetedClaim(PlaybackOwnershipLink link, String claimId) {
    if (!_syncEnabled) {
      link.send(
        OwnershipClaimReject(claimId: claimId, reason: 'sync_disabled'),
      );
      return;
    }
    link.send(OwnershipClaimAck(claimId: claimId));
    _setOwner(
      selfDeviceId,
      claim: OwnershipClaim(
        deviceId: selfDeviceId,
        claimId: claimId,
        reason: ClaimReason.manualHandoff,
      ),
    );
    // Whoever just handed off to me is implicitly allowed to remote
    // -control me afterward, regardless of the separate "allow remote
    // control" toggle (ADR 0030) — this explicit ack *is* the consent.
    // See `RemoteControlServer`'s additive accept path.
    _lastHandoffInitiator = link.remoteDeviceId;
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
