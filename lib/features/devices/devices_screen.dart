import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/track.dart';
import '../library/providers/library_providers.dart';
import 'providers/devices_providers.dart';
import 'widgets/device_tile.dart';
import 'widgets/sync_badge.dart';

/// Устройства tab (ТЗ п.6.3): known peers with online status, a QR code
/// for pairing (carries this device's id — see
/// docs/adr/0006-device-identity-without-asymmetric-crypto.md for what
/// that id actually is), and manual sync.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final self = ref.watch(selfDeviceProvider);
    final knownDevicesAsync = ref.watch(knownDevicesProvider);
    final onlineIds = ref.watch(onlineDeviceIdsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Устройства')),
      body: ListView(
        children: [
          const SyncBadge(),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(data: self.id, size: 180),
                ),
                const SizedBox(height: 12),
                Text(self.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'Покажите этот QR-код на другом устройстве, чтобы добавить его в список',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
                ),
              ],
            ),
          ),
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
