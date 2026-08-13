import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../services/sync/pairing/pairing_models.dart';
import '../devices/devices_screen.dart';
import '../devices/providers/devices_providers.dart';
import '../library/library_screen.dart';
import '../player/mini_player.dart';
import '../playlists/playlists_screen.dart';
import '../search/search_screen.dart';

const _tabs = ['library', 'playlists', 'search', 'devices'];

/// Bottom-tab shell (ТЗ п.6.2): Библиотека / Плейлисты / Поиск / Устройства,
/// with the mini-player pinned above the tab bar so it's always reachable.
/// Also owns the incoming-pairing-request dialog (ТЗ +
/// docs/adr/0011-mutual-pairing-confirmation.md) — it needs to show up no
/// matter which tab the user is on, not just from the Устройства screen.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.tab});

  final String tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = _tabs.indexOf(tab).clamp(0, _tabs.length - 1);

    ref.listen(incomingPairingRequestsProvider, (previous, next) {
      final request = next.value;
      if (request != null) _showPairingRequestDialog(context, ref, request);
    });

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          LibraryScreen(),
          PlaylistsScreen(),
          SearchScreen(),
          DevicesScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go('/${_tabs[i]}'),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Библиотека'),
              NavigationDestination(icon: Icon(Icons.queue_music_outlined), selectedIcon: Icon(Icons.queue_music), label: 'Плейлисты'),
              NavigationDestination(icon: Icon(Icons.search), label: 'Поиск'),
              NavigationDestination(icon: Icon(Icons.devices_outlined), selectedIcon: Icon(Icons.devices), label: 'Устройства'),
            ],
          ),
        ],
      ),
    );
  }

  void _showPairingRequestDialog(BuildContext context, WidgetRef ref, IncomingPairingRequest request) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Запрос на сопряжение'),
        content: Text('«${request.fromName}» хочет синхронизироваться с этим устройством.'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(pairingServiceProvider).reject(request);
              Navigator.of(context).pop();
            },
            child: const Text('Отклонить'),
          ),
          TextButton(
            onPressed: () {
              ref.read(pairingServiceProvider).approve(request);
              Navigator.of(context).pop();
            },
            child: const Text('Разрешить'),
          ),
        ],
      ),
    );
  }
}
