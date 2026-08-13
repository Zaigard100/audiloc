import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/device.dart';
import '../../../services/sync/discovery/discovered_peer.dart';
import '../../../services/sync/discovery/discovery_event.dart';
import '../../../services/sync/metadata/sync_stats.dart';
import '../../../services/sync/pairing/pairing_models.dart';
import '../../../services/sync/share/share_models.dart';

final knownDevicesProvider = StreamProvider<List<Device>>(
  (ref) => ref.watch(devicesRepositoryProvider).watchAll(),
);

/// Every peer currently visible on the LAN via mDNS, paired or not —
/// raw discovery state, same source `onlineDeviceIdsProvider` taps.
final nearbyPeersProvider = StreamProvider<Map<String, DiscoveredPeer>>((ref) {
  final discovery = ref.watch(discoveryServiceProvider);
  final peers = <String, DiscoveredPeer>{};
  final controller = StreamController<Map<String, DiscoveredPeer>>.broadcast();

  final sub = discovery.events.listen((event) {
    switch (event) {
      case PeerFound(:final peer):
        peers[peer.deviceId] = peer;
      case PeerLost(:final deviceId):
        peers.remove(deviceId);
    }
    controller.add(Map.of(peers));
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Peers seen nearby that aren't in `devices` yet — candidates for
/// "Найдено рядом" (see docs/adr/0011-mutual-pairing-confirmation.md).
/// `SyncOrchestrator` deliberately never auto-adds these; this is purely
/// for the UI to offer a "Добавить" action.
final unpairedNearbyPeersProvider = Provider<List<DiscoveredPeer>>((ref) {
  final nearby = ref.watch(nearbyPeersProvider).value ?? const {};
  final pairedIds = (ref.watch(knownDevicesProvider).value ?? const []).map((d) => d.id).toSet();
  return [for (final peer in nearby.values) if (!pairedIds.contains(peer.deviceId)) peer];
});

/// Requests from other devices waiting for this device's user to
/// approve/reject — the app shell listens to this to pop up a dialog no
/// matter which tab is open.
final incomingPairingRequestsProvider = StreamProvider<IncomingPairingRequest>(
  (ref) => ref.watch(pairingServiceProvider).incomingRequests,
);

/// "Поделиться" offers waiting for this device's user to accept/decline —
/// same pattern as [incomingPairingRequestsProvider], but for
/// [shareServiceProvider] (docs/adr/0017-forbid-cross-profile-pairing-and-sharing.md).
final incomingShareOffersProvider = StreamProvider<IncomingShareOffer>(
  (ref) => ref.watch(shareServiceProvider).incomingOffers,
);

/// Live online/offline state, built from raw discovery events — never
/// persisted (see [Device] docs on why).
final onlineDeviceIdsProvider = StreamProvider<Set<String>>((ref) {
  final discovery = ref.watch(discoveryServiceProvider);
  final online = <String>{};
  final controller = StreamController<Set<String>>.broadcast();

  final sub = discovery.events.listen((event) {
    switch (event) {
      case PeerFound(:final peer):
        online.add(peer.deviceId);
      case PeerLost(:final deviceId):
        online.remove(deviceId);
    }
    controller.add(Set.of(online));
  });

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

final recentSyncsProvider = StreamProvider<SyncStats>(
  (ref) => ref.watch(syncOrchestratorProvider).recentSyncs,
);

class SyncBadgeState {
  const SyncBadgeState({this.recentCount});

  final int? recentCount;
}

/// Accumulates recently-applied changesets into a transient count for the
/// "синхронизировано N изменений" badge (ТЗ п.6.6), and clears it a few
/// seconds after the last change — the badge is meant to be a fleeting
/// "something just happened" hint, not a persistent counter.
class SyncBadgeNotifier extends Notifier<SyncBadgeState> {
  Timer? _clearTimer;

  @override
  SyncBadgeState build() {
    ref.listen<AsyncValue<SyncStats>>(recentSyncsProvider, (previous, next) {
      final stats = next.value;
      if (stats == null || stats.totalRecords == 0) return;
      state = SyncBadgeState(recentCount: (state.recentCount ?? 0) + stats.totalRecords);
      _clearTimer?.cancel();
      _clearTimer = Timer(const Duration(seconds: 6), () => state = const SyncBadgeState());
    });
    ref.onDispose(() => _clearTimer?.cancel());
    return const SyncBadgeState();
  }
}

final syncBadgeProvider = NotifierProvider<SyncBadgeNotifier, SyncBadgeState>(SyncBadgeNotifier.new);
