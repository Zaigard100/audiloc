import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'favorites_screen.dart';
import 'providers/playlists_providers.dart';
import 'trash_screen.dart';

/// Плейлисты tab: a grid of square cards, not a list — "Избранное" and
/// "Удалённые" are pinned first as special cards (docs/adr/0014), then
/// the user's own playlists.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Плейлисты')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPlaylist(context, ref),
        child: const Icon(Icons.add),
      ),
      body: playlistsAsync.when(
        data: (playlists) => GridView(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          children: [
            _PlaylistTile(
              label: 'Избранное',
              icon: Icons.favorite,
              color: AppTheme.accent,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const FavoritesScreen())),
            ),
            _PlaylistTile(
              label: 'Удалённые',
              icon: Icons.delete_outline,
              color: AppTheme.surfaceHigh,
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TrashScreen())),
            ),
            for (final playlist in playlists)
              _PlaylistTile(
                label: playlist.name,
                icon: Icons.queue_music,
                color: AppTheme.surfaceHigh,
                onTap: () => context.push('/playlists/${playlist.id}', extra: playlist),
              ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка: $error')),
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Название'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(playlistsRepositoryProvider).create(name);
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAccent = color == AppTheme.accent;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: isAccent ? Colors.white : AppTheme.onSurfaceMuted),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isAccent ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
