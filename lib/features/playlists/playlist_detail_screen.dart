import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/playlist.dart';
import '../../data/models/playlist_track.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';
import '../player/models/queue_source.dart';
import '../player/providers/player_providers.dart';
import 'providers/playlists_providers.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId, this.playlist});

  final String playlistId;
  final Playlist? playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(playlistItemsProvider(playlistId));
    final name = playlist?.name ??
        (ref.watch(playlistsProvider).value ?? const [])
            .cast<Playlist?>()
            .firstWhere((p) => p?.id == playlistId, orElse: () => null)
            ?.name ??
        'Плейлист';

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddTrackSheet(context, ref),
        child: const Icon(Icons.playlist_add),
      ),
      body: itemsAsync.when(
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('В плейлисте пока нет треков', style: TextStyle(color: AppTheme.onSurfaceMuted)),
              )
            : ReorderableListView.builder(
                itemCount: items.length,
                onReorderItem: (oldIndex, newIndex) => _reorder(ref, items, oldIndex, newIndex),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return TrackTile(
                    key: ValueKey(item.entryId),
                    track: item.track,
                    onTap: () {
                      ref.read(queueSourceProvider.notifier).state = PlaylistQueueSource(name);
                      ref
                          .read(playerServiceProvider)
                          .setQueue(items.map((e) => e.track).toList(), startIndex: index);
                    },
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

  /// [newIndex] (via `onReorderItem`) already accounts for [oldIndex]'s
  /// item being removed — it's the item's final index in the post-move
  /// list. `moveEntry`'s `beforePosition`/`afterPosition` mean exactly
  /// "the neighbour that should end up smaller/larger", so the
  /// neighbours of that post-move list are exactly what it needs.
  Future<void> _reorder(WidgetRef ref, List<PlaylistItem> items, int oldIndex, int newIndex) async {
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final before = newIndex > 0 ? reordered[newIndex - 1].position : null;
    final after = newIndex < reordered.length - 1 ? reordered[newIndex + 1].position : null;
    await ref
        .read(playlistsRepositoryProvider)
        .moveEntry(moved.entryId, beforePosition: before, afterPosition: after);
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
