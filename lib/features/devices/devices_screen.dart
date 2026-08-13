import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
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
          const Divider(height: 32),
          const _FileSyncStatus(),
          const SizedBox(height: 24),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Передача файлов', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            missing.isEmpty
                ? 'Все известные треки уже есть на этом устройстве'
                : 'Ожидают докачки: ${missing.length} — появятся сами, как только в сети найдётся устройство с этими файлами',
            style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
