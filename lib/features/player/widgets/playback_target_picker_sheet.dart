import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/track.dart';
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
            // Not Icons.smartphone — see full_player_screen.dart's cast
            // icon comment for why some icons don't survive release
            // icon tree-shaking; Icons.devices is already proven safe.
            leading: const Icon(Icons.devices),
            title: Text(l10n.playbackTargetThisDevice),
            trailing: target is LocalPlaybackTarget ? const Icon(Icons.check) : null,
            onTap: target is LocalPlaybackTarget ? null : () => _pullBack(context, ref),
          ),
          for (final device in candidates)
            ListTile(
              leading: const Icon(Icons.devices_other),
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

  /// Captures this device's current queue+position and sends it *in
  /// the same claim* that asks [deviceId] to become owner — one round
  /// trip, atomic: [PlaybackOwnershipCoordinator.claimForDevice] only
  /// ever returns `true` once the target has *already* successfully
  /// loaded and started that exact queue (see
  /// [PlaybackOwnershipCoordinator.claimForDevice]'s doc). So by the
  /// time this pauses locally, the target is guaranteed to actually be
  /// playing — no separate "did the queue-transfer half also succeed"
  /// step that could fail independently and leave both devices
  /// disagreeing about who's playing (one paused-but-not-really,
  /// one "owner" but with nothing loaded). A rejected/timed-out/offline
  /// target leaves this device's local playback untouched entirely.
  /// See docs/adr/0033-playback-ownership-and-handoff.md.
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

    final claimed = await ref.read(playbackOwnershipCoordinatorProvider).claimForDevice(
          deviceId,
          queueTrackIds: tracks.map((t) => t.id).toList(),
          queueIndex: index,
          positionMs: position.inMilliseconds,
        );
    if (!claimed) {
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.playbackTargetHandoffFailed(deviceName))));
      return;
    }

    // The target is confirmed actually playing this queue already
    // (that's what `claimed == true` means now) — safe to pause here.
    await playerService.pause();
    navigator.pop();
  }

  /// "Это устройство" — always a reactive, unacknowledged claim (see
  /// [PlaybackOwnershipCoordinator.claimSelf]'s doc), since there's no
  /// third party to ack. Restores the remote device's *whole* queue
  /// (`RemoteState.queueTrackIds`), not just the single current track —
  /// a single-track queue would leave this device's own next/previous
  /// with nothing to move to, the same regression ADR 0030 already
  /// fixed once for the forward handoff direction.
  Future<void> _pullBack(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final target = ref.read(activePlaybackTargetProvider).value;
    if (target is! RemotePlaybackTarget) {
      navigator.pop();
      return;
    }
    final state = ref.read(remoteControlConnectionProvider(target.deviceId)).value?.state;
    ref.read(playbackOwnershipCoordinatorProvider).claimSelf();

    if (state != null && state.queueTrackIds.isNotEmpty) {
      // Same "resolve ids -> tracks this device actually has, re-find
      // the start track by id (not position, since dropping unavailable
      // tracks can shift indices)" logic `RemoteControlServer._apply`
      // already applies to `RemoteLoadAndPlay` — duplicated rather than
      // shared, since that lives in a plain Dart service with no
      // `WidgetRef`/`tracksRepositoryProvider` access.
      final tracksRepository = ref.read(tracksRepositoryProvider);
      final startId =
          state.queueIndex >= 0 && state.queueIndex < state.queueTrackIds.length
              ? state.queueTrackIds[state.queueIndex]
              : state.trackId;
      final tracks = <Track>[];
      for (final id in state.queueTrackIds) {
        final track = await tracksRepository.byId(id);
        if (track != null && track.isAvailableLocally) tracks.add(track);
      }
      final resolvedIndex = tracks.indexWhere((t) => t.id == startId);
      if (resolvedIndex >= 0) {
        await ref.read(playerServiceProvider).setQueue(
          tracks,
          startIndex: resolvedIndex,
          autoPlay: true,
          seekTo: Duration(milliseconds: state.positionMs),
        );
      }
    }
    navigator.pop();
  }
}
