import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/models/device.dart';
import '../../../services/sync/discovery/discovery_event.dart';
import '../../../services/sync/metadata/sync_stats.dart';

final knownDevicesProvider = StreamProvider<List<Device>>(
  (ref) => ref.watch(devicesRepositoryProvider).watchAll(),
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
