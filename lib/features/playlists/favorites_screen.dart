import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../library/providers/library_providers.dart';
import '../library/widgets/track_tile.dart';
import '../player/models/queue_source.dart';
import '../player/providers/player_providers.dart';

/// "Избранное" — a live view over `favorites`, not a maintained
/// playlist (ТЗ п.6.5): a track is here for exactly as long as its heart
/// is toggled on. Sorted newest-favorited-first (see
/// `favoriteTracksProvider`). No manual drag reorder — there's no
/// position column to persist one against; the default heart toggle in
/// [TrackTile] is already how you add/remove a track here. Reached from
/// a pinned card on the Плейлисты grid (docs/adr/0014).
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(favoriteTracksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Избранное')),
      body: tracks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border, size: 64, color: AppTheme.onSurfaceMuted),
                    SizedBox(height: 16),
                    Text(
                      'Пока нет избранных треков',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Нажмите на сердечко у трека — он появится здесь',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.onSurfaceMuted),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackTile(
                  track: track,
                  onTap: () {
                    ref.read(queueSourceProvider.notifier).state = const FavoritesQueueSource();
                    ref.read(playerServiceProvider).setQueue(tracks, startIndex: index);
                  },
                );
              },
            ),
    );
  }
}
