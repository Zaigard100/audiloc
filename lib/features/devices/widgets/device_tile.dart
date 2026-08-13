import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/device.dart';
import '../../../services/sync/discovery/discovered_peer.dart';

class DeviceTile extends ConsumerWidget {
  const DeviceTile({super.key, required this.device, required this.isOnline});

  final Device device;
  final bool isOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.surfaceHigh,
        child: Icon(
          isOnline ? Icons.devices : Icons.devices_other,
          color: isOnline ? AppTheme.accent : AppTheme.onSurfaceMuted,
        ),
      ),
      title: Text(device.name),
      subtitle: Text(isOnline ? 'В сети' : _lastSeenLabel(device)),
      trailing: isOnline
          ? IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Синхронизировать сейчас',
              onPressed: () => _syncNow(ref),
            )
          : null,
    );
  }

  String _lastSeenLabel(Device device) {
    final lastOnline = device.lastOnlineAtDate;
    if (lastOnline == null) return 'Не в сети';
    return 'Не в сети · был(а) в сети ${_formatRelative(lastOnline)}';
  }

  String _formatRelative(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} дн назад';
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
