import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../../l10n/l10n.dart';
import '../library/providers/library_providers.dart';
import '../profiles/profile_switcher_sheet.dart';
import '../settings/settings_screen.dart';
import 'providers/devices_providers.dart';
import 'widgets/device_tile.dart';
import 'widgets/sync_badge.dart';

/// Устройства tab (ТЗ п.6.3): known (paired) peers with online status and
/// manual sync. Pairing itself happens through LAN discovery +
/// confirm-on-both-sides (docs/adr/0011-mutual-pairing-confirmation.md),
/// not a QR code — there's never been a scanner to read one with, only a
/// display, so it added a screen without adding a way to actually pair.
/// Also the entry point to [SettingsScreen] — the app has no separate
/// settings tab, and this is the closest thing to one
/// (docs/adr/0028-settings-screen-and-theming.md).
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(selfDeviceProvider);
    final currentProfile = ref.watch(currentProfileProvider);
    final knownDevicesAsync = ref.watch(knownDevicesProvider);
    final onlineIds = ref.watch(onlineDeviceIdsProvider).value ?? const {};
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navDevices),
        actions: [
          const _RefreshDiscoveryButton(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTitle,
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppTheme.accent,
              child: Icon(Icons.person, color: Colors.white),
            ),
            title: Text(l10n.devicesProfileLabel(currentProfile.name)),
            subtitle: Text(l10n.devicesProfileSubtitle),
            trailing: TextButton(
              onPressed: () => showProfileSwitcherSheet(context),
              child: Text(l10n.devicesChangeProfile),
            ),
          ),
          const Divider(height: 1),
          const SyncBadge(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l10n.devicesKnownDevicesLabel, style: TextStyle(color: context.colors.onSurfaceMuted)),
          ),
          knownDevicesAsync.when(
            data: (devices) {
              final others = devices.where((d) => d.id != self.id).toList();
              if (others.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Text(
                    l10n.devicesNoneFound,
                    style: TextStyle(color: context.colors.onSurfaceMuted),
                  ),
                );
              }
              return Column(
                children: [
                  for (final device in others)
                    DeviceTile(device: device, isOnline: onlineIds.contains(device.id)),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.devicesErrorPrefix(error)),
            ),
          ),
          const _NearbyUnpairedPeers(),
          const Divider(height: 32),
          const _FileSyncStatus(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Manually restarts mDNS advertising/discovery — see
/// `SyncOrchestrator.restartDiscovery` and
/// docs/adr/0026-manual-discovery-refresh.md. The automatic debounce/replay
/// (docs/adr/0025-sync-and-discovery-reliability.md) already recovers from
/// ordinary mDNS flapping on its own; this button is for the case that
/// doesn't self-heal — ordinary automatic recovery still runs exactly as
/// before, this is purely additive.
class _RefreshDiscoveryButton extends ConsumerStatefulWidget {
  const _RefreshDiscoveryButton();

  @override
  ConsumerState<_RefreshDiscoveryButton> createState() => _RefreshDiscoveryButtonState();
}

class _RefreshDiscoveryButtonState extends ConsumerState<_RefreshDiscoveryButton> {
  bool _restarting = false;

  Future<void> _restart() async {
    setState(() => _restarting = true);
    try {
      await ref.read(syncOrchestratorProvider).restartDiscovery();
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _restarting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      tooltip: context.l10n.devicesRefreshTooltip,
      onPressed: _restarting ? null : _restart,
    );
  }
}

/// Peers visible on the LAN that this device hasn't paired with yet — see
/// docs/adr/0011-mutual-pairing-confirmation.md. Nothing here syncs until
/// the *other* side also confirms.
class _NearbyUnpairedPeers extends ConsumerWidget {
  const _NearbyUnpairedPeers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearby = ref.watch(unpairedNearbyPeersProvider);
    if (nearby.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(l10n.devicesNearbyLabel, style: TextStyle(color: context.colors.onSurfaceMuted)),
        ),
        for (final peer in nearby)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: context.colors.surfaceHigh,
              child: Icon(Icons.wifi_tethering, color: context.colors.onSurfaceMuted),
            ),
            title: Text(peer.name),
            subtitle: Text(l10n.devicesUnpaired),
            trailing: TextButton(
              onPressed: () {
                ref.read(pairingServiceProvider).requestPairing(peer);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.devicesPairingRequestSent(peer.name))),
                );
              },
              child: Text(l10n.devicesAddPeer),
            ),
          ),
      ],
    );
  }
}

/// Файлы передаются напрямую между устройствами (без внешних программ —
/// см. docs/adr/0010-built-in-file-transfer.md) автоматически, как только
/// в сети окажется устройство с нужным файлом — здесь просто видно,
/// сколько треков ещё в очереди на докачку.
class _FileSyncStatus extends ConsumerWidget {
  const _FileSyncStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missing = ref.watch(missingFilesProvider).value ?? const [];
    final transfers = ref.watch(activeTransfersProvider).value ?? const {};
    final byId = {for (final track in missing) track.id: track};
    final queuedCount = missing.length - transfers.length;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.devicesFileTransferTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (missing.isEmpty)
            Text(
              l10n.devicesAllFilesPresent,
              style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12),
            )
          else ...[
            for (final entry in transfers.entries)
              if (byId[entry.key] case final track?)
                _TransferProgressRow(track: track, fraction: entry.value),
            if (queuedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.devicesQueuedCount(queuedCount),
                  style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _TransferProgressRow extends StatelessWidget {
  const _TransferProgressRow({required this.track, required this.fraction});

  final Track track;
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fraction == null
                ? track.displayTitle
                : '${track.displayTitle} — ${(fraction! * 100).round()}%',
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 4,
              color: AppTheme.accent,
              backgroundColor: context.colors.surfaceHigh,
            ),
          ),
        ],
      ),
    );
  }
}
