import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Which device the full player screen should show/control right now —
/// see docs/adr/0033-playback-ownership-and-handoff.md. Never means
/// anything to any *other* reader in the app: the mini player, keyboard
/// shortcuts, `PlaybackStateWriter`, and incoming remote control from
/// another device all keep meaning "this device's own local player",
/// exactly as before — only `full_player_screen.dart` (via
/// `ActivePlaybackController`) switches based on this.
sealed class ActivePlaybackTarget {
  const ActivePlaybackTarget();
}

class LocalPlaybackTarget extends ActivePlaybackTarget {
  const LocalPlaybackTarget();
}

class RemotePlaybackTarget extends ActivePlaybackTarget {
  const RemotePlaybackTarget({required this.deviceId, required this.deviceName});
  final String deviceId;
  final String deviceName;
}

/// Follows [PlaybackOwnershipCoordinator.currentOwner] — `null`/self →
/// [LocalPlaybackTarget], anyone else → [RemotePlaybackTarget]. Falls
/// back to [LocalPlaybackTarget] whenever the profile-wide sync toggle
/// is off, since the whole ownership system is inert then (see
/// [PlaybackOwnershipCoordinator]'s doc) — there's no "owner" concept to
/// follow.
final activePlaybackTargetProvider = StreamProvider<ActivePlaybackTarget>((ref) {
  final syncEnabled = ref.watch(profileSyncEnabledProvider).value ?? false;
  if (!syncEnabled) return Stream.value(const LocalPlaybackTarget());

  final coordinator = ref.watch(playbackOwnershipCoordinatorProvider);
  final selfId = ref.watch(selfDeviceProvider).id;
  final devicesRepository = ref.watch(devicesRepositoryProvider);

  Future<ActivePlaybackTarget> resolve(String? ownerId) async {
    if (ownerId == null || ownerId == selfId) return const LocalPlaybackTarget();
    final device = await devicesRepository.byId(ownerId);
    return RemotePlaybackTarget(deviceId: ownerId, deviceName: device?.name ?? ownerId);
  }

  final controller = StreamController<ActivePlaybackTarget>();
  Future<void> emit(String? ownerId) async {
    if (controller.isClosed) return;
    controller.add(await resolve(ownerId));
  }

  unawaited(emit(coordinator.currentOwner));
  final sub = coordinator.ownerChanges.listen(emit);
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});
