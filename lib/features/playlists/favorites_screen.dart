import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.favoritesTitle)),
      body: tracks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite_border, size: 64, color: AppTheme.onSurfaceMuted),
                    const SizedBox(height: 16),
                    Text(
                      l10n.favoritesEmptyTitle,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.favoritesEmptyBody,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.onSurfaceMuted),
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
