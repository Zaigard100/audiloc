import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/playlist.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';
import 'providers/playlists_providers.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId, this.playlist});

  final String playlistId;
  final Playlist? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(playlistItemsProvider(playlistId));

    return Scaffold(
      appBar: AppBar(title: Text(playlist?.name ?? 'Плейлист')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTrackSheet(context, ref),
        child: const Icon(Icons.playlist_add),
      ),
      body: itemsAsync.when(
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('В плейлисте пока нет треков', style: TextStyle(color: AppTheme.onSurfaceMuted)),
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return TrackTile(
                    track: item.track,
                    onTap: () => ref
                        .read(playerServiceProvider)
                        .setQueue(items.map((e) => e.track).toList(), startIndex: index),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      color: AppTheme.onSurfaceMuted,
                      onPressed: () => ref.read(playlistsRepositoryProvider).removeEntry(item.entryId),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка: $error')),
      ),
    );
  }

  Future<void> _showAddTrackSheet(BuildContext context, WidgetRef ref) async {
    final allTracks = ref.read(libraryTracksProvider).value ?? const [];
    final currentIds = (ref.read(playlistItemsProvider(playlistId)).value ?? const [])
        .map((e) => e.track.id)
        .toSet();
    final available = allTracks.where((t) => !currentIds.contains(t.id)).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        expand: false,
        builder: (context, scrollController) => available.isEmpty
            ? const Center(child: Text('Все треки уже в плейлисте', style: TextStyle(color: AppTheme.onSurfaceMuted)))
            : ListView.builder(
                controller: scrollController,
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final track = available[index];
                  return TrackTile(
                    track: track,
                    trailing: const Icon(Icons.add, color: AppTheme.accent),
                    onTap: () async {
                      await ref.read(playlistsRepositoryProvider).addTrack(playlistId, track.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  );
                },
              ),
      ),
    );
  }
}
