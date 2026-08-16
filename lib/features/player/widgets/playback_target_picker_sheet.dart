import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../../devices/providers/devices_providers.dart';
import '../../devices/providers/remote_control_providers.dart';
import '../providers/player_providers.dart';
import '../providers/playback_ownership_providers.dart';
import '../providers/queue_resolution.dart';

/// Spotify-Connect-style device picker, opened from the cast icon on the
/// full player screen — see docs/adr/0033-playback-ownership-and-handoff.md.
/// Lists paired devices this coordinator currently has a live ownership
/// link to (i.e. confirmed sync-enabled *right now*, not just paired —
/// [PlaybackOwnershipCoordinator.linkedDeviceIds]), plus a pinned "this
/// device" entry.
Future<void> showPlaybackTargetPicker(BuildContext context, WidgetRef ref) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PlaybackTargetPickerSheet(),
    );

class _PlaybackTargetPickerSheet extends ConsumerWidget {
  const _PlaybackTargetPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final target = ref.watch(activePlaybackTargetProvider).value ?? const LocalPlaybackTarget();
    final linkedIds = ref.watch(playbackOwnershipCoordinatorProvider).linkedDeviceIds;
    final knownDevices = ref.watch(knownDevicesProvider).value ?? const [];
    final candidates = knownDevices.where((d) => linkedIds.contains(d.id)).toList();

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(l10n.playbackTargetPickerTitle, style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.smartphone),
            title: Text(l10n.playbackTargetThisDevice),
            trailing: target is LocalPlaybackTarget ? const Icon(Icons.check) : null,
            onTap: target is LocalPlaybackTarget ? null : () => _pullBack(context, ref),
          ),
          for (final device in candidates)
            ListTile(
              leading: const Icon(Icons.speaker_outlined),
              title: Text(device.name),
              trailing: target is RemotePlaybackTarget && target.deviceId == device.id
                  ? const Icon(Icons.check)
                  : null,
              onTap: target is RemotePlaybackTarget && target.deviceId == device.id
                  ? null
                  : () => _handOff(context, ref, device.id, device.name),
            ),
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                l10n.playbackTargetNoDevices,
                style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }

  /// Captures this device's current queue+position, asks [deviceId] to
  /// become owner, and — only once that's confirmed *and* a
  /// remote-control connection to it is actually accepted — sends it
  /// the queue and pauses locally. Local playback is never touched
  /// unless every step above succeeds, so a rejected/timed-out/offline
  /// target never leaves this device stranded mid-handoff. See
  /// docs/adr/0033-playback-ownership-and-handoff.md.
  Future<void> _handOff(BuildContext context, WidgetRef ref, String deviceId, String deviceName) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final playerService = ref.read(playerServiceProvider);
    final currentTrack = playerService.currentTrack;
    if (currentTrack == null) {
      navigator.pop();
      return;
    }
    final tracks = await resolveQueueTracks(ref, ref.read(queueSourceProvider));
    final index = tracks.indexWhere((t) => t.id == currentTrack.id);
    if (index < 0) {
      navigator.pop();
      return;
    }
    final position = playerService.position;

    final claimed = await ref.read(playbackOwnershipCoordinatorProvider).claimForDevice(deviceId);
    if (!claimed) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.playbackTargetHandoffFailed(deviceName))));
      return;
    }

    // The target just became owner — the additive accept path in
    // RemoteControlServer (ADR 0033) now lets this device's own
    // remote-control connection through regardless of the "allow
    // remote control" toggle, but the connection itself still needs a
    // moment to actually establish.
    final connected = await _awaitRemoteControlAccepted(ref, deviceId);
    if (!connected) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.playbackTargetHandoffFailed(deviceName))));
      return;
    }

    ref.read(remoteControlControllerProvider(deviceId)).loadAndPlay(
          tracks.map((t) => t.id).toList(),
          index,
          position,
        );
    await playerService.pause();
    navigator.pop();
  }

  /// "Это устройство" — always a reactive, unacknowledged claim (see
  /// [PlaybackOwnershipCoordinator.claimSelf]'s doc), since there's no
  /// third party to ack. Restores only the single current track, not
  /// the remote device's whole queue — `RemoteState` doesn't carry a
  /// queue today (a scoped-down v1, see
  /// docs/adr/0033-playback-ownership-and-handoff.md's "Файлы" section
  /// for the follow-up this leaves open).
  Future<void> _pullBack(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final target = ref.read(activePlaybackTargetProvider).value;
    if (target is! RemotePlaybackTarget) {
      navigator.pop();
      return;
    }
    final state = ref.read(remoteControlConnectionProvider(target.deviceId)).value?.state;
    ref.read(playbackOwnershipCoordinatorProvider).claimSelf();

    final trackId = state?.trackId;
    if (trackId != null) {
      final track = await ref.read(tracksRepositoryProvider).byId(trackId);
      if (track != null && track.isAvailableLocally) {
        await ref.read(playerServiceProvider).setQueue(
          [track],
          autoPlay: true,
          seekTo: Duration(milliseconds: state!.positionMs),
        );
      }
    }
    navigator.pop();
  }
}

/// `remoteControlConnectionProvider` is `.autoDispose` — a bare
/// `ref.read()` wouldn't keep it alive long enough to actually reach
/// `accepted`. `listenManual` (same pattern as `awaitFirstValue`,
/// `queue_resolution.dart`) keeps it alive for exactly as long as this
/// waits, no longer.
Future<bool> _awaitRemoteControlAccepted(
  WidgetRef ref,
  String deviceId, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final completer = Completer<bool>();
  final sub = ref.listenManual(remoteControlConnectionProvider(deviceId), (previous, next) {
    final status = next.value?.status;
    if (completer.isCompleted) return;
    if (status == RemoteControlStatus.accepted) {
      completer.complete(true);
    } else if (status == RemoteControlStatus.rejected) {
      completer.complete(false);
    }
  }, fireImmediately: true);
  final result = await completer.future.timeout(timeout, onTimeout: () => false);
  sub.close();
  return result;
}
