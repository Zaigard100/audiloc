import 'dart:async';

import '../../data/models/device.dart';
import '../../data/repositories/devices_repository.dart';
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
    required DiscoveryService discoveryService,
    required MetadataSyncService metadataSyncService,
    required DevicesRepository devicesRepository,
  })  : _discoveryService = discoveryService,
        _metadataSyncService = metadataSyncService,
        _devicesRepository = devicesRepository {
    _discoverySub = _discoveryService.events.listen(_handleDiscoveryEvent);
    _statsSub = _metadataSyncService.onChangesetApplied.listen(_recentSyncController.add);
  }

  final DiscoveryService _discoveryService;
  final MetadataSyncService _metadataSyncService;
  final DevicesRepository _devicesRepository;

  late final StreamSubscription<DiscoveryEvent> _discoverySub;
  late final StreamSubscription<SyncStats> _statsSub;

  final _recentSyncController = StreamController<SyncStats>.broadcast();

  /// Feeds the "синхронизировано N изменений" badge (ТЗ п.6.6).
  Stream<SyncStats> get recentSyncs => _recentSyncController.stream;

  Future<void> start(int metadataSyncPort) async {
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
  }

  Future<void> _handleDiscoveryEvent(DiscoveryEvent event) async {
    switch (event) {
      case PeerFound(:final peer):
        // Only already-paired peers auto-sync — an unpaired one showing
        // up here is surfaced to the UI separately (nearbyPeersProvider)
        // so the user can send/receive a pairing request for it instead.
        final existing = await _devicesRepository.byId(peer.deviceId);
        if (existing == null) return;
        await _devicesRepository.upsert(Device(
          id: peer.deviceId,
          name: peer.name,
          host: peer.host,
          syncPort: peer.port,
          lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
        ));
        _metadataSyncService.connectToPeer(peer.deviceId, peer.metadataSyncUri);
      case PeerLost(:final deviceId):
        await _metadataSyncService.disconnectFromPeer(deviceId);
    }
  }

  /// Only tears down what this class created (subscriptions, its own
  /// stream). [_discoveryService] and [_metadataSyncService] are injected
  /// and owned by their own providers, which dispose them independently.
  Future<void> dispose() async {
    await _discoverySub.cancel();
    await _statsSub.cancel();
    await _recentSyncController.close();
  }
}
