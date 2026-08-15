import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../about/about_screen.dart';
import '../library/providers/library_providers.dart';
import '../profiles/profile_switcher_sheet.dart';
import 'providers/devices_providers.dart';
import 'widgets/device_tile.dart';
import 'widgets/sync_badge.dart';

/// Устройства tab (ТЗ п.6.3): known (paired) peers with online status and
/// manual sync. Pairing itself happens through LAN discovery +
/// confirm-on-both-sides (docs/adr/0011-mutual-pairing-confirmation.md),
/// not a QR code — there's never been a scanner to read one with, only a
/// display, so it added a screen without adding a way to actually pair.
/// Also the entry point to [AboutScreen] — the app has no separate
/// settings tab, and this is the closest thing to one.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(selfDeviceProvider);
    final currentProfile = ref.watch(currentProfileProvider);
    final knownDevicesAsync = ref.watch(knownDevicesProvider);
    final onlineIds = ref.watch(onlineDeviceIdsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Устройства'),
        actions: [
          const _RefreshDiscoveryButton(),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'О приложении',
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
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
            title: Text('Профиль: ${currentProfile.name}'),
            subtitle: const Text('У каждого профиля своя библиотека и свои устройства'),
            trailing: TextButton(
              onPressed: () => showProfileSwitcherSheet(context),
              child: const Text('Сменить'),
            ),
          ),
          const Divider(height: 1),
          const SyncBadge(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Известные устройства', style: TextStyle(color: AppTheme.onSurfaceMuted)),
          ),
          knownDevicesAsync.when(
            data: (devices) {
              final others = devices.where((d) => d.id != self.id).toList();
              if (others.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Text(
                    'Пока не найдено ни одного устройства в локальной сети',
                    style: TextStyle(color: AppTheme.onSurfaceMuted),
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
              child: Text('Ошибка: $error'),
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
      tooltip: 'Обновить список устройств',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Найдено рядом', style: TextStyle(color: AppTheme.onSurfaceMuted)),
        ),
        for (final peer in nearby)
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppTheme.surfaceHigh,
              child: Icon(Icons.wifi_tethering, color: AppTheme.onSurfaceMuted),
            ),
            title: Text(peer.name),
            subtitle: const Text('Не сопряжено'),
            trailing: TextButton(
              onPressed: () {
                ref.read(pairingServiceProvider).requestPairing(peer);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Запрос на сопряжение отправлен «${peer.name}»')),
                );
              },
              child: const Text('Добавить'),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Передача файлов', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (missing.isEmpty)
            const Text(
              'Все известные треки уже есть на этом устройстве',
              style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
            )
          else ...[
            for (final entry in transfers.entries)
              if (byId[entry.key] case final track?)
                _TransferProgressRow(track: track, fraction: entry.value),
            if (queuedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'В очереди: $queuedCount — появятся сами, как только в сети '
                  'найдётся устройство с этими файлами',
                  style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
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
              backgroundColor: AppTheme.surfaceHigh,
            ),
          ),
        ],
      ),
    );
  }
}
