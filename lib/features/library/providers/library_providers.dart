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
