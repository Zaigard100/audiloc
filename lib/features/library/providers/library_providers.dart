import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/providers.dart';
import '../../../data/models/track.dart';

final libraryTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(tracksRepositoryProvider).watchAll(),
);

final favoriteIdsProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(favoritesRepositoryProvider).watchFavoriteIds(),
);

final librarySearchQueryProvider = StateProvider<String>((ref) => '');

final filteredLibraryTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(libraryTracksProvider).value ?? const [];
  final query = ref.watch(librarySearchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return tracks;
  return tracks
      .where((t) =>
          t.displayTitle.toLowerCase().contains(query) ||
          t.displayArtist.toLowerCase().contains(query) ||
          t.displayAlbum.toLowerCase().contains(query))
      .toList();
});

/// "Избранное" as a live view, not a maintained playlist (ТЗ п.6.5): a
/// track appears here for exactly as long as its heart is toggled on,
/// with no separate storage or upkeep beyond `favorites`.
final favoriteTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(libraryTracksProvider).value ?? const [];
  final favoriteIds = ref.watch(favoriteIdsProvider).value ?? const {};
  return tracks.where((t) => favoriteIds.contains(t.id)).toList();
});

/// Genres aren't stored anywhere of their own — this is just the distinct,
/// non-empty `tracks.genre` values already loaded, so it stays in sync
/// with the library for free.
final genresProvider = Provider<List<String>>((ref) {
  final tracks = ref.watch(libraryTracksProvider).value ?? const [];
  final genres = <String>{
    for (final t in tracks)
      if (t.genre != null && t.genre!.trim().isNotEmpty) t.genre!.trim(),
  };
  return genres.toList()..sort();
});

final tracksByGenreProvider = Provider.family<List<Track>, String>((ref, genre) {
  final tracks = ref.watch(libraryTracksProvider).value ?? const [];
  return tracks.where((t) => t.genre?.trim() == genre).toList();
});

/// Soft-deleted tracks ("Удалённые"): hidden from the library, file left
/// alone on disk, restorable — see `TracksRepository.delete`/`.restore`.
final deletedTracksProvider = StreamProvider<List<Track>>(
  (ref) => ref.watch(tracksRepositoryProvider).watchDeleted(),
);
