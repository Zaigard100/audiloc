import 'dart:async';

import '../../data/models/device.dart';
import '../../data/repositories/devices_repository.dart';
import 'discovery/discovered_peer.dart';
import 'discovery/discovery_event.dart';
import 'discovery/discovery_service.dart';
import 'metadata/metadata_sync_service.dart';
import 'metadata/sync_stats.dart';

/// The "клей" (glue, ТЗ п.4) between discovery and metadata sync: when an
/// *already paired* peer appears on the LAN, refresh it in `devices` and
/// open a sync connection automatically (ТЗ п.7 — no manual action
/// required once paired); when it disappears, tear the connection down.
///
/// Peers that aren't paired yet are deliberately left alone here — see
/// docs/adr/0011-mutual-pairing-confirmation.md. `PairingService` is what
/// turns a first-seen peer into a `devices` row (with the user's
/// confirmation on both sides); this class only ever auto-syncs peers
/// that already made it into that table.
class SyncOrchestrator {
  SyncOrchestrator({
    required String selfDeviceId,
    required DiscoveryService discoveryService,
    required MetadataSyncService metadataSyncService,
    required DevicesRepository devicesRepository,
  })  : _selfDeviceId = selfDeviceId,
        _discoveryService = discoveryService,
        _metadataSyncService = metadataSyncService,
        _devicesRepository = devicesRepository {
    _discoverySub = _discoveryService.events.listen(_handleDiscoveryEvent);
    _statsSub = _metadataSyncService.onChangesetApplied.listen(_recentSyncController.add);
  }

  final String _selfDeviceId;
  final DiscoveryService _discoveryService;
  final MetadataSyncService _metadataSyncService;
  final DevicesRepository _devicesRepository;

  late final StreamSubscription<DiscoveryEvent> _discoverySub;
  late final StreamSubscription<SyncStats> _statsSub;

  final _recentSyncController = StreamController<SyncStats>.broadcast();

  int? _metadataSyncPort;
  Timer? _refreshTimer;

  /// Feeds the "синхронизировано N изменений" badge (ТЗ п.6.6).
  Stream<SyncStats> get recentSyncs => _recentSyncController.stream;

  Future<void> start(int metadataSyncPort) async {
    _metadataSyncPort = metadataSyncPort;
    await _metadataSyncService.startServer();
    try {
      await _discoveryService.startAdvertising(metadataSyncPort);
      await _discoveryService.startDiscovery();
    } catch (_) {
      // mDNS goes through a platform plugin (bonsoir) — a flaky
      // environment there (missing multicast permissions, no plugin
      // binding in a test harness, whatever) shouldn't stop the rest of
      // the app from working. Sync is a bonus, not a gate (ТЗ п.7); the
      // metadata sync server above is already up regardless.
    }
    // Automatic counterpart to [restartDiscovery]'s manual button — the
    // user asked for devices that are genuinely online to just always
    // show up, without having to remember to press "обновить" whenever
    // that happens. Runs [DiscoveryService.refresh], not [.restart]: no
    // [PeerPresenceTracker.reset], so peers that are still actually
    // online never visibly flap offline-then-online every cycle — only
    // the native mDNS listener/broadcast gets torn down and
    // re-established, the same recovery the manual button already
    // relies on for a listener that silently got stuck (Wi-Fi network
    // switch, doze/sleep). 45s: frequent enough that "стал доступен"
    // shows up promptly, far below the sync-storm territory ADR
    // 0025 hit at "on every mDNS re-announce" (bonsoir itself
    // re-announces roughly every few seconds).
    _refreshTimer = Timer.periodic(const Duration(seconds: 45), (_) => restartDiscovery(gentle: true));
  }

  /// Bound to the manual "обновить" button on the Устройства screen —
  /// see docs/adr/0026-manual-discovery-refresh.md. The debounce/replay in
  /// `PeerPresenceTracker` (docs/adr/0025-sync-and-discovery-reliability.md)
  /// already self-heals ordinary mDNS flapping automatically; this exists
  /// for what that can't: the OS-level mDNS listener itself getting stuck
  /// (a Wi-Fi network switch, doze/sleep, a long time backgrounded) is
  /// invisible from inside a running discovery stream — nothing short of
  /// actually tearing it down and starting a fresh one recovers from it.
  ///
  /// [gentle] (only ever `true` for the periodic timer in [start]) skips
  /// [PeerPresenceTracker.reset]'s immediate "everyone just went
  /// offline" signal — see [DiscoveryService.refresh]'s doc for why the
  /// manual button and the automatic timer need different behavior here.
  Future<void> restartDiscovery({bool gentle = false}) async {
    final port = _metadataSyncPort;
    if (port == null) return; // start() never ran yet — nothing to restart
    try {
      if (gentle) {
        await _discoveryService.refresh(port);
      } else {
        await _discoveryService.restart(port);
      }
    } catch (_) {
      // Same reasoning as start() — mDNS is a bonus, not a gate.
    }
  }

  Future<void> _handleDiscoveryEvent(DiscoveryEvent event) async {
    switch (event) {
      case PeerFound(:final peer):
        // Only already-paired peers auto-sync — an unpaired one showing
        // up here is surfaced to the UI separately (nearbyPeersProvider)
        // so the user can send/receive a pairing request for it instead.
        final existing = await _devicesRepository.byId(peer.deviceId);
        if (existing == null) return;
        await _refreshDeviceRecord(existing, peer);
        // Both sides discover each other via mDNS and would otherwise
        // each dial out independently, opening two redundant connections
        // for the same pair — doubling traffic, and with 3+ mutually
        // paired devices, doubling every hop of the relay each of those
        // connections' server side also does for third-party changes
        // (docs/adr/0025-sync-and-discovery-reliability.md). Only the side whose
        // id sorts lower initiates; the other just accepts the incoming
        // connection — both sides compute the same comparison, so exactly
        // one of them ever dials.
        if (_selfDeviceId.compareTo(peer.deviceId) < 0) {
          _metadataSyncService.connectToPeer(peer.deviceId, peer.metadataSyncUri);
        }
      case PeerLost(:final deviceId):
        await _metadataSyncService.disconnectFromPeer(deviceId);
    }
  }

  /// `devices` is a CRDT table — any write here is synced to every paired
  /// peer. Unconditionally upserting on every discovery event (bonsoir
  /// re-announces each peer periodically, more often in aggregate with
  /// more devices) turned into a steady drip of no-op "changes" rippling
  /// around the mesh, which is most of what showed up as "endless
  /// synchronization" with 3+ devices (docs/adr/0025-sync-and-discovery-reliability.md).
  /// Only actually write when the address moved, or occasionally so
  /// "last seen" stays roughly fresh for when the device does go offline.
  Future<void> _refreshDeviceRecord(Device existing, DiscoveredPeer peer) async {
    final addressChanged = existing.host != peer.host || existing.syncPort != peer.port;
    if (addressChanged) {
      await _devicesRepository.upsert(Device(
        id: peer.deviceId,
        name: peer.name,
        host: peer.host,
        syncPort: peer.port,
        lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
      ));
      return;
    }
    final lastSeen = existing.lastOnlineAtDate;
    if (lastSeen == null || DateTime.now().difference(lastSeen) > const Duration(minutes: 5)) {
      await _devicesRepository.touchLastOnline(peer.deviceId, DateTime.now());
    }
  }

  /// Only tears down what this class created (subscriptions, its own
  /// stream). [_discoveryService] and [_metadataSyncService] are injected
  /// and owned by their own providers, which dispose them independently.
  Future<void> dispose() async {
    _refreshTimer?.cancel();
    await _discoverySub.cancel();
    await _statsSub.cancel();
    await _recentSyncController.close();
  }
}
