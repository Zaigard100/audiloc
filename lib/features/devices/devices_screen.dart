import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
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
          const _SyncthingSettings(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SyncthingSettings extends ConsumerStatefulWidget {
  const _SyncthingSettings();

  @override
  ConsumerState<_SyncthingSettings> createState() => _SyncthingSettingsState();
}

class _SyncthingSettingsState extends ConsumerState<_SyncthingSettings> {
  final _controller = TextEditingController();
  String? _status;

  @override
  void initState() {
    super.initState();
    ref.read(secureSettingsServiceProvider).getSyncthingApiKey().then((key) {
      if (!mounted || key == null) return;
      _controller.text = key;
      ref.read(syncthingApiKeyProvider.notifier).state = key;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Передача файлов через Syncthing', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text(
            'AudiLoc сам файлы не передаёт — для этого используется локально запущенный Syncthing (localhost:8384). Вставьте его API-ключ, чтобы включить интеграцию.',
            style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Syncthing API key', isDense: true),
                  obscureText: true,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: const Text('Сохранить')),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    await ref.read(secureSettingsServiceProvider).setSyncthingApiKey(key);
    ref.read(syncthingApiKeyProvider.notifier).state = key;

    final client = ref.read(syncthingClientProvider);
    final reachable = client != null && await client.ping();
    setState(() => _status = reachable ? 'Syncthing найден и отвечает' : 'Не удалось связаться с Syncthing на localhost:8384');
  }
}
