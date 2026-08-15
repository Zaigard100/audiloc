import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/device.dart';
import '../../../l10n/l10n.dart';
import '../../../services/sync/discovery/discovered_peer.dart';

class DeviceTile extends ConsumerWidget {
  const DeviceTile({super.key, required this.device, required this.isOnline});

  final Device device;
  final bool isOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListTile(
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
