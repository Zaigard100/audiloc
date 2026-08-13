import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'providers/library_providers.dart';
import 'widgets/delete_track_action.dart';
import 'widgets/track_tile.dart';

/// Tracks in one genre — reached from the Library tab's "Жанры" list.
/// Genres aren't stored anywhere themselves (see [genresProvider]), so
/// this screen only needs the genre name, not an id: it's a live view,
/// not a maintained collection. "Сохранить как плейлист" is the escape
/// hatch for when a live view isn't enough — it snapshots the tracks
/// shown right now into a real, independently editable playlist.
class GenreTracksScreen extends ConsumerWidget {
  const GenreTracksScreen({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksByGenreProvider(genre));

    return Scaffold(
      appBar: AppBar(
        title: Text(genre),
        actions: [
          IconButton(
            icon: const Icon(Icons.playlist_add_outlined),
            tooltip: 'Сохранить как плейлист',
            onPressed: tracks.isEmpty ? null : () => _saveAsPlaylist(context, ref, tracks.map((t) => t.id)),
          ),
        ],
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('Пусто'))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackTile(
                  track: track,
                  onTap: () => ref.read(playerServiceProvider).setQueue(tracks, startIndex: index),
                  onLongPress: () => confirmAndDeleteTrack(context, ref, track),
                );
              },
            ),
    );
  }

  Future<void> _saveAsPlaylist(BuildContext context, WidgetRef ref, Iterable<String> trackIds) async {
    final playlists = ref.read(playlistsRepositoryProvider);
    final playlist = await playlists.create(genre);
    for (final trackId in trackIds) {
      await playlists.addTrack(playlist.id, trackId);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Плейлист «$genre» создан (${trackIds.length} треков)')),
      );
    }
  }
}
