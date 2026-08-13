import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../devices/devices_screen.dart';
import '../library/library_screen.dart';
import '../player/mini_player.dart';
import '../playlists/playlists_screen.dart';
import '../search/search_screen.dart';

const _tabs = ['library', 'playlists', 'search', 'devices'];

/// Bottom-tab shell (ТЗ п.6.2): Библиотека / Плейлисты / Поиск / Устройства,
/// with the mini-player pinned above the tab bar so it's always reachable.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.tab});

  final String tab;

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexOf(tab).clamp(0, _tabs.length - 1);

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
}
