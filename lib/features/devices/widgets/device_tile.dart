import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/device.dart';
import '../../../l10n/l10n.dart';
import '../../../services/remote_control/remote_control_models.dart';
import '../../../services/sync/discovery/discovered_peer.dart';
import '../providers/remote_control_providers.dart';
import 'device_actions_sheet.dart';

class DeviceTile extends ConsumerWidget {
  const DeviceTile({super.key, required this.device, required this.isOnline});

  final Device device;
  final bool isOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Only attempted while online — nearbyPeersProvider (which the
    // connection provider watches) never has an entry for an offline
    // device anyway, but gating here too skips creating the family entry
    // at all for the common case of a paired-but-offline device.
    final remote = isOnline ? ref.watch(remoteControlConnectionProvider(device.id)).value : null;
    // Hidden entirely while profile-wide sync is on
    // (docs/adr/0033-playback-ownership-and-handoff.md) — control now
    // happens from the player's own cast/handoff picker, which already
    // shows exactly one active target; keeping this inline duplicate
    // around too would just be a second, easy-to-miss place the same
    // buttons could stop working from (e.g. loadAndPlay here would
    // silently fight the ownership protocol instead of going through
    // it).
    final syncEnabled = ref.watch(profileSyncEnabledProvider).value ?? false;
    final canControl = !syncEnabled && remote?.status == RemoteControlStatus.accepted;

    final tile = ListTile(
      leading: CircleAvatar(
        backgroundColor: context.colors.surfaceHigh,
        child: Icon(
          isOnline ? Icons.devices : Icons.devices_other,
          color: isOnline ? AppTheme.accent : context.colors.onSurfaceMuted,
        ),
      ),
      title: Text(device.name),
      subtitle: Text(isOnline ? l10n.deviceOnline : _lastSeenLabel(l10n, device)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isOnline)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: l10n.deviceSyncNowTooltip,
              onPressed: () => _syncNow(ref),
            ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: l10n.deviceUnpairTooltip,
            onPressed: () => _confirmUnpair(context, ref),
          ),
        ],
      ),
      onLongPress: canControl ? () => showDeviceActionsSheet(context, ref, device) : null,
    );

    if (!canControl) return tile;
    return Column(
      children: [
        // Right-click opens the same menu as long-press — desktop has no
        // long-press gesture (same pattern as TrackTile/PlaylistTile).
        GestureDetector(
          onSecondaryTap: () => showDeviceActionsSheet(context, ref, device),
          child: tile,
        ),
        _RemoteControls(deviceId: device.id, state: remote!.state),
      ],
    );
  }

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deviceUnpairTitle),
        content: Text(l10n.deviceUnpairBody(device.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.deviceUnpairConfirm)),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(metadataSyncServiceProvider).disconnectFromPeer(device.id);
    await ref.read(devicesRepositoryProvider).delete(device.id);
  }

  String _lastSeenLabel(AppLocalizations l10n, Device device) {
    final lastOnline = device.lastOnlineAtDate;
    if (lastOnline == null) return l10n.deviceOffline;
    return l10n.deviceLastSeen(_formatRelative(l10n, lastOnline));
  }

  String _formatRelative(AppLocalizations l10n, DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return l10n.deviceLastSeenJustNow;
    if (diff.inMinutes < 60) return l10n.deviceLastSeenMinutes(diff.inMinutes);
    if (diff.inHours < 24) return l10n.deviceLastSeenHours(diff.inHours);
    return l10n.deviceLastSeenDays(diff.inDays);
  }

  void _syncNow(WidgetRef ref) {
    if (device.host == null || device.syncPort == null) return;
    final peer = DiscoveredPeer(
      deviceId: device.id,
      name: device.name,
      host: device.host!,
      port: device.syncPort!,
    );
    ref.read(metadataSyncServiceProvider).connectToPeer(device.id, peer.metadataSyncUri);
  }
}

/// Inline play/pause/next/previous + a read-only progress bar for a
/// device that's confirmed to allow remote control — see
/// docs/adr/0030-remote-playback-control.md. Deliberately a
/// `LinearProgressIndicator`, not a `Slider`: display only, no seeking
/// from here (that's what the "запустить то, что у меня на паузе"/
/// "выбрать трек" actions in [showDeviceActionsSheet] are for).
class _RemoteControls extends ConsumerWidget {
  const _RemoteControls({required this.deviceId, required this.state});

  final String deviceId;
  final RemoteState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(remoteControlControllerProvider(deviceId));
    final isPlaying = state?.isPlaying ?? false;
    final positionMs = state?.positionMs ?? 0;
    final durationMs = state?.durationMs ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                visualDensity: VisualDensity.compact,
                onPressed: controller.previous,
              ),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                visualDensity: VisualDensity.compact,
                onPressed: isPlaying ? controller.pause : controller.play,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                visualDensity: VisualDensity.compact,
                onPressed: controller.next,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  state?.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.colors.onSurfaceMuted),
                ),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: durationMs == 0 ? 0 : positionMs / durationMs,
              minHeight: 3,
              color: AppTheme.accent,
              backgroundColor: context.colors.surfaceHigh,
            ),
          ),
        ],
      ),
    );
  }
}
